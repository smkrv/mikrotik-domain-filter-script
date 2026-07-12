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

@test "validate_domain: accepts hyphen inside a label" {
    # a-b.com passes the general regex AND the hyphen rule: the hyphen is
    # neither at a label boundary nor adjacent to a dot.
    run validate_domain "a-b.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: rejects label ending with hyphen" {
    # example-.com passes the general regex but is rejected by the dedicated
    # hyphen rule -(\.|$): a hyphen may not sit at the end of a label.
    run validate_domain "example-.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects label starting with hyphen after a dot" {
    # sub.-example.com passes the general regex but is rejected by the hyphen
    # rule (^|\.)-: a label may not begin with a hyphen.
    run validate_domain "sub.-example.com"
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
