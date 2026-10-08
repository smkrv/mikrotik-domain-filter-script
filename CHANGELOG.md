# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.2] - 2026-10-08

### Fixed

- Tolerate transient DNS failures below a configurable percentage while keeping them uncached; preserve existing output when failures exceed the threshold.
- Allow Gist exports to update either configured list independently and skip lists without an ID. Reject malformed configured IDs before sending any update.
- Retry tolerated transient DNS failures even when source checksums are unchanged; return to the no-op path after recovery.
- Use a temporary test root in install tests so they run with Bats 1.2.1.

### Changed

- Cap DNS workers at 64, rotate oversized `script.log` to `script.log.1`, and check for the `ps` dependency.
- Document transient DNS handling, repeated processing for persistent SERVFAIL, optional Gist IDs, worker limits, and log rotation.
- Clarify that a malformed configured Gist ID causes enabled exports to fail.

## [2.2.1] - 2026-10-08

### Fixed

- Keep the lock inode in `state/`; cleanup and a competing process no longer remove the active lock or erase its PID. Help and version commands leave the log unchanged.
- Record source checksums and the success timestamp only after validation and publication. Failed runs retry; source removals and empty output files trigger processing.
- Download each source once per run and reuse that snapshot. Available main and special sources can still update when another URL fails. Configured whitelist download failures stop publication; an empty whitelist is allowed.
- Strip source comments before tokenization so domain names mentioned in comments cannot enter the output.
- Treat DNS transport failures, HTTP errors, malformed JSON and SERVFAIL as retryable failures. Cache only confirmed NXDOMAIN as negative, with a separate one-day TTL; recheck legacy `invalid` entries immediately.
- Preserve domains returning NOERROR without an A answer, including names used as suffixes. Accept punycode TLDs, enforce the 63-character label limit and preserve names with five or more labels.
- Stage DNS results before publication, validate once and remove tolerated invalid rows. Failed local publication restores previous outputs, including their absence on a first run.
- Validate settings from the shell and `.env` consistently, handle CRLF and matching quotes, and keep inherited GitHub tokens out of child environments. Bound GitHub requests by connection and total timeouts and reject HTTP errors.
- Stop background workers and their descendants before releasing the lock. Apply directory ownership consistently when run through sudo.
- Preserve whitelist policy on extraction errors and retain the previous PSL on failed downloads or malformed responses. Cache eviction handles paths containing spaces without deleting unrelated files.
- Roll back interrupted local publication before unlocking, including a signal between the two output renames.
- RouterOS: fetch and validate the complete list before changing entries, add missing entries before removing stale ones, handle CRLF, and reject oversized or malformed lists. Prevent overlapping jobs of the same named script.
- `make install` embeds the release version and configuration directory. `make setup` preserves edited source files; `make -C ... run` uses the target directory.

### Changed

- Classify domains and apply whitelist suffixes with awk lookups instead of per-domain grep processes. Use a bounded DNS worker pool that takes the next domain as a worker becomes free.
- CI runs `make check`, `make deps`, `make lint` and `make test` for main, pull requests and release tags. Missing dependencies fail the job.
- Fix ineffective negative Bats assertions and add regressions for locking, source snapshots, DNS cache, publication, installation and the full CLI pipeline.

### Documentation

- Document DNS cache migration, staged publication limits and installed working-directory behavior. Correct the RouterOS 6 compatibility claim; the updater requires RouterOS 7.20.6 or later.
- The RouterOS updater was reviewed against the scripting documentation but was not executed on a router. Test it on the target version before scheduling it.

## [2.2.0] - 2026-07-13

### Fixed
- `check_intersections`: `grep -vFf` matched substrings, so removing an intersecting `example.com` also silently deleted `myexample.com` and `example.com.hk` from the main list; now `grep -vxFf` (whole-line match)
- `check_updates_needed`: `current_md5` was never truncated between runs, so stale entries accumulated and update detection reported changes forever; now cleared at the start of each run
- Download failure during the update check was reported as "No updates needed" with exit 0; `check_updates_needed` now distinguishes "no changes" (1) from "check failed" (2) and the script exits with an error on failure
- `WORK_DIR` in `.env` crashed the script (`readonly variable` under `set -e`); the key is no longer accepted from `.env` (it decides where `.env` itself is read from), shell environment still works
- `while read` loops silently dropped the last line of `sources*.txt` and `.env` when the file had no trailing newline
- Numeric `.env` values with leading zeros (e.g. `08`) passed validation but aborted the script in arithmetic (octal parsing); now rejected with a warning
- `log_cache_stats` used a shell glob that exceeded ARG_MAX on caches with tens of thousands of entries; now uses `find -exec`
- `check_required_files` error message pointed to a nonexistent `scripts/` directory instead of `config/`
- Makefile: color escape codes printed literally (`\033[36m`) because plain `echo` does not interpret them; colors are now real escape bytes
- Makefile: `make release` always failed with shellcheck installed - `make lint` used the default severity (style) while CI uses `--severity=warning`; lint now matches CI
- Makefile: `make lint` silently skipped linting when shellcheck was absent; now fails with a clear message
- Makefile: `make release` tagged HEAD with uncommitted changes outside VERSION and overwrote nothing on existing tags; now requires a clean tree and refuses existing tags

