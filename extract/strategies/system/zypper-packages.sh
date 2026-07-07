#!/bin/bash
## Name: zypper-packages
## Description: Parse `zypper packages` box table (S | Repository | Name | Version | Arch)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/zypper-packages/basic.txt

# `zypper packages` prints a pipe-delimited box table:
#   S | Repository | Name | Version | Arch
#   --+------------+------+---------+-----
#   i | openSUSE-Oss | bash | 5.2.15-1.1 | x86_64
# preceded by "Loading repository data..." style status lines. One record per
# package row; status lines, the header and the "--+--" separator are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"| Repository"* ]] || return 1
    [[ "$text" == *"| Arch"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk -F'|' '
        function trim(s){ gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); gsub(/[ \t]+/,"_",s); return s }
        {
            if ($0 !~ /\|/) next                       # only table rows
            if ($0 ~ /Repository/) next                # header
            if ($0 ~ /^[ \t]*-.*\+/) next              # --+-- separator
            if (NF < 5) next
            s=trim($1); repo=trim($2); name=trim($3); ver=trim($4); arch=trim($5)
            e++
            print "entry" e ".s " (s==""?"-":s)
            print "entry" e ".repository " repo
            print "entry" e ".name " name
            print "entry" e ".version " ver
            print "entry" e ".arch " arch
        }
        END{ if(e>0) print "total_entries " e }
    '
}
