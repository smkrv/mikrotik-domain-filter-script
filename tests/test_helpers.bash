#!/usr/bin/env bash
# Load script functions for testing

# Source the main script's functions without executing main
load_script_functions() {
    # Create a temporary modified script that doesn't execute main
    local temp_script
    temp_script=$(mktemp)
    sed -e '/^parse_arguments "\$@"/,$d' -e 's/^set -e$//' "$(dirname "$BATS_TEST_DIRNAME")/bin/mikrotik-domain-filter" > "$temp_script"
    # Set required variables
    WORK_DIR=$(mktemp -d)
    export WORK_DIR
    export TMP_DIR="${WORK_DIR}/tmp"
    export CACHE_DIR="${WORK_DIR}/cache"
    export STATE_DIR="${WORK_DIR}/state"
    export LOG_FILE="${WORK_DIR}/script.log"
    export PUBLIC_SUFFIX_FILE="${WORK_DIR}/public_suffix_list.dat"
    mkdir -p "$TMP_DIR" "$CACHE_DIR" "$STATE_DIR"
    touch "$LOG_FILE"
    source "$temp_script"
    rm -f "$temp_script"
}

teardown() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}
