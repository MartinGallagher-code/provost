"""David A. Wheeler's `sloccount DIR`: progress chatter, a per-directory
table (tab-separated header, space-padded rows), language totals, then the
COCOMO estimate block and licence footer."""
from lib import Doc, fake

TOOL = "sloccount"

LANGS = ["ansic", "cpp", "python", "sh", "perl", "java", "ruby", "lisp", "yacc", "lex", "asm",
         "fortran", "php", "cs", "ada", "ml", "haskell", "tcl", "exp", "sed", "awk", "makefile"]
DIRS = ["src", "lib", "tests", "docs", "tools", "scripts", "include", "contrib", "top_dir",
        "examples", "bindings", "po", "m4", "debian", "third_party_libraries"]


def comma(n):
    return f"{n:,}"


def generate(rng):
    d = Doc()
    dirs = rng.sample(DIRS, rng.randint(2, 8))
    if rng.random() < .8:
        for x in dirs:
            d.skip(f"Creating filelist for {x}")
        d.skip("Categorizing files.")
        d.skip("Finding a working MD5 command....")
        d.skip("Found a working MD5 command.")
        d.skip("Computing results.")
        d.blank()
        d.blank()
    langs = rng.sample(LANGS, rng.randint(1, 6))
    totals = {l: 0 for l in langs}
    rows = []
    for x in dirs:
        if rng.random() < .2:
            rows.append((0, x, "(none)"))
            continue
        used = rng.sample(langs, rng.randint(1, len(langs)))
        counts = sorted(((rng.choice([rng.randint(1, 300), rng.randint(100, 60000)]), l) for l in used), reverse=True)
        for c, l in counts:
            totals[l] += c
        rows.append((sum(c for c, _ in counts), x, ",".join(f"{l}={c}" for c, l in counts)))
    rows.sort(key=lambda r: -r[0])
    d.line("SLOC\tDirectory\tSLOC-by-Language (Sorted)", "header", ["SLOC", "Directory", "SLOC-by-Language (Sorted)"])
    for n, x, by in rows:
        d.line(f"{str(n).ljust(8)}{x.ljust(16)}{by}" if len(x) < 16 else f"{str(n).ljust(8)}{x} {by}",
               "row", [str(n), x, by])
    d.blank()
    d.blank()
    d.section("Totals grouped by language (dominant language first):")
    total = sum(totals.values()) or 1
    for l, c in sorted(totals.items(), key=lambda kv: -kv[1]):
        if not c:
            continue
        pct = f"({100 * c / total:.2f}%)"
        d.line(f"{(l + ':').ljust(11)}{str(c).rjust(8)} {pct}", "kv", [l, str(c), pct])
    for _ in range(rng.choice([2, 4])):
        d.blank()
    ksloc = total / 1000
    pm = 2.4 * ksloc ** 1.05
    months = 2.5 * pm ** 0.38
    salary = rng.choice([56286, 60000, 75000, 95000])
    over = rng.choice(["2.40", "2.00", "1.80"])
    cost = pm / 12 * salary * float(over)
    W = 58

    def est(key, *vals):
        d.line(key.ljust(W) + "= " + " ".join(vals), "kv", [key] + list(vals))

    est("Total Physical Source Lines of Code (SLOC)", comma(total))
    est("Development Effort Estimate, Person-Years (Person-Months)", f"{pm / 12:.2f}", f"({pm:.2f})")
    d.skip(" (Basic COCOMO model, Person-Months = 2.4 * (KSLOC**1.05))")
    est("Schedule Estimate, Years (Months)", f"{months / 12:.2f}", f"({months:.2f})")
    d.skip(" (Basic COCOMO model, Months = 2.5 * (person-months**0.38))")
    est("Estimated Average Number of Developers (Effort/Schedule)", f"{pm / months:.2f}")
    est("Total Estimated Cost to Develop", f"$ {comma(int(cost))}")
    sal = f"${comma(salary)}/year"
    d.line(f" (average salary = {sal}, overhead = {over}).", "row", ["average salary", sal, "overhead", over])
    if rng.random() < .85:
        d.skip("SLOCCount, Copyright (C) 2001-2004 David A. Wheeler")
        d.skip("SLOCCount is Open Source Software/Free Software, licensed under the GNU GPL.")
        d.skip("SLOCCount comes with ABSOLUTELY NO WARRANTY, and you are welcome to")
        d.skip("redistribute it under certain conditions as specified by the GNU GPL license;")
        d.skip("see the documentation for details.")
        d.skip("Please credit this data as \"generated using David A. Wheeler's 'SLOCCount'.\"")
    return d
