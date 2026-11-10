# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# provost_redact.awk -- the secret scrub (PV-033). A capture's input passes
# through it before anything is stored: every known secret pattern is
# replaced by [REDACTED:kind], and the count of each kind is written to
# COUNTS ("kind<TAB>n" a line) so the capture can record what was scrubbed.
#
#   LC_ALL=C awk -f provost_redact.awk -v MODE=secrets -v COUNTS=FILE < in > out
#
# The kinds, each a pattern a secret scanner would flag with few false alarms:
#   private-key     a PEM or PGP private key block, BEGIN line to END line
#                   (to the end of the input when there is no END line)
#   authorization   the value of an Authorization: or Proxy-Authorization:
#                   header (to the end of the line, or of its quotes)
#   bearer          a token after the word Bearer (16 characters or more)
#   url-password    the password in scheme://user:password@host
#   aws-access-key  AKIA/ASIA/ABIA/ACCA + 16 capitals and digits
#   github-token    ghp_/gho_/ghu_/ghs_/ghr_ + 36, or github_pat_ + 22 or more
#   slack-token     xoxb-/xoxa-/xoxp-/xoxo-/xoxs-/xoxr- + 10 or more
#   vault-token     hvs./hvb./hvr. + 20 or more
#   jwt             three base64url parts, the first two starting eyJ
#   password, secret, token, api-key
#                   the value after a key whose name ends in password or
#                   passphrase; secret, private_key, credential(s); token;
#                   api_key, apikey or access_key -- as KEY=VALUE, KEY: VALUE,
#                   "KEY": "VALUE", or after --KEY on a command line
#
# A value that already says it is hidden or empty (yes, no, true, false,
# none, null, -, ***, <hidden>, $VAR, ...) is left as it is. Nothing here
# looks at host names or addresses: those are data, and are pseudonymised
# only on export (provost_pseudo.awk).
#
# mawk-safe: no interval expressions, no gawk extensions. Run under LC_ALL=C,
# so lengths are bytes and tolower() keeps every offset.

function _rep(s, n,    o) { o = ""; while (n-- > 0) o = o s; return o }

function redact_init() {
    if (_RX_INIT) return
    _RX_INIT = 1
    RX_PEM_BEGIN = "-----BEGIN [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----"
    RX_PEM_END   = "-----END [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----"
    RX_AUTH = "(proxy-)?authorization[\"']?[ \t]*[:=][ \t]*"
    RX_URL  = "[A-Za-z][A-Za-z0-9+.-]*://[^/ \t:@'\"<>]+:[^/ \t'\"<>]+@"
    RX_BEARER = "bearer[ \t]+"
    RX_TOKCH = "[A-Za-z0-9._~+/=-]"
    # Token formats, each with the characters around it checked by _bounded.
    NTOK = 0
    TOK[++NTOK] = "(AKIA|ASIA|ABIA|ACCA)" _rep("[A-Z0-9]", 16);           TOKK[NTOK] = "aws-access-key"
    TOK[++NTOK] = "gh[pousr]_" _rep("[A-Za-z0-9]", 36) "[A-Za-z0-9]*";    TOKK[NTOK] = "github-token"
    TOK[++NTOK] = "github_pat_" _rep("[A-Za-z0-9_]", 22) "[A-Za-z0-9_]*"; TOKK[NTOK] = "github-token"
    TOK[++NTOK] = "xox[abposr]-" _rep("[A-Za-z0-9-]", 10) "[A-Za-z0-9-]*"; TOKK[NTOK] = "slack-token"
    TOK[++NTOK] = "hv[sbr][.]" _rep("[A-Za-z0-9_-]", 20) "[A-Za-z0-9_-]*"; TOKK[NTOK] = "vault-token"
    TOK[++NTOK] = "eyJ" _rep("[A-Za-z0-9_-]", 10) "[A-Za-z0-9_-]*[.]eyJ" _rep("[A-Za-z0-9_-]", 10) "[A-Za-z0-9_-]*[.]" _rep("[A-Za-z0-9_-]", 10) "[A-Za-z0-9_-]*"; TOKK[NTOK] = "jwt"
    # KEY=VALUE secrets: the key is the whole run of name characters, and
    # its name must END in one of these words.
    RX_KV = "[a-z0-9_.-]*(password|passphrase|secret|private[_-]?key|credentials?|token|api[_-]?key|apikey|access[_-]?key)[\"']?[ \t]*[:=][ \t]*"
    RX_FLAG = "--?[a-z0-9_.-]*(password|passphrase|secret|private[_-]?key|credentials?|token|api[_-]?key|apikey|access[_-]?key)[ \t]+"
    RX_STOP = "[ \t,;&\"'`<>(){}|]"
    # A line (lower-cased) with none of these in it has nothing to scrub: most
    # lines, so they skip every rule below.
    RX_ANY = "authorization|bearer|://|akia|asia|abia|acca|gh[pousr]_|github_pat_|xox[abposr]-|hv[sbr][.]|eyj|pass|secret|token|key|credential"
}

