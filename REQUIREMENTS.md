# Requirements  

## System Requirements  
- Bash version: >= 4.0  
- Operating System: Ubuntu 20.04+ / Debian 10+ / macOS 10.15+  
- Minimum disk space: 100MB for logs and cache  
- Internet connection for downloading domain lists  

## Required Commands and Utilities  
- curl (>= 7.68.0) - for downloading files and API requests  
- jq (>= 1.6) - for JSON processing  
- grep (GNU grep) - for text processing  
- awk (GNU awk) - for text processing  
- sort - for list sorting  
- parallel - for parallel processing  
- md5sum - for checksum verification  

## Optional Dependencies   
- logrotate - for log management  
- systemd (if running as a service)  

## Network Requirements  
- Access to DNS servers (default: Cloudflare DoH DNS)  
- Access to GitHub API (for Gist updates)  
- Unrestricted access to domain list sources  

## Permissions  
- Execute permissions for script files  
- Write permissions in working directory  
- Sudo rights might be required for initial setup
