<div align="center">  

[![GitHub last commit](https://img.shields.io/github/last-commit/smkrv/mikrotik-domain-filter-script.svg?style=flat-square)](https://github.com/smkrv/mikrotik-domain-filter-script/commits) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT) [![RouterOS](https://img.shields.io/badge/RouterOS-7.20.6-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) [![RouterOS](https://img.shields.io/badge/RouterOS-6.17-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) ![Status](https://img.shields.io/badge/Status-Production-green?style=flat-square) [![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat-square&logo=Cloudflare&logoColor=white)](https://www.cloudflare.com/) [![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-red?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org/releases/bookworm/) [![Ubuntu LTS](https://img.shields.io/badge/Ubuntu%20LTS-22.04-orange?style=flat-square&logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/22.04/) [![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success?style=flat-square&logo=gnu-bash&logoColor=white)](https://github.com/smkrv/mikrotik-domain-filter-script/actions/workflows/shellcheck.yml) ![English](https://img.shields.io/badge/en-English-blue?style=flat-square)


  <img src="/docs/images/logo@2x.png" alt="Mikrotik Domain Filter Script" style="width: 70%; max-width: 960px; max-height: 480px; aspect-ratio: 16/9; object-fit: contain;"/>

  ### Mikrotik Domain Filter Script: Bash solution for filtering domain lists, creating Adlists and DNS Static or DNS FWD entries for Mikrotik RouterOS
</div>

---

## Introduction

**Mikrotik Domain Filter Script** is a robust Bash solution (designed to run on Linux systems, not on RouterOS) primarily designed for filtering and processing domain lists for [Mikrotik](https://mikrotik.com/) devices, enabling straightforward management of blocklists or allowlists. This script also adapts seamlessly to other network environments, making it suitable for a wide range of domain-based filtering tasks. By combining domain classification, DNS validation, and whitelist handling, this tool offers a comprehensive workflow to create accurate and reliable filtered lists, ensuring efficient network policy enforcement.

Furthermore, this script is an excellent fit for building and maintaining [Adlists](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Adlist), which are curated collections of domains serving advertisements. By returning the IP address `0.0.0.0` for ad-serving domain queries, the Adlist feature effectively null-routes unwanted content, improving user experience and reducing bandwidth usage.  
In addition, the script integrates seamlessly with [DNS Static](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-DNSStatic) in Mikrotik RouterOS, allowing administrators to override specific DNS queries with custom entries, regular expressions, or dummy IP addresses for better control over DNS resolution. This functionality is particularly helpful for redirecting or blocking traffic at the DNS level—whether it’s entire zones or select domains.  
Lastly, the script can also aid in generating DNS FWD records, making it a comprehensive solution for all DNS-related configurations in a Mikrotik environment. The repository [includes an example script (dns-static-updater.rsc)](/routeros/dns-static-updater.rsc) specifically tailored for RouterOS, demonstrating how to load domain lists onto the router and form DNS FWD entries, ensuring an even smoother integration process.

#### TLDR; ⚡ Quick Setup Guide

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
> ⓘ **Tip**: Run `make help` to see all available commands!

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

- **Path Settings**: The script defines various paths for working directories, source files, output files, and temporary files.
- **Global Variables**: Variables for statistics like `TOTAL_DOMAINS`, `PROCESSED_DOMAINS`, and `VALID_DOMAINS` are declared.
- **Logging**: A logging mechanism is set up to record events and errors in a log file.
- **Lock Mechanism**: A file lock is used to ensure that only one instance of the script runs at a time, preventing conflicts.
- **Directory Initialization**: Required directories are checked and created if they don’t exist.
- **Dependency Check**: The script verifies the presence of required system tools: `curl`, `jq`, `grep`, `awk`, `sort`, `flock`, `find`, and `md5sum`.

### File Checks and Cleanup

- **Required Files**: The script checks for the existence of essential files like `sources.txt`, `sources_special.txt`, and others. If any are missing, the script exits with an error.
- **Cleanup**: Temporary files and outdated cache files are cleaned up to free up space and maintain script efficiency.

### Public Suffix List

- **Loading Public Suffix List**: The script downloads and updates the Public Suffix List if it’s outdated. This list is used to determine the type of domains (second-level, regional, etc.).
- The script utilizes the Mozilla Public Suffix List[^¹](https://publicsuffix.org/) - a standardized database of domain suffix information that helps properly identify the registrable domain parts.

### Domain Filtering and Classification

- **Initial Filtering**: Domains are filtered based on regex patterns to ensure they match the expected format. Invalid domains are discarded.
- **Domain Classification**: Domains are classified into second-level, regional, and other types. This involves parsing the domain, checking against the Public Suffix List, and categorizing accordingly.
- **Whitelist Application**: A whitelist of domains is applied to filter out domains that should not be blocked or allowed.

### DNS Checks  

- **Domain Validation**: Each domain is checked via DNS to ensure it resolves correctly. This involves sending a DNS query and verifying the response.  
- **Parallel Processing**: To improve efficiency, DNS checks are performed concurrently using background subshells. Results are stored in temporary files and aggregated.
- **DNS Resolution Method**: Verification is performed using Cloudflare's DNS-over-HTTPS (DoH) service[^¹](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/), which provides:  
  - Encrypted DNS queries  
  - JSON API support  
  - High reliability and performance  

**Endpoint**: `https://cloudflare-dns.com/dns-query`  

For detailed information about the API requests and response format, please refer to the [official documentation](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/).

### Result Validation and Saving

- **Result Validation**: The final lists of domains are validated to ensure they meet the required format and are correctly classified.
- **Saving Results**: The validated domain lists are saved to output files. Backups are created before overwriting existing files to ensure data integrity.
- **Gist Update**: If the results are valid, the script updates GitHub Gists with the new domain lists.

### Update Checks and Backups

- **Update Needed Check**: The script checks if the source files have changed using MD5 checksums. If no changes are detected, the script exits early to save resources.
- **Backup Restoration**: If any step fails, the script restores backups of the output files to maintain the previous state.

### Pipeline Summary

1. **Initialization**: Set up paths, variables, and dependencies.
2. **File Checks**: Verify required files and clean up temporary files.
3. **Public Suffix List**: Load and update the Public Suffix List.
4. **Domain Filtering**:
   - Initial filter based on regex.
   - Classify domains into types.
   - Apply whitelist.
5. **DNS Checks**: Validate domains via DNS in parallel.
6. **Result Validation and Saving**:
   - Validate final domain lists.
   - Save results to output files.
   - Update GitHub Gists.
7. **Cleanup and Backup**: Clean temporary files and restore backups if needed.

This script ensures that domain lists are accurately filtered, validated, and updated, providing a robust solution for managing domain-based network policies.

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
This file contains a list of URLs from which whitelist domain lists are downloaded. Each URL should be on a separate line. The script downloads and processes these lists to create a comprehensive whitelist. Domains found in these lists will be excluded from both the main and special lists during processing.  

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

This part describes the detailed process of handling domains from downloaded lists, including filtering, validation, whitelisting, and special list exclusions. The examples provided will use the specified domains and their subdomains, along with complex input formats such as Clash and Clash New.

#### 1. Initial Filtering

The initial filtering step removes invalid domains, comments, and empty lines from the input lists. It also converts all domains to lowercase and removes any spaces. Additionally, it handles complex formats like Clash and Clash New, extracting only the domains.

**Example Input:**
```
# This is a comment
MikroTik.com
help.mikrotik.com
Debian.org
youtube.com
wikipedia.org
instagram.com
tiktok.com
spotify.com
googlevideo.com
invalid domain
.invalid
invalid.
# Clash format
ALLOW-IP, 1.1.1.1
ALLOW-IP, 8.8.8.8
FALLBACK, example.com
# Clash New format
rule, DOMAIN-SUFFIX, example.com
rule, IP-CIDR, 1.1.1.1/32
```

**Example Output:**
```
debian.org
googlevideo.com
mikrotik.com
instagram.com
spotify.com
tiktok.com
wikipedia.org
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

#### 2. Domain Classification

Domains are classified into three categories: second-level, regional, and other.

**Second-level domains:**
```
debian.org
mikrotik.com
wikipedia.org
youtube.com
```

**Regional domains:**
```
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

**Other domains:**
```
help.mikrotik.com
cdn.cache.googlevideo.com
help.instagram.com
cdn.spotify.com
global.tiktok.com
```

#### 3. DNS Validation

Domains are checked for validity using DNS queries. Only domains that resolve correctly are retained.

**Example Input:**
```
debian.org
googlevideo.com
instagram.com
mikrotik.com
spotify.com
tiktok.com
wikipedia.org
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

**Example Output (assuming all domains resolve correctly):**
```
debian.org
googlevideo.co
instagram.com
mikrotik.com
spotify.com
tiktok.com
wikipedia.org
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

#### 4. Whitelisting

Domains listed in the whitelist are excluded from the main and special lists.

**Example Whitelist:**
```
mikrotik.com
wikipedia.org
```

**Main List Before Whitelisting:**
```
debian.org
googlevideo.com
help.mikrotik.com
instagram.com
mikrotik.com
spotify.com
tiktok.com
wikipedia.org
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

**Main List After Whitelisting:**
```
debian.org
googlevideo.com
instagram.com
spotify.com
tiktok.com
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

#### 5. Special List Exclusion

Domains in the special list are excluded from the main list to avoid duplicates.

**Example Special List:**
```
tiktok.com
youtube.co.uk
```

**Main List Before Exclusion:**
```
debian.org
googlevideo.com
instagram.com
spotify.com
tiktok.com
youtube.com
youtube.co.uk
instagram.net.pl
workplace.co.jp
```

**Main List After Exclusion:**
```
debian.org
googlevideo.com
instagram.com
spotify.com
instagram.net.pl
workplace.co.jp
```

#### Summary of Processing Steps

1. **Initial Filtering:** Remove invalid domains, comments, and empty lines. Convert to lowercase and remove spaces. Extract domains from complex formats like Clash and Clash New.
2. **Domain Classification:** Classify domains into second-level, regional, and other categories.
3. **DNS Validation:** Check domain validity using DNS queries.
4. **Whitelisting:** Exclude domains listed in the whitelist.
5. **Special List Exclusion:** Exclude domains from the special list to avoid duplicates.

#### Example Final Output

**Main List:**
```
debian.org
googlevideo.com
instagram.com
spotify.com
instagram.net.pl
workplace.co.jp
```

**Special List:**
```
tiktok.com
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

#### Key Features
- Direct GitHub API integration
- Support for environment variables
- Configurable Gist updates
- Improved error handling
- Detailed logging

#### Requirements
- `curl` for API requests
- `jq` for JSON processing

#### Notes
- The `.env` file must have restricted permissions (`chmod 600`) — the script warns if permissions are too open
- Environment variables can also be set directly in the shell
- Set `EXPORT_GISTS=false` to disable Gist updates
- All numeric values are validated; GIST_ID is validated as hex (20-32 chars)

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
│   └── test_extract_domains.bats   # Domain extraction tests
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
- **Test first, backup always, deploy confidently!**
- Monitor log files (`script.log`) for issues
- Ensure sufficient disk space for cache and logs
- The script uses file locking (`flock`) to prevent concurrent runs
- All files and directories are created with owner-only permissions (700/600)
- HTTPS is enforced for all external connections (source downloads, DNS-over-HTTPS, GitHub API)

---

### Script Workflow Diagram

```markdown
# ➤ Main Process Flow

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
[DNS Validation]
   │
   ├── Parallel DNS checks
   ├── Cache results
   └── Retry failed checks
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
   └── Remove duplicates
   │
   ▼
[Result Validation]
   │
   ├── Format check
   ├── DNS resolution verification
   └── Content validation
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

# ➤ Error Handling Flow

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

# ➤ Parallel Processing

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

This workflow ensures reliable and efficient domain list processing while maintaining data integrity and handling errors gracefully.

### Benchmarking

> **Environment**: Amazon Lightsail (512 MB RAM, 2 vCPUs, 20 GB SSD, Debian 12.8)  
> **Processing**: 86K domains + 12K whitelist + 2.7K special → 1,970 unique (main) + 431 unique (special)  
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

## ⚠️ Legal Disclaimer and Limitation of Liability  

### ❗ Software Disclaimer  

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,   
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A   
PARTICULAR PURPOSE AND NONINFRINGEMENT.  

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,   
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER   
DEALINGS IN THE SOFTWARE.  

## 📝 License

Author: SMKRV
[MIT License](https://opensource.org/licenses/MIT) - see [LICENSE](LICENSE) for details.

## 💡 Support the Project

The best support is:
- Sharing feedback
- Contributing ideas
- Recommending to friends
- Reporting issues
- Star the repository

If you want to say thanks financially, you can send a small token of appreciation in USDT:

**USDT Wallet (TRC10/TRC20):**
`TXC9zYHYPfWUGi4Sv4R1ctTBGScXXQk5HZ`

*Open-source is built by community passion!* 🚀

---
<div align="center">
Made with ❤️ for the Mikrotik Community

[Report Bug](https://github.com/smkrv/mikrotik-domain-filter-script/issues) · [Request Feature](https://github.com/smkrv/mikrotik-domain-filter-script/issues)
</div>
