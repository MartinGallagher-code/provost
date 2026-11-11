# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""LLM-written parsing templates: Claude writes one template per tool, once;
every later capture of that tool is parsed by the template, offline and
deterministically (provost --llm, PROVOST_LLM=1).

A template is JSON — regular expressions, one per kind of line:

    {"format": 1, "tool": "pmset-g",
     "detect": "^Now drawing from '",              # recognises this tool's output
     "skip": ["^-+$"],                             # decoration: rules, banners, prompts
     "blocks": [
       {"name": "batteries", "kind": "table",
        "header": "^\\s*NAME\\s+",                 # optional: the table's header line(s)
        "line": "^\\s*-(?P<id>\\S+) \\((?P<pid>id=\\d+)\\)\\t(?P<charge>\\d+%); ...$",
        "columns": {"pid": "process id"}},          # optional display names
       {"name": "settings", "kind": "kv",
        "line": "^\\s*(?P<key>\\S.*?)\\s{2,}(?P<value>\\S.*)$"}]}

Each non-blank line is a `skip` line, a block's header line, or a block's
data line (`line` must match the whole line; the first block that matches
wins); anything else is uncovered. A table block yields one record per data
line (its named groups, in order); a kv block yields one record of
key -> value. Records go out in the extract engine's flat format, so the
engine measures them like any parse and provost's quality gate decides.

A format-2 template carries a small Python parser instead of regexes, for
output no line-by-line pattern can describe (records that span lines,
indented attribute blocks, section titles that become a column):

    {"format": 2, "tool": "ip-addr", "detect": "^\\d+: \\S+: <",
     "parser": "import re\\ndef parse(lines):\\n    ..."}

`parse(lines)` returns the same blocks `apply` makes (name, kind, lines,
records), and runs in sandbox.py: a separate interpreter with a whitelist of
builtins and imports, a CPU and memory limit, no files and no network.

    python3 template.py apply TEMPLATE INPUT [--out DIR]   # blk.N.txt / blk.N.rec per block, notes.tsv
    python3 template.py find INPUT [--dirs D1:D2]          # the best stored template for INPUT
    python3 template.py learn INPUT --out TEMPLATE [--tool NAME]   # ask Claude (needs a key)
    python3 template.py key INPUT [--name NAME]            # the template file name for INPUT
    python3 template.py misses TEMPLATE INPUT              # line kinds in INPUT the template has not met
    python3 template.py repair TEMPLATE INPUT --out NEW [--tool NAME]   # ask Claude to extend it
    python3 template.py judge TEMPLATE INPUT --out NEW [--tool NAME]    # have Claude review it

After `learn` and after `repair`, a second call reviews the result (the
judge, JUDGE.md): Claude sees the capture, the template and the tables it
makes, and answers PASS or a list of structural fixes (a parent the rows do
not keep, a record split across tables, a header half applied, a line kind
misread). A fix list goes back to the template's writer once; the revision
is kept only if it reads the capture at least as well and still reads the
earlier captures. The verdict is stored in the template ("judge").
--no-judge (provost: PROVOST_LLM_JUDGE=0) skips it.

`learn`, `repair` and `judge` send the capture's text (and repair, the
captures a template was written from: its "examples") to the Anthropic API:
provost only runs them under --llm with a key. Stdlib only.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sandbox  # noqa: E402  (the static check; the parser itself runs in a subprocess)

SHIPPED = os.path.join(HERE, "templates")
GUIDE = os.path.join(HERE, "GUIDE.md")
JUDGE = os.path.join(HERE, "JUDGE.md")
SANDBOX = os.path.join(HERE, "sandbox.py")
PARSER_TIMEOUT = 10      # apply (format 2): wall-clock seconds for the boxed parser
MAX_LINES = 400          # learn: larger captures are not sent
MAX_BYTES = 64 * 1024
MAX_LINE = 4096          # apply: longer lines are uncovered (keeps regexes cheap)
MIN_COVERAGE = 0.8       # a learned template must cover this share of its capture
RETRIES = 3              # learn: more tries on a rate limit, an overload or a dropped connection
API_VERSION = "2026-10-21"
FALLBACK_BETA = "server-side-fallback-2026-07-01"
_KEYCHARS = re.compile(r"[^\w.%()/+#@-]+")


class TemplateError(Exception):
    pass


def _name(s):
    s = s.strip().rstrip(":=").strip()
    return _KEYCHARS.sub("_", s).strip("_") or "field"


def read_lines(path):
    if path == "-":
        data = sys.stdin.read()
    else:
        with open(path, encoding="utf-8", errors="replace") as fh:
            data = fh.read()
    lines = data.split("\n")
    return lines[:-1] if len(lines) > 1 and lines[-1] == "" else lines


