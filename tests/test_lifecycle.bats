#!/usr/bin/env bats
setup() { load test_helpers; load_script_functions; }
@test "help and version preserve existing logs" {
    printf 'keep\n' > "$LOG_FILE"
    run env WORK_DIR="$WORK_DIR" bash "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter" --help
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG_FILE")" = keep ]
}
@test "shell environment is validated without an env file" {
    run env WORK_DIR="$WORK_DIR" MAX_PARALLEL_JOBS=0 DNS_TIMEOUT=abc CACHE_TTL_DAYS=08 bash -c 'source "$1"; printf "%s %s %s" "$MAX_PARALLEL_JOBS" "$DNS_TIMEOUT" "$CACHE_TTL_DAYS"' _ "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5 10 90" ]]
}
@test "CRLF quoted env values are trimmed and secrets are not exported" {
    printf 'EXPORT_GISTS = "true"\r\nGITHUB_TOKEN = "test-token"\r\nDNS_TIMEOUT = 12\r\n' > "$WORK_DIR/.env"
    run env WORK_DIR="$WORK_DIR" GITHUB_TOKEN=inherited bash -c 'source "$1"; printf "%s %s %s\n" "$EXPORT_GISTS" "$DNS_TIMEOUT" "$GITHUB_TOKEN"; env | grep "^GITHUB_TOKEN=" && exit 9; exit 0' _ "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true 12 test-token"* ]]
}
@test "sourcing leaves errexit and traps unchanged" {
    run env WORK_DIR="$WORK_DIR" bash -c 'trap ":" TERM; before=$(trap -p TERM); source "$1"; [[ $- != *e* ]] && [[ $(trap -p TERM) == "$before" ]]' _ "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
}
@test "cleanup and release preserve the lock inode and lock ownership" {
    acquire_lock
    local inode
    inode=$(stat -c %i "$LOCK_FILE")
    cleanup
    [ -f "$LOCK_FILE" ]
    run flock -n "$LOCK_FILE" true
    [ "$status" -ne 0 ]
    release_lock
    [ "$(stat -c %i "$LOCK_FILE")" = "$inode" ]
}
@test "Github failures are status checked and bounded" {
    curl() {
        local failed=false connected=false bounded=false arg
        for arg in "$@"; do
            [[ $arg != --fail ]] || failed=true
            [[ $arg != --connect-timeout ]] || connected=true
            [[ $arg != --max-time ]] || bounded=true
        done
        [[ $failed == true && $connected == true && $bounded == true ]] && return 22
        printf '{"id":"unexpected"}\n'
    }
    run github_api_request PATCH https://api.github.com/gists/example ''
    [ "$status" -eq 22 ]
    [ -z "$(find "$TMP_DIR" -name 'auth.*' -print)" ]
}
@test "release terminates descendants before unlocking" {
    acquire_lock
    bash -c 'sleep 300 & echo $! > "$1"; wait' _ "$WORK_DIR/child" &
    local worker=$! child
    while [[ ! -s "$WORK_DIR/child" ]]; do sleep 0.01; done
    child=$(cat "$WORK_DIR/child")
    release_lock
    run ps -o stat= -p "$child"
    kill "$child" 2>/dev/null || true
    [[ "$status" -ne 0 || "$output" == Z* ]]
    wait "$worker" 2>/dev/null || true
}
@test "SIGTERM waits for active descendants and releases a reusable lock" {
    env WORK_DIR="$WORK_DIR" bash -c '
        source "$1"
        trap "trap_cleanup 143" TERM
        trap "trap_cleanup \$?" EXIT
        acquire_lock || exit 1
        bash -c '\''sleep 300 & echo $! > "$1/descendant"; touch "$1/ready"; wait'\'' _ "$WORK_DIR" &
        wait
    ' _ "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter" > "$WORK_DIR/signal.log" 2>&1 &
    local parent=$! child rc=0 attempt
    for attempt in {1..100}; do
        [[ ! -f "$WORK_DIR/ready" ]] || break
        kill -0 "$parent" 2>/dev/null || break
        sleep 0.01
    done
    [ -f "$WORK_DIR/ready" ]
    child=$(cat "$WORK_DIR/descendant")
    run flock -n "$LOCK_FILE" true
    [ "$status" -ne 0 ]
    kill -TERM "$parent"
    wait "$parent" || rc=$?
    [ "$rc" -eq 143 ]
    run ps -o stat= -p "$child"
    kill "$child" 2>/dev/null || true
    [[ "$status" -ne 0 || "$output" == Z* ]]
    run flock -n "$LOCK_FILE" true
    [ "$status" -eq 0 ]
    [ -f "$LOCK_FILE" ]
}
@test "cache eviction with spaces cannot remove a sibling sentinel" {
    local victim="$WORK_DIR/sentinel" spaced="$CACHE_DIR/cache with spaces.cache"
    printf 'keep\n' > "$victim"
    printf 'valid\n' > "$spaced"
    # Spaces are legal in configured paths; GNU tools must retain filenames.
    # A crafted basename puts the absolute sibling path in xargs token position.
    local nested="$CACHE_DIR/evict $WORK_DIR"
    mkdir -p "$nested"
    printf 'valid\n' > "$nested/sentinel.cache"
    printf 'keep\n' > "$WORK_DIR/sentinel.cache"
    du() { printf '2048\t%s\n' "$CACHE_DIR"; }
    cleanup
    [ "$(cat "$victim")" = keep ]
    [ "$(cat "$WORK_DIR/sentinel.cache")" = keep ]
}
