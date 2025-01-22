<div align="center">  

  ![GitHub last commit](https://img.shields.io/github/last-commit/smkrv/mikrotik-domain-filter-script.svg?style=flat-square) [![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg?style=flat-square)](https://creativecommons.org/licenses/by-nc-sa/4.0/) ![RouterOS](https://img.shields.io/badge/RouterOS-7.17-blue) ![RouterOS](https://img.shields.io/badge/RouterOS-6.17-blue) ![Status](https://img.shields.io/badge/Status-Production-green) ![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?logo=Cloudflare&logoColor=white) ![English](https://img.shields.io/badge/en-English-blue?style=flat-square)


  <img src="/assets/images/logo@2x.png" alt="HA Text AI" style="width: 50%; max-width: 256px; max-height: 128px; aspect-ratio: 2/1; object-fit: contain;"/>

  ### Mikrotik Domain Filter Script: Bash solution for filtering domain lists, creating Adlists and DNS Static entries for Mikrotik RouterOS
</div>

**Mikrotik Domain Filter Script** is a robust Bash solution (designed to run on *nix systems, not on RouterOS) primarily designed for filtering and processing domain lists for [Mikrotik](https://mikrotik.com/) devices, enabling straightforward management of blocklists or allowlists. This script also adapts seamlessly to other network environments, making it suitable for a wide range of domain-based filtering tasks. By combining domain classification, DNS validation, and whitelist handling, this tool offers a comprehensive workflow to create accurate and reliable filtered lists, ensuring efficient network policy enforcement.

Furthermore, this script is an excellent fit for building and maintaining [Adlists](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Adlist), which are curated collections of domains serving advertisements. By returning the IP address `0.0.0.0` for ad-serving domain queries, the Adlist feature effectively null-routes unwanted content, improving user experience and reducing bandwidth usage.  
In addition, the script integrates seamlessly with [DNS Static](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-DNSStatic) in Mikrotik RouterOS, allowing administrators to override specific DNS queries with custom entries, regular expressions, or dummy IP addresses for better control over DNS resolution. This functionality is particularly helpful for redirecting or blocking traffic at the DNS level—whether it’s entire zones or select domains.  
Lastly, the script can also aid in generating DNS FWD records, making it a comprehensive solution for all DNS-related configurations in a Mikrotik environment. The repository [includes an example script (dns-static-updater.rsc)](dns-static-updater.rsc) specifically tailored for RouterOS, demonstrating how to load domain lists onto the router and form DNS FWD entries, ensuring an even smoother integration process.

#### 1. **Initialization and Setup**

- **Path Settings**: The script defines various paths for working directories, source files, output files, and temporary files.
- **Global Variables**: Variables for statistics like `TOTAL_DOMAINS`, `PROCESSED_DOMAINS`, and `VALID_DOMAINS` are declared.
- **Logging**: A logging mechanism is set up to record events and errors in a log file.
- **Lock Mechanism**: A file lock is used to ensure that only one instance of the script runs at a time, preventing conflicts.
- **Directory Initialization**: Required directories are checked and created if they don’t exist.
- **Dependency Check**: The script verifies the presence of required system tools like `curl`, `grep`, `awk`, `sort`, and `parallel`.

#### 2. **File Checks and Cleanup**

- **Required Files**: The script checks for the existence of essential files like `sources.txt`, `sources_special.txt`, and others. If any are missing, the script exits with an error.
- **Cleanup**: Temporary files and outdated cache files are cleaned up to free up space and maintain script efficiency.

#### 3. **Public Suffix List**

- **Loading Public Suffix List**: The script downloads and updates the Public Suffix List if it’s outdated. This list is used to determine the type of domains (second-level, regional, etc.).

#### 4. **Domain Filtering and Classification**

- **Initial Filtering**: Domains are filtered based on regex patterns to ensure they match the expected format. Invalid domains are discarded.
- **Domain Classification**: Domains are classified into second-level, regional, and other types. This involves parsing the domain, checking against the Public Suffix List, and categorizing accordingly.
- **Whitelist Application**: A whitelist of domains is applied to filter out domains that should not be blocked or allowed.

#### 5. **DNS Checks**  

- **Domain Validation**: Each domain is checked via DNS to ensure it resolves correctly. This involves sending a DNS query and verifying the response.  
- **Parallel Processing**: To improve efficiency, DNS checks are performed in parallel using the `parallel` tool. Results are stored in temporary files and aggregated.  
- **DNS Resolution Method**: Verification is performed using Cloudflare's DNS-over-HTTPS (DoH) service[^¹](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/), which provides:  
  - Encrypted DNS queries  
  - JSON API support  
  - High reliability and performance  

**Endpoint**: `https://cloudflare-dns.com/dns-query`  

For detailed information about the API requests and response format, please refer to the [official documentation](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/).

#### 6. **Result Validation and Saving**

- **Result Validation**: The final lists of domains are validated to ensure they meet the required format and are correctly classified.
- **Saving Results**: The validated domain lists are saved to output files. Backups are created before overwriting existing files to ensure data integrity.
- **Gist Update**: If the results are valid, the script updates GitHub Gists with the new domain lists.

#### 7. **Update Checks and Backups**

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
https://raw.githubusercontent.com/example/repo/main/domains.txt
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
https://raw.githubusercontent.com/example/repo/main/special-domains.txt
https://example.com/additional-special-domains.txt
```

#### `WHITELIST_FILE`

**File Path:** `${WORK_DIR}/sources_whitelist.txt`

**Description:**
This file contains a list of domains that should be excluded from both the main and special lists. Each domain should be on a separate line. The script will use this file to filter out domains that are listed in the whitelist.

**Format:**
```
example.com
example.org
example.net
```

**Example Contents:**
```
mikrotik.com
wikipedia.org
```

### Summary

- **`SOURCES_FILE`**: Contains URLs for downloading the main domain lists.
- **`SOURCESSPECIAL_FILE`**: Contains URLs for downloading the special domain lists.
- **`WHITELIST_FILE`**: Contains domains that should be excluded from both the main and special lists.

Each file should have one URL or domain per line, with no additional spaces or characters.

### Detailed Description of Domain Processing in Downloaded Lists

This document describes the detailed process of handling domains from downloaded lists, including filtering, validation, whitelisting, and special list exclusions. The examples provided will use the specified domains and their subdomains, along with complex input formats such as Clash and Clash New.

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
googlevideo.com
instagram.com
spotify.com
tiktok.com
```

#### 3. DNS Validation

Domains are checked for validity using DNS queries. Only domains that resolve correctly are retained.

**Example Input:**
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

**Example Output (assuming all domains resolve correctly):**
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

### Summary of Processing Steps

1. **Initial Filtering:** Remove invalid domains, comments, and empty lines. Convert to lowercase and remove spaces. Extract domains from complex formats like Clash and Clash New.
2. **Domain Classification:** Classify domains into second-level, regional, and other categories.
3. **DNS Validation:** Check domain validity using DNS queries.
4. **Whitelisting:** Exclude domains listed in the whitelist.
5. **Special List Exclusion:** Exclude domains from the special list to avoid duplicates.

### Example Final Output

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

## Legal Disclaimer and Limitation of Liability  

### Software Disclaimer  

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
