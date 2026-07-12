#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "check_intersections: exact match only, substring domains survive" {
    # Regression guard for the grep -vxFf fix. special contains example.com;
    # main also has myexample.com and sub-example.com which merely contain
    # "example.com" as a substring. With the old grep -vFf (no -x) both were
    # wrongly removed. Whole-line matching must keep them.
    local main="${TMP_DIR}/ci_main.txt"
    local special="${TMP_DIR}/ci_special.txt"
    printf 'example.com\nmyexample.com\nsub-example.com\n' > "$main"
    printf 'example.com\n' > "$special"

    run check_intersections "$main" "$special"
    [ "$status" -eq 0 ]
    ! grep -Fxq "example.com" "$main"
    grep -Fxq "myexample.com" "$main"
    grep -Fxq "sub-example.com" "$main"
}

@test "check_intersections: full overlap empties main with code 0" {
    local main="${TMP_DIR}/ci_main.txt"
    local special="${TMP_DIR}/ci_special.txt"
    printf 'example.com\n' > "$main"
    printf 'example.com\n' > "$special"

    run check_intersections "$main" "$special"
    [ "$status" -eq 0 ]
    [ ! -s "$main" ]
}

@test "check_intersections: no overlap leaves main unchanged" {
    local main="${TMP_DIR}/ci_main.txt"
    local special="${TMP_DIR}/ci_special.txt"
    printf 'a.com\nb.com\n' > "$main"
    printf 'c.com\n' > "$special"

    run check_intersections "$main" "$special"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$main")" -eq 2 ]
    grep -Fxq "a.com" "$main"
    grep -Fxq "b.com" "$main"
}

@test "check_intersections: empty main returns error" {
    local main="${TMP_DIR}/ci_main.txt"
    local special="${TMP_DIR}/ci_special.txt"
    printf '' > "$main"
    printf 'example.com\n' > "$special"

    run check_intersections "$main" "$special"
    [ "$status" -eq 1 ]
}
