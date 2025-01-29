#!/bin/bash
set -e

# @license: CC BY-NC-SA 4.0 International
# @author: SMKRV
# @github: https://github.com/smkrv/mikrotik-domain-filter-script
# @source: https://github.com/smkrv/mikrotik-domain-filter-script
#
# Mikrotik Domain Filter Script is a robust Bash solution primarily designed
# for filtering and processing domain lists for Mikrotik devices, enabling
# straightforward management of blocklists or allowlists.
#
# For a detailed description, please visit the GitHub repository:
# https://github.com/smkrv/mikrotik-domain-filter-script
#
# By combining domain classification, DNS validation, and whitelist handling,
# this tool offers a comprehensive workflow to create accurate and reliable
# filtered lists, ensuring efficient network policy enforcement. It is also
# suitable for building and maintaining Adlists by returning 0.0.0.0 for
# domains serving advertisements, integrating seamlessly with DNS Static in
# Mikrotik RouterOS, and aiding in generating DNS FWD records.

# Enable debugging
# set -x

# Path settings
# Important: Verify that the following directory path is correct
readonly WORK_DIR="/home/domain-filter-mikrotik"
readonly SOURCES_FILE="${WORK_DIR}/sources.txt"
readonly SOURCESSPECIAL_FILE="${WORK_DIR}/sources_special.txt"
readonly WHITELIST_FILE="${WORK_DIR}/sources_whitelist.txt"
readonly PUBLIC_SUFFIX_FILE="${WORK_DIR}/public_suffix_list.dat"
readonly LOG_FILE="${WORK_DIR}/script.log"

# This lock file path must also be correct to avoid conflicts
readonly LOCK_FILE="/tmp/domains_update.lock"

# Temporary directories and files
readonly TMP_DIR="${WORK_DIR}/tmp"
readonly CACHE_DIR="${WORK_DIR}/cache"

# Output files
readonly OUTPUT_FILE="${WORK_DIR}/filtered_domains_mikrotik.txt"
readonly OUTPUT_FILESPECIAL="${WORK_DIR}/filtered_domains_special_mikrotik.txt"

# Load environment variables from .env file if it exists
if [[ -f "${WORK_DIR}/.env" ]]; then
    # shellcheck disable=SC1090
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove quotes and export variable
        value="${value%\"}"
        value="${value#\"}"
        export "$key=$value"
    done < "${WORK_DIR}/.env"
fi

# GitHub Gist settings !Use env var if available
readonly EXPORT_GISTS=${EXPORT_GISTS:-false}  # Default to false if not set
readonly GITHUB_TOKEN=${GITHUB_TOKEN:-""}     # GitHub access token
readonly GIST_ID_MAIN=${GIST_ID_MAIN:-""}     # Gist ID for main list
readonly GIST_ID_SPECIAL=${GIST_ID_SPECIAL:-""} # Gist ID for special list

# Performance settings
readonly MAX_PARALLEL_JOBS=5
readonly DNS_RATE_LIMIT=5
readonly DNS_TIMEOUT=10
readonly DNS_MAX_RETRIES=3

# Export variables for parallel
export DNS_TIMEOUT
export DNS_RATE_LIMIT
export LOG_FILE
export DNS_MAX_RETRIES

# Global variables for statistics
declare -i TOTAL_DOMAINS=0

# Enable debugging
# exec 2>"${WORK_DIR}/debug.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Clear old log
: > "$LOG_FILE"

# Check for required files
check_required_files() {
    local missing_files=()

    [[ ! -f "$SOURCES_FILE" ]] && missing_files+=("$SOURCES_FILE")
    [[ ! -f "$SOURCESSPECIAL_FILE" ]] && missing_files+=("$SOURCESSPECIAL_FILE")

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "ERROR: Missing required files:"
        printf '%s\n' "${missing_files[@]}"
        exit 1
    fi
}

# Enhanced logging
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    echo "ERROR: $1" >&2
    exit 1
}