# -- the template ---------------------------------------------------------
def compile_template(t):
    """Validate a template dict and compile its regexes (format 1) or check
    its parser statically (format 2); raises TemplateError."""
    if not isinstance(t, dict) or t.get("format") not in (1, 2):
        raise TemplateError("not a format-1 or format-2 template")

    def rx(p, what):
        if not isinstance(p, str) or not p:
            raise TemplateError(f"{what}: expected a regular expression")
        try:
            return re.compile(p)
        except re.error as exc:
            raise TemplateError(f"{what}: {exc}") from None

    detect = rx(t["detect"], "detect") if t.get("detect") else None
    if t["format"] == 2:
        try:
            sandbox.check(t.get("parser"))
        except sandbox.ParserError as exc:
            raise TemplateError(f"parser: {exc}") from None
        return {"_compiled": True, "format": 2, "detect": detect, "parser": t["parser"]}
    blocks = t.get("blocks")
    if not isinstance(blocks, list) or not blocks:
        raise TemplateError("a template needs at least one block")
    out = {"_compiled": True, "format": 1, "detect": detect,
           "skip": [rx(p, "skip") for p in t.get("skip", [])], "blocks": []}
    for i, b in enumerate(blocks):
        kind = b.get("kind")
        if kind not in ("table", "kv"):
            raise TemplateError(f"block {i}: kind must be table or kv")
        line = rx(b.get("line"), f"block {i} line")
        groups = list(line.groupindex)
        if not groups:
            raise TemplateError(f"block {i}: its line regex has no named groups")
        if kind == "kv" and not {"key", "value"} <= set(groups):
            raise TemplateError(f"block {i}: a kv block's line needs groups key and value")
        cols = b.get("columns") or {}
        out["blocks"].append({
            "name": _name(b.get("name") or f"block{i + 1}"), "kind": kind, "line": line,
            "header": rx(b["header"], f"block {i} header") if b.get("header") else None,
            "groups": groups, "columns": {g: _name(cols.get(g, g)) for g in groups}})
    return out


def apply(t, lines):
    """-> (blocks, covered, nonblank, skipped): blocks is a list of
    {name, kind, lines: [index], records: [dict]} for the blocks that matched;
    covered counts skip, header and data lines, skipped the skip lines."""
    ct = t if _compiled(t) else compile_template(t)
    if ct["format"] == 2:
        return _apply_parser(ct, lines)
    res = [{"name": b["name"], "kind": b["kind"], "lines": [], "records": []} for b in ct["blocks"]]
    covered = nonblank = skipped = 0
    for j, ln in enumerate(lines):
        if not ln.strip():
            continue
        nonblank += 1
        if len(ln) > MAX_LINE:
            continue
        if any(s.search(ln) for s in ct["skip"]):
            covered += 1
            skipped += 1
            continue
        for b, r in zip(ct["blocks"], res):
            if b["header"] is not None and b["header"].search(ln):
                r["lines"].append(j)
                covered += 1
                break
            m = b["line"].fullmatch(ln)
            if m:
                r["lines"].append(j)
                covered += 1
                vals = {g: (m.group(g) or "").strip() for g in b["groups"]}
                if b["kind"] == "table":
                    r["records"].append({b["columns"][g]: v for g, v in vals.items()})
                elif vals["key"]:
                    r["records"].append({_name(vals["key"]): vals["value"]})
                break
    return [r for r in res if r["records"]], covered, nonblank, skipped


def _compiled(t):
    return isinstance(t, dict) and t.get("_compiled") is True


def _apply_parser(ct, lines):
    """Format 2: run the template's parser in the sandbox (a subprocess) and
    shape its blocks like format 1's: (blocks, covered, nonblank, skipped)."""
    blocks, used, skip, nonblank = _run_parser(ct, lines)
    return blocks, len(used | skip), len(nonblank), len(skip)


def _run_parser(ct, lines):
    """-> (blocks, used line indexes, skip line indexes, non-blank indexes)."""
    req = json.dumps({"code": ct["parser"], "lines": lines}, ensure_ascii=False).encode("utf-8")
    try:
        p = subprocess.run([sys.executable, "-I", "-S", SANDBOX], input=req, capture_output=True,
                           timeout=PARSER_TIMEOUT, env={"PATH": os.environ.get("PATH", "")})
    except subprocess.TimeoutExpired:
        raise TemplateError(f"the parser ran longer than {PARSER_TIMEOUT}s") from None
    except OSError as exc:
        raise TemplateError(f"the parser could not be run: {exc}") from None
    try:
        res = json.loads(p.stdout.decode("utf-8"))
    except ValueError:
        err = p.stderr.decode("utf-8", "replace").strip().splitlines()
        raise TemplateError("the parser died" + (f": {err[-1]}" if err else f" (exit {p.returncode})")) from None
    if "error" in res:
        raise TemplateError(res["error"])
    nonblank = {j for j, ln in enumerate(lines) if ln.strip()}
    skip = set(res["skip"]) & nonblank
    blocks, used = [], set()
    for b in res["blocks"]:
        recs = [{_name(k): v for k, v in r.items()} for r in b["records"]]
        recs = [r for r in recs if r]
        if not recs:
            continue
        bl = set(b["lines"]) & nonblank
        used |= bl
        blocks.append({"name": _name(b["name"]), "kind": b["kind"], "lines": sorted(bl), "records": recs})
    skip -= used
    return blocks, used, skip, nonblank


_CELL = re.compile(r"[\t\r\n]")
_WORD = re.compile(r"[^\W_]")      # a letter or a digit, in any script


def _cell(v):
    """A value kept to its cell: a tab, CR or newline inside it becomes one
    space, as the engine's _clean_value does. The flat format is one field
    per line and the tidy output is TSV: a parser that joins a multi-line
    body into one value (an `err=<` block, a docstring) would otherwise make
    each continuation line a field of its own, repeated on every row. Unlike
    _clean_value it does not trim: a parser keeps a source line's indent or
    a whitespace-only text node on purpose."""
    return _CELL.sub(" ", v) if isinstance(v, str) else v