# The kind a key=value secret is counted as, from its (lower-case) key.
function _kv_kind(k) {
    if (k ~ /pass(word|phrase)["']?[ \t]*[:=]?[ \t]*$/) return "password"
    if (k ~ /token["']?[ \t]*[:=]?[ \t]*$/) return "token"
    if (k ~ /secret/) return "secret"
    if (k ~ /(api[_-]?key|apikey|access[_-]?key)["']?[ \t]*[:=]?[ \t]*$/) return "api-key"
    return "secret"
}

# True when VALUE is not a secret worth hiding: empty, a yes/no word, a mask,
# a placeholder (<hidden>, $VAR, %VAR%, PASSWORD), or something already
# redacted. For any KIND but a password, also an identifier ("unexpected
# token: expected", 'Token': m.group(...)): tokens, keys and secrets are not
# lower-case words, passwords can be. After a --flag (FLAG set), a lower-case
# word is never taken for one: that is help text ("--password  force a
# password prompt").
function _kv_exempt(v, kind, flag,    l) {
    if (v == "") return 1
    if ((kind != "password" || flag) && (v ~ /^[A-Za-z][a-z_.]*$/ || v ~ /^[a-z][a-z_.]*\[/)) return 1
    if (v ~ /^[A-Z][A-Z_]*$/) return 1
    l = tolower(v)
    if (l ~ /^(true|false|yes|no|on|off|none|null|nil|n\/a|-|redacted|hidden|masked|required|optional|set|unset|undefined|empty)$/) return 1
    if (l ~ /^[*]+$/ || l ~ /^x+$/ || l ~ /^[.][.][.]$/) return 1
    if (l ~ /^<.*>$/ || l ~ /^\[redacted/ || l ~ /^[$%]/) return 1
    return 0
}

# _bounded(S, START, LEN): the match at START..START+LEN-1 has no word
# character (letter, digit, '_') right before or right after it.
function _bounded(s, st, ln,    b, a) {
    b = (st > 1) ? substr(s, st - 1, 1) : ""
    a = substr(s, st + ln, 1)
    return (b !~ /[A-Za-z0-9_]/ && a !~ /[A-Za-z0-9_]/)
}

# The end (exclusive offset) of a value starting at POS in S: up to the
# closing quote Q when Q is set, else up to the first stop character.
function _vend(s, pos, q,    rest, i) {
    rest = substr(s, pos)
    if (q != "") { i = index(rest, q); return (i ? pos + i - 1 : length(s) + 1) }
    if (match(rest, RX_STOP)) return pos + RSTART - 1
    return length(s) + 1
}

# scrub(S): S (one line, or what is left of one) with every secret replaced.
function scrub(s,    out, ls, pre, st, q, ve, v, k, t, i, m) {
    redact_init()
    if (tolower(s) !~ RX_ANY) return s
    # Authorization headers: the whole value.
    out = ""
    for (;;) {
        ls = tolower(s)
        if (!match(ls, RX_AUTH)) break
        st = RSTART; m = RLENGTH
        pre = (st > 1) ? substr(s, st - 1, 1) : ""
        if (pre ~ /[A-Za-z0-9_]/) { out = out substr(s, 1, st + m - 1); s = substr(s, st + m); continue }
        q = ""
        if (pre == "\"" || pre == "'") q = pre                  # 'Authorization: ...'
        if (substr(s, st + m, 1) == "\"" || substr(s, st + m, 1) == "'") { q = substr(s, st + m, 1); m++ }
        ve = (q != "") ? _vend(s, st + m, q) : length(s) + 1
        if (ve > st + m) {
            out = out substr(s, 1, st + m - 1) "[REDACTED:authorization]"; RC["authorization"]++
        } else {
            out = out substr(s, 1, st + m - 1)
        }
        s = substr(s, ve)
    }
    s = out s
    # Credentials in a URL: keep the user, hide the password.
    out = ""
    while (match(s, RX_URL)) {
        st = RSTART; m = RLENGTH
        t = substr(s, st, m)                       # scheme://user:pass@
        i = index(t, "://"); k = substr(t, i + 3)  # user:pass@
        i = i + 2 + index(k, ":")                  # offset of the ':' in t
        out = out substr(s, 1, st + i - 1) "[REDACTED:url-password]@"; RC["url-password"]++
        s = substr(s, st + m)
    }
    s = out s
    # Token formats.
    for (k = 1; k <= NTOK; k++) {
        out = ""
        while (match(s, TOK[k])) {
            st = RSTART; m = RLENGTH
            if (_bounded(s, st, m)) {
                out = out substr(s, 1, st - 1) "[REDACTED:" TOKK[k] "]"; RC[TOKK[k]]++
            } else {
                out = out substr(s, 1, st + m - 1)
            }
            s = substr(s, st + m)
        }
        s = out s
    }
    # Bearer TOKEN (16 characters or more).
    out = ""
    for (;;) {
        ls = tolower(s)
        if (!match(ls, RX_BEARER)) break
        st = RSTART; m = RLENGTH
        v = substr(s, st + m)
        if ((st == 1 || substr(s, st - 1, 1) !~ /[A-Za-z0-9_]/) && match(v, "^" RX_TOKCH "+") && RLENGTH >= 16) {
            out = out substr(s, 1, st + m - 1) "[REDACTED:bearer]"; RC["bearer"]++
            s = substr(v, RLENGTH + 1)
        } else {
            out = out substr(s, 1, st + m - 1); s = v
        }
    }
    s = out s
    # KEY=VALUE, KEY: VALUE, "KEY": "VALUE". Not a key inside a longer name
    # (arn:aws:...:secret:NAME, a path).
    out = ""
    for (;;) {
        ls = tolower(s)
        if (!match(ls, RX_KV)) break
        st = RSTART; m = RLENGTH
        pre = (st > 1) ? substr(s, st - 1, 1) : ""
        if (pre ~ /[:\/@=\\]/) { out = out substr(s, 1, st + m - 1); s = substr(s, st + m); continue }
        k = substr(ls, st, m)
        q = substr(s, st + m, 1)
        if (q == "\"" || q == "'") { ve = _vend(s, st + m + 1, q); v = substr(s, st + m + 1, ve - st - m - 1); m++ }
        else { q = ""; ve = _vend(s, st + m, ""); v = substr(s, st + m, ve - st - m) }
        if (!_kv_exempt(v, _kv_kind(k), 0)) {
            t = _kv_kind(k)
            out = out substr(s, 1, st + m - 1) "[REDACTED:" t "]"; RC[t]++
            s = substr(s, st + m + length(v))
        } else {
            out = out substr(s, 1, st + m - 1); s = substr(s, st + m)
        }
    }
    s = out s
    # --KEY VALUE on a command line.
    out = ""
    for (;;) {
        ls = tolower(s)
        if (!match(ls, RX_FLAG)) break
        st = RSTART; m = RLENGTH
        pre = (st > 1) ? substr(s, st - 1, 1) : ""
        k = substr(ls, st, m)
        q = substr(s, st + m, 1)
        if (pre ~ /[A-Za-z0-9_.-]/ || q == "-") { out = out substr(s, 1, st + m - 1); s = substr(s, st + m); continue }
        if (q == "\"" || q == "'") { ve = _vend(s, st + m + 1, q); v = substr(s, st + m + 1, ve - st - m - 1); m++ }
        else { q = ""; ve = _vend(s, st + m, ""); v = substr(s, st + m, ve - st - m) }
        if (!_kv_exempt(v, _kv_kind(k), 1)) {
            t = _kv_kind(k)
            out = out substr(s, 1, st + m - 1) "[REDACTED:" t "]"; RC[t]++
            s = substr(s, st + m + length(v))
        } else {
            out = out substr(s, 1, st + m - 1); s = substr(s, st + m)
        }
    }
    return out s
}

# scrub_line(LINE): the line as it is to be kept, PEM blocks included.
# Sets SCRUB_DROP to 1 when nothing of the line is to be kept: a line that
# began inside a private key block and left nothing after its END. Call
# scrub_reset() between documents.
function scrub_reset() { IN_PEM = 0 }
function scrub_line(line,    out, was, st, m) {
    redact_init()
    out = ""; was = IN_PEM
    for (;;) {
        if (IN_PEM) {
            if (match(line, RX_PEM_END)) { line = substr(line, RSTART + RLENGTH); IN_PEM = 0; continue }
            line = ""; break
        }
        if (index(line, "-----BEGIN") && match(line, RX_PEM_BEGIN)) {
            st = RSTART; m = RLENGTH               # (scrub() below runs match() too)
            out = out scrub(substr(line, 1, st - 1)) "[REDACTED:private-key]"
            RC["private-key"]++
            line = substr(line, st + m); IN_PEM = 1
            continue
        }
        out = out scrub(line); break
    }
    SCRUB_DROP = (was && out == "")
    return out
}

# Write the counts, "kind<TAB>n" a line, sorted by kind.
function redact_counts(file,    k, n, i, j, K, t) {
    n = 0
    for (k in RC) K[++n] = k
    for (i = 2; i <= n; i++) { t = K[i]; for (j = i - 1; j >= 1 && K[j] > t; j--) K[j + 1] = K[j]; K[j + 1] = t }
    for (i = 1; i <= n; i++) printf "%s\t%d\n", K[i], RC[K[i]] > file
    close(file)
}

MODE == "secrets" { l = scrub_line($0); if (!SCRUB_DROP) print l }
END { if (MODE == "secrets" && COUNTS != "") redact_counts(COUNTS) }
