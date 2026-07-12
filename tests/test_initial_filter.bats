#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "initial_filter: lowercases domains" {
    local input="${TMP_DIR}/if_input.txt"
    local result_file="${TMP_DIR}/if_output.txt"
    printf 'EXAMPLE.COM\n' > "$input"
    run initial_filter "$input" "$result_file"
    [ "$status" -eq 0 ]
    grep -Fxq "example.com" "$result_file"
    ! grep -Fxq "EXAMPLE.COM" "$result_file"
}

@test "initial_filter: drops comment and empty lines" {
    local input="${TMP_DIR}/if_input.txt"
    local result_file="${TMP_DIR}/if_output.txt"
    printf '# comment\nexample.com\n\ngoogle.com\n' > "$input"
    run initial_filter "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
    ! grep -q "comment" "$result_file"
}

@test "initial_filter: drops domains longer than 253 chars" {
    local input="${TMP_DIR}/if_input.txt"
    local result_file="${TMP_DIR}/if_output.txt"
    local long_domain
    long_domain=$(printf '%0.sa' {1..300}).com
    printf '%s\nexample.com\n' "$long_domain" > "$input"
    run initial_filter "$input" "$result_file"
    [ "$status" -eq 0 ]
    grep -Fxq "example.com" "$result_file"
    ! grep -Fxq "$long_domain" "$result_file"
}

@test "initial_filter: sorts and deduplicates" {
    local input="${TMP_DIR}/if_input.txt"
    local result_file="${TMP_DIR}/if_output.txt"
    printf 'b.com\na.com\na.com\n' > "$input"
    run initial_filter "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    [ "$(head -n 1 "$result_file")" = "a.com" ]
    grep -Fxq "b.com" "$result_file"
}

@test "initial_filter: empty result returns error" {
    local input="${TMP_DIR}/if_input.txt"
    local result_file="${TMP_DIR}/if_output.txt"
    printf '# only a comment\n' > "$input"
    run initial_filter "$input" "$result_file"
    [ "$status" -eq 1 ]
}