def flat_records(block):
    """The engine's flat format: `entryN.col value` lines + total_entries for
    a table, `key value` lines for a kv block (a repeated key gets _2, _3)."""
    if block["kind"] == "kv":
        seen, out = {}, []
        for rec in block["records"]:
            for k, v in rec.items():
                seen[k] = seen.get(k, 0) + 1
                out.append(f"{k if seen[k] == 1 else f'{k}_{seen[k]}'} {_cell(v)}")
        return out
    out = []
    for n, rec in enumerate(block["records"], 1):
        out += [f"entry{n}.{k} {_cell(v)}" for k, v in rec.items()]
    out.append(f"total_entries {len(block['records'])}")
    return out


def notes(ct, lines, classified=None):
    """The lines a template drops as decoration (skip) or does not read that
    still carry a word or a number: a title, a version banner, a summary
    count, a warning or an error between the rows. provost files them
    beside the template's datasets (NAME.notes), so a line that carries
    information is set aside, never lost; a line of rules, box glyphs or
    carets alone is decoration. CLASSIFIED is _classify's result when the
    caller has it. -> [{line, kind, text}], line numbered from 1."""
    read, skip, unread = classified or _classify(ct, lines)
    return [{"line": str(j + 1), "kind": "skipped" if j in skip else "unread", "text": _cell(lines[j]).strip()}
            for j in sorted(skip | unread) if _WORD.search(lines[j])]


def write_blocks(blocks, lines, out_dir, tool="", notes_=()):
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "tool"), "w", encoding="utf-8") as fh:
        fh.write(_name(tool) + "\n" if tool else "")
    for n, b in enumerate(blocks, 1):
        with open(os.path.join(out_dir, f"blk.{n}.txt"), "w", encoding="utf-8") as fh:
            fh.write("".join(lines[j] + "\n" for j in b["lines"]))
        with open(os.path.join(out_dir, f"blk.{n}.rec"), "w", encoding="utf-8") as fh:
            fh.write("".join(r + "\n" for r in flat_records(b)))
        with open(os.path.join(out_dir, f"blk.{n}.name"), "w", encoding="utf-8") as fh:
            fh.write(b["name"] + "\n")
    # notes.tsv is already tidy (line, kind, text): provost files it as is
    path = os.path.join(out_dir, "notes.tsv")
    if notes_:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("line\tkind\ttext\n" + "".join(f"{r['line']}\t{r['kind']}\t{r['text']}\n" for r in notes_))
    elif os.path.exists(path):
        os.remove(path)


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def find(lines, dirs):
    """The stored template that covers most of these lines (its detect regex
    must match one of them): (path, coverage) or (None, 0)."""
    best = (None, 0.0)
    for d in dirs:
        if not d or not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".json"):
                continue
            path = os.path.join(d, f)
            try:
                ct = compile_template(load(path))
            except (OSError, ValueError, TemplateError):
                continue
            if ct["detect"] is None or not any(ct["detect"].search(ln) for ln in lines[:200]):
                continue
            blocks, cov, nb, _ = apply(ct, lines)
            score = cov / nb if nb and blocks else 0.0
            if score > best[1]:
                best = (path, score)
    return best


def key(lines, name=""):
    """The file name a template for this capture is stored under: the
    dataset name when there is one, else a signature of its first lines
    (digits folded, spaces collapsed)."""
    if name:
        return _name(name) + ".json"
    sig = [re.sub(r"\s+", " ", re.sub(r"\d", "0", ln.strip())) for ln in lines if ln.strip()][:3]
    return "sig-" + hashlib.sha1("\n".join(sig).encode()).hexdigest()[:12] + ".json"


# -- learning a template from Claude ---------------------------------------
def _api_key():
    return os.environ.get("PROVOST_LLM_API_KEY") or os.environ.get("ANTHROPIC_API_KEY") or ""


def _log_call(msg, purpose, tool, secs):
    """PROVOST_LLM_LOG names a file that gets one JSON line per API reply
    (what it was for, the tool, the model that answered, its usage): the
    cost of a run can be added up afterwards."""
    path = os.environ.get("PROVOST_LLM_LOG")
    if not path:
        return
    rec = {"purpose": purpose, "tool": tool, "model": msg.get("model"), "stop_reason": msg.get("stop_reason"),
           "usage": msg.get("usage"), "seconds": round(secs, 1)}
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
    except OSError:
        pass


