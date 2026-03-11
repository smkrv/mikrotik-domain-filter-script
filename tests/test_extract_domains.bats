#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "extract_domains: plain domain list" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf 'example.com\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$output")" -eq 2 ]
}

@test "extract_domains: skips comments and empty lines" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf '# comment\nexample.com\n\n# another\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$output")" -eq 2 ]
}

@test "extract_domains: handles Clash DOMAIN-SUFFIX format" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf 'DOMAIN-SUFFIX,example.com\nDOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$output")" -eq 2 ]
}

@test "extract_domains: handles Clash format with leading dash" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf '  - DOMAIN-SUFFIX,example.com\n  - DOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$output")" -eq 2 ]
}

@test "extract_domains: deduplicates domains" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf 'example.com\nexample.com\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$output")" -eq 2 ]
}

@test "extract_domains: empty input produces empty output" {
    local input="${TMP_DIR}/input.txt"
    local output="${TMP_DIR}/output.txt"
    printf '' > "$input"
    run extract_domains "$input" "$output"
    [ "$status" -eq 0 ]
}
