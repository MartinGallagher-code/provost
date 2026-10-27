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

    python3 template.py apply TEMPLATE INPUT [--out DIR]   # blk.N.txt / blk.N.rec per block
    python3 template.py find INPUT [--dirs D1:D2]          # the best stored template for INPUT
    python3 template.py learn INPUT --out TEMPLATE [--tool NAME]   # ask Claude (needs a key)
    python3 template.py key INPUT [--name NAME]            # the template file name for INPUT

`learn` sends the capture's text to the Anthropic API: provost only runs it
under --llm. Stdlib only.
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


def flat_records(block):
    """The engine's flat format: `entryN.col value` lines + total_entries for
    a table, `key value` lines for a kv block (a repeated key gets _2, _3)."""
    if block["kind"] == "kv":
        seen, out = {}, []
        for rec in block["records"]:
            for k, v in rec.items():
                seen[k] = seen.get(k, 0) + 1
                out.append(f"{k if seen[k] == 1 else f'{k}_{seen[k]}'} {v}")
        return out
    out = []
    for n, rec in enumerate(block["records"], 1):
        out += [f"entry{n}.{k} {v}" for k, v in rec.items()]
    out.append(f"total_entries {len(block['records'])}")
    return out


def write_blocks(blocks, lines, out_dir, tool=""):
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


def _report(lines, t):
    """Why a template falls short on its own capture, for a second try."""
    ct = compile_template(t)
    if ct["format"] == 2:
        blocks, used, skip, nonblank = _run_parser(ct, lines)
        return len(used | skip) / max(1, len(nonblank)), sorted(nonblank - used - skip)
    blocks, cov, nb, _ = apply(ct, lines)
    used = {j for b in blocks for j in b["lines"]}
    miss = [j for j, ln in enumerate(lines) if ln.strip() and j not in used
            and not any(s.search(ln) for s in ct["skip"])]
    return cov / max(1, nb), miss


def learn(lines, tool="", model="claude-opus-5-5"):
    """Ask Claude for a template for this capture, check it on the capture,
    and give it one more try with the lines it missed. -> template dict."""
    if len(lines) > MAX_LINES or sum(len(ln) + 1 for ln in lines) > MAX_BYTES:
        raise TemplateError(f"the capture is too large to send (over {MAX_LINES} lines or {MAX_BYTES // 1024} KB)")
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
            return t
        last = f"it covers {cov:.0%} of the lines"
        shown = "\n".join(f"{j} |{lines[j]}" for j in miss[:40])
        messages += [{"role": "assistant", "content": text},
                     {"role": "user", "content": f"The template covers {cov:.0%} of the non-blank lines. "
                      f"These lines match no skip, header or line pattern:\n{shown}\n"
                      "Reply with the corrected JSON only."}]
    raise TemplateError(f"Claude's template does not fit this capture ({last})")


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
    p = sub.add_parser("key")
    p.add_argument("input")
    p.add_argument("--name", default="")
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
            blocks, cov, nb, skipped = apply(compile_template(t), lines)
            if not blocks:
                return 1
            if a.out:
                write_blocks(blocks, lines, a.out, t.get("tool") or "")
            if a.records:
                print("\n".join(flat_records(blocks[0])))
            else:
                print(f"{len(blocks)}\t{cov * 100 // max(1, nb)}\t{skipped}")
        elif a.cmd == "learn":
            t = learn(lines, a.tool, a.model)
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
