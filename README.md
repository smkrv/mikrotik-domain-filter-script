<div align="center">  

[![GitHub last commit](https://img.shields.io/github/last-commit/smkrv/mikrotik-domain-filter-script.svg?style=flat-square)](https://github.com/smkrv/mikrotik-domain-filter-script/commits) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT) [![RouterOS](https://img.shields.io/badge/RouterOS-7.20.6-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) [![RouterOS](https://img.shields.io/badge/RouterOS-6.17-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) ![Status](https://img.shields.io/badge/Status-Production-green?style=flat-square) [![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat-square&logo=Cloudflare&logoColor=white)](https://www.cloudflare.com/) [![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-red?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org/releases/bookworm/) [![Ubuntu LTS](https://img.shields.io/badge/Ubuntu%20LTS-22.04-orange?style=flat-square&logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/22.04/) [![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success?style=flat-square&logo=gnu-bash&logoColor=white)](https://github.com/smkrv/mikrotik-domain-filter-script/actions/workflows/shellcheck.yml) ![English](https://img.shields.io/badge/en-English-blue?style=flat-square)


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
> - Install dependencies: `sudo apt-get install curl jq gawk grep util-linux`
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
- **Logging**: Events and errors are recorded in `script.log`; processing statistics are tracked per stage and logged.
- **Lock Mechanism**: A file lock (`flock`) ensures that only one instance of the script runs at a time.
- **Directory Initialization**: Required directories are checked and created if they don't exist.
- **Dependency Check**: The script verifies the presence of required system tools: `curl`, `jq`, `awk`, `grep`, `sort`, `flock`, `find`, `md5sum`, and `comm`.

### File Checks and Cleanup

- **Required Files**: The script checks for the existence of essential files like `sources.txt`, `sources_special.txt`, and others. If any are missing, the script exits with an error.
- **Cleanup**: Temporary files and outdated cache files are removed to free space.

### Public Suffix List

- **Loading Public Suffix List**: The script downloads and updates the Public Suffix List if it's outdated. This list is used to determine the type of domains (second-level, regional, etc.).
- The script uses the Mozilla Public Suffix List[^¹](https://publicsuffix.org/) - a standardized database of domain suffixes that identifies the registrable part of a domain.

### Domain Filtering and Classification

- **Initial Filtering**: Domains are filtered based on regex patterns to ensure they match the expected format. Invalid domains are discarded.
- **Domain Classification**: Domains are classified into second-level, regional, and other types. This involves parsing the domain, checking against the Public Suffix List, and categorizing accordingly.
- **Whitelist Application**: A whitelist of domains is applied to filter out domains that should not be blocked or allowed.

### DNS Checks  

- **Domain Validation**: Each domain that survived filtering, whitelisting, and intersection checks is queried for an A record; only resolving domains reach the output files.
- **Parallel Processing**: DNS checks run concurrently in background subshells (5 workers by default). Results are stored in per-domain temporary files and aggregated; verdicts are cached.
- **DNS Resolution Method**: Verification uses Cloudflare's DNS-over-HTTPS (DoH) service[^¹](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/): queries travel over an encrypted channel and return JSON that the script parses with `jq`.

**Endpoint**: `https://cloudflare-dns.com/dns-query`  

For detailed information about the API requests and response format, please refer to the [official documentation](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/).

### Result Validation and Saving

- **Result Validation**: Every line of the final lists is checked against the domain format; empty lists or lists with more than 10 invalid entries are rejected.
- **Saving Results**: The validated domain lists are saved to output files. Backups are created before overwriting existing files.
- **Gist Update**: If the results are valid, the script updates GitHub Gists with the new domain lists.

### Update Checks and Backups

- **Update Needed Check**: The script checks if the source files have changed using MD5 checksums. If no changes are detected, the script exits early to save resources.
- **Backup Restoration**: If any step fails, the script restores backups of the output files to maintain the previous state.

### Pipeline Summary

1. **Initialization**: Check required files, create directories, verify dependencies, acquire the lock.
2. **Public Suffix List**: Load or refresh the Public Suffix List.
3. **Update Check**: Compare MD5 checksums of the sources; exit early if nothing changed.
4. **Loading**: Download the main, special, and whitelist lists.
5. **Filtering and Classification**: Extract domains, drop invalid entries, classify into second-level, regional, and other.
6. **Whitelist and Intersections**: Remove whitelisted domains, then move domains present in both lists to the special list.
7. **DNS Checks**: Validate the remaining domains via DNS in parallel.
8. **Validation and Saving**: Validate the final lists, save them with backups, update GitHub Gists.
9. **Cleanup**: Remove temporary files; restore previous output if a step failed.

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

**Each file should have one URL or domain per line, with no additional spaces or characters. Inline comments can be added after the URL using `#`, and comments can also be placed before or after the line.**

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

Domains are classified into three categories using the Public Suffix List: second-level, regional, and other.

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

Each remaining domain is queried for an A record via DNS-over-HTTPS; only resolving domains are kept. DNS runs last, after all filtering, so no queries are wasted on domains that would be removed anyway.

#### Example Final Output

Assuming every domain above resolves:

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
GIST_ID_MAIN="your_main_gist_id"
GIST_ID_SPECIAL="your_special_gist_id"
```

Gist updates go directly through the GitHub API (`curl` + `jq`, both already required by the script). The token needs the `gist` scope.

#### Notes
- The `.env` file must have restricted permissions (`chmod 600`) - the script warns if permissions are too open
- Environment variables can also be set directly in the shell; `WORK_DIR` is honored only from the shell environment, not from `.env`
- Set `EXPORT_GISTS=false` to disable Gist updates
- Numeric values are validated (positive integers, no leading zeros); GIST_ID is validated as hex (20-32 chars)

---

### Project Structure

```
mikrotik-domain-filter-script/
├── .github/
│   └── workflows/
│       └── shellcheck.yml          # CI/CD: ShellCheck, syntax, Makefile, bats tests
├── bin/
│   └── mikrotik-domain-filter      # Main domain filtering script
├── config/
│   ├── sources.txt.example         # Example: main domain list URLs
│   ├── sources_special.txt.example # Example: special domain list URLs
│   └── sources_whitelist.txt.example # Example: whitelist URLs
├── docs/
│   ├── images/
│   │   └── logo@2x.png
│   └── REQUIREMENTS.md             # System requirements documentation
├── routeros/
│   └── dns-static-updater.rsc      # MikroTik RouterOS script
├── tests/
│   ├── test_helpers.bash           # Bats test helper functions
│   ├── test_validate_domain.bats   # Domain validation tests
│   ├── test_extract_domains.bats   # Domain extraction tests
│   ├── test_initial_filter.bats    # Initial filtering tests
│   ├── test_process_domains.bats   # Domain classification tests
│   ├── test_apply_whitelist.bats   # Whitelist application tests
│   ├── test_check_intersections.bats        # List intersection tests
│   ├── test_prepare_domains_for_dns_check.bats # DNS input preparation tests
│   └── test_validate_results.bats  # Final list validation tests
├── .editorconfig                   # Editor configuration
├── .gitignore                      # Git ignore rules
├── CHANGELOG.md                    # Version changelog
├── CODE_OF_CONDUCT.md
├── LICENSE                         # MIT License
├── Makefile                        # Build and installation commands
├── VERSION                         # Semantic version file
└── README.md
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
```

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

```markdown
# Main Process Flow

[START]
   │
   ▼
[Initialization]
   │
   ├── Check required files
   ├── Initialize directories
   ├── Check dependencies
   ├── Acquire lock
   └── Load Public Suffix List
   │
   ▼
[Update Check]
   │
   ├── Calculate MD5 of source files
   ├── Compare with previous MD5
   └── Exit if no changes
   │
   ▼
[Load Domain Lists]
   │
   ├── Download from sources.txt
   ├── Download from sources_special.txt
   └── Download from sources_whitelist.txt (if exists)
   │
   ▼
[Initial Processing]
   │
   ├── Remove invalid domains
   ├── Convert to lowercase
   ├── Remove duplicates
   └── Basic format validation
   │
   ▼
[Domain Classification]
   │
   ├── Second-level domains
   ├── Regional domains
   └── Other domains
   │
   ▼
[Whitelist Application]
   │
   ├── Load whitelist
   ├── Filter main list
   └── Filter special list
   │
   ▼
[List Intersection Check]
   │
   ├── Compare main and special lists
   └── Move duplicates to special list
   │
   ▼
[DNS Validation]
   │
   ├── Parallel DNS checks
   ├── Cache results
   └── Retry failed checks
   │
   ▼
[Result Validation]
   │
   ├── Format check
   └── Size check
   │
   ▼
[Save Results]
   │
   ├── Create backups
   ├── Save main list
   └── Save special list
   │
   ▼
[Update Gists]
   │
   ├── Update main list gist
   └── Update special list gist
   │
   ▼
[Cleanup]
   │
   ├── Remove temporary files
   ├── Clear old cache
   └── Release lock
   │
   ▼
[END]

# Error Handling Flow

[Error Detected]
   │
   ▼
[Log Error]
   │
   ▼
[Restore Backups]
   │
   ▼
[Cleanup]
   │
   ▼
[Release Lock]
   │
   ▼
[Exit with Error]

# Parallel Processing

[DNS Checks]
   │
   ├── Worker 1 ──> Process domains
   ├── Worker 2 ──> Process domains
   ├── Worker 3 ──> Process domains
   ├── Worker 4 ──> Process domains
   └── Worker 5 ──> Process domains
   │
   ▼
[Aggregate Results]
```

### Benchmarking

> **Environment**: Amazon Lightsail (512 MB RAM, 2 vCPUs, 20 GB SSD, Debian 12.8)  
> **Processing**: 86K domains + 12K whitelist + 2.7K special reduced to 1,970 unique (main) + 431 unique (special)  
> **Performance**: 24 min processing time, 42% peak CPU

### MikroTik Router Configuration

#### System Requirements
- RouterOS version 6.17 or higher (tested on 6.17 and 7.20.6)
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
- The script enforces a configurable entry limit (default: 5000) to prevent memory exhaustion
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

[Report Bug](https://github.com/smkrv/mikrotik-domain-filter-script/issues) · [Request Feature](https://github.com/smkrv/mikrotik-domain-filter-script/issues)
</div>
