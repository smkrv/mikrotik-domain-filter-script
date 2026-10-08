#!/usr/bin/env bats
setup() { load test_helpers; load_script_functions; }
@test "save publishes staged content to public outputs" {
    printf 'old.example.com\n' > "$OUTPUT_FILE"
    printf 'old.example.org\n' > "$OUTPUT_FILESPECIAL"
    printf 'new.example.com\n' > "$TMP_DIR/main"
    printf 'new.example.org\n' > "$TMP_DIR/special"
    save_results "$TMP_DIR/main" "$TMP_DIR/special"
    [ "$(cat "$OUTPUT_FILE")" = new.example.com ]
    [ "$(cat "$OUTPUT_FILESPECIAL")" = new.example.org ]
}
@test "failed second rename on first publication restores absence" {
    printf 'example.com\n' > "$TMP_DIR/main"
    printf 'example.org\n' > "$TMP_DIR/special"
    mv() { [[ $2 != "$OUTPUT_FILESPECIAL" ]] || return 1; command mv "$@"; }
    run save_results "$TMP_DIR/main" "$TMP_DIR/special"
    [ "$status" -ne 0 ]
    [ ! -e "$OUTPUT_FILE" ]
    [ ! -e "$OUTPUT_FILESPECIAL" ]
}
@test "TERM between publication renames restores old pair or original absence" {
    local mode
    for mode in existing absent; do
        rm -f "$OUTPUT_FILE" "$OUTPUT_FILESPECIAL"
        if [[ $mode == existing ]]; then
            printf 'old.example.com\n' > "$OUTPUT_FILE"
            printf 'old.example.org\n' > "$OUTPUT_FILESPECIAL"
        fi
        run env WORK_DIR="$WORK_DIR" bash -c '
            source "$1"
            trap "trap_cleanup 143" TERM
            trap "trap_cleanup \$?" EXIT
            acquire_lock || exit 1
            mkdir -p "$TMP_DIR"
            printf "new.example.com\n" > "$TMP_DIR/main"
            printf "new.example.org\n" > "$TMP_DIR/special"
            signal_sent=false
            mv() {
                command mv "$@" || return
                if [[ $2 == "$OUTPUT_FILE" && $signal_sent == false ]]; then
                    signal_sent=true
                    kill -TERM "$BASHPID"
                fi
            }
            save_results "$TMP_DIR/main" "$TMP_DIR/special"
        ' _ "${BATS_TEST_DIRNAME}/../bin/mikrotik-domain-filter"
        [ "$status" -eq 143 ]
        if [[ $mode == existing ]]; then
            [ "$(cat "$OUTPUT_FILE")" = old.example.com ]
            [ "$(cat "$OUTPUT_FILESPECIAL")" = old.example.org ]
        else
            [ ! -e "$OUTPUT_FILE" ]
            [ ! -e "$OUTPUT_FILESPECIAL" ]
        fi
    done
}
