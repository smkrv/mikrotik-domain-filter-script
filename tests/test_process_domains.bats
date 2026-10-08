#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
    # Create a minimal PSL file
    printf 'com\norg\nnet\nco.uk\nnet.pl\nco.jp\n' > "$PUBLIC_SUFFIX_FILE"
}

@test "process_domains: standalone subdomain goes to other.txt" {
    local input="${TMP_DIR}/input.txt"
    local output_dir="${TMP_DIR}/classified"

    # api.stripe.com is 3-level; stripe.com is NOT in input
    # So api.stripe.com should go to other.txt
    printf 'api.stripe.com\nexample.com\n' > "$input"

    run process_domains "$input" "$output_dir"
    [ "$status" -eq 0 ]
    [ -f "${output_dir}/other.txt" ]
    grep -Fxq "api.stripe.com" "${output_dir}/other.txt"
}

@test "process_domains: parent classified before child suppresses child" {
    local input="${TMP_DIR}/input.txt"
    local output_dir="${TMP_DIR}/classified2"

    # Both example.com and api.example.com in input (alphabetical order)
    # After level-sort, example.com (level 2) comes first
    # api.example.com should be suppressed (parent already in second_level)
    printf 'api.example.com\nexample.com\n' > "$input"

    process_domains "$input" "$output_dir"
    local rc=$?
    [ "$rc" -eq 0 ]

    grep -Fxq "example.com" "${output_dir}/second.txt"
    # api.example.com should NOT appear in other.txt (parent suppresses it)
    run grep -Fxq "api.example.com" "${output_dir}/other.txt" 2>/dev/null
    [ "$status" -eq 1 ]
}

@test "process_domains: regional domain classified correctly" {
    local input="${TMP_DIR}/input.txt"
    local output_dir="${TMP_DIR}/classified"

    printf 'youtube.co.uk\n' > "$input"

    run process_domains "$input" "$output_dir"
    [ "$status" -eq 0 ]
    grep -Fxq "youtube.co.uk" "${output_dir}/regional.txt"
}

@test "process_domains: empty input returns error" {
    local input="${TMP_DIR}/input_empty.txt"
    local output_dir="${TMP_DIR}/classified_empty"

    printf '' > "$input"

    run process_domains "$input" "$output_dir"
    [ "$status" -eq 1 ]
}

@test "process_domains: preserves every label before whitelist" {
    printf 'a.b.c.example.com\nother.com\n' > "$TMP_DIR/deep"
    printf 'a.b.c.example.com\n' > "$TMP_DIR/whitelist"
    process_domains "$TMP_DIR/deep" "$TMP_DIR/classified"
    grep -Fxq a.b.c.example.com "$TMP_DIR/classified/other.txt"
    prepare_domains_for_dns_check "$TMP_DIR/classified" "$TMP_DIR/prepared"
    apply_whitelist "$TMP_DIR/prepared" "$TMP_DIR/whitelist" "$TMP_DIR/result"
    [ "$(cat "$TMP_DIR/result")" = other.com ]
}