def call_claude(system, messages, model, effort="medium", max_tokens=16000, timeout=300,
                purpose="", tool=""):
    """One Messages API request over plain HTTP (no SDK: provost stays
    dependency-free), retried on a rate limit, an overload or a dropped
    connection. Returns the reply's text; raises TemplateError."""
    k = _api_key()
    if not k:
        raise TemplateError("no API key (set PROVOST_LLM_API_KEY or ANTHROPIC_API_KEY)")
    base = os.environ.get("PROVOST_LLM_BASE_URL", "https://api.anthropic.com").rstrip("/")
    body = {"model": model, "max_tokens": max_tokens, "system": system, "messages": messages,
            "output_config": {"effort": effort},
            # a safety classifier can decline harmless tool output (seen on
            # security tools): let the API retry on its recommended fallback
            "fallbacks": "default"}
    req = urllib.request.Request(base + "/v1/messages", data=json.dumps(body).encode(), method="POST",
                                 headers={"content-type": "application/json", "x-api-key": k,
                                          "anthropic-version": API_VERSION,
                                          "anthropic-beta": FALLBACK_BETA})
    for attempt in range(RETRIES + 1):
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                msg = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            try:
                detail = json.loads(exc.read().decode("utf-8")).get("error", {}).get("message", "")
            except (ValueError, OSError):
                detail = ""
            err = f"the API answered {exc.code}" + (f": {detail}" if detail else "")
            if exc.code not in (408, 409, 429) and exc.code < 500:
                raise TemplateError(err) from None
            try:
                wait = float(exc.headers.get("retry-after") or 0)
            except (TypeError, ValueError):
                wait = 0.0
        except (urllib.error.URLError, OSError, ValueError) as exc:
            err, wait = f"the API could not be reached: {exc}", 0.0
            # a timeout or a dropped connection is worth another try; a refused
            # connection, a bad address or a garbled reply is not
            if not isinstance(getattr(exc, "reason", exc), (TimeoutError, ConnectionResetError)):
                raise TemplateError(err) from None
        if attempt == RETRIES:
            raise TemplateError(err) from None
        time.sleep(min(60.0, max(wait, 2.0 * 2 ** attempt)))
    _log_call(msg, purpose, tool, time.monotonic() - t0)
    if msg.get("stop_reason") == "refusal":
        cat = (msg.get("stop_details") or {}).get("category") or "unspecified"
        raise TemplateError(f"the model declined this capture (refusal: {cat})")
    text = "".join(b.get("text", "") for b in msg.get("content", []) if b.get("type") == "text")
    if not text.strip():
        raise TemplateError(f"the reply has no text (stop reason {msg.get('stop_reason')})")
    return text


def _parse(text):
    t = text.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1].rsplit("```", 1)[0]
    try:
        return json.loads(t)
    except ValueError as exc:
        raise TemplateError(f"the reply is not JSON: {exc}") from None


def _classify(ct, lines):
    """-> (read, skipped, unread): the indexes of the non-blank lines a
    compiled template takes as header or data lines, drops as decoration
    (skip), and leaves unread."""
    nonblank = {j for j, ln in enumerate(lines) if ln.strip()}
    if ct["format"] == 2:
        blocks, used, skip, nonblank = _run_parser(ct, lines)
        return used, skip, nonblank - used - skip
    read, skip = set(), set()
    for j in nonblank:
        ln = lines[j]
        if len(ln) > MAX_LINE:
            continue
        if any(s.search(ln) for s in ct["skip"]):
            skip.add(j)
        elif any((b["header"] is not None and b["header"].search(ln)) or b["line"].fullmatch(ln)
                 for b in ct["blocks"]):
            read.add(j)
    return read, skip, nonblank - read - skip


def _cover(read, skip, unread):
    return (len(read) + len(skip)) / max(1, len(read) + len(skip) + len(unread))


def _report(lines, t):
    """Why a template falls short on its own capture, for a second try."""
    read, skip, unread = _classify(compile_template(t), lines)
    return _cover(read, skip, unread), sorted(unread)


def _too_large(lines):
    if len(lines) > MAX_LINES or sum(len(ln) + 1 for ln in lines) > MAX_BYTES:
        raise TemplateError(f"the capture is too large to send (over {MAX_LINES} lines or {MAX_BYTES // 1024} KB)")


def _numbered(lines, idx):
    return "\n".join(f"{j} |{lines[j]}" for j in idx)


def learn(lines, tool="", model="claude-opus-5-5", review=True):
    """Ask Claude for a template for this capture, check it on the capture,
    and give it one more try with the lines it missed; then (REVIEW) have the
    judge review it (review). -> template dict."""
    _too_large(lines)
    with open(GUIDE, encoding="utf-8") as fh:
        system = fh.read()
    body = "\n".join(f"{j} |{ln}" for j, ln in enumerate(lines))
    messages = [{"role": "user", "content": f"Tool: {tool or '(unnamed)'}\nLines: {len(lines)}\n\n{body}\n"}]
    last = None
    for attempt in range(2):
        text = call_claude(system, messages, model, purpose="learn", tool=tool)
        try:
            t = _parse(text)
            cov, miss = _report(lines, t)
        except TemplateError as exc:
            last = str(exc)
            messages += [{"role": "assistant", "content": text},
                         {"role": "user", "content": f"That template is invalid: {exc}. Reply with the corrected JSON only."}]
            continue
        if cov >= MIN_COVERAGE:
            t.setdefault("tool", tool)
            # the capture it was written from: repair checks a changed
            # template still reads it
            t["examples"] = ["\n".join(lines)]
            return review_template(t, lines, tool, model) if review else t
        last = f"it covers {cov:.0%} of the lines"
        shown = "\n".join(f"{j} |{lines[j]}" for j in miss[:40])
        messages += [{"role": "assistant", "content": text},
                     {"role": "user", "content": f"The template covers {cov:.0%} of the non-blank lines. "
                      f"These lines match no skip, header or line pattern:\n{shown}\n"
                      "Reply with the corrected JSON only."}]
    raise TemplateError(f"Claude's template does not fit this capture ({last})")


