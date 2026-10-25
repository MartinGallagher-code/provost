"""`gcovr [-r .] [--branches]`: dashed banner and `Directory:` line, then a
File/Lines/Exec/Cover/Missing table (long file names wrap their numbers
onto the next line) and a TOTAL row."""
from lib import Doc, fake

TOOL = "gcovr"


def _ranges(rng, n):
    out, ln = [], rng.randint(1, 40)
    for _ in range(n):
        ln += rng.randint(1, 60)
        if rng.random() < .4:
            e = ln + rng.randint(1, 12)
            out.append(f"{ln}-{e}")
            ln = e
        else:
            out.append(str(ln))
    return ",".join(out)


def generate(rng):
    d = Doc()
    W = 78
    branches = rng.random() < .3
    d.skip("-" * W)
    d.skip(("GCC Code Coverage Report").center(W).rstrip())
    root = rng.choice([".", f"/home/{fake.user(rng)}/src/{fake.word(rng)}", f"/builds/{fake.word(rng)}/{fake.word(rng)}", "../src"])
    d.kv("Directory", root)
    d.skip("-" * W)
    cols = ["File", "Branches", "Taken", "Cover", "Missing"] if branches else ["File", "Lines", "Exec", "Cover", "Missing"]
    fw = 40 if branches else 42
    d.line(cols[0].ljust(fw) + cols[1].rjust(8) + cols[2].rjust(8) + cols[3].rjust(7) + "   " + cols[4], "header", cols)
    d.skip("-" * W)
    tl = te = 0
    dirs = ["src", "src/core", "lib", "include", "src/net", "tests", "third_party/" + fake.word(rng)]
    for _ in range(rng.randint(1, 18)):
        name = rng.choice(dirs) + "/" + rng.choice([fake.word(rng), fake.name(rng, "_")]) + rng.choice([".c", ".cpp", ".cc", ".h", ".hpp"])
        if rng.random() < .1:
            name = rng.choice(dirs) + "/" + "/".join(fake.word(rng) for _ in range(3)) + "/" + fake.name(rng, "_") + "_implementation_details.cpp"
        lines = rng.randint(0, 900)
        ex = lines if rng.random() < .3 else rng.randint(0, lines)
        tl, te = tl + lines, te + ex
        cov = "--%" if lines == 0 else f"{int(100 * ex / lines)}%"
        miss = _ranges(rng, rng.randint(1, 9)) if ex < lines else None
        nums = str(lines).rjust(8) + str(ex).rjust(8) + cov.rjust(7) + ("   " + miss if miss else "")
        if len(name) >= fw:
            d.line(name, "row", [name, None, None, None, None])
            d.line(" " * fw + nums, "cont", [str(lines), str(ex), cov] + ([miss] if miss else []))
        else:
            d.line(name.ljust(fw) + nums, "row", [name, str(lines), str(ex), cov, miss])
    d.skip("-" * W)
    cov = "--%" if tl == 0 else f"{int(100 * te / tl)}%"
    d.line("TOTAL".ljust(fw) + str(tl).rjust(8) + str(te).rjust(8) + cov.rjust(7), "row", ["TOTAL", str(tl), str(te), cov, None])
    d.skip("-" * W)
    if rng.random() < .3:
        d.line(f"lines: {cov} ({te} out of {tl})", "kv", ["lines", f"{cov} ({te} out of {tl})"])
        bc = rng.randint(0, 3000)
        bt = rng.randint(0, bc)
        bp = f"{100 * bt / bc:.1f}%" if bc else "0.0%"
        d.line(f"branches: {bp} ({bt} out of {bc})", "kv", ["branches", f"{bp} ({bt} out of {bc})"])
    return d
