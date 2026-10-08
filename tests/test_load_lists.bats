#!/usr/bin/env bats
setup() { load test_helpers; load_script_functions; }
@test "comments cannot contribute domains" {
    printf 'https://example.com/list\n' > "$SOURCES_FILE"
    curl() { while [[ $1 != -o ]]; do shift; done; printf '# see tracker-docs.net\nads.example.com # cdn.partner.org\n' > "$2"; }
    load_lists "$SOURCES_FILE" "$TMP_DIR/raw"
    [ "$(cat "$TMP_DIR/raw")" = ads.example.com ]
}
@test "comment-only optional whitelist succeeds empty" {
    printf '# optional\n' > "$WHITELIST_FILE"
    load_lists "$WHITELIST_FILE" "$TMP_DIR/raw"
    [ ! -s "$TMP_DIR/raw" ]
}
@test "configured unavailable whitelist fails" {
    printf 'https://example.com/list\n' > "$WHITELIST_FILE"
    curl() { return 22; }
    run load_lists "$WHITELIST_FILE" "$TMP_DIR/raw"
    [ "$status" -ne 0 ]
}