# -- repairing a stored template --------------------------------------------
# A template describes the layout its tool has shown so far. When a later
# capture shows a kind of line the template has not met, the template either
# leaves it unread or, worse, a skip pattern drops it while coverage reads
# 100%. Repair sends the template, the captures it was written from and the
# new capture to Claude once, to be extended; the extension is kept only if
# it still reads every line of the earlier captures the template read.
MAX_EXAMPLES = 3         # captures a template keeps: the first and the latest
SHOW = 60                # lines listed in a repair request
_SIG_RUN = re.compile(r"([^\w\s])\1+")
REPAIR_ASK = (
    "Extend the template so that it reads the new capture as correctly as the earlier ones: a new kind "
    "of record gets its own block (or its own columns), and a line that carries data must not be skipped. "
    "It must still read every line of the earlier captures that it reads now. If the lines listed are only "
    "decoration, return the template unchanged. Reply with the complete template JSON only (format 1 or 2), "
    "without the earlier captures.")


def _kind(ln):
    """A line's kind, to tell a new kind of line from one met before: its
    first word as printed (digits folded), the rest folded to its shape (a
    run of words, numbers and names like `beta-2` or `v1.4` to `a`, a run of
    one punctuation mark to one, spacing to one space). Another host, file
    or count in a banner is not a new kind of line; a WARNING line where
    there were only INFO lines is."""
    s = _SIG_RUN.sub(r"\1", re.sub(r"\d+", "0", ln.strip()))
    head, _, rest = s.partition(" ")
    rest = re.sub(r"a(?:\s+a)+", "a", re.sub(r"[\w.-]+", "a", rest))
    return (head + " " + re.sub(r"\s+", " ", rest).strip()).strip()


def _split(text):
    lines = text.split("\n")
    return lines[:-1] if len(lines) > 1 and lines[-1] == "" else lines


def _examples(t):
    return [e for e in t.get("examples") or [] if isinstance(e, str)]


def misses(t, lines):
    """What a stored template meets in this capture that it has not met
    before: the non-blank lines it leaves unread, and the lines its skip
    patterns drop, of a kind (_kind) it neither left unread nor skipped on the
    captures it was written from (its examples). With no examples, only
    unread lines count. -> (unread, skipped) line indexes."""
    ct = compile_template(t)
    read, skip, unread = _classify(ct, lines)
    known_u, known_s = set(), set()
    exl = [_split(e) for e in _examples(t)]
    for el in exl:
        _, s, u = _classify(ct, el)
        known_u |= {_kind(el[j]) for j in u}
        known_s |= {_kind(el[j]) for j in s}
    return (sorted(j for j in unread if _kind(lines[j]) not in known_u),
            sorted(j for j in skip if exl and _kind(lines[j]) not in known_s))


def repair(t, lines, tool="", model="claude-opus-5-5", review=True):
    """Ask Claude to extend a stored template for what this capture shows
    that it has not met before (misses), and check the extension: it must
    cover this capture at least as well as the template did (and 80%), and
    still read every line of its examples that the template read. One more
    try with what fell short; then (REVIEW) have the judge review the result
    on this capture (review). -> the extended (or unchanged) template, with
    this capture added to its examples."""
    _too_large(lines)
    ct = compile_template(t)
    new_u, new_s = misses(t, lines)
    examples = _examples(t)
    exl = [_split(e) for e in examples]
    before = [_classify(ct, el)[0] for el in exl]
    cov0 = _cover(*_classify(ct, lines))
    with open(GUIDE, encoding="utf-8") as fh:
        system = fh.read()
    parts = [f"Tool: {tool or t.get('tool') or '(unnamed)'}",
             "This template was written from earlier captures of the tool:",
             json.dumps(_bare(t), indent=1, ensure_ascii=False)]
    for n, el in enumerate(exl, 1):
        parts += [f"Earlier capture {n} ({len(el)} lines):", _numbered(el, range(len(el)))]
    parts += [f"A new capture of the same tool ({len(lines)} lines):", _numbered(lines, range(len(lines)))]
    if new_u:
        parts += ["On the new capture the template leaves these lines unread (no skip, header or line "
                  "pattern takes them):", _numbered(lines, new_u[:SHOW])]
    if new_s:
        parts += ["Its skip patterns drop these lines of the new capture, a kind the earlier captures "
                  "never showed:", _numbered(lines, new_s[:SHOW])]
    messages = [{"role": "user", "content": "\n\n".join(parts + [REPAIR_ASK]) + "\n"}]
    for attempt in range(2):
        text = call_claude(system, messages, model, purpose="repair", tool=tool)
        try:
            t2 = _parse(text)
            if not isinstance(t2, dict):
                raise TemplateError("not a format-1 or format-2 template")
            t2 = _bare(t2)
            short, shown = _shortfall(compile_template(t2), lines, cov0, exl, before, "the new capture")
        except TemplateError as exc:
            last = f"the template is invalid: {exc}"
            messages += [{"role": "assistant", "content": text},
                         {"role": "user", "content": f"That template is invalid: {exc}. Reply with the corrected JSON only."}]
            continue
        if not short:
            t2.setdefault("tool", t.get("tool") or tool)
            keep = examples if len(examples) < MAX_EXAMPLES else examples[:1] + examples[len(examples) - MAX_EXAMPLES + 2:]
            t2["examples"] = keep + ["\n".join(lines)]
            return review_template(t2, lines, tool, model, exl) if review else t2
        last = "; ".join(short)
        messages += [{"role": "assistant", "content": text},
                     {"role": "user", "content": "That template falls short: " + last + ".\n\n" + "\n\n".join(shown)
                      + "\n\nReply with the corrected complete template JSON only."}]
    raise TemplateError(f"Claude's extension of the template does not hold ({last})")


