"""poppler `pdffonts`: a fixed-width table (name/type/encoding/emb/sub/uni/
object ID) under a dashed rule; the object ID is `num gen`."""
from lib import Doc, fake

TOOL = "pdffonts"

BASE = ["Helvetica", "Helvetica-Bold", "Times-Roman", "Times-Italic", "Courier", "Symbol", "ArialMT",
        "Arial-BoldMT", "TimesNewRomanPSMT", "Calibri", "Calibri-Bold", "Cambria-Math", "DejaVuSans",
        "LiberationSerif-Italic", "CMR10", "CMMI10", "CMSY10", "SFRM1000", "MinionPro-Regular",
        "MyriadPro-SemiboldCondensedIt", "NotoSansCJKjp-Regular", "SourceCodePro-Medium", "Wingdings-Regular"]
TYPES = ["Type 1", "Type 1C", "Type 3", "TrueType", "CID TrueType", "CID Type 0C", "Type 1 (OT)",
         "CID Type 0C (OT)", "TrueType (CID)"]
ENCS = ["Custom", "Standard", "WinAnsi", "Identity-H", "Builtin", "MacRoman"]


def _subset(rng):
    return "".join(rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(6)) + "+"


def generate(rng):
    d = Doc()
    if rng.random() < .15:
        d.skip(f"Syntax Error ({rng.randint(100, 99999)}): Illegal character '{rng.choice(')>}')}'")
    d.line("name                                 type              encoding         emb sub uni object ID",
           "header", ["name", "type", "encoding", "emb", "sub", "uni", "object ID"])
    d.skip("------------------------------------ ----------------- ---------------- --- --- --- ---------")
    obj = rng.randint(5, 40)
    for _ in range(rng.randint(1, 14)):
        t = rng.choice(TYPES)
        if t == "Type 3" and rng.random() < .6:
            name = "[none]"
        else:
            name = (_subset(rng) if rng.random() < .6 else "") + rng.choice(BASE)
        enc = "Identity-H" if t.startswith("CID") else rng.choice(ENCS)
        emb = rng.choice(["yes", "yes", "no"])
        sub = "yes" if name[6:7] == "+" else "no"
        uni = rng.choice(["yes", "no"])
        obj += rng.randint(1, 30)
        oid = f"{obj:6d} {rng.choice([0, 0, 0, 1]):2d}"
        text = f"{name:<36s} {t:<17s} {enc:<16s} {emb:<3s} {sub:<3s} {uni:<3s} {oid}"
        d.line(text, "row", [name, t, enc, emb, sub, uni, oid.strip()])
    return d
