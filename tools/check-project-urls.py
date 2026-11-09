#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Fetch every [project.urls] entry in pyproject.toml; fail on any that does
not resolve (an HTTP 4xx/5xx after redirects, or no answer at all).

PyPI shows these links on provost's page, and one of them (Documentation,
provost.readthedocs.io) was a 404 for a release before anyone noticed
(PV-034). CI runs this so a dead link fails a pull request instead.

usage: tools/check-project-urls.py [PYPROJECT]
"""
import re
import sys
import urllib.error
import urllib.request


def project_urls(text):
    """The name = "url" pairs of the [project.urls] table (stdlib only: no
    tomllib before Python 3.11, and the table is flat)."""
    out, inside = [], False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            inside = s == "[project.urls]"
            continue
        m = re.match(r'^([A-Za-z0-9_. -]+?)\s*=\s*"([^"]+)"\s*(#.*)?$', s) if inside else None
        if m:
            out.append((m.group(1).strip('" '), m.group(2)))
    return out


def status(url, timeout=20):
    """The final HTTP status for URL (redirects followed), or an error text."""
    for method in ("HEAD", "GET"):          # some hosts refuse HEAD
        req = urllib.request.Request(url, method=method,
                                     headers={"User-Agent": "provost-url-check"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status
        except urllib.error.HTTPError as e:
            if method == "HEAD" and e.code in (403, 405, 501):
                continue
            return e.code
        except (urllib.error.URLError, OSError) as e:
            if method == "HEAD":
                continue
            return f"no answer ({e})"
    return "no answer"


def main(argv):
    path = argv[1] if len(argv) > 1 else "pyproject.toml"
    with open(path, encoding="utf-8") as f:
        urls = project_urls(f.read())
    if not urls:
        print(f"{path}: no [project.urls] entries found", file=sys.stderr)
        return 1
    bad = 0
    for name, url in urls:
        st = status(url)
        ok = isinstance(st, int) and st < 400
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {url} -> {st}")
        bad += not ok
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