### Security
- `--max-filesize` (100 MB) added to all downloads (source lists, Public Suffix List) to limit memory/disk exhaustion from a hostile source; enforced by curl when the server sends Content-Length
- `GITHUB_TOKEN` from `.env` is no longer exported into the environment of child processes (curl, jq, grep run on untrusted downloaded data); it stays in the shell only

### Changed
- `check_dependencies` and `make deps` now verify the full tool set actually used: curl, jq, awk, grep, sort, flock, find, md5sum, comm
- CI: removed `paths` filters - previously changes to Makefile, workflow, config, or RouterOS files bypassed all CI jobs
- CI: `apt-get update` before ShellCheck install (parity with the bats job, avoids stale-index 404s)
- `make test` now runs the bats suite (was a version-print smoke test that always passed)
- RouterOS script header: tested versions aligned with README (6.17, 7.20.6)

### Documentation
- README: worked example rebuilt so every stage's output is derivable from its input; stage order now matches the code (DNS validation runs last, after whitelisting and intersection checks)
- README: workflow diagram reordered to match the actual pipeline; removed claims about nonexistent `TOTAL_DOMAINS`/`PROCESSED_DOMAINS`/`VALID_DOMAINS` variables
- README: project structure tree includes all test files; dependency list matches `check_dependencies`
- README and script header rewritten without filler prose; emoji and typographic symbols removed
- REQUIREMENTS: Bash requirement corrected to >= 4.3 (negative array subscripts); `comm` added to the tool list

### Added
- Bats test coverage for `initial_filter`, `check_intersections` (including a regression test for the substring-match fix), `prepare_domains_for_dns_check`, `validate_results`; content assertions in `extract_domains` tests; hyphen-rule tests for `validate_domain`

## [2.1.1] - 2026-03-12

### Fixed
- Critical: domains classified as "other" (standalone subdomains) were silently dropped from DNS check
- Critical: domain classification order-dependent - children processed before parents due to alphabetical sort
- Critical: `trap_cleanup` always exited with code 0 (signal exit code masked by `log` return value)
- `check_updates_needed` did not strip inline comments from source files (unlike `load_lists`)
- `update_gists` ARG_MAX risk: file content passed as command-line argument instead of temp file
- Whitelist silently ignored 5+ level domains and non-PSL 4-level domains
- Per-signal traps (INT=130, TERM=143) guarantee correct exit codes on interruption
- URL whitespace validation in `load_lists` and `check_updates_needed`
- `grep -F` substring match replaced with `awk` field match in MD5 comparison
- `mv` error check added for sorted domain registry
- SC2155: `local var=$()` split into declaration and assignment (grep_exit, WORK_DIR)
- `update_gists` jq error handling with proper temp file cleanup on failure

### Removed
- Unreachable `exit 1` after `error()` call
- Unreachable `else` branch in `check_updates_needed` (file always exists due to earlier `touch`)
- Unused subdirectory creation in `process_domains`

## [2.1.0] - 2026-03-12

### Fixed
- Critical: `set -e` + `((var++))` causing script abort when counter starts at 0
- Critical: DNS validation using NS records instead of A records (subdomains were incorrectly marked invalid)
- Replaced fragile grep-based JSON parsing with jq in DNS validation
- Simplified `release_lock()` - removed broken `/proc` filesystem check
- Replaced GNU-only `find -printf` with `stat -c` in cache cleanup
- `grep -v` exit code 1 no longer treated as error when all lines filtered by whitelist
- Empty `update_state.dat` no longer causes arithmetic error on first run
- `extract_domains` output now properly feeds into `initial_filter` (Clash-format domains no longer lost)
- Whitelist regex patterns now escape dots to prevent false matches (`google.com` no longer matches `googleXcom`)
- Double cleanup/release_lock on normal exit path removed
- Duplicate error output to stderr removed (was writing to both stdout+stderr+logfile)
- Predictable temp file names replaced with `mktemp` XXXXXX (prevents collisions and race conditions)
- RouterOS script license header updated from CC BY-NC-SA 4.0 to MIT
- `cleanup()` path matching uses glob instead of regex (safe with special chars in WORK_DIR path)

### Security
- File and directory permissions tightened from world-readable (755/644) to owner-only (700/600)
- `.env` file permissions warning when not restricted to 600/400
- RouterOS script: entry count limit (5000) to prevent memory exhaustion, removed squattable example URL
- GitHub Actions `actions/checkout` pinned to commit SHA (v4.2.2)
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
- **BREAKING**: Dropped macOS support - Linux only (Debian 10+, Ubuntu 20.04+)
- Removed unused GNU `parallel` dependency; added `flock` to dependency check
- Replaced `grep -P` (PCRE) with `grep -E` (ERE) for broader Linux compatibility

### Removed
- Dead `DNS_RATE_LIMIT` configuration variable (was exported but never used)

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

[Unreleased]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.2.2...HEAD
[2.2.2]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.2.1...v2.2.2
[2.2.1]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.1.1...v2.2.0
[2.1.1]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/smkrv/mikrotik-domain-filter-script/compare/v1.0.7...v2.0.0
[1.0.7]: https://github.com/smkrv/mikrotik-domain-filter-script/releases/tag/v1.0.7