def _bare(t):
    """A template without what provost keeps beside its patterns (the
    captures it was written from, the judge's verdict): what is sent to
    Claude, and what is compared to tell a changed template."""
    return {k: v for k, v in t.items() if k not in ("examples", "judge")}


def _shortfall(ct2, lines, cov0, exl, before, what):
    """How a changed template (compiled) falls short of the one it replaces:
    it must cover LINES at least as well (COV0) and at least MIN_COVERAGE,
    and still read every line of the earlier captures EXL it read (BEFORE).
    -> (short: [reason], shown: [lines it no longer reads])."""
    short, shown = [], []
    cov = _cover(*_classify(ct2, lines))
    if cov < min(cov0, 1.0) - 1e-9 or cov < MIN_COVERAGE:
        short.append(f"it covers {cov:.0%} of {what}'s non-blank lines "
                     f"(the template covered {cov0:.0%}; at least {max(cov0, MIN_COVERAGE):.0%} is needed)")
    for n, (el, was) in enumerate(zip(exl, before), 1):
        lost = sorted(was - _classify(ct2, el)[0])
        if lost:
            short.append(f"on earlier capture {n} it no longer reads {len(lost)} line(s) the template read")
            shown.append(f"Earlier capture {n}, lines it no longer reads:\n" + _numbered(el, lost[:SHOW]))
    return short, shown


# -- the judge: a review of what a template makes of a capture ---------------
# Coverage says a template reads the lines; it cannot say the tables keep the
# capture's structure. After learn and after repair, one more call shows
# Claude the capture, the template and the tables it makes (JUDGE.md), and
# asks for PASS or a short list of structural fixes. The fixes go back to
# the template's writer once (GUIDE.md); the revision is kept only if it
# reads the capture at least as well and still reads the earlier captures.
JUDGE_ROWS = 40          # rows of each table shown to the judge
MAX_FIXES = 5
JUDGE_EFFORT = "high"
JUDGE_ASK = ("Review what the template makes of the capture, on the checks in your instructions. Reply with "
             '{"verdict": "PASS"} or {"verdict": "FIX", "fixes": [...]} only.')
REVISE_ASK = ("Revise the template to make these fixes, and keep what is right as it is. It must still read the "
              "capture at least as well as it does now" + "{earlier}" + ". Reply with the complete template JSON "
              "only (format 1 or 2), without the earlier captures.")


def _ranges(idx):
    """Line indexes as runs: [3, 4, 5, 9] -> '3-5, 9'."""
    out, idx = [], sorted(idx)
    i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and idx[j + 1] == idx[j] + 1:
            j += 1
        out.append(str(idx[i]) if i == j else f"{idx[i]}-{idx[j]}")
        i = j + 1
    return ", ".join(out)


def show(t, lines):
    """What a template makes of a capture, as the judge reads it: each block
    as a table (its columns, its rows, the lines it read), then the lines it
    sets aside (skipped as decoration, or left unread)."""
    ct = t if _compiled(t) else compile_template(t)
    if ct["format"] == 2:
        blocks, used, skip, nonblank = _run_parser(ct, lines)
        unread = nonblank - used - skip
    else:
        blocks = apply(ct, lines)[0]
        _, skip, unread = _classify(ct, lines)
    out = []
    for n, b in enumerate(blocks, 1):
        recs = b["records"]
        out.append(f"Table {n}: {b['name']} ({b['kind']}, {len(recs)} {'row' if len(recs) == 1 else 'rows'}, "
                   f"read from lines {_ranges(b['lines'])})")
        if b["kind"] == "kv":
            rows = ["key\tvalue"] + [ln.replace(" ", "\t", 1) for ln in flat_records(b)]
            more = len(rows) - 1 - JUDGE_ROWS
        else:
            cols = []
            for r in recs:
                cols += [k for k in r if k not in cols]
            rows = ["\t".join(cols)] + ["\t".join(str(_cell(r.get(c, ""))) for c in cols) for r in recs]
            more = len(recs) - JUDGE_ROWS
        out.append("\n".join(rows[:JUDGE_ROWS + 1]) + (f"\n... and {more} more" if more > 0 else ""))
    if not blocks:
        out.append("(no tables: the template reads nothing from this capture)")
    aside = sorted(skip | unread)
    if aside:
        out.append(f"Lines set aside ({len(aside)}):\n" + "\n".join(
            f"{j} |{lines[j]}    [{'skipped as decoration' if j in skip else 'unread'}]" for j in aside[:SHOW])
            + (f"\n... and {len(aside) - SHOW} more" if len(aside) > SHOW else ""))
    else:
        out.append("Lines set aside: none")
    return "\n\n".join(out)


