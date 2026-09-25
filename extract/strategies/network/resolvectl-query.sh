#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: resolvectl-query
## Description: Parse `resolvectl query` answer into one wide record (name/addresses/link)
## Version: 1.0
## Priority: 22
## Sample: samples/resolvectl-query/basic.txt

# `resolvectl query NAME` prints the resolved addresses, then "-- ..." metadata
# lines:
#   example.com: 93.184.216.34                      -- link: eth0
#                2606:2800:220:1:248:1893:25c8:1946 -- link: eth0
#   -- Information acquired via protocol DNS in 24.1ms.
# This is a single observation (key/value snapshot): one wide record with the
# query name, the IPv4/IPv6 answers and the resolving link.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"-- link:"* ]] || return 1
    [[ "$text" == *"Information acquired via protocol"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        /-- link:/ {
            # Split off the "-- link: X" trailer.
            head=$0; sub(/[ \t]*--[ \t]*link:.*$/,"",head)
            lk=$0; sub(/^.*--[ \t]*link:[ \t]*/,"",lk); gsub(/[ \t]+/,"",lk)
            link=lk
            # head is either "name: address" (first) or "address" (continuation).
            if (head ~ /:[ \t]/ && head !~ /^[ \t]/) {
                nm=head; sub(/:.*$/,"",nm); gsub(/[ \t]+/,"",nm); name=nm
                addr=head; sub(/^[^:]*:[ \t]*/,"",addr); gsub(/[ \t]+/,"",addr)
                ipv4=addr
            } else {
                a=head; gsub(/[ \t]+/,"",a); ipv6=a
            }
        }
        END{
            print "entry1.name " (name==""?"-":name)
            print "entry1.address " (ipv4==""?"-":ipv4)
            print "entry1.address_ipv6 " (ipv6==""?"-":ipv6)
            print "entry1.link " (link==""?"-":link)
            print "total_entries 1"
        }
    '
}
