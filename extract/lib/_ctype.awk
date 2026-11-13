# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# extract/lib/_ctype.awk — the engine's cell classifier, one letter per cell.
#
# Two programs share it, so a cell is judged the same way in both:
#   * the extract engine's column-type consistency (_FR_CONS_AWK in
#     lib/_discovery.sh), which reads it into its awk program text;
#   * provost's column types (transform/types.sh, PV-040), which judges the
#     cells of each column a capture files and records the result beside the
#     dataset.
# Call cons_init() once before ctype(). Run it under LC_ALL=C (byte-wise, as
# the engine does). mawk-safe: no gawk-only features.
    # ctype(v): one letter per cell — E empty/null, I integer, D decimal,
    # N number with a unit (size, rate, duration, percent, 1,234), T date /
    # time / datetime / clock duration, A IP / CIDR / MAC / host:port,
    # H hex / hash / uuid, V version, P path / URL, F flag, O digits and
    # punctuation (`8,1`, `0:0`), W word (one token), X text (several
    # tokens), R rule / box-art debris; Q (dotted quad: IPv4 or version)
    # and U (dotted date or calendar version) count for both readings.
    function ctype(v,   lv, n, i, t, dt, anyd) {
        sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        if (v == "") return "E"
        lv = tolower(v)
        if (lv ~ /^(-+|n\/a|na|none|null|nil|<none>|\(none\)|<nil>|\?|unknown|undefined|\*)$/) return "E"
        # rule / box-art debris: no letter or digit, and a run of 3 of one
        # punctuation byte or any non-ASCII byte (`-----+----`, `│`, `├─`)
        if (lv !~ /[a-z0-9]/ && (lv ~ /[^ -~]/ || lv ~ /(--|==|__|\+\+|~~|\*\*|\.\.|##)[-=_+~*.#]/)) return "R"
        if (index(lv, " ") == 0 && index(lv, "\t") == 0) return ctok(lv)
        # several tokens: a date / time written in words and numbers
        n = split(lv, _ct, /[ \t]+/); dt = 1; anyd = 0
        for (i = 1; i <= n; i++) {
            t = _ct[i]; sub(/,$/, "", t)
            if (t ~ _RE_MON || t ~ _RE_WDAY || t ~ _RE_TIME || t ~ _RE_DATE || t ~ _RE_DTIME) { anyd = 1; continue }
            if (t ~ /^[0-9]+$/ && length(t) <= 4) continue
            if (t ~ /^(am|pm|utc|gmt|z|[a-z][a-z]?[sd]t|[-+][0-9][0-9]:?[0-9][0-9])$/) continue
            dt = 0; break
        }
        if (dt && anyd) return "T"
        # a number and its unit: `12 kB`, `30 ms`, `5 days`, `2 weeks ago`
        if (lv ~ _RE_NUMSP) return (lv ~ / (ago|from now)$/ ? "T" : "N")
        return "X"
    }
    function ctok(t) {
        if (t ~ /^[-+]?[0-9]+$/) return "I"
        if (t ~ /^[-+]?([0-9]+\.[0-9]*|\.[0-9]+)(e[-+]?[0-9]+)?$/) return "D"
        # dotted numbers: 3 parts are a version, or (a 4-digit year at one
        # end) a date or a calendar version; 4 parts an IPv4 or a version
        if (t ~ /^[0-9]+\.[0-9]+\.[0-9]+$/)
            return (t ~ /^([0-9][0-9][0-9][0-9]\.[0-9][0-9]?\.[0-9][0-9]?|[0-9][0-9]?\.[0-9][0-9]?\.[0-9][0-9][0-9][0-9])$/ ? "U" : "V")
        if (t ~ _RE_TIME || t ~ _RE_DATE || t ~ _RE_DTIME || t ~ _RE_MON || t ~ _RE_WDAY || t ~ _RE_MONDAY) return "T"
        if (t ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) return (ip4ok(t) ? "Q" : "V")
        if (t ~ _RE_IP4) return (ip4ok(t) ? "A" : "W")
        if (t ~ _RE_MAC || t ~ _RE_HOSTPORT) return "A"
        if (index(t, ":") && t ~ _RE_IP6) return "A"
        if (t ~ /^0x[0-9a-f]+$/ || (length(t) >= 7 && t ~ /^[0-9a-f]+$/ && t ~ /[a-f]/ && t ~ /[0-9]/) || t ~ _RE_UUID) return "H"
        if (t ~ _RE_NUM) return "N"
        if (t ~ _RE_VER) return "V"
        if (t ~ /^(\/|~\/|~$|\.\.?\/|[a-z]:\\|\\\\)/ || index(t, "://")) return "P"
        if (t ~ /^(yes|no|true|false|on|off|y|n|t|f|enabled|disabled|\+|ok)$/) return "F"
        # digits and punctuation that are no number, date or address
        # (`8,1`, `0:0`, a date cut short as `2026-10-`)
        if (t !~ /[a-z]/ && t ~ /[0-9]/) return "O"
        return "W"
    }
    # every octet of a dotted quad is at most 255
    function ip4ok(t,   q, k, j) {
        sub(/[\/:].*$/, "", t); k = split(t, q, ".")
        for (j = 1; j <= k; j++) if (q[j] + 0 > 255) return 0
        return 1
    }
    function cons_init(   u, mon, wday) {
        u = "[a-z%][a-z]?[a-z]?[a-z]?"
        # a number, its unit, and more duration parts (`1h30m`, `2d3h`)
        _RE_NUM = "^[-+]?[$]?([0-9]+(,[0-9][0-9][0-9])*(\\.[0-9]+)?|\\.[0-9]+)(" u ")?([0-9]+(\\.[0-9]+)?(ms|us|ns|[wdhms]))*(/" u ")?$"
        _RE_NUMSP = "^[-+]?[0-9]+(,[0-9][0-9][0-9])*(\\.[0-9]+)? (%|[kmgtpe]i?b?|bytes?|blocks?|pages?|[kmg]?hz|[kmg]?bps|x|[nuµm]?s|secs?|seconds?|mins?|minutes?|hrs?|hours?|days?|weeks?|months?|yrs?|years?)(/" u ")?( ago| from now)?$"
        mon = "(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)"
        wday = "(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)"
        _RE_MON = "^" mon "[a-z]*\\.?$"
        _RE_WDAY = "^" wday "[a-z]*,?$"
        _RE_MONDAY = "^" mon "[0-9][0-9]?$"
        _RE_TIME = "^([0-9]+-)?[0-9]+:[0-5][0-9](:[0-5][0-9])?([.,][0-9]+)?(am|pm|z)?$"
        _RE_DATE = "^([0-9][0-9][0-9][0-9][-/][0-9][0-9]?[-/][0-9][0-9]?|[0-9][0-9]?[-/][0-9][0-9]?[-/][0-9][0-9]([0-9][0-9])?|[0-9][0-9]?[-/ ]" mon "[a-z]*[-/ ][0-9][0-9]([0-9][0-9])?)$"
        _RE_DTIME = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][t_][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?([.,][0-9]+)?(z|[-+][0-9][0-9]:?[0-9][0-9])?$"
        _RE_IP4 = "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+(/[0-9]+|:[0-9*]+)?$"
        _RE_IP6 = "^\\[?[0-9a-f]*:[0-9a-f:]*:[0-9a-f.]*(%[a-z0-9]+)?\\]?(/[0-9]+|:[0-9*]+)?$"
        _RE_MAC = "^[0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f]$"
        _RE_HOSTPORT = "^(\\*|\\[[0-9a-f:]*\\]|[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+):([0-9]+|\\*)$"
        _RE_UUID = "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f-]+$"
        _RE_VER = "^v?[0-9]+(:[0-9]+)?(\\.[0-9]+)+([-+~._#a-z0-9]*)?(/v?[0-9]+(\\.[0-9]+)+)?$|^v[0-9]+$|^[0-9]+(\\.[0-9]+)*[-+~](rc|beta|alpha|dev|pre|post|git|el|fc|ubuntu|deb|r)[a-z0-9._~+-]*$"
        _CONS_INIT = 1
    }
