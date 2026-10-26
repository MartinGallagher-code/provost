"""TeX Live `tlmgr info PKG`: an aligned `key:  value` report per package
(the `sizes:` line holds several sub-pairs), optionally followed by
`--list` file sections; several packages are separated by blank lines."""
from lib import Doc

TOOL = "tlmgr-info"

PKGS = [("amsmath", "AMS mathematical facilities for LaTeX", "maths", "collection-latexrequired"),
        ("hyperref", "Extensive support for hypertext in LaTeX", "hyper pdf-feat", "collection-latexrecommended"),
        ("geometry", "Flexible and complete interface to document dimensions", "page-layout", "collection-latex"),
        ("biblatex", "Sophisticated Bibliographies in LaTeX", "biblio", "collection-bibtexextra"),
        ("tikz-cd", "Create commutative diagrams with TikZ", "diagram-comm", "collection-pictures"),
        ("pgf", "Create PostScript and PDF graphics in TeX", "graphics graphics-in-tex", "collection-basic"),
        ("fontspec", "Advanced font selection in XeLaTeX and LuaLaTeX", "font-sel luatex xetex",
         "collection-latexrecommended"),
        ("siunitx", "A comprehensive (SI) units package", "units", "collection-science"),
        ("booktabs", "Publication quality tables in LaTeX", "table", "collection-latexrecommended"),
        ("minted", "Highlighted source code for LaTeX", "listing", "collection-latexextra"),
        ("beamer", "A LaTeX class for producing presentations and slides", "presentation", "collection-latexrecommended")]
LIC = ["lppl1.3c", "lppl1.3", "lppl", "gpl2", "mit", "lppl1.3c gpl2", "pd"]


def generate(rng):
    d = Doc()
    picks = rng.sample(PKGS, rng.randint(1, 3))
    with_files = rng.random() < .3
    w = rng.choice([12, 12, 13])
    for i, (name, short, topics, coll) in enumerate(picks):
        if i:
            d.blank()
        inst = rng.random() < .75
        pairs = [("package", name), ("repository", rng.choice(["https://mirror.ctan.org/systems/texlive/tlnet",
                                                               "http://mirrors.mit.edu/CTAN/systems/texlive/tlnet",
                                                               "/usr/local/texlive/2023/tlpkg"]))]
        if rng.random() < .3:
            pairs = pairs[:1]
        pairs += [("category", "Package"), ("shortdesc", short)]
        if rng.random() < .8:
            pairs.append(("longdesc", short + ". The package " + rng.choice([
                "provides a number of enhancements and is distributed as part of the core bundle.",
                "is maintained on GitHub and documented in the accompanying manual.",
                "requires a recent LaTeX kernel."])))
        pairs += [("installed", "Yes" if inst else "No"), ("revision", str(rng.randint(10000, 69000)))]
        for k, v in pairs:
            d.line((k + ":").ljust(w + 1) + v, "kv", [k, v])
        sz = [("src", f"{rng.randint(1, 2000)}k"), ("doc", f"{rng.randint(10, 9000)}k"), ("run", f"{rng.randint(5, 3000)}k")]
        if rng.random() < .2:
            sz = sz[1:]
        d.line("sizes:".ljust(w + 1) + ", ".join(f"{a}: {b}" for a, b in sz), "row",
               ["sizes"] + [x for p in sz for x in p])
        more = [("relocatable", "No"), ("cat-version", f"{rng.randint(1, 9)}.{rng.randint(0, 30)}{rng.choice(['', 'a', 'n'])}"),
                ("cat-date", f"{rng.randint(2015, 2026)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d} "
                             f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} +0{rng.randint(0, 2)}00"),
                ("cat-license", rng.choice(LIC)), ("cat-topics", topics),
                ("cat-related", rng.choice(["", "amsfonts", "pgfplots tikz-3dplot", "biber"])),
                ("collection", coll)]
        for k, v in more:
            if not v or rng.random() < .1:
                continue
            d.line((k + ":").ljust(w + 1) + v, "kv", [k, v])
        if with_files and inst:
            d.section("Included files, by type:")
            for kind in rng.sample(["run", "doc", "src"], rng.randint(1, 3)):
                d.section(f"  {kind} files:")
                ext = {"run": [".sty", ".cls", ".def", ".cfg"], "doc": [".pdf", "/README.md"],
                       "src": [".dtx", ".ins"]}[kind]
                for _ in range(rng.randint(1, 6)):
                    base = rng.choice([name, name + "-" + rng.choice(["base", "core", "compat", "doc"])])
                    root = "tex/latex" if kind == "run" else ("doc/latex" if kind == "doc" else "source/latex")
                    f = f"texmf-dist/{root}/{name}/{base}{rng.choice(ext)}"
                    d.line("    " + f, "row", [f])
    return d
