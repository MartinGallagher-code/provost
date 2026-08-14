#!/usr/bin/env python3
"""check_docx.py — is this .docx actually openable?

A review workbook that Word refuses to open is worse than no workbook: the
failure is silent at build time and only shows up when the reviewer double
clicks it. One shipped that way — 216 raw ESC bytes from ANSI colour codes in
the corpus inputs, written straight into word/document.xml. They are legal in
JSON, and the docx library passed them through, but XML 1.0 forbids C0 control
characters ESCAPED OR NOT, so the document was malformed and Word just failed.

Run this on anything before sending it:

    python3 tests/corpus/check_docx.py FILE.docx

Exit 0 = every part is a well-formed XML document with no illegal characters.
Non-zero, with the reason, otherwise.
"""
import re
import sys
import zipfile
import xml.dom.minidom

# XML 1.0 forbids these outright; \t \n \r are the only control chars allowed.
ILLEGAL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def check(path):
    problems = []
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile as e:
        return [f"not a valid zip container: {e}"]

    bad_member = z.testzip()
    if bad_member:
        problems.append(f"corrupt zip member: {bad_member}")

    names = z.namelist()
    if "word/document.xml" not in names:
        problems.append("no word/document.xml — this is not a Word document")

    for name in names:
        if not (name.endswith(".xml") or name.endswith(".rels")):
            continue
        data = z.read(name)
        hits = ILLEGAL.findall(data)
        if hits:
            seen = sorted({hex(h[0]) for h in hits})
            problems.append(
                f"{name}: {len(hits)} XML-illegal control byte(s) {seen} — "
                "Word will refuse to open this"
            )
        try:
            xml.dom.minidom.parseString(data)
        except Exception as e:  # noqa: BLE001 - report whatever the parser says
            problems.append(f"{name}: not well-formed XML: {e}")
    return problems


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    path = sys.argv[1]
    problems = check(path)
    if problems:
        print(f"INVALID: {path}")
        for p in problems:
            print(f"  - {p}")
        return 1
    with zipfile.ZipFile(path) as z:
        doc = z.read("word/document.xml").decode("utf-8", "replace")
    print(
        f"OK: {path} — {len(z.namelist())} parts, "
        f"{doc.count('<w:tbl>')} tables, {doc.count('Heading2')} entries"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
