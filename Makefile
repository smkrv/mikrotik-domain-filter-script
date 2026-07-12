# Mikrotik Domain Filter Script
# https://github.com/smkrv/mikrotik-domain-filter-script

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Version from VERSION file
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")

# Installation paths
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SYSCONFDIR ?= /etc/mikrotik-domain-filter

# Script name
SCRIPT_NAME := mikrotik-domain-filter

# Colors for output (real escape bytes: plain echo does not interpret \033)
CYAN := $(shell printf '\033[36m')
GREEN := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RED := $(shell printf '\033[31m')
RESET := $(shell printf '\033[0m')

.PHONY: help version install uninstall check deps setup run clean test lint \
        bump-patch bump-minor bump-major

## help: Show this help message
help:
	@echo ""
	@echo "$(CYAN)Mikrotik Domain Filter Script v$(VERSION)$(RESET)"
	@echo ""
	@echo "$(GREEN)Usage:$(RESET)"
	@echo "  make <target>"
	@echo ""
	@echo "$(GREEN)Targets:$(RESET)"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/## /  /' | column -t -s ':'
	@echo ""

## version: Show current version
version:
	@echo "$(VERSION)"

## install: Install script to system (requires sudo)
install: check
	@echo "$(CYAN)Installing $(SCRIPT_NAME) v$(VERSION)...$(RESET)"
	@install -d $(DESTDIR)$(BINDIR)
	@install -m 755 bin/$(SCRIPT_NAME) $(DESTDIR)$(BINDIR)/$(SCRIPT_NAME)
	@echo "$(GREEN)✓ Installed to $(BINDIR)/$(SCRIPT_NAME)$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: Create config directory and copy example files:$(RESET)"
	@echo "  sudo mkdir -p $(SYSCONFDIR)"
	@echo "  sudo cp config/*.example $(SYSCONFDIR)/"
	@echo "  cd $(SYSCONFDIR) && sudo rename 's/\.example$$//' *.example"

## uninstall: Remove script from system (requires sudo)
uninstall:
	@echo "$(CYAN)Uninstalling $(SCRIPT_NAME)...$(RESET)"
	@rm -f $(DESTDIR)$(BINDIR)/$(SCRIPT_NAME)
	@echo "$(GREEN)✓ Removed $(BINDIR)/$(SCRIPT_NAME)$(RESET)"
	@echo "$(YELLOW)Note: Config directory $(SYSCONFDIR) was not removed$(RESET)"

## check: Verify script syntax
check:
	@echo "$(CYAN)Checking script syntax...$(RESET)"
	@bash -n bin/$(SCRIPT_NAME) && echo "$(GREEN)✓ Syntax OK$(RESET)"

## deps: Check dependencies (same set as the script's runtime check)
deps:
	@echo "$(CYAN)Checking dependencies...$(RESET)"
	@missing=0; \
	for dep in curl jq awk grep sort flock find md5sum comm; do \
		command -v $$dep >/dev/null 2>&1 || { echo "$(RED)✗ $$dep not found$(RESET)"; missing=1; }; \
	done; \
	[ $$missing -eq 0 ] || exit 1
	@echo "$(GREEN)✓ All dependencies found$(RESET)"

## setup: Create local working directory with config files
setup:
	@echo "$(CYAN)Setting up local working directory...$(RESET)"
	@mkdir -p work/{tmp,cache,state}
	@cp config/sources.txt.example work/sources.txt
	@cp config/sources_special.txt.example work/sources_special.txt
	@cp config/sources_whitelist.txt.example work/sources_whitelist.txt
	@echo "$(GREEN)✓ Created work/ directory with config files$(RESET)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(RESET)"
	@echo "  1. Edit work/sources.txt with your domain list URLs"
	@echo "  2. Edit work/sources_special.txt for special domains"
	@echo "  3. Edit work/sources_whitelist.txt for whitelisted domains"
	@echo "  4. Run: make run"

