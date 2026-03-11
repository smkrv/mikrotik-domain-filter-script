#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "extract_domains: plain domain list" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf 'example.com\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
}

@test "extract_domains: skips comments and empty lines" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '# comment\nexample.com\n\n# another\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
}

@test "extract_domains: handles Clash DOMAIN-SUFFIX format" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf 'DOMAIN-SUFFIX,example.com\nDOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
}

@test "extract_domains: handles Clash format with leading dash" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '  - DOMAIN-SUFFIX,example.com\n  - DOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
}

@test "extract_domains: deduplicates domains" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf 'example.com\nexample.com\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
}

@test "extract_domains: empty input returns error" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 1 ]
}
