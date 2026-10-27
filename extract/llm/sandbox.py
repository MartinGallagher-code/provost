# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Runs one format-2 template's parser (Python source Claude wrote for one
tool) on one capture, in a box: a separate interpreter (`python3 -I -S`),
builtins cut down to a whitelist, imports limited to a few pure modules, a
CPU and memory limit, no files, no network, nothing from the environment.

    python3 -I -S sandbox.py < {"code": "...", "lines": [...]}   -> JSON

The parser is `parse(lines) -> blocks`: a list of
{"name", "kind": "table"|"kv", "lines": [line index...], "records": [dict...]}
or {"blocks": [...], "skip": [line index...]} (skip: decoration lines, so
they count as covered). The reply is that structure, checked, or
{"error": "..."}. `check(code)` is the static part (imports, names) and is
what template.py runs before a parser is ever stored or executed.

Stdlib only; provost runs this at capture time.
"""
import ast
import json
import sys

ALLOWED_MODULES = {"re", "json", "collections", "itertools", "math", "string"}
BANNED_NAMES = {"open", "exec", "eval", "compile", "__import__", "globals", "locals", "vars", "dir",
                "getattr", "setattr", "delattr", "input", "breakpoint", "memoryview", "type", "super",
                "object", "classmethod", "staticmethod", "property", "help", "exit", "quit"}
SAFE_BUILTINS = ["abs", "all", "any", "bool", "chr", "dict", "divmod", "enumerate", "filter", "float",
                 "frozenset", "hasattr", "hash", "id", "int", "isinstance", "issubclass", "iter", "len",
                 "list", "map", "max", "min", "next", "ord", "pow", "range", "repr", "reversed", "round",
                 "set", "slice", "sorted", "str", "sum", "tuple", "zip", "True", "False", "None",
                 "Exception", "ValueError", "KeyError", "IndexError", "TypeError", "AttributeError",
                 "StopIteration", "RuntimeError", "ZeroDivisionError", "AssertionError", "LookupError",
                 "ArithmeticError", "NotImplementedError"]
CPU_SECONDS = 5
MEMORY_BYTES = 512 * 1024 * 1024
MAX_RECORDS = 100000


class ParserError(Exception):
    pass


def check(code):
    """Static check: parses CODE, refuses imports outside ALLOWED_MODULES,
    dunder attributes and the banned names; requires a `parse` function.
    Raises ParserError."""
    if not isinstance(code, str) or not code.strip():
        raise ParserError("the parser is empty")
    try:
        tree = ast.parse(code, "<parser>")
    except SyntaxError as exc:
        raise ParserError(f"the parser has a syntax error: line {exc.lineno}: {exc.msg}") from None
    has_parse = False
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            mods = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module or ""]
            for m in mods:
                if m.split(".")[0] not in ALLOWED_MODULES:
                    raise ParserError(f"the parser imports {m}; only {', '.join(sorted(ALLOWED_MODULES))} are allowed")
        elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
            raise ParserError(f"the parser uses the attribute {node.attr}")
        elif isinstance(node, ast.Name) and node.id in BANNED_NAMES:
            raise ParserError(f"the parser uses {node.id}")
        elif isinstance(node, (ast.Global, ast.Nonlocal)):
            raise ParserError("the parser uses global/nonlocal")
        elif isinstance(node, ast.FunctionDef) and node.name == "parse":
            has_parse = True
    if not has_parse:
        raise ParserError("the parser defines no parse(lines) function")


def _limits():
    try:
        import resource
        resource.setrlimit(resource.RLIMIT_CPU, (CPU_SECONDS, CPU_SECONDS))
        soft, hard = resource.getrlimit(resource.RLIMIT_AS)
        lim = MEMORY_BYTES if hard in (resource.RLIM_INFINITY, -1) else min(MEMORY_BYTES, hard)
        resource.setrlimit(resource.RLIMIT_AS, (lim, lim))
    except (ImportError, ValueError, OSError):
        pass


def _import(name, globals=None, locals=None, fromlist=(), level=0):
    if level or name.split(".")[0] not in ALLOWED_MODULES:
        raise ImportError(f"import of {name} is not allowed")
    return __import__(name, globals, locals, fromlist, 0)


def _validate(result, nlines):
    skip = []
    if isinstance(result, dict):
        skip = result.get("skip") or []
        result = result.get("blocks")
    if not isinstance(result, list):
        raise ParserError("parse() must return a list of blocks or {'blocks': [...], 'skip': [...]}")
    if not isinstance(skip, list) or not all(isinstance(j, int) and 0 <= j < nlines for j in skip):
        raise ParserError("skip must be a list of line indexes")
    blocks, total = [], 0
    for i, b in enumerate(result):
        if not isinstance(b, dict):
            raise ParserError(f"block {i} is not a dict")
        kind = b.get("kind")
        if kind not in ("table", "kv"):
            raise ParserError(f"block {i}: kind must be table or kv")
        lines = b.get("lines") or []
        if not isinstance(lines, list) or not all(isinstance(j, int) and 0 <= j < nlines for j in lines):
            raise ParserError(f"block {i}: lines must be a list of line indexes")
        recs = b.get("records") or []
        if not isinstance(recs, list) or len(recs) > MAX_RECORDS:
            raise ParserError(f"block {i}: records must be a list")
        out = []
        for r in recs:
            if not isinstance(r, dict):
                raise ParserError(f"block {i}: every record must be a dict")
            rec = {}
            for k, v in r.items():
                if not isinstance(k, str):
                    raise ParserError(f"block {i}: a record key is not a string")
                if v is None:
                    v = ""
                elif not isinstance(v, (str, int, float, bool)):
                    raise ParserError(f"block {i}: the value of {k!r} is not a string or number")
                rec[k] = v if isinstance(v, str) else json.dumps(v)
            out.append(rec)
        total += len(out)
        if total > MAX_RECORDS:
            raise ParserError("too many records")
        blocks.append({"name": str(b.get("name") or f"block{i + 1}"), "kind": kind,
                       "lines": sorted(set(lines)), "records": out})
    return {"blocks": blocks, "skip": sorted(set(skip))}


def run(code, lines):
    """-> {"blocks": [...], "skip": [...]} or raises ParserError. Call it only
    from this file's main (in the boxed interpreter)."""
    check(code)
    builtins = {n: __builtins__[n] if isinstance(__builtins__, dict) else getattr(__builtins__, n)
                for n in SAFE_BUILTINS}
    builtins["__import__"] = _import
    builtins["print"] = lambda *a, **k: None
    env = {"__builtins__": builtins, "__name__": "template"}
    try:
        exec(compile(code, "<parser>", "exec"), env)  # noqa: S102 (that is the point of this file)
        result = env["parse"](list(lines))
    except ParserError:
        raise
    except MemoryError:
        raise ParserError("the parser ran out of memory") from None
    except RecursionError:
        raise ParserError("the parser recursed too deep") from None
    except Exception as exc:  # noqa: BLE001 (any error in Claude's code is a parser error)
        raise ParserError(f"the parser failed: {type(exc).__name__}: {exc}") from None
    return _validate(result, len(lines))


def main():
    _limits()
    try:
        req = json.loads(sys.stdin.read())
        out = run(req.get("code", ""), req.get("lines", []))
    except ParserError as exc:
        out = {"error": str(exc)}
    except (ValueError, TypeError, KeyError) as exc:
        out = {"error": f"bad request: {exc}"}
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
