#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
    # Create a minimal PSL file
    printf 'com\norg\nnet\nco.uk\n' > "$PUBLIC_SUFFIX_FILE"
}

@test "apply_whitelist: 5-level domain is whitelisted" {
    local input="${TMP_DIR}/wl_input1.txt"
    local whitelist="${TMP_DIR}/wl_list1.txt"
    local result_file="${TMP_DIR}/wl_output1.txt"

    printf 'a.b.c.example.com\nother.com\n' > "$input"
    printf 'a.b.c.example.com\n' > "$whitelist"

    run apply_whitelist "$input" "$whitelist" "$result_file"
    [ "$status" -eq 0 ]
    ! grep -Fxq "a.b.c.example.com" "$result_file"
    grep -Fxq "other.com" "$result_file"
}

@test "apply_whitelist: 4-level non-PSL domain is whitelisted" {
    local input="${TMP_DIR}/wl_input2.txt"
    local whitelist="${TMP_DIR}/wl_list2.txt"
    local result_file="${TMP_DIR}/wl_output2.txt"

    printf 'a.b.example.com\nother.com\n' > "$input"
    printf 'a.b.example.com\n' > "$whitelist"

    run apply_whitelist "$input" "$whitelist" "$result_file"
    [ "$status" -eq 0 ]
    ! grep -Fxq "a.b.example.com" "$result_file"
    grep -Fxq "other.com" "$result_file"
}

@test "apply_whitelist: 2-level domain whitelists itself and subdomains" {
    local input="${TMP_DIR}/wl_input3.txt"
    local whitelist="${TMP_DIR}/wl_list3.txt"
    local result_file="${TMP_DIR}/wl_output3.txt"

    printf 'example.com\nsub.example.com\nother.org\n' > "$input"
    printf 'example.com\n' > "$whitelist"

    run apply_whitelist "$input" "$whitelist" "$result_file"
    [ "$status" -eq 0 ]
    ! grep -Fxq "example.com" "$result_file"
    ! grep -Fxq "sub.example.com" "$result_file"
    grep -Fxq "other.org" "$result_file"
}

@test "apply_whitelist: empty whitelist passes all domains through" {
    local input="${TMP_DIR}/wl_input4.txt"
    local whitelist="${TMP_DIR}/wl_list4.txt"
    local result_file="${TMP_DIR}/wl_output4.txt"

    printf 'example.com\nother.com\n' > "$input"
    printf '' > "$whitelist"

    run apply_whitelist "$input" "$whitelist" "$result_file"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$result_file" | tr -d ' ')" -eq 2 ]
}
