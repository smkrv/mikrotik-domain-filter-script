#!/usr/bin/env bats

setup() {
    load test_helpers
}

@test "Gist export updates main when special Gist ID is absent" {
    export EXPORT_GISTS=true GITHUB_TOKEN=test-token
    export GIST_ID_MAIN=0123456789abcdef0123456789abcdef
    unset GIST_ID_SPECIAL
    load_script_functions
    printf 'main.example.com\n' > "$TMP_DIR/main"
    printf 'special.example.com\n' > "$TMP_DIR/special"
    github_api_request() {
        local id=${2##*/}
        printf '%s\n' "$id" >> "$WORK_DIR/gist_ids"
        printf '{"id":"%s"}\n' "$id"
    }

    run update_gists "$TMP_DIR/main" "$TMP_DIR/special"
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK_DIR/gist_ids")" = "$GIST_ID_MAIN" ]
    [[ "$output" == *"Skipping Gist update for filtered_domains_special_mikrotik.txt: no Gist ID configured"* ]]
}

@test "Gist export requires at least one Gist ID" {
    export EXPORT_GISTS=true GITHUB_TOKEN=test-token
    unset GIST_ID_MAIN GIST_ID_SPECIAL
    load_script_functions
    printf 'main.example.com\n' > "$TMP_DIR/main"
    printf 'special.example.com\n' > "$TMP_DIR/special"

    run update_gists "$TMP_DIR/main" "$TMP_DIR/special"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Gist export requires a token and at least one Gist ID"* ]]
}

# An invalid provided ID is a configuration error, not an optional missing ID.
@test "Gist export rejects an invalid configured ID before publishing either list" {
    export EXPORT_GISTS=true GITHUB_TOKEN=test-token
    export GIST_ID_MAIN=0123456789abcdef0123456789abcdef
    export GIST_ID_SPECIAL=invalid-special-id
    load_script_functions
    printf 'main.example.com\n' > "$TMP_DIR/main"
    printf 'special.example.org\n' > "$TMP_DIR/special"
    github_api_request() {
        printf '%s\n' "$2" >> "$WORK_DIR/gist_calls"
        printf '{"id":"%s"}\n' "${2##*/}"
    }
    run update_gists "$TMP_DIR/main" "$TMP_DIR/special"
    [ "$status" -ne 0 ]
    [ ! -e "$WORK_DIR/gist_calls" ]
}

@test "Gist export rejects an unmatched quote in a configured dotenv ID" {
    export EXPORT_GISTS=true GITHUB_TOKEN=test-token
    export GIST_ID_MAIN=0123456789abcdef0123456789abcdef
    unset GIST_ID_SPECIAL
    WORK_DIR=$(mktemp -d)
    export WORK_DIR
    printf '%s\n' 'GIST_ID_SPECIAL="unfinished' > "$WORK_DIR/.env"
    chmod 600 "$WORK_DIR/.env"
    run bash -c '
        source "$1"
        mkdir -p "$TMP_DIR"
        printf "main.example.com\n" > "$TMP_DIR/main"
        printf "special.example.org\n" > "$TMP_DIR/special"
        github_api_request() {
            printf "%s\n" "$2" >> "$WORK_DIR/gist_calls"
            printf "{\"id\":\"%s\"}\n" "${2##*/}"
        }
        update_gists "$TMP_DIR/main" "$TMP_DIR/special"
    ' _ "$BATS_TEST_DIRNAME/../bin/mikrotik-domain-filter"
    [ "$status" -ne 0 ]
    [ ! -e "$WORK_DIR/gist_calls" ]
}