# Lock function
acquire_lock() {
    log "Attempting to acquire lock..."

    # Create file descriptor for the entire script
    exec 9>"$LOCK_FILE"

    if ! flock -n 9; then
        log "Script is already running (PID: $(cat "$LOCK_FILE" 2>/dev/null || echo 'unknown'))"
        exit 1
    fi

    echo $$ >&9
    log "Lock acquired successfully"
}

# Unlock function
release_lock() {
    log "Releasing lock..."
    flock -u 9
    exec 9>&-
    rm -f "$LOCK_FILE"
}

# Signal handling
trap cleanup EXIT
trap 'log "Script interrupted"; release_lock; exit 1' INT TERM

init_directories() {
    log "Initialization started..."

    # Check and create all required directories
    local dirs=("$WORK_DIR" "$TMP_DIR" "$CACHE_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if ! mkdir -p "$dir"; then
                error "Failed to create directory $dir"
            fi
        fi
        if [[ ! -w "$dir" ]]; then
            error "No write permissions for $dir"
        fi

        if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
            echo "ERROR: No write permissions for log directory"
            exit 1
        fi

        if [[ -f "$LOG_FILE" && ! -w "$LOG_FILE" ]]; then
            echo "ERROR: No write permissions for log file"
            exit 1
        fi

    done

    log "Initialization completed successfully"
}

# Function to clean up temporary files
cleanup() {
    log "Cleaning up temporary files..."

    # Check for existence and correctness of temporary directory path
    if [[ -d "$TMP_DIR" && "$TMP_DIR" != "/" && "$TMP_DIR" =~ ^/home/unblock/tmp ]]; then
        if [[ -n "$(find "$TMP_DIR" -type f)" ]]; then
            find "$TMP_DIR" -type f -delete
            log "Temporary files cleaned"
        fi
        if [[ -n "$(find "$TMP_DIR" -type d -empty)" ]]; then
            find "$TMP_DIR" -type d -empty -delete
            log "Empty directories cleaned"
        fi
        mkdir -p "$TMP_DIR"
    fi

    # Clean old cache files
    if [[ -d "$CACHE_DIR" ]]; then
        local cache_files_count
        cache_files_count=$(find "$CACHE_DIR" -type f -name "*.cache" -mtime +90 -delete -print | wc -l)
        if [[ $cache_files_count -gt 0 ]]; then
            log "Removed $cache_files_count outdated cache files"
        fi
    fi
}

# Function to check dependencies
check_dependencies() {
    local deps=(curl jq awk grep parallel)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            error "Required dependency: $dep"
        fi
    done
}

# Function to check domain via DNS
check_domain() {
    local domain=$1
    local retry_count=0
    local success=false
    local cache_file="${CACHE_DIR}/${domain}.cache"

    # Check cache
    if [[ -f "$cache_file" ]]; then
        local cache_time
        cache_time=$(stat -c %Y "$cache_file")
        local current_time
        current_time=$(date +%s)
        # Check if cache is older than 3 months
        if (( current_time - cache_time < 7776000 )); then
            local cache_status
            cache_status=$(cat "$cache_file")
            [[ "$cache_status" == "valid" ]] && return 0 || return 1
        fi
    fi

    while [[ $retry_count -lt $DNS_MAX_RETRIES && $success == false ]]; do
        [[ $retry_count -gt 0 ]] && sleep 2

        if curl --connect-timeout $DNS_TIMEOUT --max-time $DNS_TIMEOUT -s -f \
            --header "accept: application/dns-json" \
            "https://cloudflare-dns.com/dns-query?name=${domain}&type=NS" | \
            grep -q '"Status":0.*"Answer":\[.*"type":2'; then
            echo "valid" > "$cache_file"
            success=true
            return 0
        fi

        ((retry_count++))
    done

    echo "invalid" > "$cache_file"
    return 1
}
export -f check_domain

# Function for parallel domain checking
check_domains_parallel() {
    local input=$1
    local output=$2
    local temp_output="${output}.tmp"
    local valid_count=0

    # Check if input file exists
    if [[ ! -f "$input" ]]; then
        log "ERROR: Input file $input does not exist"
        return 1
    fi

    # Check write permissions for output file
    if [[ ! -w "$(dirname "$output")" ]]; then
        log "ERROR: No write permissions for directory $(dirname "$output")"
        return 1
    fi

    local total
    total=$(wc -l < "$input")
    if [[ $total -eq 0 ]]; then
        log "WARNING: Input file $input is empty"
        return 1
    fi

    log "Starting DNS checks for: $input (total domains: $total)"
    : > "$temp_output"

    local current=0
    local processed=0

    # Create temporary file for atomic result writing
    local results_file="${TMP_DIR}/dns_results_$$"
    local count_file="${TMP_DIR}/valid_count_$$"
    : > "$results_file"
    : > "$count_file"

    while IFS= read -r domain; do
        (
            if check_domain "$domain"; then
                echo "$domain" >> "$results_file"
                echo "1" >> "$count_file"
                log "Domain $domain is valid"
            fi
        ) &

        ((current++))
        ((processed++))

        # Control parallel processes
        if [[ $((current % MAX_PARALLEL_JOBS)) -eq 0 ]] || [[ $processed -eq $total ]]; then
            wait
            # Count intermediate valid domains
            if [[ -f "$count_file" ]]; then
                valid_count=$(wc -l < "$count_file")
            fi
            current=0
            # Update progress every 100 domains
            if [[ $((processed % 100)) -eq 0 ]] || [[ $processed -eq $total ]]; then
                log "Progress: $processed out of $total (valid: $valid_count)"
            fi
        fi
    done < "$input"

    wait

    # Final count of valid domains
    if [[ -f "$count_file" ]]; then
        valid_count=$(wc -l < "$count_file")
        rm -f "$count_file"
    fi

    # Collect all results
    if [[ -f "$results_file" ]]; then
        sort -u "$results_file" > "$temp_output"
        rm -f "$results_file"

        if [[ -s "$temp_output" ]]; then
            mv "$temp_output" "$output"
            local final_count
            final_count=$(wc -l < "$output")
            log "DNS check completed successfully. Valid domains: $final_count"
            return 0
        else
            log "ERROR: No valid domains after check"
            rm -f "$temp_output"
            return 1
        fi
    else
        log "ERROR: Check results file not found"
        return 1
    fi
}

# Function to load Public Suffix List
load_public_suffix_list() {
    if [[ ! -f "$PUBLIC_SUFFIX_FILE" ]] || [[ -n $(find "$PUBLIC_SUFFIX_FILE" -mtime +7 -print) ]]; then
        log "Updating Public Suffix List..."
        curl -s "https://publicsuffix.org/list/public_suffix_list.dat" | \
        grep -v '^//' | grep -v '^$' > "$PUBLIC_SUFFIX_FILE"

        if [[ ! -s "$PUBLIC_SUFFIX_FILE" ]]; then
            error "Failed to download Public Suffix List. Check internet connection and access rights."
        fi
    fi
}

# Function to validate domain
validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$ ]] || return 1
    [[ "$domain" =~ \.\. ]] && return 1
    [[ "$domain" =~ (^|\.)-|-(\.|$) ]] && return 1
    [[ ${#domain} -gt 253 ]] && return 1
    return 0
}
export -f validate_domain

# Function for initial filtering
initial_filter() {
    local input=$1
    local output=$2

    log "Initial filtering: $input"

    grep -P '^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$' "$input" | \
    grep -v '^#' | \
    grep -v '^$' | \
    tr '[:upper:]' '[:lower:]' | \
    tr -d ' ' | \
    awk 'length <= 253' | \
    sort -u > "$output"

    TOTAL_DOMAINS=$(wc -l < "$output")
    log "Found unique domains: $TOTAL_DOMAINS"
}

# Function to determine domain type
get_domain_type() {
    local domain=$1
    local parts
    IFS='.' read -ra parts <<< "$domain"
    local levels=${#parts[@]}
    local base="${parts[-2]}.${parts[-1]}"

    if [[ $levels -eq 2 ]]; then
        echo "second"
    elif grep -Fxq "$base" "$PUBLIC_SUFFIX_FILE"; then
        echo "regional"
    else
        echo "other"
    fi
}

# Function to process and classify domains
process_domains() {
    local input=$1
    local output_dir=$2

    log "Classifying domains from: $input"

    # Create all required directories and files
    mkdir -p "${output_dir}/{second,regional,other}"

    local second_level="${output_dir}/second.txt"
    local regional="${output_dir}/regional.txt"
    local other="${output_dir}/other.txt"
    local base_domains="${output_dir}/base_domains.tmp"

    # Create all files from scratch
    : > "$second_level"
    : > "$regional"
    : > "$other"
    : > "$base_domains"

    # Check that all files are created successfully
    for file in "$second_level" "$regional" "$other" "$base_domains"; do
        if [[ ! -f "$file" ]]; then
            log "ERROR: Failed to create file $file"
            return 1
        fi
    done

    log "Directories and files prepared for classification"

    # First pass - find all second-level and regional domains
    while IFS= read -r domain; do
        local parts
        IFS='.' read -ra parts <<< "$domain"
        local levels=${#parts[@]}

        # Limit to 4th level
        if [[ $levels -gt 4 ]]; then
            domain="${parts[-4]}.${parts[-3]}.${parts[-2]}.${parts[-1]}"
        fi

        if [[ $levels -eq 2 ]]; then
            echo "$domain" >> "$second_level"
            echo "$domain" >> "$base_domains"
        else
            local base_domain="${parts[-2]}.${parts[-1]}"
            if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                if [[ $levels -eq 3 ]]; then
                    echo "$domain" >> "$regional"
                    echo "$domain" >> "$base_domains"
                fi
            fi
        fi
    done < "$input"

    # Check that files are not empty after first pass
    if [[ ! -s "$base_domains" ]]; then
        log "WARNING: No base domains found in $input"
        return 1
    fi

    # Second pass - filter subdomains
    while IFS= read -r domain; do
        local parts
        IFS='.' read -ra parts <<< "$domain"
        local skip=false

        # Skip already processed domains
        if grep -Fxq "$domain" "$base_domains"; then
            continue
        fi

        # Check if domain is a subdomain of already known domains
        while IFS= read -r base; do
            if [[ "$domain" == *".$base" ]]; then
                skip=true
                break
            fi
        done < "$base_domains"

        [[ $skip == true ]] && continue

        echo "$domain" >> "$other"
    done < "$input"

    # Sort and remove duplicates
    for file in "$second_level" "$regional" "$other"; do
        if [[ -f "$file" ]]; then
            sort -u -o "$file" "$file"
        fi
    done

    # Check results before deleting temporary files
    if [[ -f "$base_domains" ]]; then
        rm -f "$base_domains"
    else
        log "WARNING: File $base_domains not found during deletion attempt"
    fi

    # Statistics
    local second_count=0 regional_count=0 other_count=0
    [[ -f "$second_level" ]] && second_count=$(wc -l < "$second_level")
    [[ -f "$regional" ]] && regional_count=$(wc -l < "$regional")
    [[ -f "$other" ]] && other_count=$(wc -l < "$other")

    log "Classification statistics:"
    log "- Second-level domains: $second_count"
    log "- Regional domains: $regional_count"
    log "- Other domains: $other_count"

    # Check operation success
    if [[ $second_count -eq 0 && $regional_count -eq 0 && $other_count -eq 0 ]]; then
        log "ERROR: No domains found after classification"
        return 1
    fi

    return 0
}

# Function to prepare domains for DNS check
prepare_domains_for_dns_check() {
    local input_dir=$1
    local output=$2

    cat "${input_dir}/second.txt" "${input_dir}/regional.txt" 2>/dev/null | \
    sort -u > "$output"

    local total
    total=$(wc -l < "$output")
    log "Domains prepared for DNS check: $total"
}

# Function to apply whitelist
apply_whitelist() {
    local input=$1
    local whitelist=$2
    local output=$3

    log "Applying whitelist to: $input"

    if [[ ! -f "$input" || ! -f "$whitelist" ]]; then
        log "ERROR: One of the files does not exist"
        return 1
    fi

    # Create temporary file for exclusion patterns
    local whitelist_pattern="${TMP_DIR}/whitelist_pattern.txt"
    true > "$whitelist_pattern"

    # Process whitelist
    while IFS= read -r domain; do
        local parts
        IFS='.' read -ra parts <<< "${domain//./ }"
        local levels=${#parts[@]}
        local base_domain

        if [[ $levels -eq 2 ]]; then
            # Second-level domain
            echo "^${domain}$" >> "$whitelist_pattern"
            echo "\.${domain}$" >> "$whitelist_pattern"
        elif [[ $levels -eq 3 ]]; then
            # Check if domain is regional
            base_domain="${parts[-2]}.${parts[-1]}"
            if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                echo "^${domain}$" >> "$whitelist_pattern"
                echo "\.${domain}$" >> "$whitelist_pattern"
            fi
        fi
    done < "$whitelist"

    # Apply filter
    if [[ -s "$whitelist_pattern" ]]; then
        grep -vf "$whitelist_pattern" "$input" > "$output"
    else
        cp "$input" "$output"
    fi

    local removed=$(($(wc -l < "$input") - $(wc -l < "$output")))
    log "Domains removed by whitelist: $removed"

    rm -f "$whitelist_pattern"
}

# Function to check intersections between lists
check_intersections() {
    local main_list=$1
    local special_list=$2

    log "Checking intersections between lists..."

    local intersect
    intersect=$(grep -Fx -f "$main_list" "$special_list")
    if [[ -n "$intersect" ]]; then
        log "WARNING: Intersections found between lists:"
        echo "$intersect" | while read -r domain; do
            log "Duplicate domain: $domain"
        done
        return 1
    fi
    return 0
}

# Function to load lists from sources
load_lists() {
    local sources=$1
    local output=$2

    true > "$output"

    if [[ ! -f "$sources" ]]; then
        log "ERROR: Sources file $sources does not exist"
        return 1
    fi

    while read -r source; do
      [[ -z "$source" || "$source" == "#"* ]] && continue

      log "Loading from source: $source"
      local response
      response=$(curl -s --max-time 30 --retry 3 --retry-delay 2 "$source")

      if [[ $? -eq 0 && -n "$response" ]]; then
          echo "$response" | tr -s '[:space:]' '\n' >> "$output"
      else
          log "WARNING: Failed to load $source"
      fi
  done < "$sources"
}

# Function to validate results
validate_results() {
  local main_list=$1
  local special_list=$2

  # Check for file existence
  [[ ! -f "$main_list" ]] && return 1
  [[ ! -f "$special_list" ]] && return 1

  # Check file size
  [[ ! -s "$main_list" ]] && return 1
  [[ ! -s "$special_list" ]] && return 1

  # Check content format
  while read -r line; do
      validate_domain "$line" || return 1
  done < "$main_list"

  while read -r line; do
      validate_domain "$line" || return 1
  done < "$special_list"

  return 0
}

# Function to save results
save_results() {
  local main_list=$1
  local special_list=$2

  log "Starting to save results..."

  # Check for results existence
  if [[ ! -s "$main_list" || ! -s "$special_list" ]]; then
      log "ERROR: Empty results to save"
      return 1
  fi

  # Check write permissions for directories
  local main_dir
  main_dir=$(dirname "$main_list")
  local special_dir
  special_dir=$(dirname "$special_list")

  if [[ ! -w "$main_dir" || ! -w "$special_dir" || \
        (-f "$main_list" && ! -w "$main_list") || \
        (-f "$special_list" && ! -w "$special_list") ]]; then
      log "ERROR: Insufficient permissions to write results"
      return 1
  fi

  # Create temporary files with unique identifier
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local temp_main="${main_list}.${timestamp}.tmp"
  local temp_special="${special_list}.${timestamp}.tmp"

  # Copy data to temporary files
  if ! cp "$main_list" "$temp_main" || ! cp "$special_list" "$temp_special"; then
      log "ERROR: Failed to create temporary files"
      rm -f "$temp_main" "$temp_special"
      return 1
  fi

  # Check temporary files content
  local main_count
  main_count=$(wc -l < "$temp_main")
  local special_count
  special_count=$(wc -l < "$temp_special")

  log "Prepared for saving: $main_count domains in main list, $special_count in special list"

  if [[ $main_count -eq 0 || $special_count -eq 0 ]]; then
      log "ERROR: One of the lists is empty"
      rm -f "$temp_main" "$temp_special"
      return 1
  fi

  # Check validity of domains in temporary files
  local invalid_domains=0
  while IFS= read -r domain; do
      if ! validate_domain "$domain"; then
          log "ERROR: Invalid domain in main list: $domain"
          ((invalid_domains++))
      fi
  done < "$temp_main"

  while IFS= read -r domain; do
      if ! validate_domain "$domain"; then
          log "ERROR: Invalid domain in special list: $domain"
          ((invalid_domains++))
      fi
  done < "$temp_special"

  if [[ $invalid_domains -gt 0 ]]; then
      log "ERROR: Found $invalid_domains invalid domains"
      rm -f "$temp_main" "$temp_special"
      return 1
  fi

  # Create backups of current files
  local backup_main="${main_list}.backup"
  local backup_special="${special_list}.backup"

  if [[ -f "$main_list" ]]; then
      cp "$main_list" "$backup_main"
  fi
  if [[ -f "$special_list" ]]; then
      cp "$special_list" "$backup_special"
  fi

  # Atomic update of files
  if ! mv "$temp_main" "$main_list" || ! mv "$temp_special" "$special_list"; then
      log "ERROR: Failed to update results files"
      # Restore from backups if they exist
      [[ -f "$backup_main" ]] && mv "$backup_main" "$main_list"
      [[ -f "$backup_special" ]] && mv "$backup_special" "$special_list"
      return 1
  fi

  # Set access permissions
  chmod 644 "$main_list" "$special_list"

  # Check final results
  if [[ ! -s "$main_list" || ! -s "$special_list" ]]; then
      log "ERROR: Problem saving results"
      # Restore from backups
      [[ -f "$backup_main" ]] && mv "$backup_main" "$main_list"
      [[ -f "$backup_special" ]] && mv "$backup_special" "$special_list"
      return 1
  fi

  # Delete backups if successful
  rm -f "$backup_main" "$backup_special"

  log "Results saved successfully"
  log "Main list: $main_count domains"
  log "Special list: $special_count domains"

  return 0
}

# Function to update gists
update_gists() {
    [[ "$EXPORT_GISTS" != "true" ]] && return 0

    log "Starting gist update..."

    # Check requirements
    command -v curl >/dev/null 2>&1 || { log "ERROR: curl is required"; return 1; }
    command -v jq >/dev/null 2>&1 || { log "ERROR: jq is required"; return 1; }

    [[ -z "$GITHUB_TOKEN" ]] && { log "ERROR: GITHUB_TOKEN is not set"; return 1; }

    # Update main list
    if [[ -n "$GIST_ID_MAIN" && -f "$OUTPUT_FILE" ]]; then
        log "Updating main list gist..."
        local content
        content=$(cat "$OUTPUT_FILE")

        local response
        response=$(curl -s -X PATCH \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "{
                \"files\": {
                    \"$(basename "$OUTPUT_FILE")\": {
                        \"content\": $(echo "$content" | jq -R -s .)
                    }
                }
            }" \
            "https://api.github.com/gists/$GIST_ID_MAIN")

        if echo "$response" | jq -e '.id' > /dev/null; then
            log "✅ Main list gist updated successfully"
        else
            log "❌ Error updating main list gist"
            return 1
        fi
    fi

    # Update special list
    if [[ -n "$GIST_ID_SPECIAL" && -f "$OUTPUT_FILESPECIAL" ]]; then
        log "Updating special list gist..."
        local content
        content=$(cat "$OUTPUT_FILESPECIAL")

        local response
        response=$(curl -s -X PATCH \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "{
                \"files\": {
                    \"$(basename "$OUTPUT_FILESPECIAL")\": {
                        \"content\": $(echo "$content" | jq -R -s .)
                    }
                }
            }" \
            "https://api.github.com/gists/$GIST_ID_SPECIAL")

        if echo "$response" | jq -e '.id' > /dev/null; then
            log "✅ Special list gist updated successfully"
        else
            log "❌ Error updating special list gist"
            return 1
        fi
    fi

    return 0
}

# Function to check if update is needed
check_updates_needed() {
  local main_md5="${TMP_DIR}/main.md5"
  local special_md5="${TMP_DIR}/special.md5"
  local white_md5="${TMP_DIR}/white.md5"

  # Save current MD5
  md5sum "$SOURCES_FILE" > "$main_md5"
  md5sum "$SOURCESSPECIAL_FILE" > "$special_md5"
  [[ -f "$WHITELIST_FILE" ]] && md5sum "$WHITELIST_FILE" > "$white_md5"

  # Check for changes
  if [[ -f "${main_md5}.old" ]] && \
     diff -q "$main_md5" "${main_md5}.old" >/dev/null && \
     diff -q "$special_md5" "${special_md5}.old" >/dev/null && \
     { [[ ! -f "$WHITELIST_FILE" ]] || diff -q "$white_md5" "${white_md5}.old" >/dev/null; }; then
      return 1
  fi

  # Update old MD5
  mv "$main_md5" "${main_md5}.old"
  mv "$special_md5" "${special_md5}.old"
  [[ -f "$white_md5" ]] && mv "$white_md5" "${white_md5}.old"

  return 0
}

# Helper function to restore backups
restore_backups() {
  log "Restoring backups..."
  [[ -f "${OUTPUT_FILE}.bak" ]] && mv "${OUTPUT_FILE}.bak" "$OUTPUT_FILE"
  [[ -f "${OUTPUT_FILESPECIAL}.bak" ]] && mv "${OUTPUT_FILESPECIAL}.bak" "$OUTPUT_FILESPECIAL"
}

# Main function
main() {

log "Script started..."

# Check required files
check_required_files
# Initialization
init_directories
check_dependencies || error "Missing required dependencies"
acquire_lock
load_public_suffix_list

log "Starting main processing..."

  # Check if update is needed
  if ! check_updates_needed; then
      log "Lists have not changed. Skipping processing."
      release_lock
      exit 0
  fi

  # Clean temporary files
  cleanup

  # Load lists
  local main_raw="${TMP_DIR}/main_raw.txt"
  local special_raw="${TMP_DIR}/special_raw.txt"
  local whitelist_raw="${TMP_DIR}/whitelist_raw.txt"

  log "Loading lists..."
  load_lists "$SOURCES_FILE" "$main_raw"
  load_lists "$SOURCESSPECIAL_FILE" "$special_raw"
  [[ -f "$WHITELIST_FILE" ]] && load_lists "$WHITELIST_FILE" "$whitelist_raw"

  # Create backups of current files
  if [[ -f "$OUTPUT_FILE" ]]; then
      cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"
      log "Backup of main list created"
  fi
  if [[ -f "$OUTPUT_FILESPECIAL" ]]; then
      cp "$OUTPUT_FILESPECIAL" "${OUTPUT_FILESPECIAL}.bak"
      log "Backup of special list created"
  fi

  # Process main list
  log "Processing main list..."
  initial_filter "$main_raw" "${TMP_DIR}/main_initial.txt"
  if ! process_domains "${TMP_DIR}/main_initial.txt" "${TMP_DIR}/main"; then
      log "ERROR: Failed to process main domain list"
      restore_backups
      exit 1
  fi
  prepare_domains_for_dns_check "${TMP_DIR}/main" "${TMP_DIR}/main_filtered.txt"

  # Process special list
  log "Processing special list..."
  initial_filter "$special_raw" "${TMP_DIR}/special_initial.txt"
  if ! process_domains "${TMP_DIR}/special_initial.txt" "${TMP_DIR}/special"; then
      log "ERROR: Failed to process special domain list"
      restore_backups
      exit 1
  fi
  prepare_domains_for_dns_check "${TMP_DIR}/special" "${TMP_DIR}/special_filtered.txt"

  # Apply whitelist if exists
  if [[ -f "$whitelist_raw" ]]; then
      log "Applying whitelist..."
      initial_filter "$whitelist_raw" "${TMP_DIR}/whitelist.txt"
      apply_whitelist "${TMP_DIR}/main_filtered.txt" "${TMP_DIR}/whitelist.txt" "${TMP_DIR}/main_filtered_clean.txt"
      apply_whitelist "${TMP_DIR}/special_filtered.txt" "${TMP_DIR}/whitelist.txt" "${TMP_DIR}/special_filtered_clean.txt"
      mv "${TMP_DIR}/main_filtered_clean.txt" "${TMP_DIR}/main_filtered.txt"
      mv "${TMP_DIR}/special_filtered_clean.txt" "${TMP_DIR}/special_filtered.txt"
  fi

  # Check for intersections
  if ! check_intersections "${TMP_DIR}/main_filtered.txt" "${TMP_DIR}/special_filtered.txt"; then
      log "ERROR: Intersections found between lists"
      restore_backups
      exit 1
  fi

  # DNS checks
  log "Performing DNS checks..."
  if ! check_domains_parallel "${TMP_DIR}/main_filtered.txt" "$OUTPUT_FILE" || \
     ! check_domains_parallel "${TMP_DIR}/special_filtered.txt" "$OUTPUT_FILESPECIAL"; then
      log "ERROR: Error during DNS checks"
      restore_backups
      exit 1
  fi

  # Validate results
  if ! validate_results "$OUTPUT_FILE" "$OUTPUT_FILESPECIAL"; then
      log "ERROR: Results failed validation"
      restore_backups
      exit 1
  fi

  # Save results
  if ! save_results "$OUTPUT_FILE" "$OUTPUT_FILESPECIAL"; then
      log "ERROR: Failed to save results"
      restore_backups
      exit 1
  fi

  # Update gists only if valid results exist
  if [[ -s "$OUTPUT_FILE" ]] && [[ -s "$OUTPUT_FILESPECIAL" ]]; then
      if ! update_gists; then
          log "ERROR: Failed to update gists"
          exit 1
      fi
  else
      log "ERROR: Empty results, skipping gist update"
      restore_backups
      exit 1
  fi

  # Clean temporary files and backups
  cleanup
  rm -f "${OUTPUT_FILE}.bak" "${OUTPUT_FILESPECIAL}.bak"

  log "Processing completed successfully"
  log "Main list: $(wc -l < "$OUTPUT_FILE") domains"
  log "Special list: $(wc -l < "$OUTPUT_FILESPECIAL") domains"

  release_lock
}

{
  main "$@"
  exit 0  # Explicitly indicate successful completion
} || {
  error "Script terminated with error (code: $?)"
}
