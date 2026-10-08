#!/usr/bin/env bats
setup() {
    load test_helpers
    export DNS_MAX_RETRIES=1 DNS_TIMEOUT=1 DNS_MAX_FAILURE_PERCENT=5 CACHE_INVALID_TTL_DAYS=1
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
@test "DNS parallel: transient failure within threshold is skipped" {
    for i in {1..25}; do printf 'domain%s.example.com\n' "$i"; done > "$TMP_DIR/input"
    check_domain() { [[ "$1" = domain25.example.com ]] && return 2; return 0; }
    run check_domains_parallel "$TMP_DIR/input" "$TMP_DIR/output"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMP_DIR/output")" -eq 24 ]
    sed '/^domain25\.example\.com$/d' "$TMP_DIR/input" | sort > "$TMP_DIR/expected"
    cmp "$TMP_DIR/expected" "$TMP_DIR/output"
    grep -Fq 'domain25.example.com' "$LOG_FILE"
}
@test "DNS parallel: transient failure above threshold preserves existing output" {
    printf 'example.com\nother.com\n' > "$TMP_DIR/input"
    printf 'previous.com\n' > "$TMP_DIR/output"
    check_domain() { [[ "$1" = example.com ]] && return 2; return 0; }
    run check_domains_parallel "$TMP_DIR/input" "$TMP_DIR/output"
    [ "$status" -eq 2 ]
    [ "$(cat "$TMP_DIR/output")" = previous.com ]
    grep -Fq 'ERROR: DNS checks inconclusive: 1 of 2 domains failed transiently (limit 5%)' "$LOG_FILE"
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
@test "DNS_MAX_FAILURE_PERCENT above 100 falls back to 5" {
    run env WORK_DIR="$WORK_DIR" DNS_MAX_FAILURE_PERCENT=101 bash -c \
        'source "$1"; printf "value=%s\n" "$DNS_MAX_FAILURE_PERCENT"' _ \
        "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: Invalid numeric value for DNS_MAX_FAILURE_PERCENT, using default"* ]]
    [[ "$output" == *"value=5"* ]]
}
