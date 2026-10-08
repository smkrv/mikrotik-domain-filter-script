#!/usr/bin/env bats
setup() {
    load test_helpers; load_script_functions
    printf 'https://example.com/main\n' > "$SOURCES_FILE"
    printf 'https://example.com/special\n' > "$SOURCESSPECIAL_FILE"
    printf 'old.example.com\n' > "$OUTPUT_FILE"
    printf 'old.example.org\n' > "$OUTPUT_FILESPECIAL"
    printf '123\n' > "$STATE_DIR/update_state.dat"
    check_dependencies() { :; }
    load_public_suffix_list() { :; }
    check_updates_needed() { mkdir -p "$TMP_DIR/downloads"; printf 'pending\n' > "$TMP_DIR/downloads/current_md5"; }
    load_lists() { printf 'new.example.com\n' > "$2"; }
    process_domain_list() { cp "$2" "$TMP_DIR/${3}_filtered.txt"; }
    check_intersections() { :; }
    check_domains_parallel() { cp "$1" "$2"; }
}
@test "failed second DNS stage preserves both public outputs and update state" {
    check_domains_parallel() {
        if [[ $1 == *special* ]]; then
            printf "%s" "$(cat "$OUTPUT_FILE")" > "$WORK_DIR/observed"
            return 2
        fi
        cp "$1" "$2"
    }
    run main
    [ "$status" -ne 0 ]
    [ "$(cat "$WORK_DIR/observed")" = old.example.com ]
    [ "$(cat "$OUTPUT_FILE")" = old.example.com ]
    [ "$(cat "$OUTPUT_FILESPECIAL")" = old.example.org ]
    [ "$(cat "$STATE_DIR/update_state.dat")" = 123 ]
}
@test "failed gist publication preserves outputs and state" {
    update_gists() { return 1; }
    run main
    [ "$status" -ne 0 ]
    [ "$(cat "$OUTPUT_FILE")" = old.example.com ]
    [ "$(cat "$STATE_DIR/update_state.dat")" = 123 ]
}
@test "tolerated invalid rows are removed before publication" {
    check_domains_parallel() { printf 'example.com\nbad..domain\n' > "$2"; }
    update_gists() { :; }
    main
    [ "$(cat "$OUTPUT_FILE")" = example.com ]
    [ "$(cat "$OUTPUT_FILESPECIAL")" = example.com ]
}

@test "CLI commits successful inputs, skips unchanged, and retries transient failure" {
    mkdir -p "$WORK_DIR/stubs"
    printf 'com\norg\n' > "$PUBLIC_SUFFIX_FILE"
    cat > "$WORK_DIR/stubs/curl" <<'STUB'
#!/bin/bash
out='' url='' domain=''
while (($#)); do
    case $1 in
        -o|--output) out=$2; shift ;;
        https://*) url=$1 ;;
    esac
    shift
done
printf '%s\n' "$url" >> "$WORK_DIR/http_calls"
case "$url" in
    https://example.com/main) if [[ -n "$out" ]]; then printf 'main.example.com\n' > "$out"; else printf 'main.example.com\n'; fi ;;
    https://example.com/special) if [[ -n "$out" ]]; then printf 'special.example.org\n' > "$out"; else printf 'special.example.org\n'; fi ;;
    *cloudflare-dns.com*)
        if [[ -f "$WORK_DIR/transient" ]]; then exit 28; fi
        printf '{"Status":0,"Answer":[{"type":1,"data":"192.0.2.1"}]}\n'
        ;;
    *) exit 22 ;;
esac
STUB
    chmod +x "$WORK_DIR/stubs/curl"
    # Real CLI, real pipeline and persistent cache; only HTTP is replaced.
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" DNS_MAX_RETRIES=1 bash "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [ "$(cat "$OUTPUT_FILE")" = main.example.com ]
    [ "$(cat "$OUTPUT_FILESPECIAL")" = special.example.org ]
    cp "$STATE_DIR/update_state.dat" "$WORK_DIR/old_state"
    cp "$TMP_DIR/downloads/previous_md5" "$WORK_DIR/old_manifest"
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" DNS_MAX_RETRIES=1 bash "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    cmp "$STATE_DIR/update_state.dat" "$WORK_DIR/old_state"
    [ "$(wc -l < "$WORK_DIR/http_calls")" -eq 6 ]
    # A changed source adds a never-cached domain, then transport fails.
    sed -i 's/main.example.com/new.example.com/' "$WORK_DIR/stubs/curl"
    touch "$WORK_DIR/transient"
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" DNS_MAX_RETRIES=1 bash "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -ne 0 ]
    [ "$(cat "$OUTPUT_FILE")" = main.example.com ]
    [ "$(cat "$OUTPUT_FILESPECIAL")" = special.example.org ]
    cmp "$STATE_DIR/update_state.dat" "$WORK_DIR/old_state"
    cmp "$TMP_DIR/downloads/previous_md5" "$WORK_DIR/old_manifest"
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" DNS_MAX_RETRIES=1 bash "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -ne 0 ]
    cmp "$STATE_DIR/update_state.dat" "$WORK_DIR/old_state"
}
@test "whitelist extraction IO failure aborts instead of dropping policy" {
    printf 'https://example.com/whitelist\n' > "$WHITELIST_FILE"
    mktemp() { [[ $1 != "$TMP_DIR/extracted_"* ]] || return 1; command mktemp "$@"; }
    run main
    [ "$status" -ne 0 ]
    [ "$(cat "$OUTPUT_FILE")" = old.example.com ]
    [ "$(cat "$STATE_DIR/update_state.dat")" = 123 ]
}
@test "all-invalid staging is rejected before any Gist publication" {
    check_domains_parallel() { printf 'bad..domain\n' > "$2"; }
    update_gists() { touch "$WORK_DIR/gist_called"; }
    run main
    [ "$status" -ne 0 ]
    [ ! -e "$WORK_DIR/gist_called" ]
    [ "$(cat "$OUTPUT_FILE")" = old.example.com ]
    [ "$(cat "$STATE_DIR/update_state.dat")" = 123 ]
}
