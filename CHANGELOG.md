# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Critical: `set -e` + `((var++))` causing script abort when counter starts at 0
- Critical: DNS validation using NS records instead of A records (subdomains were incorrectly marked invalid)
- Replaced fragile grep-based JSON parsing with jq in DNS validation
- Simplified `release_lock()` — removed broken `/proc` filesystem check
- Replaced GNU-only `find -printf` with `stat -c` in cache cleanup
- `grep -v` exit code 1 no longer treated as error when all lines filtered by whitelist
- Empty `update_state.dat` no longer causes arithmetic error on first run
- `extract_domains` output now properly feeds into `initial_filter` (Clash-format domains no longer lost)
- Whitelist regex patterns now escape dots to prevent false matches (`google.com` no longer matches `googleXcom`)
- Double cleanup/release_lock on normal exit path removed
- Duplicate error output to stderr removed (was writing to both stdout+stderr+logfile)
- Predictable temp file names replaced with `mktemp` XXXXXX (prevents collisions and race conditions)

### Removed
- Dead `DNS_RATE_LIMIT` configuration variable (was exported but never used)

### Security
- Fixed: GITHUB_TOKEN no longer exposed in process list (uses temp header file with chmod 600)
- Fixed: Auth temp file guaranteed cleanup via `|| rc=$?` pattern (prevents leak on curl failure)
- Fixed: .env numeric values validated to prevent curl argument injection; zero values rejected
- Fixed: GIST_ID format validated (hex, 20-32 chars) to prevent GitHub API path traversal
- Fixed: URL scheme validation enforces HTTPS-only for all source downloads and update checks
- Fixed: `--proto '=https'` added to all curl calls to prevent scheme downgrade via redirects
- Fixed: Domain re-validation at DNS check entry point (defense-in-depth)
- Fixed: Lock file moved from world-writable /tmp to WORK_DIR/tmp (prevents symlink attacks)
- Fixed: Gist payload written to temp file to avoid ARG_MAX limits on large domain lists

### Changed
- **BREAKING**: Dropped macOS support — Linux only (Debian 10+, Ubuntu 20.04+)
- Removed unused GNU `parallel` dependency; added `flock` to dependency check
- Replaced `grep -P` (PCRE) with `grep -E` (ERE) for broader Linux compatibility

## [2.0.0] - 2026-01-15

### Changed
- **BREAKING**: Reorganized repository structure
  - Main script moved to `bin/mikrotik-domain-filter` (renamed, no `.sh` extension)
  - Configuration examples moved to `config/`
  - RouterOS scripts moved to `routeros/`
  - Documentation moved to `docs/`
- License changed from CC BY-NC-SA 4.0 to MIT
- Improved parallel DNS checking with atomic file operations (fixes race condition)
- Enhanced `.env` file loading with key validation (security improvement)
- Made performance settings configurable via environment variables
- Improved Public Suffix List handling with validation and fallback
- Better error messages and logging throughout

### Added
- `Makefile` with installation, setup, and version management commands
- `.editorconfig` for consistent code style
- `.gitignore` for proper file exclusion
- Version management via `VERSION` file
- `CHANGELOG.md` for tracking changes
- Configurable cache TTL and performance settings
- Cross-platform `stat` command support (Linux + macOS)
- Improved source loading with inline comment handling

### Fixed
- Critical bug in `release_lock()` - incorrect `/proc` path
- Race condition in parallel DNS processing
- Double negation in `check_required_files()`
- Magic numbers replaced with named constants
- ShellCheck warnings resolved

### Removed
- `STRUCTURE.md` (content merged into README)
- Old `scripts/` directory structure

## [1.0.7] - 2025-09-02

### Added
- Initial public release
- Domain filtering and classification
- DNS validation via Cloudflare DoH
- Whitelist support
- GitHub Gist export functionality
- RouterOS script for DNS static entries

---

[Unreleased]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v1.0.7...v2.0.0
[1.0.7]: https://github.com/smkrv/mikrotik-domain-filter-script/releases/tag/v1.0.7
