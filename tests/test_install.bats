#!/usr/bin/env bats

setup() {
    REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    TEST_ROOT=$(mktemp -d)
    PACKAGE_ROOT="$TEST_ROOT/package"
    mkdir -p "$PACKAGE_ROOT/bin" "$PACKAGE_ROOT/config"
    cp "$REPO_ROOT/Makefile" "$REPO_ROOT/VERSION" "$PACKAGE_ROOT/"
    cp "$REPO_ROOT/bin/mikrotik-domain-filter" "$PACKAGE_ROOT/bin/"
    cp "$REPO_ROOT"/config/*.example "$PACKAGE_ROOT/config/"
    INSTALL_PREFIX="$TEST_ROOT/prefix"
    CONFIG_DIR="$TEST_ROOT/config space"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

# Contract: installation reports the release version independently of caller cwd.
@test "install embeds release version" {
    # A package version differs from the script fallback, as after a release bump.
    printf '9.8.7\n' > "$PACKAGE_ROOT/VERSION"
    run make -C "$PACKAGE_ROOT" install PREFIX="$INSTALL_PREFIX" SYSCONFDIR="$CONFIG_DIR"
    [ "$status" -eq 0 ]
    run "$INSTALL_PREFIX/bin/mikrotik-domain-filter" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"9.8.7"* ]]
}

# Contract: installed default uses SYSCONFDIR, with explicit WORK_DIR taking precedence.
@test "install sets default config directory and honors WORK_DIR" {
    run make -C "$PACKAGE_ROOT" install PREFIX="$INSTALL_PREFIX" SYSCONFDIR="$CONFIG_DIR"
    [ "$status" -eq 0 ]
    run env -u WORK_DIR bash -c 'source "$1"; printf "%s\n" "$WORK_DIR"' _ "$INSTALL_PREFIX/bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [ "$output" = "$CONFIG_DIR" ]
    run env WORK_DIR="$TEST_ROOT/override" bash -c 'source "$1"; printf "%s\n" "$WORK_DIR"' _ "$INSTALL_PREFIX/bin/mikrotik-domain-filter"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_ROOT/override" ]
}

@test "setup preserves edited configuration" {
    run make -C "$PACKAGE_ROOT" setup
    [ "$status" -eq 0 ]
    printf 'https://example.com/custom.txt\n' > "$PACKAGE_ROOT/work/sources.txt"
    run make -C "$PACKAGE_ROOT" setup
    [ "$status" -eq 0 ]
    [ "$(cat "$PACKAGE_ROOT/work/sources.txt")" = 'https://example.com/custom.txt' ]
}

@test "make -C run uses target directory even with inherited PWD" {
    cat > "$PACKAGE_ROOT/bin/mikrotik-domain-filter" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$WORK_DIR"
SCRIPT
    chmod +x "$PACKAGE_ROOT/bin/mikrotik-domain-filter"
    run env PWD=/unrelated make -C "$PACKAGE_ROOT" run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PACKAGE_ROOT/work"* ]]
    [[ "$output" != *'/unrelated/work'* ]]
}
