r"""pyup `safety check` (1.x/2.x text report): an 80-column `+====+` box
holding the ASCII-art banner, a REPORT block, then a bordered pipe table
(package | installed | affected | ID) or a "No known security
vulnerabilities found." line; with --full-report each row is followed by a
wrapped advisory paragraph."""
import textwrap
from lib import Doc

TOOL = "safety-check"

ART = [
    r"                               /$$$$$$            /$$",
    r"                              /$$__  $$          | $$",
    r"           /$$$$$$$  /$$$$$$ | $$  \__//$$$$$$  /$$$$$$   /$$   /$$",
    r"          /$$_____/ |____  $$| $$$$   /$$__  $$|_  $$_/  | $$  | $$",
    r"         |  $$$$$$   /$$$$$$$| $$_/  | $$$$$$$$  | $$    | $$  | $$",
    r"          \____  $$ /$$__  $$| $$    | $$_____/  | $$ /$$| $$  | $$",
    r"          /$$$$$$$/|  $$$$$$$| $$    |  $$$$$$$  |  $$$$/|  $$$$$$$",
    r"         |_______/  \_______/|__/     \_______/   \___/   \____  $$",
    r"                                                          /$$  | $$",
    r"                                                         |  $$$$$$/",
    r"  by pyup.io                                              \______/",
]
VULNS = [("django", "<2.2.24", "Django before 2.2.24 allows QuerySet.order_by SQL injection if order_by is untrusted input."),
         ("urllib3", "<1.24.2", "The urllib3 library before 1.24.2 for Python mishandles certain cases where the desired set of CA certificates is different from the OS store."),
         ("jinja2", "<2.11.3", "This affects the package jinja2 from 0.0.0 and before 2.11.3. The ReDoS vulnerability is mainly due to the `_punctuation_re regex` operator."),
         ("pyyaml", "<5.4", "A vulnerability was discovered in the PyYAML library in versions before 5.4, where it is susceptible to arbitrary code execution."),
         ("requests", "<2.31.0", "Requests 2.31.0 includes a fix for CVE-2023-32681: Unintended leak of Proxy-Authorization header."),
         ("pillow", "<9.0.1", "Pillow 9.0.1 includes a fix for CVE-2022-22817: PIL.ImageMath.eval in Pillow before 9.0.0 allows evaluation of arbitrary expressions."),
         ("cryptography", ">=3.1,<41.0.2", "Cryptography 41.0.2 includes a fix for CVE-2023-38325: an issue with SSH certificates."),
         ("flask", "<2.2.5", "Flask 2.2.5 and 2.3.2 include a fix for CVE-2023-30861: possible disclosure of permanent session cookie."),
         ("werkzeug", "<2.2.3", "Werkzeug 2.2.3 includes a fix for CVE-2023-25577: high resource usage when parsing multipart form data."),
         ("numpy", "<1.22.0", "Numpy 1.22.0 includes a fix for CVE-2021-41496: buffer overflow in the array_from_pyobj function."),
         ("setuptools", "<65.5.1", "Setuptools 65.5.1 includes a fix for CVE-2022-40897: Regular Expression Denial of Service (ReDoS)."),
         ("certifi", "<2022.12.7", "Certifi 2022.12.07 includes a fix for CVE-2022-23491: removal of TrustCor root certificates."),
         ("sqlalchemy", "<1.2.18", "SQLAlchemy through 1.2.17 has SQL Injection when the group_by parameter can be controlled."),
         ("lxml", "<4.6.5", "Lxml 4.6.5 includes a fix for CVE-2021-43818: HTML Cleaner allows crafted and SVG embedded scripts to pass through.")]
EQ = "+" + "=" * 78 + "+"


def boxed(text):
    return "| " + text.ljust(76) + " |"


def generate(rng):
    d = Doc()
    d.skip(EQ)
    d.skip(boxed(""))
    for a in ART:
        d.skip("|" + a.ljust(78) + "|")
    d.skip(boxed(""))
    d.skip(EQ)
    d.line(boxed("REPORT"), "section", ["REPORT"])
    n = rng.randint(8, 240)
    db = rng.choice(["using free DB (updated once a month)", "using default DB", "using PyUp's commercial DB"])
    d.skip(boxed(f"checked {n} packages, {db}"))
    vulns = rng.sample(VULNS, rng.randint(0, 6))
    if not vulns:
        d.skip(EQ)
        d.skip(boxed("No known security vulnerabilities found."))
        d.skip(EQ)
        return d
    w = [26, 9, 24, 8]
    sep = "+" + "+".join("=" * (x + 2) for x in w) + "+"
    dash = "+" + "+".join("-" * (x + 2) for x in w) + "+"

    def row(c):
        return "| " + " | ".join(c[i].ljust(w[i]) for i in range(4)) + " |"

    d.skip(sep)
    hdr = ["package", "installed", "affected", "ID"]
    d.line(row(hdr), "header", hdr)
    d.skip(sep)
    full = rng.random() < .35
    for i, (pkg, aff, desc) in enumerate(vulns):
        lim = [int(x) for x in aff.split("<")[-1].split(".")]
        k = max(i for i, x in enumerate(lim) if x > 0)
        k = rng.randint(0, k) if lim[0] > 0 and rng.random() < .3 else k
        while lim[k] == 0:
            k -= 1
        lim[k] -= rng.randint(1, min(lim[k], 3))
        lim[k + 1:] = [rng.randint(0, 12) for _ in lim[k + 1:]]
        inst = ".".join(map(str, lim))
        vid = str(rng.randint(25000, 62000))
        cells = [pkg, inst, aff, vid]
        d.line(row(cells), "row", cells)
        if full:
            d.skip(dash)
            for ln in textwrap.wrap(desc, 76):
                d.skip(boxed(ln))
            if i < len(vulns) - 1:
                d.skip(sep)
    d.skip(EQ)
    return d
