# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""tools/offline_bundle.py: the offline install bundle (PV-025).

Stdlib only, no network, fake wheels: run with
    python3 -m unittest discover -s tests/offline_bundle -v
CI (the `offline bundle` job) also builds a real bundle, validates its SBOM
against the CycloneDX schema and installs it with networking off.
"""
import contextlib
import hashlib
import io
import json
import os
import shutil
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import offline_bundle as ob  # noqa: E402


def make_wheel(directory, name, version, requires=(), license_expr="MIT"):
    fn = "%s-%s-py3-none-any.whl" % (name.replace("-", "_"), version)
    meta = "Metadata-Version: 2.4\nName: %s\nVersion: %s\n" % (name, version)
    if license_expr:
        meta += "License-Expression: %s\n" % license_expr
    for r in requires:
        meta += "Requires-Dist: %s\n" % r
    with zipfile.ZipFile(os.path.join(directory, fn), "w") as z:
        z.writestr("%s-%s.dist-info/METADATA" % (name.replace("-", "_"), version), meta)
        z.writestr("%s/__init__.py" % name.replace("-", "_"), "")
    return fn


def make_sdist(directory, name, version):
    fn = "%s-%s.tar.gz" % (name, version)
    with tarfile.open(os.path.join(directory, fn), "w:gz") as t:
        data = b"x"
        info = tarfile.TarInfo("%s-%s/PKG-INFO" % (name, version))
        info.size = len(data)
        t.addfile(info, io.BytesIO(data))
    return fn


def quiet(fn, *a):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = fn(*a)
        except SystemExit as e:
            rc = e.code
    return rc, out.getvalue(), err.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.dist = os.path.join(self.tmp, "dist")
        self.out = os.path.join(self.tmp, "out")
        os.makedirs(self.dist)
        os.environ["SOURCE_DATE_EPOCH"] = "1700000000"
        self.addCleanup(os.environ.pop, "SOURCE_DATE_EPOCH", None)

    def build(self, *extra):
        rc, out, err = quiet(ob.main, ["build", "--dist", self.dist, "--out", self.out] + list(extra))
        return rc, out.strip(), err

    def standard(self, requires=("numpy; extra == 'lm'", "provost-model; extra == \"lm\"")):
        make_wheel(self.dist, "provost", "9.9.9", requires, "GPL-3.0-or-later")
        make_sdist(self.dist, "provost", "9.9.9")
        rc, d, err = self.build()
        self.assertEqual(rc, 0, err)
        return d


class BuildTest(Base):
    def test_layout(self):
        d = self.standard()
        self.assertEqual(os.path.basename(d), "provost-9.9.9-offline")
        self.assertEqual(sorted(os.listdir(d)), [
            "INSTALL.md", "SHA256SUMS", "provost-9.9.9-py3-none-any.whl",
            "provost-9.9.9.cdx.json", "provost-9.9.9.tar.gz"])
        with open(os.path.join(d, "INSTALL.md")) as f, open(ob.INSTALL_DOC) as g:
            self.assertEqual(f.read(), g.read())

    def test_sums_cover_every_file(self):
        d = self.standard()
        with open(os.path.join(d, "SHA256SUMS")) as f:
            lines = f.read().splitlines()
        names = [l.split("  ", 1)[1] for l in lines]
        self.assertEqual(names, sorted(n for n in os.listdir(d) if n != "SHA256SUMS"))
        for l in lines:
            digest, name = l.split("  ", 1)
            with open(os.path.join(d, name), "rb") as f:
                self.assertEqual(digest, hashlib.sha256(f.read()).hexdigest())

    def test_sbom(self):
        d = self.standard()
        with open(os.path.join(d, "provost-9.9.9.cdx.json")) as f:
            bom = json.load(f)
        self.assertEqual((bom["bomFormat"], bom["specVersion"]), ("CycloneDX", "1.5"))
        self.assertEqual(bom["metadata"]["component"]["purl"], "pkg:pypi/provost@9.9.9")
        self.assertEqual(bom["metadata"]["timestamp"], "2023-11-14T22:13:20Z")
        files = {}
        for c in bom["components"]:
            props = {p["name"]: p["value"] for p in c.get("properties", [])}
            if "provost:file" in props:
                files[props["provost:file"]] = c
        self.assertEqual(sorted(files), ["provost-9.9.9-py3-none-any.whl", "provost-9.9.9.tar.gz"])
        whl = files["provost-9.9.9-py3-none-any.whl"]
        self.assertEqual(whl["purl"], "pkg:pypi/provost@9.9.9?file_name=provost-9.9.9-py3-none-any.whl")
        self.assertEqual(whl["licenses"], [{"expression": "GPL-3.0-or-later"}])
        names = {c["name"]: c for c in bom["components"]}
        for tool in ("bash", "git", "awk", "python3"):
            self.assertEqual(names[tool]["scope"], "required", tool)
        self.assertEqual(names["less"]["scope"], "optional")
        refs = {c["bom-ref"] for c in bom["components"]}
        top = [x for x in bom["dependencies"] if x["ref"] == "pkg:pypi/provost@9.9.9"][0]
        self.assertEqual(set(top["dependsOn"]), refs)

    def test_sbom_is_reproducible(self):
        d1 = self.standard()
        with open(os.path.join(d1, "SHA256SUMS")) as f:
            first = f.read()
        shutil.rmtree(self.out)
        rc, d2, err = self.build()
        with open(os.path.join(d2, "SHA256SUMS")) as f:
            self.assertEqual(f.read(), first)

    def test_refuses_an_existing_directory(self):
        self.standard()
        rc, _, err = self.build()
        self.assertEqual(rc, 1)
        self.assertIn("exists", err)

    def test_needs_one_wheel_and_one_sdist(self):
        make_wheel(self.dist, "provost", "9.9.9")
        rc, _, err = self.build()
        self.assertEqual(rc, 1)
        self.assertIn("one provost wheel and one provost sdist", err)

    def test_wheel_and_sdist_versions_must_agree(self):
        make_wheel(self.dist, "provost", "9.9.9")
        make_sdist(self.dist, "provost", "9.9.8")
        rc, _, err = self.build()
        self.assertEqual(rc, 1)
        self.assertIn("wheel is 9.9.9", err)

    def test_a_missing_dependency_fails_the_build(self):
        make_wheel(self.dist, "provost", "9.9.9", ["requests>=2"])
        make_sdist(self.dist, "provost", "9.9.9")
        rc, _, err = self.build()
        self.assertEqual(rc, 1)
        self.assertIn("requires requests, which has no wheel in the bundle", err)

    def test_further_wheels_satisfy_it(self):
        make_wheel(self.dist, "provost", "9.9.9", ["requests>=2; python_version >= '3.8'"])
        make_sdist(self.dist, "provost", "9.9.9")
        extra = os.path.join(self.tmp, "wheels")
        os.makedirs(extra)
        make_wheel(extra, "requests", "2.0", license_expr="")
        rc, d, err = self.build("--wheels", extra)
        self.assertEqual(rc, 0, err)
        self.assertIn("requests-2.0-py3-none-any.whl", os.listdir(d))
        self.assertEqual(ob.check(d), [])


class CheckTest(Base):
    def test_clean_bundle(self):
        d = self.standard()
        self.assertEqual(ob.check(d), [])
        rc, out, _ = quiet(ob.main, ["check", d])
        self.assertEqual(rc, 0)
        self.assertTrue(out.startswith("ok "))

    def test_signatures_are_not_checksummed(self):
        d = self.standard()
        for n in list(os.listdir(d)):
            with open(os.path.join(d, n + ".sigstore.json"), "w") as f:
                f.write("{}")
        self.assertEqual(ob.check(d), [])

    def test_tampered_file(self):
        d = self.standard()
        with open(os.path.join(d, "provost-9.9.9.tar.gz"), "ab") as f:
            f.write(b"!")
        problems = ob.check(d)
        self.assertIn("provost-9.9.9.tar.gz: SHA-256 does not match SHA256SUMS", problems)
        self.assertIn("provost-9.9.9.tar.gz: the SBOM's SHA-256 does not match the file", problems)
        rc, out, _ = quiet(ob.main, ["check", d])
        self.assertEqual(rc, 1)
        self.assertIn("FAIL ", out)

    def test_unlisted_and_missing_files(self):
        d = self.standard()
        with open(os.path.join(d, "stray.txt"), "w") as f:
            f.write("x")
        os.remove(os.path.join(d, "INSTALL.md"))
        problems = ob.check(d)
        self.assertIn("stray.txt is not in SHA256SUMS", problems)
        self.assertIn("SHA256SUMS names INSTALL.md, which is missing", problems)

    def test_a_package_the_sbom_does_not_list(self):
        d = self.standard()
        make_wheel(d, "other", "1.0")
        problems = ob.check(d)
        self.assertIn("other-1.0-py3-none-any.whl is not in the SBOM", problems)

    def test_the_sbom_must_name_the_system_tools(self):
        d = self.standard()
        p = os.path.join(d, "provost-9.9.9.cdx.json")
        with open(p) as f:
            bom = json.load(f)
        bom["components"] = [c for c in bom["components"] if c["name"] != "git"]
        with open(p, "w") as f:
            json.dump(bom, f)
        self.assertIn("the SBOM does not name the system tool git", ob.check(d))

    def test_no_sums(self):
        d = self.standard()
        os.remove(os.path.join(d, "SHA256SUMS"))
        self.assertEqual(ob.check(d), ["no SHA256SUMS"])

    def test_malformed_sums_line(self):
        d = self.standard()
        with open(os.path.join(d, "SHA256SUMS"), "a") as f:
            f.write("not a checksum line\n")
        self.assertIn("SHA256SUMS line 5 is not 'HASH  NAME'", ob.check(d))


class PackTest(Base):
    def test_reproducible_and_complete(self):
        d = self.standard()
        rc, out, _ = quiet(ob.main, ["pack", d])
        self.assertEqual(rc, 0)
        tgz = out.strip()
        self.assertEqual(tgz, d + ".tar.gz")
        with open(tgz, "rb") as f:
            first = f.read()
        os.remove(tgz)
        quiet(ob.main, ["pack", d])
        with open(tgz, "rb") as f:
            self.assertEqual(f.read(), first)
        with tarfile.open(tgz) as t:
            members = t.getmembers()
        self.assertEqual([m.name for m in members],
                         ["provost-9.9.9-offline"] + ["provost-9.9.9-offline/" + n for n in sorted(os.listdir(d))])
        self.assertTrue(all(m.uid == 0 and m.mtime == 1700000000 for m in members))


class AgreementTest(unittest.TestCase):
    """The tool list agrees with what provost says it needs."""

    def test_docs_name_every_tool(self):
        with open(ob.INSTALL_DOC) as f:
            doc = f.read()
        for name, _, _ in ob.SYSTEM_TOOLS:
            self.assertIn(name.split("-")[0], doc, name)

    def test_readme_requirements_are_required(self):
        with open(os.path.join(ROOT, "README.md")) as f:
            self.assertIn("Requires bash and git", f.read())
        self.assertTrue({"bash", "git"} <= set(ob.REQUIRED_TOOLS))

    def test_core_has_no_python_dependencies(self):
        # the bundle holds provost's wheel alone; a [project] dependency would
        # need its wheels bundled too (tools/offline_bundle.py build --wheels)
        with open(os.path.join(ROOT, "pyproject.toml")) as f:
            text = f.read()
        project = text.split("[project]", 1)[1].split("\n[", 1)[0]
        self.assertNotRegex(project, r"(?m)^dependencies\s*=")


if __name__ == "__main__":
    unittest.main()
