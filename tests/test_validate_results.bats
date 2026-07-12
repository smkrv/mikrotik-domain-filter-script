#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "validate_results: two valid lists pass" {
    local main="${TMP_DIR}/vr_main.txt"
    local special="${TMP_DIR}/vr_special.txt"
    printf 'example.com\ngoogle.com\n' > "$main"
    printf 'test.org\n' > "$special"

    run validate_results "$main" "$special"
    [ "$status" -eq 0 ]
}

@test "validate_results: missing special file returns error" {
    local main="${TMP_DIR}/vr_main.txt"
    local special="${TMP_DIR}/vr_missing.txt"
    printf 'example.com\n' > "$main"

    run validate_results "$main" "$special"
    [ "$status" -eq 1 ]
}

@test "validate_results: empty main file returns error" {
    local main="${TMP_DIR}/vr_main.txt"
    local special="${TMP_DIR}/vr_special.txt"
    printf '' > "$main"
    printf 'test.org\n' > "$special"

    run validate_results "$main" "$special"
    [ "$status" -eq 1 ]
}

@test "validate_results: more than 10 invalid domains returns error" {
    local main="${TMP_DIR}/vr_main.txt"
    local special="${TMP_DIR}/vr_special.txt"
    # 11 invalid domains (double dots fail validate_domain) trips the >10 guard.
    printf '%.0sbad..domain\n' {1..11} > "$main"
    printf 'test.org\n' > "$special"

    run validate_results "$main" "$special"
    [ "$status" -eq 1 ]
}

@test "validate_results: up to 10 invalid domains only warns" {
    local main="${TMP_DIR}/vr_main.txt"
    local special="${TMP_DIR}/vr_special.txt"
    # Exactly 10 invalid domains stays under the >10 guard: WARNING, not error.
    printf '%.0sbad..domain\n' {1..10} > "$main"
    printf 'test.org\n' > "$special"

    run validate_results "$main" "$special"
    [ "$status" -eq 0 ]
}
