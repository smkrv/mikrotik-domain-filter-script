# Requirements

## System Requirements
- Bash version: >= 4.3 (the script uses negative array subscripts)
- Operating System: Ubuntu 20.04+ / Debian 10+ (Linux only)
- Minimum disk space: 100MB for logs and cache
- Internet connection for downloading domain lists

## Required Commands and Utilities
- curl (>= 7.68.0) - for downloading files and API requests
- jq (>= 1.6) - for JSON processing
- grep (GNU grep >= 3.0) - for text processing
- awk (GNU awk >= 5.0) - for text processing
- sort (GNU coreutils) - for list sorting
- md5sum (GNU coreutils) - for checksum verification
- comm (GNU coreutils) - for list intersection checks
- flock (util-linux) - for file locking
- find (GNU findutils) - for file operations

## Optional Dependencies
- logrotate - for log management
- systemd (if running as a service)

## Network Requirements
- Access to DNS servers (default: Cloudflare DoH at cloudflare-dns.com)
- Access to GitHub API (for Gist updates, optional)
- Unrestricted access to domain list sources

## Permissions
- Execute permissions for script files
- Write permissions in working directory
- Sudo rights might be required for initial setup

## Environment Variables
Configure these variables in the shell or in `WORK_DIR/.env`. Numeric values must be positive decimal integers without leading zeros. `WORK_DIR` itself is accepted only from the shell:

| Variable | Default | Description |
|----------|---------|-------------|
| `EXPORT_GISTS` | `false` | Enable GitHub Gist exports |
| `GITHUB_TOKEN` | - | GitHub Personal Access Token |
| `GIST_ID_MAIN` | - | Gist ID for main domain list |
| `GIST_ID_SPECIAL` | - | Gist ID for special domain list |
| `MAX_PARALLEL_JOBS` | `5` | Number of parallel DNS checks |
| `DNS_TIMEOUT` | `10` | DNS query timeout in seconds |
| `DNS_MAX_RETRIES` | `3` | Maximum DNS query retries |
| `CACHE_TTL_DAYS` | `90` | Positive DNS cache TTL in days |
| `CACHE_INVALID_TTL_DAYS` | `1` | NXDOMAIN cache TTL in days |
