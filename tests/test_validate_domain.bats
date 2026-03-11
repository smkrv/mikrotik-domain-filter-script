#!/usr/bin/env bats

setup() {
    load test_helpers
    load_script_functions
}

@test "validate_domain: valid second-level domain" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: valid subdomain" {
    run validate_domain "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: valid regional domain" {
    run validate_domain "example.co.uk"
    [ "$status" -eq 0 ]
}

@test "validate_domain: rejects empty string" {
    run validate_domain ""
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain starting with dot" {
    run validate_domain ".example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain with double dots" {
    run validate_domain "example..com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain starting with hyphen" {
    run validate_domain "-example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain over 253 chars" {
    local long_domain
    long_domain=$(printf '%0.sa' {1..250}).com
    run validate_domain "$long_domain"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects single-label domain" {
    run validate_domain "localhost"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain with spaces" {
    run validate_domain "example .com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects path traversal attempt" {
    run validate_domain "../../etc/passwd"
    [ "$status" -eq 1 ]
}
