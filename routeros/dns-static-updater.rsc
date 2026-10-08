# Updates managed DNS FWD entries from an HTTPS domain list.
# Requires RouterOS 7.20.6 or later; RouterOS 6 is unsupported.
# Set listname, fwdto and url before importing as a named system script.
# fwdto is the forward-to target. Preserve localhost for existing deployments;
# verify that target on your router before changing it to an upstream IP or
# a configured DNS forwarder name.
# Run one instance at a time; this update is not a RouterOS transaction.
# Fetch output=user has a 64 KB limit. Reject responses at the conservative
# 64512-byte boundary, empty lists, malformed domains and >maxEntries lists.
# Split larger lists upstream; this script never applies a truncated list.
# Old entries remain until validation and every required addition succeed.
# An addition failure can leave new entries alongside the old entries.
# Back up configuration before first use. Live RouterOS testing is required.
# https://help.mikrotik.com/docs/spaces/ROS/pages/8978514/Fetch
# @license: MIT
# @author: SMKRV
# @github: https://github.com/smkrv/mikrotik-domain-filter-script

:local listname "allow-list";
:local fwdto "localhost";
:local url "https://YOUR_GITHUB_RAW_URL_HERE/special-domains.txt";
:local maxEntries 5000;
:local maxBytes 64512;
:local marker ("Added by " . $listname . " script");
:local wanted [:toarray ""];
:local kept [:toarray ""];
:local addedCounter 0;
:local removedCounter 0;

# Official named-script guard; import/run this as a single named system script.
:if ([/system script job print count-only as-value where script=[:jobname]] > 1) do={
    :error "DNS updater is already running";
}

:log info ("Fetching DNS list for " . $listname);
:local fetchResult [/tool fetch url=$url mode=https check-certificate=yes as-value output=user];
:if (($fetchResult->"status") != "finished") do={
    :error "DNS list fetch did not finish; existing entries retained";
}
:local data ($fetchResult->"data");
:local size [:len $data];
:if ($size = 0 or $size >= $maxBytes) do={
    :error "DNS list empty or at fetch size limit; existing entries retained";
}

# Parse and validate the entire response before changing DNS entries.
:local pos 0;
:while ($pos < $size) do={
    :local end [:find $data "\n" $pos];
    :if ([:typeof $end] = "nil") do={ :set end $size; }
    :local line [:pick $data $pos $end];
    :set pos ($end + 1);
    :while ([:len $line] > 0 and ([:pick $line 0 1] = " " or [:pick $line 0 1] = "\t")) do={
        :set line [:pick $line 1 [:len $line]];
    }
    :while ([:len $line] > 0 and ([:pick $line ([:len $line] - 1) [:len $line]] = " " or [:pick $line ([:len $line] - 1) [:len $line]] = "\r" or [:pick $line ([:len $line] - 1) [:len $line]] = "\t")) do={
        :set line [:pick $line 0 ([:len $line] - 1)];
    }
    :if ([:len $line] > 0 and [:pick $line 0 1] != "#") do={
        :set line [:convert $line transform=lc];
        :if ([:len $line] > 253 or !($line ~ "^[a-z0-9.-]+\$")) do={
            :error ("Invalid DNS domain: " . $line . "; existing entries retained");
        }
        :local start 0;
        :local labels 0;
        :while ($start < [:len $line]) do={
            :local dot [:find $line "." $start];
            :if ([:typeof $dot] = "nil") do={ :set dot [:len $line]; }
            :local label [:pick $line $start $dot];
            :if ([:len $label] = 0 or [:len $label] > 63 or [:pick $label 0 1] = "-" or [:pick $label ([:len $label] - 1) [:len $label]] = "-") do={
                :error ("Invalid DNS label: " . $line . "; existing entries retained");
            }
            :set labels ($labels + 1);
            :set start ($dot + 1);
        }
        :if ($labels < 2 or [:pick $line ([:len $line] - 1) [:len $line]] = ".") do={
            :error ("Invalid DNS domain: " . $line . "; existing entries retained");
        }
        :set ($wanted->$line) true;
        :if ([:len $wanted] > $maxEntries) do={
            :error "DNS list exceeds entry limit; existing entries retained";
        }
    }
}
:if ([:len $wanted] = 0) do={
    :error "DNS list contains no domains; existing entries retained";
}

# Capture old IDs so later removal cannot touch entries added by this run.
:local oldIds [/ip dns static find where address-list=$listname comment=$marker];
:foreach id in=$oldIds do={
    :local name [:convert [/ip dns static get $id name] transform=lc];
    :if (($wanted->$name) = true and [/ip dns static get $id type] = "FWD" and [/ip dns static get $id forward-to] = $fwdto and [/ip dns static get $id match-subdomain] = true and [/ip dns static get $id disabled] = false) do={
        :set ($kept->$name) true;
    }
}

# Add before removing anything. Abort on failure, retaining all old entries.
:foreach domain,value in=$wanted do={
    :if (($kept->$domain) != true) do={
        :do {
            /ip dns static add name=$domain type=FWD forward-to=$fwdto address-list=$listname match-subdomain=yes disabled=no comment=$marker;
        } on-error={
            :error ("Cannot add DNS entry for " . $domain . "; old entries retained, retry after fixing the error");
        }
        :set addedCounter ($addedCounter + 1);
        :delay 10ms;
    }
}

# All additions succeeded. Remove obsolete or mismatched managed entries only.
:foreach id in=$oldIds do={
    :local name [:convert [/ip dns static get $id name] transform=lc];
    :if (($wanted->$name) != true or [/ip dns static get $id type] != "FWD" or [/ip dns static get $id forward-to] != $fwdto or [/ip dns static get $id match-subdomain] != true or [/ip dns static get $id disabled] != false) do={
        /ip dns static remove $id;
        :set removedCounter ($removedCounter + 1);
        :delay 10ms;
    }
}
:log info ("DNS update completed for " . $listname . ": added " . $addedCounter . ", removed " . $removedCounter);
