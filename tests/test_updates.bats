#!/usr/bin/env bats
setup() {
    load test_helpers; load_script_functions
    printf 'https://example.com/main\nhttps://example.com/removed\n' > "$SOURCES_FILE"
    printf 'https://example.com/special\n' > "$SOURCESSPECIAL_FILE"
    curl() {
        local target='' url='' arg
        while (($#)); do
            arg=$1; shift
            if [[ $arg == -o ]]; then target=$1; shift; elif [[ $arg == https://* ]]; then url=$arg; fi
        done
        printf '%s\n' "$url" >> "$WORK_DIR/calls"
        [[ $url != *failed* ]] || return 22
        printf 'example.com\n' > "$target"
    }
}
@test "update check leaves persistent state uncommitted" {
    check_updates_needed
    [ ! -s "$STATE_DIR/update_state.dat" ]
    [ ! -s "$TMP_DIR/downloads/previous_md5" ]
}
@test "removed URL changes full manifest" {
    check_updates_needed
    cp "$TMP_DIR/downloads/current_md5" "$TMP_DIR/downloads/previous_md5"
    date +%s > "$STATE_DIR/update_state.dat"
    printf 'example.com\n' > "$OUTPUT_FILE"
    printf 'example.org\n' > "$OUTPUT_FILESPECIAL"
    run check_updates_needed
    [ "$status" -eq 1 ]
    printf 'https://example.com/main\n' > "$SOURCES_FILE"
    run check_updates_needed
    [ "$status" -eq 0 ]
}
@test "one failed source does not block successful sources" {
    printf 'https://example.com/failed\nhttps://example.com/main\n' > "$SOURCES_FILE"
    run check_updates_needed
    [ "$status" -eq 0 ]
}

@test "sources are fetched once per run" {
    check_updates_needed
    load_lists "$SOURCES_FILE" "$TMP_DIR/raw"
    [ "$(wc -l < "$WORK_DIR/calls")" -eq 3 ]
}
@test "failed timestamp commit leaves previous manifest unchanged" {
    mkdir -p "$TMP_DIR/downloads"
    printf 'old\n' > "$TMP_DIR/downloads/previous_md5"
    printf 'new\n' > "$TMP_DIR/downloads/current_md5"
    printf '123\n' > "$STATE_DIR/update_state.dat"
    mv() { [[ $1 != "$STATE_DIR/update_state.pending" ]] || return 1; command mv "$@"; }
    run commit_update_state
    [ "$status" -ne 0 ]
    [ "$(cat "$TMP_DIR/downloads/previous_md5")" = old ]
    [ "$(cat "$STATE_DIR/update_state.dat")" = 123 ]
}
@test "zero byte public output forces processing despite equal manifest" {
    check_updates_needed
    cp "$TMP_DIR/downloads/current_md5" "$TMP_DIR/downloads/previous_md5"
    date +%s > "$STATE_DIR/update_state.dat"
    : > "$OUTPUT_FILE"
    printf 'example.org\n' > "$OUTPUT_FILESPECIAL"
    run check_updates_needed
    [ "$status" -eq 0 ]
}