## run: Run the script with local work directory
run: check
	@echo "$(CYAN)Running $(SCRIPT_NAME) v$(VERSION)...$(RESET)"
	@WORK_DIR="$(PWD)/work" bin/$(SCRIPT_NAME)

## clean: Clean temporary and cache files
clean:
	@echo "$(CYAN)Cleaning temporary files...$(RESET)"
	@rm -rf work/tmp/* work/cache/* 2>/dev/null || true
	@echo "$(GREEN)✓ Cleaned$(RESET)"

# test does not depend on deps: runtime tools (flock etc.) are not needed
# to run the bats suite, and the script checks them itself at startup
## test: Run smoke test and bats suite
test: check
	@echo "$(CYAN)Running tests...$(RESET)"
	@bin/$(SCRIPT_NAME) --version
	@command -v bats >/dev/null 2>&1 || { echo "$(RED)✗ bats not installed (apt-get install bats / brew install bats-core)$(RESET)"; exit 1; }
	@bats tests/
	@echo "$(GREEN)✓ All tests passed$(RESET)"

## lint: Run shellcheck linter (same severity as CI)
lint:
	@echo "$(CYAN)Running shellcheck...$(RESET)"
	@command -v shellcheck >/dev/null 2>&1 || { echo "$(RED)✗ shellcheck not installed$(RESET)"; exit 1; }
	@shellcheck --severity=warning --shell=bash bin/$(SCRIPT_NAME) && echo "$(GREEN)✓ No issues found$(RESET)"

# Version bumping targets
## bump-patch: Bump patch version (x.y.Z)
bump-patch:
	@echo "$(CYAN)Bumping patch version...$(RESET)"
	@current=$$(cat VERSION); \
	major=$$(echo $$current | cut -d. -f1); \
	minor=$$(echo $$current | cut -d. -f2); \
	patch=$$(echo $$current | cut -d. -f3); \
	new_patch=$$((patch + 1)); \
	new_version="$$major.$$minor.$$new_patch"; \
	echo "$$new_version" > VERSION; \
	echo "$(GREEN)✓ Version bumped: $$current -> $$new_version$(RESET)"

## bump-minor: Bump minor version (x.Y.0)
bump-minor:
	@echo "$(CYAN)Bumping minor version...$(RESET)"
	@current=$$(cat VERSION); \
	major=$$(echo $$current | cut -d. -f1); \
	minor=$$(echo $$current | cut -d. -f2); \
	new_minor=$$((minor + 1)); \
	new_version="$$major.$$new_minor.0"; \
	echo "$$new_version" > VERSION; \
	echo "$(GREEN)✓ Version bumped: $$current -> $$new_version$(RESET)"

## bump-major: Bump major version (X.0.0)
bump-major:
	@echo "$(CYAN)Bumping major version...$(RESET)"
	@current=$$(cat VERSION); \
	major=$$(echo $$current | cut -d. -f1); \
	new_major=$$((major + 1)); \
	new_version="$$new_major.0.0"; \
	echo "$$new_version" > VERSION; \
	echo "$(GREEN)✓ Version bumped: $$current -> $$new_version$(RESET)"

## release: Create a new release tag (requires clean tree)
release: check lint test
	@echo "$(CYAN)Creating release v$(VERSION)...$(RESET)"
	@if ! git diff --quiet || ! git diff --cached --quiet; then \
		echo "$(RED)✗ Working tree has uncommitted changes$(RESET)"; \
		echo "$(YELLOW)Commit everything first, then run make release$(RESET)"; \
		exit 1; \
	fi
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then \
		echo "$(RED)✗ Tag v$(VERSION) already exists$(RESET)"; \
		echo "$(YELLOW)Bump VERSION first (make bump-patch / bump-minor / bump-major)$(RESET)"; \
		exit 1; \
	fi
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "$(GREEN)✓ Tag v$(VERSION) created$(RESET)"
	@echo "$(YELLOW)Push with: git push origin v$(VERSION)$(RESET)"
