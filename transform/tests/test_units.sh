#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# Unit test for provost/transform/units.sh (PV-032, `--units base`): the
# conversion table, how a unit is read from a column's name, from a NAME_unit
# column and from its cells, which columns are left alone, and that every
# conversion is exact. Runs under whatever `awk` is first on PATH (mawk on
# Ubuntu; CI's quick-checks job).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../units.sh"

pass=0; fail=0
same () { if [[ "$2" == "$3" ]]; then echo "  ok   $1"; pass=$((pass+1))
          else echo "  FAIL $1"; echo "       want: $(printf '%q' "$2")"; echo "       got:  $(printf '%q' "$3")"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# cell VALUE [TOOL...] -> "base value<TAB>base unit<TAB>unit=factor", or "-"
cell () { local v="$1"; shift; printf '%s\n' "$v" | _core_units_cell "$@"; }
# hdr NAME -> the unit the column name carries, or "-"
hdr () { printf '%s\n' "$1" | _core_units_header; }
# conv TSV [TOOL...] -> the converted file, then "--", then the record
conv () {
    local t="$1"; shift
    printf '%s' "$t" > "$T/in.tsv"
    _core_units_base "$T/in.tsv" "$T/out.tsv" "$T/map" "$@"
    cat "$T/out.tsv"; printf -- '--\n'; cat "$T/map"
}
TAB=$'\t'

echo "== the conversion table (the ticket's list first)"
same "KB is 10^3 bytes"            "5000${TAB}B${TAB}KB=10^3"            "$(cell '5 KB')"
same "kB is 10^3 bytes"            "5000${TAB}B${TAB}kB=10^3"            "$(cell '5kB')"
same "KiB is 2^10 bytes"           "5120${TAB}B${TAB}KiB=2^10"           "$(cell '5 KiB')"
same "MB/s is 10^6 bytes a second" "9400000000${TAB}B/s${TAB}MB/s=10^6"  "$(cell '9400 MB/s')"
same "GB/s is 10^9 bytes a second" "9400000000${TAB}B/s${TAB}GB/s=10^9"  "$(cell '9.4 GB/s')"
same "Mb/s is 10^6 bits a second"  "1000000${TAB}bit/s${TAB}Mb/s=10^6"   "$(cell '1 Mb/s')"
same "Gbit/s is 10^9 bits a second" "25000000000${TAB}bit/s${TAB}Gbit/s=10^9" "$(cell '25 Gbit/s')"
same "us is 10^-6 s"               "0.00025${TAB}s${TAB}us=10^-6"        "$(cell '250 us')"
same "ms is 10^-3 s"               "0.000041${TAB}s${TAB}ms=10^-3"       "$(cell '0.041 ms')"
same "µs (micro sign) is 10^-6 s"  "0.00025${TAB}s${TAB}µs=10^-6"        "$(cell '250 µs')"
same "μs (Greek mu) is 10^-6 s"    "0.00025${TAB}s${TAB}μs=10^-6"        "$(cell '250μs')"
same "ns is 10^-9 s"               "0.000000003${TAB}s${TAB}ns=10^-9"    "$(cell '3 ns')"
same "usec / msec / nsec (fio)"    "0.5${TAB}s${TAB}msec=10^-3"          "$(cell '500msec')"
same "s, sec and seconds"          "2${TAB}s${TAB}seconds=1"             "$(cell '2 seconds')"
same "MiB/s (fio)"                 "505413632${TAB}B/s${TAB}MiB/s=2^20"  "$(cell '482MiB/s')"
same "GiB"                         "30279519436.8${TAB}B${TAB}GiB=2^30"  "$(cell '28.2GiB')"
same "MBytes, as labelled"         "112000000${TAB}B${TAB}MBytes=10^6"   "$(cell '112 MBytes')"
same "Mbits/sec"                   "9980000${TAB}bit/s${TAB}Mbits/sec=10^6" "$(cell '9.98 Mbits/sec')"
same "kbit/s (vnstat)"             "158720${TAB}bit/s${TAB}kbit/s=10^3"  "$(cell '158.72_kbit/s')"
same "Mbps is bits"                "100000000${TAB}bit/s${TAB}Mbps=10^6" "$(cell '100Mbps')"
same "MBps is bytes"               "100000000${TAB}B/s${TAB}MBps=10^6"   "$(cell '100MBps')"
same "bps"                         "8${TAB}bit/s${TAB}bps=1"             "$(cell '8 bps')"
same "Kibit is 2^10 bits"          "1024${TAB}bit${TAB}Kibit=2^10"       "$(cell '1 Kibit')"
same "EiB past 2^53, exactly"      "1152921504606846976${TAB}B${TAB}EiB=2^60" "$(cell '1 EiB')"
same "PB past 2^53, exactly"       "123456789012345678000${TAB}B${TAB}PB=10^15" "$(cell '123456.789012345678 PB')"
same "a fraction of a binary unit, exactly" "1.5${TAB}B${TAB}KiB=2^10" "$(cell '0.00146484375 KiB')"
same "an exponent"                 "1200000000${TAB}B${TAB}MB=10^6"      "$(cell '1.2e+03 MB')"
same "a negative number"           "-0.0005${TAB}s${TAB}ms=10^-3"        "$(cell '-0.5 ms')"
same "zero"                        "0${TAB}B${TAB}MB=10^6"               "$(cell '0 MB')"
same "a leading decimal point"     "500000${TAB}B${TAB}MB=10^6"          "$(cell '.5 MB')"
same "fio's 'value (same in another unit)': the first" \
     "505413632${TAB}B/s${TAB}MiB/s=2^20" "$(cell '482MiB/s (505MB/s)')"

echo "== bits and bytes, SI and IEC: never guessed"
same "a bare b is not a unit"       "-" "$(cell '100 b')"
same "lowercase mb (millibits?) is not read" "-" "$(cell '5 mb')"
same "a bare multiplier (free -h's Gi) is not read" "-" "$(cell '7.8Gi')"
same "a bare multiplier (df -h's G) is not read"    "-" "$(cell '1.2G')"
same "a bare K is not read"         "-" "$(cell '128K')"
same "parentheses holding another quantity: not read" "-" "$(cell '482MiB/s (505ms)')"
same "parentheses holding no number: not read"        "-" "$(cell '482MiB/s (x)')"
same "a range is not a number"      "-" "$(cell '60001-60001msec')"
same "a thousands separator is not read" "-" "$(cell '1,234 MB')"
same "trailing words are not a unit" "-" "$(cell '5 MB extra')"
same "an IP address is not a size"   "-" "$(cell '10.0.2.5')"
same "a huge exponent is refused"    "-" "$(cell '1e999 MB')"

echo "== tool conventions: iperf's byte labels are binary"
same "iperf3: MBytes is 2^20"       "117440512${TAB}B${TAB}MBytes=2^20 (iperf)" "$(cell '112 MBytes' iperf3)"
same "iperf: KBytes is 2^10"        "421888${TAB}B${TAB}KBytes=2^10 (iperf)"    "$(cell '412 KBytes' iperf)"
same "iperf3-intervals: MBytes/sec is 2^20" "3145728${TAB}B/s${TAB}MBytes/sec=2^20 (iperf)" "$(cell '3 MBytes/sec' iperf3-intervals)"
same "iperf3: Mbits/sec stays 10^6" "940000000${TAB}bit/s${TAB}Mbits/sec=10^6" "$(cell '940 Mbits/sec' iperf3)"
same "another tool: MBytes as labelled" "112000000${TAB}B${TAB}MBytes=10^6" "$(cell '112 MBytes' aligned-columns)"

echo "== a unit in a column's name"
same "(UNIT) after an underscore"  "MB/s"  "$(hdr 'Bandwidth_(MB/s)')"
same "(UNIT) after a space"        "MB/s"  "$(hdr 'Bandwidth (MB/s)')"
same "(UNIT) attached"             "us"    "$(hdr 'Latency(us)')"
same "[UNIT]"                      "MB"    "$(hdr 'Size[MB]')"
same "(s) after an underscore"     "s"     "$(hdr 'Time_(s)')"
same "(s) attached is a plural"    "-"     "$(hdr 'Error(s)')"
same "the whole name"              "MB/s"  "$(hdr 'MB/s')"
same "the last word"               "MB/s"  "$(hdr 'Best_Rate_MB/s')"
same "the last word (ms)"          "ms"    "$(hdr 'rtt_ms')"
same "not a bare s as the last word" "-"   "$(hdr 'kb_read_s')"
same "not glued to a word"         "-"     "$(hdr 'rxkB/s')"
same "not after per"               "-"     "$(hdr 'requests_per_ms')"
same "not a bare base word as a name" "-"  "$(hdr 'bytes')"
same "not a one-letter name"       "-"     "$(hdr 'B')"
same "not a count over time"       "-"     "$(hdr 'Messages/s')"
same "(bytes) is read"             "bytes" "$(hdr 'Size_(bytes)')"
same "(avg) is not a unit"         "-"     "$(hdr 'Size (avg)')"

echo "== whole datasets"
same "a unit in the name: plain numbers converted, NAME[UNIT] after it" \
     "n${TAB}Size${TAB}Bandwidth_(MB/s)${TAB}Bandwidth_(MB/s)[B/s]
1${TAB}1${TAB}3.26${TAB}3260000
2${TAB}2${TAB}6.55${TAB}6550000
--
Bandwidth_(MB/s)${TAB}Bandwidth_(MB/s)[B/s]${TAB}B/s${TAB}name${TAB}MB/s=10^6" \
     "$(conv "n${TAB}Size${TAB}Bandwidth_(MB/s)
1${TAB}1${TAB}3.26
2${TAB}2${TAB}6.55
")"
same "units in the cells, mixed prefixes of one quantity" \
     "n${TAB}rx${TAB}rx[B]
1${TAB}1.5 GiB${TAB}1610612736
2${TAB}512 MiB${TAB}536870912
3${TAB}-${TAB}
--
rx${TAB}rx[B]${TAB}B${TAB}cells${TAB}GiB=2^30,MiB=2^20" \
     "$(conv "n${TAB}rx
1${TAB}1.5 GiB
2${TAB}512 MiB
3${TAB}-
")"
same "a NAME_unit column: each row in its own unit, NAME[UNIT] after the pair" \
     "transfer${TAB}transfer_unit${TAB}transfer[B]${TAB}retr
112${TAB}MBytes${TAB}117440512${TAB}0
1.5${TAB}GBytes${TAB}1610612736${TAB}2
--
transfer${TAB}transfer[B]${TAB}B${TAB}column transfer_unit${TAB}MBytes=2^20 (iperf),GBytes=2^30 (iperf)" \
     "$(conv "transfer${TAB}transfer_unit${TAB}retr
112${TAB}MBytes${TAB}0
1.5${TAB}GBytes${TAB}2
" iperf3-intervals)"
same "a NAME_unit column holding something else: left alone" \
     "cwnd${TAB}cwnd_unit
0.041${TAB}0/861
--" \
     "$(conv "cwnd${TAB}cwnd_unit
0.041${TAB}0/861
")"
same "one unreadable cell leaves the whole column alone" \
     "n${TAB}size
1${TAB}5 MB
2${TAB}4.0K
--" \
     "$(conv "n${TAB}size
1${TAB}5 MB
2${TAB}4.0K
")"
same "a header-unit column with a non-plain number is left alone" \
     "kB/s
1,234.5
567.8
--" \
     "$(conv "kB/s
1,234.5
567.8
")"
same "bytes and bits in one column: left alone" \
     "rate
5 MB/s
5 Mb/s
--" \
     "$(conv "rate
5 MB/s
5 Mb/s
")"
same "a size and a time in one column: left alone" \
     "v
5 MB
3 s
--" \
     "$(conv "v
5 MB
3 s
")"
same "a name clash takes a leading _ (and the new column still follows its own)" \
     "a${TAB}_a[s]${TAB}a[s]
5 ms${TAB}0.005${TAB}x
--
a${TAB}_a[s]${TAB}s${TAB}cells${TAB}ms=10^-3" \
     "$(conv "a${TAB}a[s]
5 ms${TAB}x
")"
same "no unit anywhere: the file is unchanged, the record empty" \
     "n${TAB}name
1${TAB}a
--" \
     "$(conv "n${TAB}name
1${TAB}a
")"
same "a blank line is kept" \
     "t${TAB}t[s]
1 s${TAB}1

2 ms${TAB}0.002
--
t${TAB}t[s]${TAB}s${TAB}cells${TAB}s=1,ms=10^-3" \
     "$(conv "t
1 s

2 ms
")"
same "a header with only a header row: unchanged" \
     "Latency_(us)
--" \
     "$(conv "Latency_(us)
")"
same "a column name holding a backslash reaches the record intact" \
     "a\\t (ms)${TAB}a\\t (ms)[s]
5${TAB}0.005
--
a\\t (ms)${TAB}a\\t (ms)[s]${TAB}s${TAB}name${TAB}ms=10^-3" \
     "$(conv 'a\t (ms)
5
')"

# The cells' own numbers are never re-rounded: a value awk would print as
# 9.00719925474099e+15 in floating point comes out digit for digit.
same "9007199254740993 B (2^53 + 1) is kept exactly" \
     "x${TAB}x[B]
9007199254740993 B${TAB}9007199254740993
--
x${TAB}x[B]${TAB}B${TAB}cells${TAB}B=1" \
     "$(conv "x
9007199254740993 B
")"

echo
echo "units: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
