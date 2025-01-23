<div align="center">  

[![GitHub last commit](https://img.shields.io/github/last-commit/smkrv/mikrotik-domain-filter-script.svg?style=flat-square)](https://github.com/smkrv/mikrotik-domain-filter-script/commits) [![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg?style=flat-square)](https://creativecommons.org/licenses/by-nc-sa/4.0/) [![RouterOS](https://img.shields.io/badge/RouterOS-7.17-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) [![RouterOS](https://img.shields.io/badge/RouterOS-6.17-blue?style=flat-square)](https://help.mikrotik.com/docs/display/ROS/RouterOS) ![Status](https://img.shields.io/badge/Status-Production-green?style=flat-square) [![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat-square&logo=Cloudflare&logoColor=white)](https://www.cloudflare.com/) [![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-red?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org/releases/bookworm/) [![Ubuntu](https://img.shields.io/badge/Ubuntu-24.10-orange?style=flat-square&logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/24.10/) [![Ubuntu LTS](https://img.shields.io/badge/Ubuntu%20LTS-22.04-orange?style=flat-square&logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/22.04/) [![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success?style=flat-square&logo=gnu-bash&logoColor=white)](https://github.com/smkrv/mikrotik-domain-filter-script/actions/workflows/shellcheck.yml) ![English](https://img.shields.io/badge/en-English-blue?style=flat-square)


  <img src="/assets/images/logo@2x.png" alt="Mikrotik Domain Filter Script" style="width: 70%; max-width: 960px; max-height: 480px; aspect-ratio: 16/9; object-fit: contain;"/>

  ### Mikrotik Domain Filter Script: Bash solution for filtering domain lists, creating Adlists and DNS Static or DNS FWD entries for Mikrotik RouterOS
</div>

---

## Introduction

**Mikrotik Domain Filter Script** is a robust Bash solution (designed to run on *nix systems, not on RouterOS) primarily designed for filtering and processing domain lists for [Mikrotik](https://mikrotik.com/) devices, enabling straightforward management of blocklists or allowlists. This script also adapts seamlessly to other network environments, making it suitable for a wide range of domain-based filtering tasks. By combining domain classification, DNS validation, and whitelist handling, this tool offers a comprehensive workflow to create accurate and reliable filtered lists, ensuring efficient network policy enforcement.

Furthermore, this script is an excellent fit for building and maintaining [Adlists](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Adlist), which are curated collections of domains serving advertisements. By returning the IP address `0.0.0.0` for ad-serving domain queries, the Adlist feature effectively null-routes unwanted content, improving user experience and reducing bandwidth usage.  
In addition, the script integrates seamlessly with [DNS Static](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-DNSStatic) in Mikrotik RouterOS, allowing administrators to override specific DNS queries with custom entries, regular expressions, or dummy IP addresses for better control over DNS resolution. This functionality is particularly helpful for redirecting or blocking traffic at the DNS level—whether it’s entire zones or select domains.  
Lastly, the script can also aid in generating DNS FWD records, making it a comprehensive solution for all DNS-related configurations in a Mikrotik environment. The repository [includes an example script (dns-static-updater.rsc)](dns-static-updater.rsc) specifically tailored for RouterOS, demonstrating how to load domain lists onto the router and form DNS FWD entries, ensuring an even smoother integration process.

#### TLDR; ⚡ Quick Setup Guide

<div style="font-size:80%; border: 1px solid #ddd; padding: 10px; border-radius: 5px; background-color: #f9f9f9;">

>  **Prerequisites**
> - Unix-like system  
> - Install dependencies: `sudo apt-get install curl jq gawk grep parallel`  
>  
> **Setup Steps**  
> 1. Create a working directory  
> 2. Copy scripts:  
>    - `mikrotik-domain-filter-bash.sh`  
>    - `update_gist.sh`  
>    - `update_gist_special.sh`  
>  
> 3. Configure scripts:  
>    - Set working directory path in `mikrotik-domain-filter-bash.sh`  
>    - Create source files:  
>      * `sources.txt`: Main domain list URLs  
>      * `sources_special.txt`: Special domain list URLs  
>      * `sources_whitelist.txt`: URLs of domain lists to exclude  
>  
> 4. Configure Gist updates (optional):  
>    - Set GitHub token and Gist variables in `update_gist.sh` and `update_gist_special.sh`  
>    - Or comment out Gist update functions in main script  
>  
> 5. Add download URLs to source files  
>  
> 6. Set execution permissions:  
>    ```bash  
>    chmod +x mikrotik-domain-filter-bash.sh update_gist.sh update_gist_special.sh  
>    ```  
>  
> 7. Run the main script:  
>    ```bash  
>    ./mikrotik-domain-filter-bash.sh  
>    ```  
>  
> **Output**  
> - Filtered domain lists:  
>   * `filtered_domains_mikrotik.txt`  
>   * `filtered_domains_special_mikrotik.txt`  
> - Logs: `script.log`  
>  
> **MikroTik Configuration**  
> 1. Import `dns-static-updater.rsc`  
> 2. Configure DNS static records import for main and special domain lists  
> 3. Set up local Mangle and other necessary rules  
>  
> ⓘ **Tip**: Test thoroughly and monitor system resources!

</div>  

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
11. [GitHub Gist Update Scripts](#github-gist-update-scripts)
12. [Project Structure](#project-structure)
13. [Installation and Setup](#installation-and-setup)
14. [Running the Script](#running-the-script)
15. [Important Notes](#important-notes)
16. [Script Workflow Diagram](#script-workflow-diagram)
17. [Prerequisites](#prerequisites)
18. [Benchmarking](#benchmarking-%EF%B8%8F-)
19. [MikroTik Router Configuration](#mikrotik-router-configuration)

---

### Initialization and Setup

- **Path Settings**: The script defines various paths for working directories, source files, output files, and temporary files.
- **Global Variables**: Variables for statistics like `TOTAL_DOMAINS`, `PROCESSED_DOMAINS`, and `VALID_DOMAINS` are declared.
- **Logging**: A logging mechanism is set up to record events and errors in a log file.
- **Lock Mechanism**: A file lock is used to ensure that only one instance of the script runs at a time, preventing conflicts.
- **Directory Initialization**: Required directories are checked and created if they don’t exist.
- **Dependency Check**: The script verifies the presence of required system tools like `curl`, `grep`, `awk`, `sort`, and `parallel`.

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
- **Parallel Processing**: To improve efficiency, DNS checks are performed in parallel using the `parallel` tool. Results are stored in temporary files and aggregated.  
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
https://example.com/domain-list1.txt
https://example.org/domain-list2.txt
https://example.net/domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.tiktok.txt
https://example.com/additional-domains.txt
```

#### `SOURCESSPECIAL_FILE`

**File Path:** `${WORK_DIR}/sources_special.txt`

**Description:**
This file contains a list of URLs from which the special domain lists are downloaded. Each URL should be on a separate line. The script will download the content from these URLs and process them to extract and filter domains, which will then be excluded from the main list to avoid duplicates.

**Format:**
```
https://example.com/special-domain-list1.txt
https://example.org/special-domain-list2.txt
https://example.net/special-domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/doh.txt
https://example.com/additional-special-domains.txt
```

#### `WHITELIST_FILE`

**File Path:** `${WORK_DIR}/sources_whitelist.txt`

**Description:**
This file contains a list of URLs from which whitelist domain lists are downloaded. Each URL should be on a separate line. The script downloads and processes these lists to create a comprehensive whitelist. Domains found in these lists will be excluded from both the main and special lists during processing.  

**Format:**
```
https://example.com/domain-list1.txt
https://example.org/domain-list2.txt
https://example.net/domain-list3.txt
```

**Example Contents:**
```
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.apple.txt
https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/domains/native.samsung.txt
```

### Summary

- **`SOURCES_FILE`**: Contains URLs for downloading the main domain lists.
- **`SOURCESSPECIAL_FILE`**: Contains URLs for downloading the special domain lists.
- **`WHITELIST_FILE`**: Contains URLs for downloading domains that should be excluded from both the main and special lists.

**Each file should have one URL or domain per line, with no additional spaces or characters.**

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

### GitHub Gist Update Scripts

This repository contains two identical shell scripts ([update_gist_special.sh](/update_gist_special.sh) and [update_gist.sh](/update_gist.sh)) that update different GitHub Gists with local file content. The scripts share the same functionality but use different variables and target different Gists.

#### Scripts Overview

Both scripts perform the same operations but are configured for different Gists:
- `update_gist_special.sh` - configured for one specific Gist
- `update_gist.sh` - configured for another Gist

The only difference between these scripts is in their configuration variables (GitHub token, Gist ID, file names, and paths).

#### Technical Details

The scripts require:
- `curl` for making API requests
- `jq` for JSON processing

Each script performs the following operations:
1. Validates the presence of required utilities
2. Reads the content from a specified local file
3. Updates the target Gist via GitHub API
4. Verifies the update was successful

#### Usage

To use either script, you need to configure the following variables:
```bash
GITHUB_TOKEN="your-github-token"
GIST_ID="your-gist-id"
FILENAME="filename-in-gist"
LOCAL_FILE_PATH="path/to/local/file"
```

After configuring the variables, you can run either script to update its corresponding Gist with the content from the specified local file.

#### Note

While the scripts are identical in functionality, they are maintained as separate files to avoid the need for changing variables when updating different Gists. This approach allows for easier automation and maintenance of multiple Gist updates.

---

### Project Structure

```
...
├── dns-static-updater.rsc      # MikroTik RouterOS script for DNS Static records import
├── mikrotik-domain-filter-bash.sh    # Main domain filtering script
├── update_gist.sh             # Script for updating main list Gist
└── update_gist_special.sh     # Script for updating special list Gist
```

### Installation and Setup

#### Prerequisites
- Unix-like operating system
- Bash shell
- Sudo rights (might be required for setup)  
- Required permissions to execute scripts
- Sufficient disk space for logs and cache

#### Setup Steps

1. **Create Directory Structure**
   - Create a working directory
   - Place all necessary source files
   - Configure required variables in scripts

2. **Prepare Scripts**
   ```bash
   # You might need sudo rights to change file permissions  
   sudo chmod +x mikrotik-domain-filter-bash.sh  
   sudo chmod +x update_gist.sh        # If using Gist updates  
   sudo chmod +x update_gist_special.sh # If using special Gist updates  

   # Or if you own the files:  
   chmod +x mikrotik-domain-filter-bash.sh  
   chmod +x update_gist.sh        # If using Gist updates  
   chmod +x update_gist_special.sh # If using special Gist updates
   ```

3. **Configure Log Rotation**
   - Set up proper log rotation to manage script logs
   - Ensure sufficient disk space for logs

4. **Gist Updates (Optional)**
   - If you don't plan to use Gist updates, comment out the calls to `update_gist.sh` and `update_gist_special.sh` in `mikrotik-domain-filter-bash.sh`

#### Running the Script

1. Execute the main script:
   ```bash
   ./mikrotik-domain-filter-bash.sh
   ```

2. Check logs for any errors if the script fails to run properly

#### Important Notes
- Verify all variables are properly configured before running
- Monitor log files for any issues
- Ensure sufficient disk space on both the script host and MikroTik router
- Regular monitoring of script execution is recommended
- **⚠️ Remember: Test first, backup always, deploy confidently! 🛡️**

---

### Prerequisites  

Before running the script, ensure that your system meets all the requirements listed in [REQUIREMENTS.md](REQUIREMENTS.md).  

The script requires several system utilities and proper permissions to function correctly. Follow the quick installation guide below to set up all necessary dependencies.  

#### Quick Dependencies Installation  

For Ubuntu/Debian systems:  
```bash  
sudo apt-get update  
sudo apt-get install curl jq gawk grep parallel
```

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

### Benchmarking ⏱️ 📈

> **Environment**: Amazon Lightsail (512 MB RAM, 2 vCPUs, 20 GB SSD, Debian 12.8)  
> **Processing**: 86K domains + 12K whitelist + 2.7K special → 1,970 unique (main) + 431 unique (special)  
> **Performance**: 24 min processing time, 42% peak CPU

### MikroTik Router Configuration

#### System Requirements  
- RouterOS version 6.17 or higher  
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
- Large lists might cause memory issues on some devices  
- The script adds a 10ms delay between operations to prevent resource exhaustion  
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
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) - see [LICENSE](LICENSE) for details.

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
