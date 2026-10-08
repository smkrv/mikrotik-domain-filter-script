<div align="center">  

[![GitHub last commit](https://img.shields.io/github/last-commit/smkrv/mikrotik-domain-filter-script.svg?style=flat-square)](https://github.com/smkrv/mikrotik-domain-filter-script/commits) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT) [![RouterOS](https://img.shields.io/badge/RouterOS-7.20.6-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) ![Status](https://img.shields.io/badge/Status-Production-green?style=flat-square) [![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat-square&logo=Cloudflare&logoColor=white)](https://www.cloudflare.com/) [![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-red?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org/releases/bookworm/) [![Ubuntu LTS](https://img.shields.io/badge/Ubuntu%20LTS-22.04-orange?style=flat-square&logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/22.04/) [![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success?style=flat-square&logo=gnu-bash&logoColor=white)](https://github.com/smkrv/mikrotik-domain-filter-script/actions/workflows/shellcheck.yml) ![English](https://img.shields.io/badge/en-English-blue?style=flat-square)


  <img src="/docs/images/logo@2x.png" alt="Mikrotik Domain Filter Script" style="width: 70%; max-width: 960px; max-height: 480px; aspect-ratio: 16/9; object-fit: contain;"/>

  ### Mikrotik Domain Filter Script: Bash solution for filtering domain lists, creating Adlists and DNS Static or DNS FWD entries for Mikrotik RouterOS
</div>

---

## Introduction

**Mikrotik Domain Filter Script** is a Bash tool that filters and processes domain lists for [Mikrotik](https://mikrotik.com/) devices. It runs on a Linux host, not on RouterOS: downloads source lists, classifies domains, applies a whitelist, validates the survivors via DNS, and writes clean lists ready to serve as blocklists or allowlists. Any other environment that consumes plain domain lists can use the output as well.

Typical uses on the RouterOS side:
- [Adlists](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Adlist): curated lists of ad-serving domains. The router answers such queries with `0.0.0.0`, which null-routes ads and saves bandwidth.
- [DNS Static](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-DNSStatic): override specific DNS queries with custom entries, regular expressions, or dummy IP addresses, for single domains or entire zones.
- DNS FWD records: the repository [includes an example script (dns-static-updater.rsc)](/routeros/dns-static-updater.rsc) that loads a domain list onto the router and creates DNS FWD entries from it.

#### TLDR; Quick Setup Guide

>  **Prerequisites**
> - Linux system (Debian 10+, Ubuntu 20.04+)
> - Install dependencies: `sudo apt-get install curl jq gawk grep util-linux procps`
>
> **Quick Start with Make**
> ```bash
> git clone https://github.com/smkrv/mikrotik-domain-filter-script.git
> cd mikrotik-domain-filter-script
> make deps      # Check dependencies
> make setup     # Create work directory with config files
> # Edit work/sources.txt, work/sources_special.txt, work/sources_whitelist.txt
> make run       # Run the script
> ```
>
> **Manual Setup**
> 1. Clone repository and create working directory
> 2. Copy config examples: `cp config/*.example work/` and rename
> 3. Edit source files with your domain list URLs
> 4. Run: `WORK_DIR=./work bin/mikrotik-domain-filter`
>
> **Output**
> - Filtered domain lists: `filtered_domains_mikrotik.txt`, `filtered_domains_special_mikrotik.txt`
> - Logs: `script.log`
>
> **MikroTik Configuration**
> 1. Import [`routeros/dns-static-updater.rsc`](/routeros/dns-static-updater.rsc) to your router
> 2. Configure the script variables (`listname`, `fwdto`, `url`)
> 3. Schedule periodic execution
>
> **Tip**: Run `make help` to see all available commands.

---

### Table of Contents

1. [Initialization and Setup](#initialization-and-setup)
2. [File Checks and Cleanup](#file-checks-and-cleanup)
3. [Public Suffix List](#public-suffix-list)
4. [Domain Filtering and Classification](#domain-filtering-and-classification)
5. [DNS Checks](#dns-checks)
6. [Result Validation and Saving](#result-validation-and-saving)
7. [Update Checks and Backups](#update-checks-and-backups)
8. [Pipeline Summary](#pipeline-summary)
9. [File Descriptions](#file-descriptions)
10. [Detailed Description of Domain Processing in Downloaded Lists](#detailed-description-of-domain-processing-in-downloaded-lists)
11. [GitHub Gist Exports](#github-gist-exports)
12. [Project Structure](#project-structure)
13. [Installation and Setup](#installation-and-setup)
14. [Running the Script](#running-the-script)
15. [Important Notes](#important-notes)
16. [Script Workflow Diagram](#script-workflow-diagram)
17. [Prerequisites](#prerequisites)
18. [Benchmarking](#benchmarking)
19. [MikroTik Router Configuration](#mikrotik-router-configuration)

---

### Initialization and Setup

- **Path Settings**: The script defines paths for working directories, source files, output files, and temporary files.
- **Logging**: Events append to `script.log` after locking. `--help`, `--version` and a competing process leave the active log unchanged. When the log exceeds 10 MiB, the next run rotates it to `script.log.1`, replacing the previous backup. External log rotation can also be used.
- **Lock Mechanism**: A file lock (`flock`) ensures that only one instance of the script runs at a time.
- **Directory Initialization**: Required directories are checked and created if they don't exist.
- **Dependency Check**: The script verifies the presence of required system tools: `curl`, `jq`, `awk`, `grep`, `sort`, `flock`, `find`, `md5sum`, `comm`, and `ps` (provided by `procps`).

### File Checks and Cleanup

- **Required Files**: The script checks for the existence of essential files like `sources.txt`, `sources_special.txt`, and others. If any are missing, the script exits with an error.
- **Cleanup**: Temporary files and outdated cache files are removed to free space.

### Public Suffix List

- **Loading Public Suffix List**: The script downloads and updates the Public Suffix List if it's outdated. This list is used to determine the type of domains (second-level, regional, etc.).
- The script uses literal two-label suffixes from the [Public Suffix List](https://publicsuffix.org/) for regional classification. It does not implement the full PSL wildcard and exception algorithm.

### Domain Filtering and Classification

- **Initial Filtering**: Domains are filtered based on regex patterns to ensure they match the expected format. Invalid domains are discarded.
- **Domain Classification**: Domains are classified into second-level, regional, and other types. This involves parsing the domain, checking against the Public Suffix List, and categorizing accordingly.
- **Whitelist Application**: A whitelist of domains is applied to filter out domains that should not be blocked or allowed.

### DNS Checks  

- **Domain Validation**: Each remaining domain is queried via Cloudflare DoH. `NOERROR` keeps the domain, including names without an A record that are used as suffixes. `NXDOMAIN` excludes it. Transient transport failures, HTTP errors and other DNS errors are never cached as invalid; an excessive share makes the update inconclusive.
- **Parallel Processing**: DNS checks use up to 5 workers by default, capped at 64; a free worker takes the next domain. Positive results are cached for 90 days; `NXDOMAIN` results expire after 1 day. Configure these separately with `CACHE_TTL_DAYS` and `CACHE_INVALID_TTL_DAYS`.
- **Transient Failures**: Transient DNS failures are not cached. If they affect no more than `DNS_MAX_FAILURE_PERCENT` (default: 5%) of the domains, those domains are skipped and retried on the next run. A larger share makes the DNS check inconclusive, aborts the update, and preserves the existing output.
- **DNS Resolution Method**: Verification uses Cloudflare's DNS-over-HTTPS (DoH) service(https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/): queries travel over an encrypted channel and return JSON that the script parses with `jq`.

**Endpoint**: `https://cloudflare-dns.com/dns-query`  

For detailed information about the API requests and response format, please refer to the [official documentation](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/).

### Result Validation and Saving

- **Result Validation**: Each staged list is checked once. Up to 10 invalid rows are removed with warnings; more than 10 invalid rows or no remaining valid domains stops publication.
- **Saving Results**: DNS results stay in temporary files until both lists pass validation. Each output is replaced by a rename, with backups retained for rollback. The two output files are replaced sequentially; readers needing a consistent pair must coordinate with the script lock.
- **Gist Update**: If the results are valid, the script updates GitHub Gists with the new domain lists.

### Update Checks and Backups

- **Update Needed Check**: The script downloads each source once per run and compares the complete checksum manifest, including source removals. Failed sources are reported; remaining sources can still be processed. Successful checksums and the timestamp are saved after output publication and any configured Gist updates.
- **Retry and Recovery**: Failed processing leaves the previous success state unchanged, so the next run retries. A configured whitelist that cannot be downloaded stops publication; an absent or empty whitelist configuration, or a downloaded comment-only list, is allowed. Empty HTTP responses are treated as failed sources. Gist updates are not transactional: if any configured Gist update fails, local outputs and update state remain unchanged, and the next run retries every configured Gist.

### Pipeline Summary

1. **Initialization**: Create the lock directory, acquire the lock, then check files and dependencies.
2. **Public Suffix List**: Load or refresh the Public Suffix List.
3. **Update Check**: Compare MD5 checksums of the sources; exit early if nothing changed.
4. **Loading**: Read the downloaded main, special, and whitelist snapshots.
5. **Filtering and Classification**: Extract domains, drop invalid entries, classify into second-level, regional, and other.
6. **Whitelist and Intersections**: Remove whitelisted domains, then move domains present in both lists to the special list.
7. **DNS Checks**: Validate the remaining domains via DNS in parallel.
8. **Validation and Saving**: Validate staged lists, update configured GitHub Gists, publish local outputs, then record the successful update state.
9. **Cleanup**: Remove temporary files and release the lock after workers exit.

### File Descriptions

Below is a detailed description of the files used in the script, including their purpose and the format of their contents.

#### `SOURCES_FILE`

**File Path:** `${WORK_DIR}/sources.txt`

**Description:**
This file contains a list of URLs from which the main domain lists are downloaded. Each URL should be on a separate line. The script will download the content from these URLs and process them to extract and filter domains.

**Format:**
```
https://example.com/domain-list1.txt # This is a comment
https://example.org/domain-list2.txt
# This is a comment
https://example.net/domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.tiktok.txt
# This is a comment
https://example.com/additional-domains.txt
```

#### `SOURCESSPECIAL_FILE`

**File Path:** `${WORK_DIR}/sources_special.txt`

**Description:**
This file contains a list of URLs from which the special domain lists are downloaded. Each URL should be on a separate line. The script will download the content from these URLs and process them to extract and filter domains, which will then be excluded from the main list to avoid duplicates.

**Format:**
```
https://example.com/special-domain-list1.txt
https://example.org/special-domain-list2.txt # This is a comment
https://example.net/special-domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/doh.txt
https://example.com/additional-special-domains.txt # This is a comment
```

#### `WHITELIST_FILE`

**File Path:** `${WORK_DIR}/sources_whitelist.txt`

**Description:**
This file contains a list of URLs from which whitelist domain lists are downloaded. Each URL should be on a separate line. The script downloads and merges these lists into a single whitelist. Domains found in it are excluded from both the main and special lists during processing.  

**Format:**
```
https://example.com/domain-list1.txt
https://example.org/domain-list2.txt
# This is a comment
https://example.net/domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.apple.txt # This is a comment
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.samsung.txt
```

### Summary

- **`SOURCES_FILE`**: Contains URLs for downloading the main domain lists.
- **`SOURCESSPECIAL_FILE`**: Contains URLs for downloading the special domain lists.
- **`WHITELIST_FILE`**: Contains URLs for downloading domains that should be excluded from both the main and special lists.

Source configuration files accept one HTTPS URL per line. Downloaded lists contain domains or supported Clash rules. Blank lines and `#` comments are ignored.

### Detailed Description of Domain Processing in Downloaded Lists

This part follows one input list through every processing stage, in the order the script actually runs them: filtering, classification, whitelisting, special list exclusion, DNS validation. The input mixes plain domains with Clash-style rules.

#### 1. Initial Filtering

Extraction and initial filtering remove invalid entries, comments, and empty lines, convert domains to lowercase, and pull domains out of Clash-format rules (`DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`). Everything else (IP rules, malformed lines) is dropped. The result is sorted and deduplicated.

**Example Input:**
```
# This is a comment
MikroTik.com
help.mikrotik.com
Debian.org
cdn.jsdelivr.net
youtube.co.uk
instagram.net.pl
workplace.co.jp
invalid domain
.invalid
invalid.
# Clash format
DOMAIN-SUFFIX,rutracker.org
- DOMAIN,ntc.party
ALLOW-IP, 1.1.1.1
IP-CIDR, 10.0.0.0/8
```

**Example Output:**
```
cdn.jsdelivr.net
debian.org
help.mikrotik.com
instagram.net.pl
mikrotik.com
ntc.party
rutracker.org
workplace.co.jp
youtube.co.uk
```

#### 2. Domain Classification

Domains are classified into three categories using the Public Suffix List: second-level, regional, and other. Classification preserves every label in a source name, including domains with five or more levels. ASCII punycode TLDs are accepted; each label is limited to 63 characters.

**Second-level domains:**
```
debian.org
mikrotik.com
ntc.party
rutracker.org
```

**Regional domains** (the suffix is a public suffix like `co.uk`):
```
instagram.net.pl
workplace.co.jp
youtube.co.uk
```

**Other domains** (standalone subdomains whose parent is not in the list):
```
cdn.jsdelivr.net
```

`help.mikrotik.com` is dropped here: its parent `mikrotik.com` is already classified, and on the router a parent entry covers its subdomains (`match-subdomain=yes`).

#### 3. Whitelisting

Domains from the whitelist, including their subdomains, are excluded from the main and special lists.

**Example Whitelist:**
```
mikrotik.com
```

**Main List After Whitelisting:**
```
cdn.jsdelivr.net
debian.org
instagram.net.pl
ntc.party
rutracker.org
workplace.co.jp
youtube.co.uk
```

#### 4. Special List Exclusion

Domains present in both lists are removed from the main list and stay in the special list, so the two outputs never overlap.

**Example Special List:**
```
youtube.co.uk
```

**Main List After Exclusion:**
```
cdn.jsdelivr.net
debian.org
instagram.net.pl
ntc.party
rutracker.org
workplace.co.jp
```

#### 5. DNS Validation

Each remaining domain is queried via DNS-over-HTTPS. `NOERROR` keeps it even without an A answer; `NXDOMAIN` removes it. Transient DNS or HTTP failures are skipped and remain uncached when within `DNS_MAX_FAILURE_PERCENT`; exceeding the threshold stops publication and leaves the previous lists available. DNS runs after filtering so excluded domains do not generate queries.

#### Example Final Output

Assuming every domain above returns `NOERROR`:

**Main List:**
```
cdn.jsdelivr.net
debian.org
instagram.net.pl
ntc.party
rutracker.org
workplace.co.jp
```

**Special List:**
```
youtube.co.uk
```

### GitHub Gist Exports

Configuration is done through environment variables in a `.env` file in your working directory:

```env
# Enable or disable Gist updates
EXPORT_GISTS=true

# GitHub Personal Access Token
GITHUB_TOKEN="your_github_token"

# Gist IDs for main and special lists
# Configure either ID or both; each list without an ID is skipped.
GIST_ID_MAIN="your_main_gist_id"
GIST_ID_SPECIAL="your_special_gist_id"
```

Gist updates go directly through the GitHub API (`curl` + `jq`, both already required by the script). The token needs the `gist` scope.

#### Notes
- The `.env` file must have restricted permissions (`chmod 600`) - the script warns if permissions are too open
- Environment variables can also be set directly in the shell; `WORK_DIR` is honored only from the shell environment, not from `.env`
- Set `EXPORT_GISTS=false` to disable Gist updates
- When exports are enabled, set `GITHUB_TOKEN` and at least one of `GIST_ID_MAIN` or `GIST_ID_SPECIAL`; the IDs are optional individually and must be 20-32 hexadecimal characters
- `DNS_MAX_FAILURE_PERCENT` sets the tolerated transient DNS failure percentage (default: 5; valid range: 1-100)
- `MAX_PARALLEL_JOBS` sets the worker count (default: 5; values above 64 are clamped to 64)
- Numeric values are validated (positive integers, no leading zeros)

---

### Project Structure

```text
mikrotik-domain-filter-script/
  .github/workflows/shellcheck.yml  # CI checks for main, PRs and release tags
  bin/mikrotik-domain-filter        # Linux entrypoint
  config/*.example                 # Source URL configuration templates
  docs/REQUIREMENTS.md              # Dependencies and environment settings
  docs/images/                     # README assets
  routeros/dns-static-updater.rsc   # RouterOS FWD list updater
  tests/test_helpers.bash           # Source-safe Bats helper
  tests/test_*.bats                 # Unit, lifecycle, CLI and install regressions
  Makefile                         # Local checks, installation and release tag
  VERSION                          # Semantic version
  CHANGELOG.md                     # Release history
  README.md
```

### Installation and Setup

#### Prerequisites

Before running the script, ensure your system meets the requirements in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md).

**Quick Dependencies Installation (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install curl jq gawk grep util-linux
```

#### Installation Options

**Option 1: Using Make (Recommended)**
```bash
git clone https://github.com/smkrv/mikrotik-domain-filter-script.git
cd mikrotik-domain-filter-script
make deps      # Verify dependencies
make setup     # Create work/ directory with configs
make run       # Run the script
```

**Option 2: System-wide Installation**
```bash
sudo make install
# Script installed to /usr/local/bin/mikrotik-domain-filter
# Default working directory: /etc/mikrotik-domain-filter
```

The installed script embeds the release version and uses `SYSCONFDIR` as its default working directory, including under cron. Set `WORK_DIR` explicitly to use another directory. Follow the configuration-copy instructions printed by `make install`; `make setup` preserves existing files in `work/`.

**Option 3: Manual Setup**
```bash
# Create working directory
mkdir -p ~/mikrotik-filter && cd ~/mikrotik-filter

# Copy and configure files
cp /path/to/repo/config/*.example .
mv sources.txt.example sources.txt
mv sources_special.txt.example sources_special.txt
mv sources_whitelist.txt.example sources_whitelist.txt

# Edit configuration files with your URLs
# Then run:
WORK_DIR=$(pwd) /path/to/repo/bin/mikrotik-domain-filter
```

#### Configuration

1. **Edit source files** in your working directory:
   - `sources.txt` - URLs of main domain blocklists
   - `sources_special.txt` - URLs of special domain lists
   - `sources_whitelist.txt` - URLs of domains to exclude

2. **Configure Gist exports** (optional) - create `.env` file:
   ```env
   EXPORT_GISTS=true
   GITHUB_TOKEN="your_token"
   GIST_ID_MAIN="gist_id"
   GIST_ID_SPECIAL="gist_id"
   ```

#### Running the Script

```bash
# With Make
make run

# Or directly
WORK_DIR=/path/to/work bin/mikrotik-domain-filter

# With options
bin/mikrotik-domain-filter --help
bin/mikrotik-domain-filter --version
```

#### Important Notes
- Test the resulting lists on a non-production router before deploying
- Monitor log files (`script.log`) for issues
- Ensure sufficient disk space for cache and logs
- The script uses file locking (`flock`) to prevent concurrent runs
- All files and directories are created with owner-only permissions (700/600)
- HTTPS is enforced for all external connections (source downloads, DNS-over-HTTPS, GitHub API)

---

### Script Workflow Diagram

```text
Parse arguments -> acquire lock -> check files and dependencies
  -> refresh PSL -> download source snapshots -> compare complete manifest
  -> extract and classify -> apply whitelist -> remove intersections
  -> bounded DNS workers -> validate staged lists
  -> update configured Gists -> publish local files -> commit success state
  -> cleanup -> release lock

Unchanged manifest within 24 hours -> release lock -> exit successfully
Processing failure -> preserve success state -> release lock -> exit nonzero
Local publication failure -> restore previous files -> exit nonzero
SIGINT/SIGTERM -> stop worker descendants -> cleanup -> release lock
```

### Benchmarking

> **Environment**: Amazon Lightsail (512 MB RAM, 2 vCPUs, 20 GB SSD, Debian 12.8)  
> **Processing**: 86K domains + 12K whitelist + 2.7K special reduced to 1,970 unique (main) + 431 unique (special)  
> **Performance**: 24 min processing time, 42% peak CPU

### MikroTik Router Configuration

#### System Requirements
- RouterOS 7.20.6 or later with DNS static `type=FWD`, `match-subdomain` and `address-list` support. RouterOS 6 is not supported by this updater.
- Sufficient storage space for DNS list download
- Memory available for DNS records processing
- Internet connection for fetching domain lists

#### Router Setup  
1. Import `dns-static-updater.rsc` to your MikroTik RouterOS  
2. Set appropriate permissions for the script execution  
3. Configure DNS settings on your router  
4. Ensure sufficient storage space for DNS list operations  

#### Script Variables Configuration  
The script requires configuration of the following variables:  

| Variable  | Description | Example |  
|-----------|-------------|---------|  
| `listname` | Name of the address-list for DNS entries | `"allow-list"` |  
| `fwdto` | DNS server address for query forwarding | `"localhost"` or `"1.1.1.1"` |  
| `url` | Raw URL of the domain list file | `"https://raw.githubusercontent.com/example/repo/main/domains.txt"` |  

#### Script Setup Instructions  
1. Set `:local listname` to your desired address-list name  
2. Set `:local fwdto` to your preferred DNS server  
3. Set `:local url` to the raw URL of your domain list  
4. Ensure the domain list file is accessible via the specified URL  

#### Important Notes  
- Use caution when adding large domain lists (beyond a few hundred domains)
- The script rejects lists above the configured entry limit (default: 5000) before changing existing entries.
- `/tool fetch output=user` has a 64 KB data limit. The updater rejects responses at or above 64512 bytes; split larger feeds into separately managed lists.
- Download and validation happen before changes. Missing entries are added first; stale managed entries are removed only after all additions succeed.
- `fwdto="localhost"` is the retained example value. Set it to a reachable DNS server or a configured RouterOS DNS forwarder and verify resolution before scheduling the script.
- Import the updater as a named system script; its job guard prevents overlapping executions of that script. Keep each managed list assigned to one script.
- An addition failure retains old entries but can leave earlier additions in place. The RouterOS update is not transactional; back up the configuration before the first run.
- Validate the revised updater on your RouterOS version before production use; its RouterOS commands are not executed by the Linux test suite.
- The script adds a 10ms delay between operations to prevent resource exhaustion
- TLS certificate verification is enabled (`check-certificate=yes`)
- Monitor system resources during initial setup with large lists

For more details about DNS configuration in RouterOS, see: [MikroTik DNS Documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Introduction)

---

## Legal Disclaimer and Limitation of Liability  

### Software Disclaimer  

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,   
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A   
PARTICULAR PURPOSE AND NONINFRINGEMENT.  

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,   
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER   
DEALINGS IN THE SOFTWARE.  

## License

Author: SMKRV
[MIT License](https://opensource.org/licenses/MIT) - see [LICENSE](LICENSE) for details.

## Support the Project

The best support is:
- Sharing feedback
- Contributing ideas
- Recommending to friends
- Reporting issues
- Star the repository

If you want to say thanks financially, you can send a small token of appreciation in USDT:

**USDT Wallet (TRC10/TRC20):**
`TXC9zYHYPfWUGi4Sv4R1ctTBGScXXQk5HZ`

---
<div align="center">
Made for the Mikrotik community

[Report Bug](https://github.com/smkrv/mikrotik-domain-filter-script/issues) | [Request Feature](https://github.com/smkrv/mikrotik-domain-filter-script/issues)
</div>
