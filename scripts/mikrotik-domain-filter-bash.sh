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

# Add state preservation
readonly STATE_DIR="${WORK_DIR}/state"
readonly PREVIOUS_STATE="${STATE_DIR}/previous_state.dat"

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
# declare -i TOTAL_DOMAINS=0

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

    if ! [[ ${#missing_files[@]} -eq 0 ]]; then
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
    if [[ -e /proc/$$fd/9 ]]; then
        flock -u 9
        exec 9>&-
        rm -f "$LOCK_FILE"
    else
        rm -f "$LOCK_FILE"
    fi
}

# Signal handling
trap 'log "Script interrupted"; trap_cleanup' INT TERM

init_directories() {
    log "Initialization started..."

    if ! mkdir -p "$STATE_DIR"; then
        error "Failed to create state directory"
    fi

    if ! chmod 755 "$STATE_DIR"; then
        log "WARNING: Failed to set permissions for state directory"
    else
        log "State directory created with correct permissions"
    fi

    # Create state file if doesn't exist
    if [[ ! -f "${STATE_DIR}/update_state.dat" ]]; then
        if ! touch "${STATE_DIR}/update_state.dat"; then
            log "WARNING: Failed to create state file"
        fi
        if ! chmod 644 "${STATE_DIR}/update_state.dat"; then
            log "WARNING: Failed to set permissions for state file"
        fi
    fi

    # Check and create all required directories with proper permissions
    local dirs=("$WORK_DIR" "$TMP_DIR" "$CACHE_DIR" "$STATE_DIR" "${TMP_DIR}/downloads")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if ! mkdir -p "$dir"; then
                error "Failed to create directory ${dir}"
            fi
            # Set proper permissions (rwxr-xr-x)
            if ! chmod 755 "$dir"; then
                log "WARNING: Failed to set permissions for ${dir}"
            fi
        fi
        if [[ ! -w "$dir" ]]; then
            error "No write permissions for ${dir}"
        fi
    done

    # Ensure proper ownership
    if [[ -n "$SUDO_USER" ]]; then
        if ! chown -R "$SUDO_USER:$SUDO_USER" "$TMP_DIR"; then
            log "WARNING: Failed to set ownership for ${TMP_DIR}"
        fi
    fi

    # Verify log file permissions
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        error "No write permissions for log directory"
    fi

    if [[ -f "$LOG_FILE" && ! -w "$LOG_FILE" ]]; then
        error "No write permissions for log file"
    fi

    log "Initialization completed successfully"
    return 0
}

# Function to clean up temporary files
cleanup() {
    log "Starting cleanup..."

    # Validate directory paths
    for dir in "$TMP_DIR" "$CACHE_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log "WARNING: Directory does not exist: $dir"
            continue
        fi
        if [[ "$dir" == "/" ]]; then
            log "ERROR: Invalid directory path: $dir"
            return 1
        fi
    done

    # Clean temporary directory
    if [[ -d "$TMP_DIR" && "$TMP_DIR" =~ ^${WORK_DIR}/tmp ]]; then
        log "Cleaning temporary directory..."

        # Create list of protected files
        local protected_files=(
            "*md5"
            "domain_registry.*"
            "previous_state.*"
            "update_state.dat"
            "*.backup"
        )

        # Build exclude pattern
        local exclude_pattern
        exclude_pattern=$(printf " ! -name '%s'" "${protected_files[@]}")

        # Remove files
        eval "find '$TMP_DIR' -type f $exclude_pattern -delete" || {
            log "WARNING: Failed to clean temporary files"
        }

        # Remove empty directories except protected ones
        find "$TMP_DIR" -type d -empty ! -name "downloads" ! -name "state" -delete 2>/dev/null || {
            log "WARNING: Failed to clean empty directories"
        }
    else
        log "WARNING: Invalid temporary directory path: $TMP_DIR"
        return 1
    fi

    # Clean old cache files
    if [[ -d "$CACHE_DIR" && "$CACHE_DIR" != "/" ]]; then
        log "Cleaning old cache files..."

        # Remove files older than 90 days
        find "$CACHE_DIR" -type f -name "*.cache" -mtime +90 -delete 2>/dev/null || {
            log "WARNING: Failed to clean old cache files"
        }

        # Check cache size and clean if needed
        local cache_size
        cache_size=$(du -sm "$CACHE_DIR" 2>/dev/null | cut -f1)
        if [[ -n "$cache_size" ]] && (( cache_size > 1024 )); then
            log "Cache size exceeds 1GB, cleaning oldest files..."
            find "$CACHE_DIR" -type f -name "*.cache" -printf '%T@ %p\n' | \
                sort -n | head -n 1000 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || {
                log "WARNING: Failed to clean large cache"
            }
        fi
    fi

    log "Cleanup completed"
    return 0
}

cleanup_invalid_cache() {
    log "Cleaning invalid cache entries..."
    find "$CACHE_DIR" -type f -name "*.cache" -exec sh -c '
        for f; do
            if ! grep -qE "^(valid|invalid)$" "$f"; then
                rm -f "$f"
            fi
        done
    ' sh {} +
}

log_cache_stats() {
    local total valid invalid
    total=$(find "$CACHE_DIR" -type f -name "*.cache" | wc -l)
    valid=$(grep -l "^valid$" "$CACHE_DIR"/*.cache 2>/dev/null | wc -l)
    invalid=$(grep -l "^invalid$" "$CACHE_DIR"/*.cache 2>/dev/null | wc -l)
    log "Cache stats - Total: $total, Valid: $valid, Invalid: $invalid"
}

handle_cache_error() {
    local domain=$1
    log "WARNING: Cache error for domain: $domain"
    rm -f "${CACHE_DIR}/${domain}.cache"
    return 1
}

# Enhanced trap handling
trap_cleanup() {
    local exit_code=$?
    log "Caught exit signal. Performing cleanup..."

    # Save current work if possible
    if [[ -f "${TMP_DIR}/main_filtered.txt" ]]; then
        if ! cp "${TMP_DIR}/main_filtered.txt" "${WORK_DIR}/main_filtered.backup" 2>/dev/null; then
            log "WARNING: Failed to save main list backup"
        fi
    fi

    if [[ -f "${WORK_DIR}/main_filtered.backup" ]]; then
        log "Saved main list backup"
    fi

    if [[ -f "${TMP_DIR}/special_filtered.txt" && -s "${TMP_DIR}/special_filtered.txt" ]]; then
        if ! cp "${TMP_DIR}/special_filtered.txt" "${WORK_DIR}/special_filtered.backup" 2>/dev/null; then
            log "WARNING: Failed to save special list backup"
        else
            log "Saved special list backup"
        fi
    fi

    cleanup
    release_lock

    log "Script terminated with exit code: ${exit_code}"
    exit "${exit_code}"
}

save_state() {
    local temp_state
    temp_state="${STATE_DIR}/state_$(date +%s).tmp"
    local main_md5 special_md5

    log "Saving state..."

    if ! [[ -d "$STATE_DIR" ]]; then
        if ! mkdir -p "$STATE_DIR"; then
            log "ERROR: Failed to create state directory"
            return 1
        fi
        if ! chmod 755 "$STATE_DIR"; then
            log "WARNING: Failed to set permissions for state directory"
        fi
    fi

    # Calculate MD5 sums with error checking
    if ! main_md5=$(md5sum "$OUTPUT_FILE" 2>/dev/null); then
        log "ERROR: Failed to calculate MD5 for main list"
        return 1
    fi

    if ! special_md5=$(md5sum "$OUTPUT_FILESPECIAL" 2>/dev/null); then
        log "ERROR: Failed to calculate MD5 for special list"
        return 1
    fi

    # Write to temporary file first
    if ! echo "${main_md5}" > "$temp_state" || ! echo "${special_md5}" >> "$temp_state"; then
        log "ERROR: Failed to write state data"
        rm -f "$temp_state"
        return 1
    fi

    # Set proper permissions
    if ! chmod 644 "$temp_state"; then
        log "WARNING: Failed to set permissions for state file"
    fi

    # Atomic move
    if ! mv "$temp_state" "$PREVIOUS_STATE"; then
        log "ERROR: Failed to update state file"
        rm -f "$temp_state"
        return 1
    fi

    log "State saved successfully"
    return 0
}

# Function to handle temporary files
handle_temp_file() {
    local prefix="$1"
    local suffix="${2:-tmp}"
    local temp_file

    if ! temp_file=$(mktemp "${TMP_DIR}/${prefix}.XXXXXX.${suffix}"); then
        log "ERROR: Failed to create temporary file with prefix ${prefix}"
        return 1
    fi

    if ! chmod 644 "$temp_file"; then
        log "WARNING: Failed to set permissions for ${temp_file}"
    fi

    echo "$temp_file"
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

    if [[ -f "$cache_file" ]]; then
        local cache_time
        cache_time=$(stat -c %Y "$cache_file")
        local current_time
        current_time=$(date +%s)
        if (( current_time - cache_time < 7776000 )); then
            local cache_status
            cache_status=$(cat "$cache_file")
            if [[ "$cache_status" != "valid" && "$cache_status" != "invalid" ]]; then
                log "WARNING: Invalid cache entry for $domain"
                rm -f "$cache_file"
            else
                [[ "$cache_status" == "valid" ]] && return 0
                return 1
            fi
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
        curl -sSL "https://publicsuffix.org/list/public_suffix_list.dat" | \
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

# Function to extract domains from various formats
extract_domains() {
    local input=$1
    local output=$2
    local temp_output="${TMP_DIR}/extracted_$(date +%s).tmp"

    log "Extracting domains from: $input"

    if ! [[ -f "$input" ]]; then
        log "ERROR: Input file does not exist: $input"
        return 1
    fi

    if ! [[ -r "$input" ]]; then
        log "ERROR: Cannot read input file: $input"
        return 1
    fi

    # Initialize temporary file with proper permissions
    if ! : > "$temp_output"; then
        log "ERROR: Failed to create temporary file"
        return 1
    fi

    if ! chmod 644 "$temp_output"; then
        log "WARNING: Failed to set permissions for temporary file"
    fi

    local processed=0
    local extracted=0

    while IFS= read -r line; do
        ((processed++))

        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Extract domain from different formats
        if [[ "$line" =~ ^[[:space:]]*-?[[:space:]]*(DOMAIN-SUFFIX|DOMAIN|DOMAIN-KEYWORD),(.+)$ ]]; then
            # Remove trailing comments and whitespace
            local domain="${BASH_REMATCH[2]%%#*}"
            domain=$(echo "$domain" | tr -d '[:space:]')

            if validate_domain "$domain"; then
                if ! echo "$domain" >> "$temp_output"; then
                    log "ERROR: Failed to write domain to temporary file"
                    rm -f "$temp_output"
                    return 1
                fi
                ((extracted++))
            fi
        elif [[ "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$ ]]; then
            if validate_domain "$line"; then
                if ! echo "$line" >> "$temp_output"; then
                    log "ERROR: Failed to write domain to temporary file"
                    rm -f "$temp_output"
                    return 1
                fi
                ((extracted++))
            fi
        fi

        # Progress logging for large files
        if (( processed % 10000 == 0 )); then
            log "Processed $processed lines, extracted $extracted domains"
        fi
    done < "$input"

    # Sort and deduplicate with error checking
    if ! sort -u "$temp_output" > "$output"; then
        log "ERROR: Failed to sort and deduplicate domains"
        rm -f "$temp_output"
        return 1
    fi

    rm -f "$temp_output"

    # Validate final output
    if ! [[ -s "$output" ]]; then
        log "WARNING: No domains were extracted"
        return 1
    fi

    local final_count
    final_count=$(wc -l < "$output")
    log "Extracted $final_count unique domains from $processed lines"

    return 0
}

# Function for initial filtering
initial_filter() {
    local input=$1
    local output=$2
    local temp_output="${TMP_DIR}/filtered_$(date +%s).tmp"

    log "Initial filtering of: $input"

    if ! [[ -f "$input" ]]; then
        log "ERROR: Input file does not exist: $input"
        return 1
    fi

    if ! [[ -r "$input" ]]; then
        log "ERROR: Cannot read input file: $input"
        return 1
    fi

    # Create temporary file with proper permissions
    if ! : > "$temp_output"; then
        log "ERROR: Failed to create temporary file"
        return 1
    fi

    if ! chmod 644 "$temp_output"; then
        log "WARNING: Failed to set permissions for temporary file"
    fi

    # Multi-stage filtering with error checking
    if ! grep -P '^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$' "$input" | \
         grep -v '^#' | \
         grep -v '^$' | \
         tr '[:upper:]' '[:lower:]' | \
         tr -d ' ' | \
         awk 'length <= 253' > "$temp_output"; then
        log "ERROR: Domain filtering failed"
        rm -f "$temp_output"
        return 1
    fi

    # Sort and deduplicate with error checking
    if ! sort -u "$temp_output" > "$output"; then
        log "ERROR: Failed to sort and deduplicate domains"
        rm -f "$temp_output"
        return 1
    fi

    rm -f "$temp_output"

    # Validate results
    if ! [[ -s "$output" ]]; then
        log "ERROR: No domains passed initial filtering"
        return 1
    fi

    local total
    total=$(wc -l < "$output")
    TOTAL_DOMAINS=$total
    log "Initially filtered domains: $total"

    return 0
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

    if ! [[ -f "$input" ]]; then
        log "ERROR: Input file does not exist: $input"
        return 1
    fi

    if ! mkdir -p "${output_dir}"/{second,regional,other}; then
        log "ERROR: Failed to create output directories"
        return 1
    fi

    local second_level="${output_dir}/second.txt"
    local regional="${output_dir}/regional.txt"
    local other="${output_dir}/other.txt"
    local base_domains="${output_dir}/base_domains.tmp"
    local domain_registry="${output_dir}/domain_registry.tmp"

    # Initialize files with proper permissions
    for file in "$second_level" "$regional" "$other" "$base_domains" "$domain_registry"; do
        if ! : > "$file"; then
            log "ERROR: Failed to create/clear file: $file"
            return 1
        fi
        if ! chmod 644 "$file"; then
            log "WARNING: Failed to set permissions for: $file"
        fi
    done

    # First pass - register domains
    while IFS= read -r domain; do
        local parts
        IFS='.' read -ra parts <<< "$domain"
        local levels=${#parts[@]}

        if [[ $levels -gt 4 ]]; then
            domain="${parts[-4]}.${parts[-3]}.${parts[-2]}.${parts[-1]}"
            levels=4
        fi

        if ! echo "$domain $levels" >> "$domain_registry"; then
            log "ERROR: Failed to write to domain registry"
            return 1
        fi
    done < "$input"

    # Second pass - classify domains
    while IFS=' ' read -r domain levels; do
        local parts
        IFS='.' read -ra parts <<< "$domain"

        if [[ $levels -eq 2 ]]; then
            if ! echo "$domain" >> "$second_level" || \
               ! echo "$domain" >> "$base_domains"; then
                log "ERROR: Failed to write second-level domain: $domain"
                return 1
            fi
        elif [[ $levels -eq 3 ]]; then
            local base_domain="${parts[-2]}.${parts[-1]}"
            if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                if ! echo "$domain" >> "$regional" || \
                   ! echo "$domain" >> "$base_domains"; then
                    log "ERROR: Failed to write regional domain: $domain"
                    return 1
                fi
            else
                if ! grep -Fxq "$base_domain" "$second_level"; then
                    if ! echo "$domain" >> "$other" || \
                       ! echo "$domain" >> "$base_domains"; then
                        log "ERROR: Failed to write other domain: $domain"
                        return 1
                    fi
                fi
            fi
        elif [[ $levels -eq 4 ]]; then
            local base_domain="${parts[-2]}.${parts[-1]}"
            local third_level="${parts[-3]}.${parts[-2]}.${parts[-1]}"

            if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                if ! grep -Fxq "$third_level" "$regional"; then
                    if ! echo "$domain" >> "$other" || \
                       ! echo "$domain" >> "$base_domains"; then
                        log "ERROR: Failed to write fourth-level domain: $domain"
                        return 1
                    fi
                fi
            else
                if ! grep -Fxq "$base_domain" "$second_level" && \
                   ! grep -Fxq "$third_level" "$other"; then
                    if ! echo "$domain" >> "$other" || \
                       ! echo "$domain" >> "$base_domains"; then
                        log "ERROR: Failed to write fourth-level domain: $domain"
                        return 1
                    fi
                fi
            fi
        fi
    done < "$domain_registry"

    # Sort and deduplicate with error checking
    for file in "$second_level" "$regional" "$other"; do
        if [[ -f "$file" ]]; then
            local temp_file="${file}.tmp"
            if ! sort -u "$file" > "$temp_file"; then
                log "ERROR: Failed to sort file: $file"
                rm -f "$temp_file"
                return 1
            fi
            if ! mv "$temp_file" "$file"; then
                log "ERROR: Failed to update sorted file: $file"
                rm -f "$temp_file"
                return 1
            fi
        fi
    done

    # Cleanup temporary files
    rm -f "$base_domains" "$domain_registry"

    # Validate results and generate statistics
    local second_count=0 regional_count=0 other_count=0

    if [[ -f "$second_level" ]]; then
        second_count=$(wc -l < "$second_level")
    fi
    if [[ -f "$regional" ]]; then
        regional_count=$(wc -l < "$regional")
    fi
    if [[ -f "$other" ]]; then
        other_count=$(wc -l < "$other")
    fi

    log "Classification results:"
    log "- Second-level domains: $second_count"
    log "- Regional domains: $regional_count"
    log "- Other domains: $other_count"

    # Verify we have at least some results
    if (( second_count + regional_count + other_count == 0 )); then
        log "ERROR: No domains classified"
        return 1
    fi

    return 0
}

# Function to prepare domains for DNS check
prepare_domains_for_dns_check() {
    local input_dir=$1
    local output=$2
    local temp_output="${output}.tmp"

    log "Preparing domains for DNS check..."

    if ! [[ -d "$input_dir" ]]; then
        log "ERROR: Input directory does not exist: $input_dir"
        return 1
    fi

    # Combine files with error checking
    if ! : > "$temp_output"; then
        log "ERROR: Failed to create temporary output file"
        return 1
    fi

    for file in "${input_dir}/second.txt" "${input_dir}/regional.txt"; do
        if [[ -f "$file" ]]; then
            if ! cat "$file" >> "$temp_output"; then
                log "ERROR: Failed to append file: $file"
                rm -f "$temp_output"
                return 1
            fi
        fi
    done

    # Sort and deduplicate
    if ! sort -u "$temp_output" > "$output"; then
        log "ERROR: Failed to sort and deduplicate domains"
        rm -f "$temp_output"
        return 1
    fi

    rm -f "$temp_output"

    # Validate result
    if ! [[ -s "$output" ]]; then
        log "ERROR: No domains prepared for DNS check"
        return 1
    fi

    local total
    total=$(wc -l < "$output")
    log "Prepared $total domains for DNS check"

    return 0
}

# Function to apply whitelist
apply_whitelist() {
    local input=$1
    local whitelist=$2
    local output=$3
    local temp_pattern="${TMP_DIR}/whitelist_pattern_$(date +%s).tmp"
    local temp_output="${TMP_DIR}/whitelist_filtered_$(date +%s).tmp"

    log "Applying whitelist to: $input"

    # Validate input files
    for file in "$input" "$whitelist"; do
        if ! [[ -f "$file" ]]; then
            log "ERROR: Required file does not exist: $file"
            return 1
        fi
        if ! [[ -r "$file" ]]; then
            log "ERROR: Cannot read file: $file"
            return 1
        fi
    done

    # Initialize temporary files
    for temp_file in "$temp_pattern" "$temp_output"; do
        if ! : > "$temp_file"; then
            log "ERROR: Failed to create temporary file: $temp_file"
            return 1
        fi
        if ! chmod 644 "$temp_file"; then
            log "WARNING: Failed to set permissions for: $temp_file"
        fi
    done

    # Process whitelist and create patterns
    while IFS= read -r domain; do
        local parts
        IFS='.' read -ra parts <<< "$domain"
        local levels=${#parts[@]}

        case $levels in
            2)
                # Second-level domain
                echo "^${domain}$" >> "$temp_pattern"
                echo "\.${domain}$" >> "$temp_pattern"
                ;;
            3)
                # Check if it's a regional domain
                local base_domain="${parts[-2]}.${parts[-1]}"
                if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                    echo "^${domain}$" >> "$temp_pattern"
                    echo "\.${domain}$" >> "$temp_pattern"
                else
                    echo "^${domain}$" >> "$temp_pattern"
                fi
                ;;
            4)
                # Only exact matches for fourth-level domains
                local base_domain="${parts[-2]}.${parts[-1]}"
                if grep -Fxq "$base_domain" "$PUBLIC_SUFFIX_FILE"; then
                    echo "^${domain}$" >> "$temp_pattern"
                fi
                ;;
        esac
    done < "$whitelist"

    # Apply whitelist patterns
    if [[ -s "$temp_pattern" ]]; then
        if ! grep -vf "$temp_pattern" "$input" > "$temp_output"; then
            log "ERROR: Failed to apply whitelist patterns"
            rm -f "$temp_pattern" "$temp_output"
            return 1
        fi
    else
        if ! cp "$input" "$temp_output"; then
            log "ERROR: Failed to copy input to temporary file"
            rm -f "$temp_pattern" "$temp_output"
            return 1
        fi
    fi

    # Final move to output
    if ! mv "$temp_output" "$output"; then
        log "ERROR: Failed to update output file"
        rm -f "$temp_pattern" "$temp_output"
        return 1
    fi

    rm -f "$temp_pattern"

    # Validate result
    local initial_count final_count
    initial_count=$(wc -l < "$input")
    final_count=$(wc -l < "$output")

    log "Whitelist applied: $initial_count -> $final_count domains"

    return 0
}

# Function to check intersections between lists
check_intersections() {
    local main_list=$1
    local special_list=$2
    local temp_intersect="${TMP_DIR}/intersections.tmp"

    log "Checking intersections between lists..."

    if ! [[ -f "$main_list" ]] || ! [[ -f "$special_list" ]]; then
        log "ERROR: One or both input files do not exist"
        return 1
    fi

    if ! [[ -s "$main_list" ]] || ! [[ -s "$special_list" ]]; then
        log "ERROR: One or both input files are empty"
        return 1
    fi

    # Create temporary file for intersections
    if ! : > "$temp_intersect"; then
        log "ERROR: Failed to create temporary file for intersections"
        return 1
    fi

    # Find intersections using comm
    if ! comm -12 <(sort "$main_list") <(sort "$special_list") > "$temp_intersect"; then
        log "ERROR: Failed to check intersections"
        rm -f "$temp_intersect"
        return 1
    fi

    # Check if we found any intersections
    if [[ -s "$temp_intersect" ]]; then
        log "WARNING: Found intersections between lists:"
        while IFS= read -r domain; do
            log "Duplicate domain: $domain"
        done < "$temp_intersect"
        rm -f "$temp_intersect"
        return 1
    fi

    rm -f "$temp_intersect"
    log "No intersections found between lists"
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
      response=$(curl -sSL --max-time 30 --retry 3 --retry-delay 2 "$source")

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
  if ! [[ -f "$main_list" ]]; then
      return 1
  fi

  if ! [[ -f "$special_list" ]]; then
      return 1
  fi

  # Check file size
  if ! [[ -s "$main_list" ]]; then
      return 1
  fi

  if ! [[ -s "$special_list" ]]; then
      return 1
  fi

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
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    log "Starting to save results..."

    # Validate input files
    for file in "$main_list" "$special_list"; do
        if ! [[ -f "$file" && -s "$file" ]]; then
            log "ERROR: Invalid or empty input file: $file"
            return 1
        fi
    done

    # Create temporary files
    local temp_main="${main_list}.${timestamp}.tmp"
    local temp_special="${special_list}.${timestamp}.tmp"
    local backup_main="${main_list}.backup"
    local backup_special="${special_list}.backup"

    # Create backups of current files
    for pair in "$main_list:$backup_main" "$special_list:$backup_special"; do
        IFS=':' read -r src dst <<< "$pair"
        if [[ -f "$src" ]]; then
            if ! cp "$src" "$dst"; then
                log "WARNING: Failed to create backup of $src"
            else
                chmod 644 "$dst" 2>/dev/null
            fi
        fi
    done

    # Validate and copy to temporary files
    for pair in "$main_list:$temp_main" "$special_list:$temp_special"; do
        IFS=':' read -r src dst <<< "$pair"

        # Count valid domains
        local valid_count=0
        while IFS= read -r domain; do
            if validate_domain "$domain"; then
                echo "$domain" >> "$dst"
                ((valid_count++))
            else
                log "WARNING: Invalid domain found: $domain"
            fi
        done < "$src"

        if [[ $valid_count -eq 0 ]]; then
            log "ERROR: No valid domains in $src"
            rm -f "$temp_main" "$temp_special"
            return 1
        fi
    done

    # Set proper permissions
    for file in "$temp_main" "$temp_special"; do
        if ! chmod 644 "$file"; then
            log "WARNING: Failed to set permissions for $file"
        fi
    done

    # Atomic moves
    if ! mv "$temp_main" "$main_list" || ! mv "$temp_special" "$special_list"; then
        log "ERROR: Failed to update result files"
        # Restore from backups
        for pair in "$backup_main:$main_list" "$backup_special:$special_list"; do
            IFS=':' read -r src dst <<< "$pair"
            [[ -f "$src" ]] && mv "$src" "$dst"
        done
        return 1
    fi

    # Clean up backups
    rm -f "$backup_main" "$backup_special"

    # Final validation
    local main_count special_count
    main_count=$(wc -l < "$main_list")
    special_count=$(wc -l < "$special_list")

    log "Results saved successfully:"
    log "- Main list: $main_count domains"
    log "- Special list: $special_count domains"

    return 0
}

# Function to update gists
update_gists() {
    [[ "$EXPORT_GISTS" != "true" ]] && return 0

    log "Starting gist update..."

    # Check requirements
    if ! command -v curl >/dev/null 2>&1; then
        log "ERROR: curl is required"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR: jq is required"
        return 1
    fi

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
                    } }" \
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
    local state_file="${STATE_DIR}/update_state.dat"
    local temp_dir="${TMP_DIR}/downloads"
    local current_md5="${temp_dir}/current_md5"
    local previous_md5="${temp_dir}/previous_md5"
    local update_needed=false

    log "Checking for updates..."

    if ! mkdir -p "$temp_dir"; then
        log "ERROR: Failed to create temporary directory"
        return 1
    fi

    if ! chmod 755 "$temp_dir"; then
        log "WARNING: Failed to set permissions for temporary directory"
    fi

    # Create files with proper permissions
    for file in "$current_md5" "$previous_md5"; do
        if ! touch "$file" 2>/dev/null; then
            log "ERROR: Cannot create file: ${file}"
            return 1
        fi
        if ! chmod 644 "$file" 2>/dev/null; then
            log "WARNING: Failed to set permissions for ${file}"
        fi
    done

    download_and_check() {
        local source=$1
        local temp_file
        temp_file="${temp_dir}/$(echo "$source" | md5sum | cut -d' ' -f1)"

        log "Downloading: $source"
        if ! curl -sSL --max-time 30 --retry 3 --retry-delay 2 "$source" -o "$temp_file"; then
            log "WARNING: Failed to download $source"
            return 1
        fi

        if ! [[ -s "$temp_file" ]]; then
            log "WARNING: Downloaded file is empty: $source"
            return 1
        fi

        local md5_sum
        if ! md5_sum=$(md5sum "$temp_file" | cut -d' ' -f1); then
            log "WARNING: Failed to calculate MD5 for $source"
            return 1
        fi

        if ! [[ $md5_sum =~ ^[a-f0-9]{32}$ ]]; then
            log "WARNING: Invalid MD5 format for $source"
            return 1
        fi

        if ! echo "${source} ${md5_sum}" >> "$current_md5"; then
            log "WARNING: Failed to write MD5 sums for $source"
            return 1
        fi

        return 0
    }

    # Process all source files
    local process_failed=false
    for source_file in "$SOURCES_FILE" "$SOURCESSPECIAL_FILE" "$WHITELIST_FILE"; do
        if [[ -f "$source_file" ]]; then
            while IFS= read -r source; do
                if [[ -z "$source" ]] || [[ "$source" == "#"* ]]; then
                    continue
                fi
                if ! download_and_check "$source"; then
                    process_failed=true
                    break 2
                fi
            done < "$source_file"
        fi
    done

    if [[ "$process_failed" == "true" ]]; then
        log "ERROR: Failed to process one or more sources"
        find "$temp_dir" -type f ! -name "*md5" -delete 2>/dev/null || true
        return 1
    fi

    # Compare current and previous states
    if [[ -f "$previous_md5" ]]; then
        local changed=false
        while IFS=' ' read -r source md5; do
            local prev_line
            prev_line=$(grep "^${source}" "$previous_md5" || echo "")

            if [[ -z "$prev_line" ]]; then
                changed=true
                log "Content changed for source: $source"
            else
                local prev_md5
                prev_md5=$(echo "$prev_line" | cut -d' ' -f2)

                if [[ "$md5" != "$prev_md5" ]]; then
                    changed=true
                    log "Content changed for source: $source"
                    log "Previous MD5: $prev_md5"
                    log "Current MD5: $md5"
                fi
            fi
        done < "$current_md5"

        if [[ "$changed" == "true" ]]; then
            update_needed=true
        fi
    else
        update_needed=true
        log "No previous state found, update needed"
    fi

    if [[ "$update_needed" == "true" ]]; then
        if ! cp "$current_md5" "$previous_md5"; then
            log "ERROR: Failed to update MD5 checksums"
            return 1
        fi

        if ! date +%s > "$state_file"; then
            log "WARNING: Failed to save update state"
        fi

        if ! chmod 644 "$state_file" 2>/dev/null; then
            log "WARNING: Failed to set permissions for state file"
        fi

        log "Update state saved"
    else
        # Force update if older than 24 hours
        if [[ -f "$state_file" ]]; then
            local last_update current_time
            last_update=$(cat "$state_file")
            current_time=$(date +%s)

            if (( current_time - last_update > 86400 )); then
                log "Forced update due to time threshold"
                update_needed=true
            fi
        fi
    fi

    # Cleanup but preserve MD5 files
    if ! find "$temp_dir" -type f ! -name "*md5" -delete 2>/dev/null; then
        log "WARNING: Failed to clean temporary files"
    fi

    return $(( update_needed == 1 ? 0 : 1 ))
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
    if ! check_required_files; then
        log "ERROR: Required files check failed"
        return 1
    fi

    # Initialize directories
    if ! init_directories; then
        log "ERROR: Failed to initialize directories"
        return 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        error "Missing required dependencies"
        return 1
    fi

    # Acquire lock
    if ! acquire_lock; then
        log "ERROR: Failed to acquire lock"
        return 1
    fi

    # Load public suffix list
    if ! load_public_suffix_list; then
        log "ERROR: Failed to load public suffix list"
        release_lock
        return 1
    fi

    log "Starting main processing..."

    # Check if update is needed
    if ! check_updates_needed; then
        log "No updates needed, exiting gracefully"
        cleanup
        cleanup_invalid_cache
        log_cache_stats
        release_lock
        return 0
    fi

    # Clean temporary files
    if ! cleanup; then
        log "ERROR: Cleanup failed"
        release_lock
        return 1
    fi

    # Initialize raw file paths
    local main_raw="${TMP_DIR}/main_raw.txt"
    local special_raw="${TMP_DIR}/special_raw.txt"
    local whitelist_raw="${TMP_DIR}/whitelist_raw.txt"

    log "Loading lists..."

    # Load main and special lists
    if ! load_lists "$SOURCES_FILE" "$main_raw"; then
        log "ERROR: Failed to load main list"
        release_lock
        return 1
    fi

    if ! load_lists "$SOURCESSPECIAL_FILE" "$special_raw"; then
        log "ERROR: Failed to load special list"
        release_lock
        return 1
    fi

    # Load whitelist if exists
    if [[ -f "$WHITELIST_FILE" ]]; then
        if ! load_lists "$WHITELIST_FILE" "$whitelist_raw"; then
            log "ERROR: Failed to load whitelist"
            release_lock
            return 1
        fi
    fi

    # Create backups of current files
    if [[ -f "$OUTPUT_FILE" ]]; then
        if ! cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"; then
            log "ERROR: Failed to create backup of main list"
            release_lock
            return 1
        fi
        log "Backup of main list created"
    fi

    if [[ -f "$OUTPUT_FILESPECIAL" ]]; then
        if ! cp "$OUTPUT_FILESPECIAL" "${OUTPUT_FILESPECIAL}.bak"; then
            log "ERROR: Failed to create backup of special list"
            release_lock
            return 1
        fi
        log "Backup of special list created"
    fi

    # Process main list
    log "Processing main list..."
    if ! extract_domains "$main_raw" "${TMP_DIR}/main_extracted.txt"; then
        log "ERROR: Failed to extract main domains"
        restore_backups
        release_lock
        return 1
    fi

    if ! initial_filter "$main_raw" "${TMP_DIR}/main_initial.txt"; then
        log "ERROR: Failed to filter main domains"
        restore_backups
        release_lock
        return 1
    fi

    if ! process_domains "${TMP_DIR}/main_initial.txt" "${TMP_DIR}/main"; then
        log "ERROR: Failed to process main domain list"
        restore_backups
        release_lock
        return 1
    fi

    if ! prepare_domains_for_dns_check "${TMP_DIR}/main" "${TMP_DIR}/main_filtered.txt"; then
        log "ERROR: Failed to prepare main domains for DNS check"
        restore_backups
        release_lock
        return 1
    fi

    # Process special list
    log "Processing special list..."
    if ! extract_domains "$special_raw" "${TMP_DIR}/special_extracted.txt" || \
       ! initial_filter "$special_raw" "${TMP_DIR}/special_initial.txt" || \
       ! process_domains "${TMP_DIR}/special_initial.txt" "${TMP_DIR}/special" || \
       ! prepare_domains_for_dns_check "${TMP_DIR}/special" "${TMP_DIR}/special_filtered.txt"; then
        log "ERROR: Failed to process special list"
        restore_backups
        release_lock
        return 1
    fi

    # Apply whitelist if exists
    if [[ -f "$whitelist_raw" ]]; then
        log "Applying whitelist..."
        if ! extract_domains "$whitelist_raw" "${TMP_DIR}/whitelist_extracted.txt" || \
           ! initial_filter "$whitelist_raw" "${TMP_DIR}/whitelist.txt" || \
           ! apply_whitelist "${TMP_DIR}/main_filtered.txt" "${TMP_DIR}/whitelist.txt" "${TMP_DIR}/main_filtered_clean.txt" || \
           ! apply_whitelist "${TMP_DIR}/special_filtered.txt" "${TMP_DIR}/whitelist.txt" "${TMP_DIR}/special_filtered_clean.txt"; then
            log "ERROR: Failed to apply whitelist"
            restore_backups
            release_lock
            return 1
        fi

        if ! mv "${TMP_DIR}/main_filtered_clean.txt" "${TMP_DIR}/main_filtered.txt" || \
           ! mv "${TMP_DIR}/special_filtered_clean.txt" "${TMP_DIR}/special_filtered.txt"; then
            log "ERROR: Failed to update filtered files"
            restore_backups
            release_lock
            return 1
        fi
    fi

    # Check for intersections
    if ! check_intersections "${TMP_DIR}/main_filtered.txt" "${TMP_DIR}/special_filtered.txt"; then
        log "ERROR: Intersections found between lists"
        restore_backups
        release_lock
        return 1
    fi

    # Perform DNS checks
    log "Performing DNS checks..."
    if ! check_domains_parallel "${TMP_DIR}/main_filtered.txt" "$OUTPUT_FILE" || \
       ! check_domains_parallel "${TMP_DIR}/special_filtered.txt" "$OUTPUT_FILESPECIAL"; then
        log "ERROR: DNS checks failed"
        restore_backups
        release_lock
        return 1
    fi

    # Validate and save results
    if ! validate_results "$OUTPUT_FILE" "$OUTPUT_FILESPECIAL"; then
        log "ERROR: Results failed validation"
        restore_backups
        release_lock
        return 1
    fi

    if ! save_results "$OUTPUT_FILE" "$OUTPUT_FILESPECIAL"; then
        log "ERROR: Failed to save results"
        restore_backups
        release_lock
        return 1
    fi

    # Update gists if results exist and are valid
    if [[ -s "$OUTPUT_FILE" ]] && [[ -s "$OUTPUT_FILESPECIAL" ]]; then
        if ! update_gists; then
            log "ERROR: Failed to update gists"
            release_lock
            return 1
        fi
    else
        log "ERROR: Empty results, skipping gist update"
        restore_backups
        release_lock
        return 1
    fi

    # Cleanup
    if ! cleanup; then
        log "WARNING: Cleanup failed"
    fi

    # Remove backups
    rm -f "${OUTPUT_FILE}.bak" "${OUTPUT_FILESPECIAL}.bak"

    log "Processing completed successfully"
    log "Main list: $(wc -l < "$OUTPUT_FILE") domains"
    log "Special list: $(wc -l < "$OUTPUT_FILESPECIAL") domains"

    release_lock
    return 0
}

# Main execution
if ! main "$@"; then
    error "Script terminated with error"
    exit 1
fi

trap_cleanup
exit 0
