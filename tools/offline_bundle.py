#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Build, check and pack provost's offline install bundle (PV-025).

An air-gapped ("high side") host has no PyPI. The bundle is everything it
needs to install provost with pip and nothing else:

    provost-X.Y.Z-offline/
        provost-X.Y.Z-py3-none-any.whl   the wheel PyPI has, byte for byte
        provost-X.Y.Z.tar.gz             the sdist PyPI has
        provost-X.Y.Z.cdx.json           CycloneDX 1.5 SBOM: every Python
                                         package file in the bundle, and the
                                         system tools provost runs
        INSTALL.md                       docs/offline-install.md
        SHA256SUMS                       the four files above
        *.sigstore.json                  one Sigstore bundle per file (the
                                         release workflow adds these)

usage:
    tools/offline_bundle.py build --dist DIST --out OUT [--wheels DIR]
        make OUT/provost-X.Y.Z-offline/ from the wheel and sdist in DIST (and
        any further wheels in DIR, e.g. an extra's dependencies); prints the
        directory it made
    tools/offline_bundle.py check DIR [--schema]
        exit 1 unless SHA256SUMS matches, it covers every file, the SBOM lists
        every package file with its hash and names the system tools, and
        every wheel's unconditional requirements are in the bundle; --schema
        also validates the SBOM against the CycloneDX 1.5 JSON schema (needs
        cyclonedx-python-lib[json-validation], CI only)
    tools/offline_bundle.py pack DIR
        write DIR.tar.gz, reproducibly (sorted, fixed times, owner 0); prints
        its path

Stdlib only (Python 3.8+), so `check` also runs on the high side. provost's
runtime stays dependency-free: nothing here ships in the wheel.
"""
import argparse
import email.parser
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tarfile
import time
import uuid
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
INSTALL_DOC = os.path.join(ROOT, "docs", "offline-install.md")

SUMS = "SHA256SUMS"
SIG_SUFFIX = ".sigstore.json"

# What provost runs outside Python. The wheel is a launcher: it execs the
# Bash tool, which runs these. Kept here, in one list, so the SBOM and the
# check agree; tests/offline_bundle/ holds it to `provost doctor` and the
# README ("Requires bash and git").
SYSTEM_TOOLS = [
    ("bash", "required", "runs provost and its extract/analyze engines (the launcher execs it)"),
    ("git", "required", "every store is a git repository; every capture is a commit"),
    ("awk", "required", "mawk or gawk; the extract and analyze engines (gawk preferred, mawk supported)"),
    ("python3", "required", "3.8 or newer: the pip launcher, the layout model (--model) and LLM templates (--llm)"),
    ("coreutils", "required", "head, tail, sort, cut, tr, wc, mktemp, date, sha256sum, base64, timeout and the like"),
    ("sed", "required", "text rewriting in the engines"),
    ("grep", "required", "text matching in the engines"),
    ("findutils", "required", "find and xargs"),
    ("util-linux", "optional", "script(1): capture a command under a pseudo-terminal"),
    ("less", "optional", "the pager for provost show on a terminal"),
]
REQUIRED_TOOLS = [name for name, need, _ in SYSTEM_TOOLS if need == "required"]


def die(msg, status=1):
    print("offline_bundle: %s" % msg, file=sys.stderr)
    sys.exit(status)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def norm(name):
    """PEP 503 normalised project name."""
    return re.sub(r"[-_.]+", "-", name).lower()


def wheel_metadata(path):
    """The METADATA of a wheel, as an email.message.Message."""
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if re.match(r"^[^/]+\.dist-info/METADATA$", n)]
        if len(names) != 1:
            die("%s: expected one .dist-info/METADATA, found %d" % (path, len(names)))
        text = z.read(names[0]).decode("utf-8")
    return email.parser.Parser().parsestr(text, headersonly=True)


def unconditional_requirements(meta):
    """Requires-Dist names that do not depend on an extra being asked for.

    Environment markers other than `extra` are treated as always true: a
    bundle that might be missing a package on some host is incomplete.
    """
    out = []
    for req in meta.get_all("Requires-Dist") or []:
        spec, _, marker = req.partition(";")
        if re.search(r"\bextra\s*==", marker):
            continue
        m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", spec)
        if m:
            out.append(norm(m.group(1)))
    return out


def sdist_name_version(filename):
    m = re.match(r"^(.+)-([^-]+)\.tar\.gz$", filename)
    if not m:
        die("%s: not an sdist name (NAME-VERSION.tar.gz)" % filename)
    return m.group(1), m.group(2)


def package_files(directory):
    return sorted(f for f in os.listdir(directory)
                  if f.endswith(".whl") or f.endswith(".tar.gz"))


def source_date():
    """SOURCE_DATE_EPOCH if set (reproducible builds), else now."""
    sde = os.environ.get("SOURCE_DATE_EPOCH")
    if sde:
        if not sde.isdigit():
            die("SOURCE_DATE_EPOCH must be whole seconds, got %r" % sde, 2)
        return int(sde)
    return int(time.time())


def sbom(directory, provost_version, when):
    """A CycloneDX 1.5 SBOM of the package files in DIRECTORY."""
    provost_ref = "pkg:pypi/provost@%s" % provost_version
    components, dist_refs = [], []
    for f in package_files(directory):
        path = os.path.join(directory, f)
        if f.endswith(".whl"):
            meta = wheel_metadata(path)
            name, version = meta["Name"], meta["Version"]
            expr = meta.get("License-Expression") or ""
            text = "" if expr else (meta.get("License") or "").strip()
            kind = "wheel"
        else:
            name, version = sdist_name_version(f)
            expr, text, kind = "", "", "sdist"
            if norm(name) == "provost":
                expr = "GPL-3.0-or-later"
        purl = "pkg:pypi/%s@%s?file_name=%s" % (norm(name), version, f)
        comp = {
            "type": "library",
            "bom-ref": purl,
            "name": norm(name),
            "version": version,
            "purl": purl,
            "hashes": [{"alg": "SHA-256", "content": sha256(path)}],
            "properties": [
                {"name": "provost:file", "value": f},
                {"name": "provost:distribution", "value": kind},
            ],
        }
        if norm(name) == "provost":
            comp["type"] = "application"
        # License-Expression is SPDX (PEP 639); the older free-text License
        # field is kept as a name, first line only
        if expr:
            comp["licenses"] = [{"expression": expr}]
        elif text:
            comp["licenses"] = [{"license": {"name": text.splitlines()[0][:200]}}]
        components.append(comp)
        dist_refs.append(purl)
    tool_refs = []
    for name, need, why in SYSTEM_TOOLS:
        ref = "system:%s" % name
        components.append({
            "type": "application",
            "bom-ref": ref,
            "name": name,
            "description": why,
            "scope": "required" if need == "required" else "optional",
            "properties": [
                {"name": "provost:source", "value": "host system (not in this bundle)"},
                {"name": "provost:requirement", "value": need},
            ],
        })
        tool_refs.append(ref)
    serial = uuid.uuid5(uuid.NAMESPACE_URL, "provost-offline:" + ",".join(
        c["hashes"][0]["content"] for c in components if "hashes" in c))
    return {
        "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:%s" % serial,
        "version": 1,
        "metadata": {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(when)),
            "tools": {"components": [{
                "type": "application",
                "name": "provost tools/offline_bundle.py",
                "version": provost_version,
            }]},
            "component": {
                "type": "application",
                "bom-ref": provost_ref,
                "name": "provost",
                "version": provost_version,
                "purl": provost_ref,
                "description": "provost offline install bundle",
                "licenses": [{"expression": "GPL-3.0-or-later"}],
                "externalReferences": [
                    {"type": "vcs", "url": "https://github.com/MartinGallagher-code/provost"},
                ],
            },
        },
        "components": components,
        "dependencies": [{"ref": provost_ref, "dependsOn": dist_refs + tool_refs}]
        + [{"ref": r} for r in dist_refs + tool_refs],
    }


def write_sums(directory, names):
    with open(os.path.join(directory, SUMS), "w", encoding="utf-8", newline="\n") as f:
        for n in sorted(names):
            f.write("%s  %s\n" % (sha256(os.path.join(directory, n)), n))


def cmd_build(args):
    dist = args.dist
    wheels = [f for f in os.listdir(dist) if f.endswith(".whl") and norm(f.split("-")[0]) == "provost"]
    sdists = [f for f in os.listdir(dist) if f.endswith(".tar.gz") and norm(sdist_name_version(f)[0]) == "provost"]
    if len(wheels) != 1 or len(sdists) != 1:
        die("%s: expected one provost wheel and one provost sdist, found %d and %d"
            % (dist, len(wheels), len(sdists)))
    version = wheel_metadata(os.path.join(dist, wheels[0]))["Version"]
    if sdist_name_version(sdists[0])[1] != version:
        die("wheel is %s but sdist is %s" % (version, sdists[0]))
    out = os.path.join(args.out, "provost-%s-offline" % version)
    if os.path.exists(out):
        die("%s exists; remove it first" % out)
    os.makedirs(out)
    for f in wheels + sdists:
        shutil.copy2(os.path.join(dist, f), out)
    if args.wheels:
        for f in sorted(os.listdir(args.wheels)):
            if f.endswith(".whl") and not os.path.exists(os.path.join(out, f)):
                shutil.copy2(os.path.join(args.wheels, f), out)
    shutil.copy2(INSTALL_DOC, os.path.join(out, "INSTALL.md"))
    bom_name = "provost-%s.cdx.json" % version
    with open(os.path.join(out, bom_name), "w", encoding="utf-8", newline="\n") as f:
        json.dump(sbom(out, version, source_date()), f, indent=2, sort_keys=False)
        f.write("\n")
    write_sums(out, [n for n in os.listdir(out) if n != SUMS])
    problems = check(out)
    if problems:
        die("built bundle fails its own check:\n  " + "\n  ".join(problems))
    print(out)
    return 0


def check(directory, schema=False):
    """Every problem with the bundle in DIRECTORY, as a list of strings."""
    problems = []
    sums_path = os.path.join(directory, SUMS)
    if not os.path.isfile(sums_path):
        return ["no %s" % SUMS]
    listed = {}
    with open(sums_path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            m = re.match(r"^([0-9a-f]{64})  ([^/\n]+)\n?$", line)
            if not m:
                problems.append("%s line %d is not 'HASH  NAME'" % (SUMS, i))
                continue
            listed[m.group(2)] = m.group(1)
    for name, digest in sorted(listed.items()):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            problems.append("%s names %s, which is missing" % (SUMS, name))
        elif sha256(path) != digest:
            problems.append("%s: SHA-256 does not match %s" % (name, SUMS))
    for name in sorted(os.listdir(directory)):
        if name == SUMS or name.endswith(SIG_SUFFIX):
            continue
        if name not in listed:
            problems.append("%s is not in %s" % (name, SUMS))
    boms = [n for n in os.listdir(directory) if n.endswith(".cdx.json")]
    if len(boms) != 1:
        return problems + ["expected one *.cdx.json SBOM, found %d" % len(boms)]
    try:
        with open(os.path.join(directory, boms[0]), encoding="utf-8") as f:
            bom = json.load(f)
    except ValueError as e:
        return problems + ["%s is not JSON: %s" % (boms[0], e)]
    if bom.get("bomFormat") != "CycloneDX" or bom.get("specVersion") != "1.5":
        problems.append("%s is not a CycloneDX 1.5 SBOM" % boms[0])
    by_file = {}
    names = set()
    for c in bom.get("components", []):
        names.add(c.get("name"))
        for p in c.get("properties", []):
            if p.get("name") == "provost:file":
                by_file[p.get("value")] = c
    present = set()
    for f in package_files(directory):
        path = os.path.join(directory, f)
        comp = by_file.get(f)
        if comp is None:
            problems.append("%s is not in the SBOM" % f)
            continue
        hashes = {h.get("alg"): h.get("content") for h in comp.get("hashes", [])}
        if hashes.get("SHA-256") != sha256(path):
            problems.append("%s: the SBOM's SHA-256 does not match the file" % f)
        if f.endswith(".whl"):
            present.add(norm(wheel_metadata(path)["Name"]))
    for f in sorted(set(by_file) - set(package_files(directory))):
        problems.append("the SBOM lists %s, which is not in the bundle" % f)
    for tool in REQUIRED_TOOLS:
        if tool not in names:
            problems.append("the SBOM does not name the system tool %s" % tool)
    for f in package_files(directory):
        if f.endswith(".whl"):
            for req in unconditional_requirements(wheel_metadata(os.path.join(directory, f))):
                if req not in present:
                    problems.append("%s requires %s, which has no wheel in the bundle" % (f, req))
    if schema:
        problems += schema_problems(os.path.join(directory, boms[0]))
    return problems


def schema_problems(path):
    """Validate against the CycloneDX 1.5 JSON schema (cyclonedx-python-lib)."""
    try:
        from cyclonedx.schema import SchemaVersion
        from cyclonedx.validation.json import JsonStrictValidator
    except ImportError:
        return ["--schema needs: pip install 'cyclonedx-python-lib[json-validation]'"]
    with open(path, encoding="utf-8") as f:
        error = JsonStrictValidator(SchemaVersion.V1_5).validate_str(f.read())
    return ["%s fails the CycloneDX 1.5 schema: %s" % (os.path.basename(path), error)] if error else []


def cmd_check(args):
    problems = check(args.dir, schema=args.schema)
    for p in problems:
        print("FAIL %s" % p)
    if not problems:
        print("ok %s: SHA256SUMS, SBOM%s and requirements agree" % (
            args.dir, " (CycloneDX 1.5 schema-valid)" if args.schema else ""))
    return 1 if problems else 0


def cmd_pack(args):
    src = os.path.normpath(args.dir)
    if not os.path.isdir(src):
        die("%s is not a directory" % src, 2)
    base = os.path.basename(src)
    out = src + ".tar.gz"
    when = source_date()
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        def add(path, arc):
            info = tar.gettarinfo(path, arc)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = when
            info.mode = 0o755 if info.isdir() else 0o644
            if info.isdir():
                tar.addfile(info)
            else:
                with open(path, "rb") as f:
                    tar.addfile(info, f)
        add(src, base)
        for name in sorted(os.listdir(src)):
            add(os.path.join(src, name), base + "/" + name)
    with open(out, "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=when) as gz:
            gz.write(raw.getvalue())
    print(out)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="offline_bundle.py",
                                 description="provost's offline install bundle (PV-025)")
    sub = ap.add_subparsers(dest="cmd")
    b = sub.add_parser("build", help="make the bundle directory")
    b.add_argument("--dist", required=True, help="directory holding the wheel and sdist")
    b.add_argument("--out", required=True, help="where to make provost-X.Y.Z-offline/")
    b.add_argument("--wheels", help="further wheels to bundle (an extra's dependencies)")
    c = sub.add_parser("check", help="check a bundle directory")
    c.add_argument("dir")
    c.add_argument("--schema", action="store_true", help="also validate the SBOM's schema")
    p = sub.add_parser("pack", help="tar.gz a bundle directory reproducibly")
    p.add_argument("dir")
    args = ap.parse_args(argv)
    if args.cmd == "build":
        return cmd_build(args)
    if args.cmd == "check":
        return cmd_check(args)
    if args.cmd == "pack":
        return cmd_pack(args)
    ap.print_help(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
