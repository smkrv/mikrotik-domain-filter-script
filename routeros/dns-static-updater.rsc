# --------------------------------------------------------------------------------------
# This script updates DNS static entries from a remote domain list in MikroTik.
# 1) Set :local listname to the desired address-list name.
# 2) Set :local fwdto to the DNS address where queries should be forwarded.
# 3) Set :local url to the raw URL that hosts the domain list.
# This script has been tested on ROS 6.17 Stable and ROS 7.17 Stable.
# DISCLAIMER: Use caution when adding large domain lists (beyond a few hundred domains).
# Large lists might cause memory issues on some devices.
# For more details, see: https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-Introduction
#
# @license: CC BY-NC-SA 4.0 International
# @author: SMKRV
# @github: https://github.com/smkrv/mikrotik-domain-filter-script
# @source: https://github.com/smkrv/mikrotik-domain-filter-script
# -------------------------------------------------------------------------------------- 

:local listname "allow-list";
:local fwdto "localhost";
:local url "https://raw.githubusercontent.com/example/repo/main/special-domains.txt";
:local counter 0;
:local removedCounter 0;
:local validDomains [:toarray ""];

# Log start
:log info ("Starting DNS entries update script for list: " . $listname);

# Step 1: Remove old entries
:log info "Removing old DNS static entries...";
:foreach i in=[/ip dns static find where address-list=$listname comment="Added by $listname script"] do={
    :local currentName [/ip dns static get $i name];
    :log info ("Removing outdated entry: " . $currentName);
    /ip dns static remove $i;
    :set removedCounter ($removedCounter + 1);

    # Add a delay of 10 milliseconds after each entry
    :delay 10ms;
}

# Step 2: Fetch the full file
:log info "Fetching source file...";
:local fetchResult [/tool fetch url=$url mode=https as-value output=user];
:local chunkData ($fetchResult->"data");
:if ([:len $chunkData] = 0) do={
    :log error "Failed to fetch DNS list or source file is empty.";
    :error "DNS list fetch failed.";
}

# Step 3: Split data into individual domains and ignore invalid rows
:log info "Processing DNS list...";
:local newline "\n";
:local pos 0;
:local len [:len $chunkData];
:while ($pos < $len) do={
    :local nlpos [:find $chunkData $newline $pos];
    :if ([:type $nlpos] = "nil") do={
        :set nlpos $len;
    }
    :local line [:pick $chunkData $pos $nlpos];
    :set pos ($nlpos + 1);

    # Clean up the domain (trim spaces)
    :while ([:len $line] > 0 and [:pick $line 0 1] = " ") do={
        :set line [:pick $line 1 [:len $line]];
    }
    :while ([:len $line] > 0 and [:pick $line ([:len $line] - 1) [:len $line]] = " ") do={
        :set line [:pick $line 0 ([:len $line] - 1)];
    }

    # Ignore empty lines and comments starting with "#"
    :if ([:len $line] > 0 && [:pick $line 0 1] != "#") do={
        :set ($validDomains->([:len $validDomains])) $line;
    }
}

:log info ("Total valid domains fetched: " . [:len $validDomains]);

# Step 4: Add new entries to DNS static
:log info "Adding new DNS static entries...";
:foreach domain in=$validDomains do={
    :if ([:len $domain] > 0) do={
        :do {
            /ip dns static add name=$domain type=FWD forward-to=$fwdto \
                address-list=$listname match-subdomain=yes \
                comment="Added by $listname script";
            :set counter ($counter + 1);
            :log info ("Added DNS entry: " . $domain);
        } on-error={
            :log warning ("Failed to add DNS entry for: " . $domain);
        }

        # Add a delay of 10 milliseconds after each entry
        :delay 10ms;
    }
}

# Complete log
:log info ("DNS update completed. Added " . $counter . " new entries, removed " . $removedCounter . "  entries from the list: " . $listname);
