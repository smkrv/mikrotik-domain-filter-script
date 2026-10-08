#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
    printf 'https://example.com/main\n' > "$SOURCES_FILE"
    printf 'https://example.com/special\n' > "$SOURCESSPECIAL_FILE"
    printf 'com\norg\n' > "$PUBLIC_SUFFIX_FILE"
    mkdir -p "$WORK_DIR/stubs"
    touch "$WORK_DIR/fail_dns"
    cat > "$WORK_DIR/stubs/curl" <<'STUB'
#!/bin/bash
out='' url=''
while (($#)); do
    case "$1" in
        -o|--output) out=$2; shift ;;
        https://*) url=$1 ;;
    esac
    shift
done
case "$url" in
    https://example.com/main)
        for i in {1..20}; do printf 'd%s.example.com\n' "$i"; done > "$out" ;;
    https://example.com/special) printf 'special.example.org\n' > "$out" ;;
    *cloudflare-dns.com*)
        if [[ "$url" == *'name=d20.example.com&'* ]]; then
            printf 'attempt\n' >> "$WORK_DIR/retries"
            [[ ! -f "$WORK_DIR/fail_dns" ]] || exit 28
        fi
        printf '{"Status":0}\n' ;;
    *) exit 22 ;;
esac
STUB
    chmod +x "$WORK_DIR/stubs/curl"
}

# PR contract: at most 5% may be skipped, but skipped names retry next run.
# One transient out of twenty is exactly 5%, so it must not abort publication.
@test "CLI retries tolerated DNS failure with unchanged sources and clears retry after recovery" {
    for attempt in 1 2; do
        run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" \
            DNS_MAX_RETRIES=1 DNS_MAX_FAILURE_PERCENT=5 \
            bash "$BATS_TEST_DIRNAME/../bin/mikrotik-domain-filter"
        [ "$status" -eq 0 ]
        [ "$(wc -l < "$OUTPUT_FILE")" -eq 19 ]
        [ "$(cat "$OUTPUT_FILESPECIAL")" = special.example.org ]
        [ ! -e "$CACHE_DIR/d20.example.com.cache" ]
        [ "$(wc -l < "$WORK_DIR/retries")" -eq "$attempt" ]
    done
    mv "$WORK_DIR/fail_dns" "$WORK_DIR/recovered"
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" \
        DNS_MAX_RETRIES=1 DNS_MAX_FAILURE_PERCENT=5 \
        bash "$BATS_TEST_DIRNAME/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$OUTPUT_FILE")" -eq 20 ]
    [ "$(wc -l < "$WORK_DIR/retries")" -eq 3 ]
    [ ! -e "$STATE_DIR/dns_retry.pending" ]
    cp "$STATE_DIR/update_state.dat" "$WORK_DIR/success_timestamp"
    run env PATH="$WORK_DIR/stubs:$PATH" WORK_DIR="$WORK_DIR" \
        DNS_MAX_RETRIES=1 DNS_MAX_FAILURE_PERCENT=5 \
        bash "$BATS_TEST_DIRNAME/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$WORK_DIR/retries")" -eq 3 ]
    [[ "$output" != *"Starting DNS checks:"* ]]
    cmp "$STATE_DIR/update_state.dat" "$WORK_DIR/success_timestamp"
}