def _verdict(text):
    v = _parse(text)
    if not isinstance(v, dict) or v.get("verdict") not in ("PASS", "FIX"):
        raise TemplateError('the review is not {"verdict": "PASS"} or {"verdict": "FIX", "fixes": [...]}')
    if v["verdict"] == "PASS":
        return "PASS", []
    fixes = [f.strip() for f in v.get("fixes") or [] if isinstance(f, str) and f.strip()]
    if not fixes:
        raise TemplateError("the review asks for fixes but lists none")
    return "FIX", fixes[:MAX_FIXES]


def judge(t, lines, tool="", model="claude-opus-5-5"):
    """One call: Claude reviews what template T makes of LINES (JUDGE.md).
    -> ("PASS", []) or ("FIX", [fix, ...]); raises TemplateError."""
    _too_large(lines)
    with open(JUDGE, encoding="utf-8") as fh:
        system = fh.read()
    parts = [f"Tool: {tool or t.get('tool') or '(unnamed)'}",
             f"The capture ({len(lines)} lines):", _numbered(lines, range(len(lines))),
             "The template:", json.dumps(_bare(t), indent=1, ensure_ascii=False),
             "What the template makes of the capture:", show(t, lines), JUDGE_ASK]
    # a review is reasoning, not writing: at medium effort the model often
    # answers without thinking at all
    text = call_claude(system, [{"role": "user", "content": "\n\n".join(parts) + "\n"}], model,
                       effort=JUDGE_EFFORT, purpose="judge", tool=tool)
    return _verdict(text)


def revise(t, lines, fixes, tool="", model="claude-opus-5-5", earlier=()):
    """The judge's FIXES go back to the template's writer once (one more try
    when the revision is invalid or falls short). The revision must cover
    LINES at least as well as T and still read every line of the EARLIER
    captures that T reads. -> the revised template (without examples or a
    verdict); raises TemplateError."""
    ct = compile_template(t)
    exl = list(earlier)
    before = [_classify(ct, el)[0] for el in exl]
    cov0 = _cover(*_classify(ct, lines))
    with open(GUIDE, encoding="utf-8") as fh:
        system = fh.read()
    parts = [f"Tool: {tool or t.get('tool') or '(unnamed)'}",
             "You wrote this template for the tool:", json.dumps(_bare(t), indent=1, ensure_ascii=False)]
    for n, el in enumerate(exl, 1):
        parts += [f"Earlier capture {n} ({len(el)} lines):", _numbered(el, range(len(el)))]
    parts += [f"The capture ({len(lines)} lines):", _numbered(lines, range(len(lines))),
              "A reviewer read what the template makes of this capture and asks for these fixes:",
              "\n".join(f"{n}. {f}" for n, f in enumerate(fixes, 1)),
              REVISE_ASK.format(earlier=", and every line of the earlier captures it reads now" if exl else "")]
    messages = [{"role": "user", "content": "\n\n".join(parts) + "\n"}]
    last = ""
    for attempt in range(2):
        text = call_claude(system, messages, model, purpose="revise", tool=tool)
        try:
            t2 = _parse(text)
            if not isinstance(t2, dict):
                raise TemplateError("not a format-1 or format-2 template")
            t2 = _bare(t2)
            short, shown = _shortfall(compile_template(t2), lines, cov0, exl, before, "the capture")
        except TemplateError as exc:
            last = f"the template is invalid: {exc}"
            messages += [{"role": "assistant", "content": text},
                         {"role": "user", "content": f"That template is invalid: {exc}. Reply with the corrected JSON only."}]
            continue
        if not short:
            return t2
        last = "; ".join(short)
        messages += [{"role": "assistant", "content": text},
                     {"role": "user", "content": "That template falls short: " + last + ".\n\n" + "\n\n".join(shown)
                      + "\n\nReply with the corrected complete template JSON only."}]
    raise TemplateError(f"the revision does not hold ({last})")


def review_template(t, lines, tool="", model="claude-opus-5-5", earlier=()):
    """The judge after learn or repair: one review of what T makes of LINES;
    a FIX list is fed back once (revise). The template that comes out (T,
    or the revision) carries the verdict as "judge":
      {"verdict": "PASS"}
      {"verdict": "FIX", "fixes": [...], "applied": true}
      {"verdict": "FIX", "fixes": [...], "applied": false, "why": "..."}
      {"verdict": "none", "why": "..."}    (the review itself failed)
    A review that fails, or a revision that does not hold, never costs the
    template: T is kept as it was. EARLIER: the other captures T was written
    from (as lists of lines). Its examples and tool carry over."""
    keep = {k: t[k] for k in ("tool", "examples") if k in t}
    try:
        verdict, fixes = judge(t, lines, tool, model)
    except TemplateError as exc:
        return dict(_bare(t), judge={"verdict": "none", "why": str(exc)}, **keep)
    if verdict == "PASS":
        return dict(_bare(t), judge={"verdict": "PASS"}, **keep)
    try:
        t2 = revise(t, lines, fixes, tool, model, earlier)
    except TemplateError as exc:
        return dict(_bare(t), judge={"verdict": "FIX", "fixes": fixes, "applied": False, "why": str(exc)}, **keep)
    t2.setdefault("tool", t.get("tool") or tool)
    return dict(t2, judge={"verdict": "FIX", "fixes": fixes, "applied": True},
                **({"examples": keep["examples"]} if "examples" in keep else {}))


