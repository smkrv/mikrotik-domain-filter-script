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
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
}

@test "extract_domains: skips comments and empty lines" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '# comment\nexample.com\n\n# another\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
    ! grep -q "comment" "$result_file"
}

@test "extract_domains: handles Clash DOMAIN-SUFFIX format" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf 'DOMAIN-SUFFIX,example.com\nDOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
}

@test "extract_domains: handles Clash format with leading dash" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '  - DOMAIN-SUFFIX,example.com\n  - DOMAIN,google.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
}

@test "extract_domains: deduplicates domains" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf 'example.com\nexample.com\ngoogle.com\n' > "$input"
    run extract_domains "$input" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 2 ]
    grep -Fxq "example.com" "$result_file"
    grep -Fxq "google.com" "$result_file"
}

@test "extract_domains: empty input reports no domains separately from IO failure" {
    local input="${TMP_DIR}/input.txt"
    local result_file="${TMP_DIR}/output.txt"
    printf '' > "$input"
    run extract_domains "$input" "$result_file"
    # Whitelist policy permits no-domain status 2; IO failures remain status 1.
    [ "$status" -eq 2 ]
    [ ! -s "$result_file" ]
}

@test "extract_domains: punycode TLD survives plain and rule inputs" {
    printf 'example.xn--p1ai\nDOMAIN-SUFFIX,other.xn--p1ai\n' > "$TMP_DIR/idn"
    run extract_domains "$TMP_DIR/idn" "$TMP_DIR/result"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP_DIR/result")" = $'example.xn--p1ai\nother.xn--p1ai' ]
}
