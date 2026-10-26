"""lcdf-typetools `otfinfo -i FONT`: the name table as `Key:` padded to a
fixed column, one field per line, some values long sentences or URLs."""
from lib import Doc

TOOL = "otfinfo"

FAMILIES = ["Source Sans Pro", "Fira Code", "Inter", "Noto Serif", "IBM Plex Mono", "Libertinus Serif",
            "EB Garamond", "Atkinson Hyperlegible", "Cormorant", "Roboto Slab", "JetBrains Mono", "Lato"]
STYLES = ["Regular", "Bold", "Italic", "Bold Italic", "Light", "SemiBold", "ExtraLight Italic", "Black"]
FOUNDRIES = [("Adobe Systems Incorporated", "ADBO", "http://www.adobe.com/type"),
             ("Google Inc.", "GOOG", "http://www.google.com/get/noto/"),
             ("IBM Corp.", "IBM ", "http://www.ibm.com"),
             ("Rasmus Andersson", "RSMS", "https://rsms.me/"),
             ("JetBrains", "JB  ", "https://www.jetbrains.com"),
             ("tyPoland Lukasz Dziedzic", "TYPO", "http://www.typoland.com/")]
DESIGNERS = ["Paul D. Hunt", "Nikita Prokopov", "Rasmus Andersson", "Mike Abbink, Bold Monday", "Georg Duffner",
             "Christian Thalmann", "Łukasz Dziedzic", "Philipp Nurullin, Konstantin Bulenkov"]


def generate(rng):
    d = Doc()
    fam = rng.choice(FAMILIES)
    sty = rng.choice(STYLES)
    fnd = rng.choice(FOUNDRIES)
    ps = fam.replace(" ", "") + "-" + sty.replace(" ", "")
    ver = f"{rng.randint(1, 4)}.{rng.randint(0, 999):03d}"
    year = rng.randint(1998, 2024)
    rows = []
    preferred = " " in sty and rng.random() < .6
    rows.append(("Family", fam if not preferred else fam + " " + sty.split()[0]))
    rows.append(("Subfamily", sty if not preferred else sty.split()[-1]))
    rows.append(("Full name", f"{fam} {sty}"))
    rows.append(("PostScript name", ps))
    if preferred:
        rows.append(("Preferred family", fam))
        rows.append(("Preferred subfamily", sty))
    if rng.random() < .3:
        rows.append(("Mac font menu name", f"{fam} {sty}"))
    rows.append(("Version", rng.choice([f"Version {ver}", f"Version {ver};PS {rng.randint(1, 2)}.000;hotconv 1.0.{rng.randint(70, 118)};makeotf.lib2.5.{rng.randint(5000, 65000)}",
                                        f"Version {ver}; ttfautohint (v1.8.{rng.randint(1, 4)})"])))
    rows.append(("Unique ID", rng.choice([f"{ver};{fnd[1].strip()};{ps};ADOBE", f"{ps}-{ver}",
                                          f"{fnd[0]}: {fam} {sty}: {year}"])))
    if rng.random() < .6:
        rows.append(("Description", rng.choice(["A humanist sans serif typeface for user interfaces.",
                                                "Monospaced font with programming ligatures",
                                                f"Copyright (c) {year} {fnd[0]}. Designed for text at small sizes on screen and in print."])))
    if rng.random() < .8:
        rows.append(("Designer", rng.choice(DESIGNERS)))
    if rng.random() < .6:
        rows.append(("Designer URL", rng.choice(["http://www.paul-hunt.com", "https://github.com/tonsky", fnd[2]])))
    rows.append(("Manufacturer", fnd[0]))
    if rng.random() < .7:
        rows.append(("Vendor URL", fnd[2]))
    if rng.random() < .5:
        rows.append(("Trademark", f"{fam.split()[0]} is a trademark of {fnd[0]} in the United States and/or other countries."))
    rows.append(("Copyright", rng.choice([f"Copyright {year} {fnd[0]} (http://www.adobe.com/), with Reserved Font Name '{fam.split()[0]}'.",
                                          f"Copyright (c) {year}-{year + rng.randint(1, 8)} The {fam} Project Authors",
                                          f"© {year} {fnd[0]}"])))
    if rng.random() < .7:
        rows.append(("License URL", rng.choice(["http://scripts.sil.org/OFL", "https://openfontlicense.org",
                                                "http://www.apache.org/licenses/LICENSE-2.0"])))
        rows.append(("License Description", rng.choice([
            "This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: http://scripts.sil.org/OFL",
            "Licensed under the Apache License, Version 2.0",
            "This Font Software is licensed under the SIL Open Font License, Version 1.1."])))
    if rng.random() < .3:
        rows.append(("Sample text", "The quick brown fox jumps over the lazy dog."))
    rows.append(("Vendor ID", fnd[1]))
    if rng.random() < .8:
        rows.append(("Permissions", rng.choice(["Installable", "Editable", "Preview & Print", "Restricted"])))
    for k, v in rows:
        d.line((k + ":").ljust(21) + v, "kv", [k, v.strip()])
    return d