def review_summary(t):
    """One line on a template's review, for provost's report and meta.tsv."""
    j = t.get("judge") if isinstance(t, dict) else None
    if not isinstance(j, dict):
        return ""
    n = len(j.get("fixes") or [])
    fx = f"{n} fix{'es' if n != 1 else ''}"
    if j.get("verdict") == "PASS":
        return "a review passed it"
    j = dict(j, why=_CELL.sub(" ", str(j.get("why", ""))))
    if j.get("verdict") == "FIX" and j.get("applied"):
        return f"revised after a review asked for {fx}"
    if j.get("verdict") == "FIX":
        return f"a review asked for {fx} that did not hold: {j.get('why', '')}"
    return f"not reviewed: {j.get('why', '')}"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("apply")
    p.add_argument("template")
    p.add_argument("input")
    p.add_argument("--out")
    p.add_argument("--records", action="store_true", help="print the first block's flat records")
    p = sub.add_parser("find")
    p.add_argument("input")
    p.add_argument("--dirs", default="")
    p = sub.add_parser("learn")
    p.add_argument("input")
    p.add_argument("--out", required=True)
    p.add_argument("--tool", default="")
    p.add_argument("--model", default=os.environ.get("PROVOST_LLM_MODEL") or "claude-opus-5-5")
    p.add_argument("--no-judge", action="store_true", help="no review of the template it writes")
    p = sub.add_parser("key")
    p.add_argument("input")
    p.add_argument("--name", default="")
    p = sub.add_parser("misses")
    p.add_argument("template")
    p.add_argument("input")
    p = sub.add_parser("repair")
    p.add_argument("template")
    p.add_argument("input")
    p.add_argument("--out", required=True)
    p.add_argument("--tool", default="")
    p.add_argument("--model", default=os.environ.get("PROVOST_LLM_MODEL") or "claude-opus-5-5")
    p.add_argument("--no-judge", action="store_true", help="no review of the template it extends")
    p = sub.add_parser("judge")
    p.add_argument("template")
    p.add_argument("input")
    p.add_argument("--out", required=True)
    p.add_argument("--tool", default="")
    p.add_argument("--model", default=os.environ.get("PROVOST_LLM_MODEL") or "claude-opus-5-5")
    a = ap.parse_args(argv)
    lines = read_lines(a.input)
    try:
        if a.cmd == "key":
            print(key(lines, a.name))
        elif a.cmd == "find":
            dirs = [d for d in a.dirs.split(":") if d] + [SHIPPED]
            path, score = find(lines, dirs)
            if not path:
                return 1
            print(f"{path}\t{score * 100:.0f}")
        elif a.cmd == "apply":
            t = load(a.template)
            ct = compile_template(t)
            classified = None
            if ct["format"] == 2:      # one run of the boxed parser for both
                blocks, used, skip, nonblank = _run_parser(ct, lines)
                cov, nb, skipped = len(used | skip), len(nonblank), len(skip)
                classified = (used, skip, nonblank - used - skip)
            else:
                blocks, cov, nb, skipped = apply(ct, lines)
            if not blocks:
                return 1
            if a.out:
                write_blocks(blocks, lines, a.out, t.get("tool") or "", notes(ct, lines, classified))
            if a.records:
                print("\n".join(flat_records(blocks[0])))
            else:
                print(f"{len(blocks)}\t{cov * 100 // max(1, nb)}\t{skipped}")
        elif a.cmd == "misses":
            u, sk = misses(load(a.template), lines)
            if u or sk:
                print(" and ".join(x for x in (u and f"{len(u)} unread line(s)", sk and f"{len(sk)} skipped line(s)") if x)
                      + " of a kind it has not met")
        elif a.cmd in ("learn", "repair", "judge"):
            # stdout: what happened (repair: extended | unchanged; learn:
            # learned; judge: reviewed), then the review's one-line summary
            bare = lambda x: {k: v for k, v in _bare(x).items() if k != "tool"}  # noqa: E731
            earlier = []
            if a.cmd == "learn":
                t = learn(lines, a.tool, a.model, review=False)
                print("learned")
            elif a.cmd == "repair":
                old = load(a.template)
                earlier = [_split(e) for e in _examples(old)]
                t = repair(old, lines, a.tool, a.model, review=False)
                print("unchanged" if bare(t) == bare(old) else "extended")
            else:
                t = load(a.template)
                compile_template(t)
                # its other captures must still read as they do; this one
                # is the capture under review
                earlier = [el for el in (_split(e) for e in _examples(t)) if el != lines]
                print("reviewed")
            before = a.out + ".before"
            if os.path.exists(before):
                os.remove(before)
            if a.cmd == "judge" or not a.no_judge:
                t0, t = t, review_template(t, lines, a.tool, a.model, earlier)
                print(review_summary(t))
                if t["judge"].get("applied"):
                    # the template as it was before the review, for a caller
                    # whose own checks refuse the revision (provost's gate)
                    with open(before, "w", encoding="utf-8") as fh:
                        json.dump(dict(t0, judge=dict(t["judge"], applied=False, why="the revision was not kept")),
                                  fh, indent=1, ensure_ascii=False)
                        fh.write("\n")
            tmp = a.out + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(t, fh, indent=1, ensure_ascii=False)
                fh.write("\n")
            os.replace(tmp, a.out)
    except (TemplateError, OSError, ValueError) as exc:
        print(f"template: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
