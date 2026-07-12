#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "prepare_domains_for_dns_check: merges, sorts and deduplicates" {
    local input_dir="${TMP_DIR}/classified"
    local result_file="${TMP_DIR}/dns_input.txt"
    mkdir -p "$input_dir"
    printf 'b.com\na.com\n' > "${input_dir}/second.txt"
    printf 'x.co.uk\n' > "${input_dir}/regional.txt"
    printf 'a.com\nc.com\n' > "${input_dir}/other.txt"

    run prepare_domains_for_dns_check "$input_dir" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 4 ]
    [ "$(head -n 1 "$result_file")" = "a.com" ]
    grep -Fxq "a.com" "$result_file"
    grep -Fxq "b.com" "$result_file"
    grep -Fxq "c.com" "$result_file"
    grep -Fxq "x.co.uk" "$result_file"
}

@test "prepare_domains_for_dns_check: skips missing files" {
    local input_dir="${TMP_DIR}/classified"
    local result_file="${TMP_DIR}/dns_input.txt"
    mkdir -p "$input_dir"
    # Only second.txt is present; regional.txt and other.txt are absent.
    printf 'example.com\n' > "${input_dir}/second.txt"

    run prepare_domains_for_dns_check "$input_dir" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file")" -eq 1 ]
    grep -Fxq "example.com" "$result_file"
}

@test "prepare_domains_for_dns_check: empty result returns error" {
    local input_dir="${TMP_DIR}/classified_empty"
    local result_file="${TMP_DIR}/dns_input.txt"
    # Directory exists but contains none of second/regional/other.
    mkdir -p "$input_dir"

    run prepare_domains_for_dns_check "$input_dir" "$result_file"
    [ "$status" -eq 1 ]
}

@test "prepare_domains_for_dns_check: missing directory returns error" {
    local input_dir="${TMP_DIR}/does_not_exist"
    local result_file="${TMP_DIR}/dns_input.txt"

    run prepare_domains_for_dns_check "$input_dir" "$result_file"
    [ "$status" -eq 1 ]
}
