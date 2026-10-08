#!/usr/bin/env bats
setup() {
    load test_helpers
    export DNS_MAX_RETRIES=1 DNS_TIMEOUT=1 CACHE_INVALID_TTL_DAYS=1
    load_script_functions
}
@test "DNS: NOERROR without A retains suffix domain" {
    curl() { printf '{"Status":0,"Answer":[]}'; }
    run check_domain example.com
    [ "$status" -eq 0 ]
    [ "$(cat "$CACHE_DIR/example.com.cache")" = valid ]
}
@test "DNS: AAAA answer retains domain" {
    curl() { printf '{"Status":0,"Answer":[{"type":28,"data":"::1"}]}'; }
    run check_domain example.com
    [ "$status" -eq 0 ]
}
@test "DNS: NXDOMAIN caches authoritative invalid" {
    curl() { printf '{"Status":3}'; }
    run check_domain example.com
    [ "$status" -eq 1 ]
    [ "$(cat "$CACHE_DIR/example.com.cache")" = nxdomain ]
}
@test "DNS: transport and HTTP failure never caches invalid" {
    curl() { return 22; }
    run check_domain example.com
    [ "$status" -eq 2 ]
    [ ! -e "$CACHE_DIR/example.com.cache" ]
}
@test "DNS: SERVFAIL never caches invalid" {
    curl() { printf '{"Status":2}'; }
    run check_domain example.com
    [ "$status" -eq 2 ]
    [ ! -e "$CACHE_DIR/example.com.cache" ]
}
@test "DNS: malformed response is transient" {
    curl() { printf 'bad gateway'; }
    run check_domain example.com
    [ "$status" -eq 2 ]
    [ ! -e "$CACHE_DIR/example.com.cache" ]
}
@test "DNS: negative cache expires after one day" {
    printf nxdomain > "$CACHE_DIR/example.com.cache"
    touch -d '2 days ago' "$CACHE_DIR/example.com.cache"
    curl() { printf '{"Status":0}'; }
    run check_domain example.com
    [ "$status" -eq 0 ]
}
@test "DNS parallel: transient preserves existing output and fails" {
    printf 'example.com\nother.com\n' > "$TMP_DIR/input"
    printf 'previous.com\n' > "$TMP_DIR/output"
    check_domain() { [[ "$1" = example.com ]] && return 2; return 0; }
    run check_domains_parallel "$TMP_DIR/input" "$TMP_DIR/output"
    [ "$status" -eq 2 ]
    [ "$(cat "$TMP_DIR/output")" = previous.com ]
}
@test "DNS parallel: unexpected worker failure propagates" {
    printf 'example.com\nother.com\n' > "$TMP_DIR/input"
    check_domain() { [[ "$1" = example.com ]] && return 7; return 0; }
    run check_domains_parallel "$TMP_DIR/input" "$TMP_DIR/output"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP_DIR/output" ]
}

@test "DNS: legacy invalid cache is rechecked immediately after upgrade" {
    printf invalid > "$CACHE_DIR/example.com.cache"
    curl() { printf '{"Status":0}'; }
    run check_domain example.com
    [ "$status" -eq 0 ]
    [ "$(cat "$CACHE_DIR/example.com.cache")" = valid ]
}
