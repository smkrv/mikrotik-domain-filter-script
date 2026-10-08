#!/usr/bin/env bats
setup() {
    load test_helpers
    load_script_functions
    printf 'co.uk\ncom\n' > "$PUBLIC_SUFFIX_FILE"
    touch -d '10 days ago' "$PUBLIC_SUFFIX_FILE"
}

@test "PSL HTTP failure preserves the previous suffixes and whitelist policy" {
    curl() {
        local target='' fail=false
        while (($#)); do
            case "$1" in
                -o) target=$2; shift ;;
                -f|--fail|-fsSL) fail=true ;;
            esac
            shift
        done
        [[ "$fail" == true ]] && return 22
        printf '<html>503 unavailable</html>\n' > "$target"
    }
    load_public_suffix_list
    [ "$(cat "$PUBLIC_SUFFIX_FILE")" = $'co.uk\ncom' ]
    printf 'sub.example.co.uk\n' > "$TMP_DIR/input"
    printf 'example.co.uk\n' > "$TMP_DIR/whitelist"
    apply_whitelist "$TMP_DIR/input" "$TMP_DIR/whitelist" "$TMP_DIR/result"
    [ ! -s "$TMP_DIR/result" ]
}

@test "PSL HTTP 200 error body does not replace the previous suffixes" {
    curl() {
        while (($#)); do
            if [[ "$1" == -o ]]; then
                printf '<html>Temporary failure</html>\n' > "$2"
                return 0
            fi
            shift
        done
        return 1
    }
    load_public_suffix_list
    [ "$(cat "$PUBLIC_SUFFIX_FILE")" = $'co.uk\ncom' ]
}
