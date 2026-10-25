"""HISAT2 alignment summary on stderr: the classic indented tree
(`N (p%) aligned ...; of these:`), or the `--new-summary` tab-indented
`Key: N (p%)` form."""
from lib import Doc, fake

TOOL = "hisat2"


def _p(n, total):
    return f"({100.0 * n / total:.2f}%)" if total else "(0.00%)"


def _split(rng, total, k):
    cuts = sorted(rng.randint(0, total) for _ in range(k - 1))
    out, prev = [], 0
    for c in cuts + [total]:
        out.append(c - prev)
        prev = c
    return out


def _mates(rng, mates):
    """Unaligned mates: most stay unaligned, the rest align once or more."""
    m0 = int(mates * rng.uniform(0.4, 0.95))
    m1 = int((mates - m0) * rng.uniform(0.5, 0.9))
    return m0, m1, mates - m0 - m1


def generate(rng):
    d = Doc()
    for _ in range(rng.choice([0, 0, 0, 1, 2])):
        d.skip(rng.choice([
            f"Warning: skipping read 'SRR{rng.randint(100000, 9999999)}.{rng.randint(1, 9999999)}' because length (1) <= # seed mismatches (0)",
            f"Warning: skipping read 'read_{rng.randint(1, 99999)}' because it was < 2 characters long",
            "Warning: Unsupported file format",
        ]))
    total = rng.choice([rng.randint(1000, 99999), rng.randint(100000, 9999999), rng.randint(10 ** 7, 9 * 10 ** 7)])
    paired = rng.random() < 0.6
    # concordant/unpaired fractions
    a0 = int(total * rng.uniform(0.01, 0.35))
    rest = total - a0
    a1 = int(rest * rng.uniform(0.75, 0.97))
    am = rest - a1
    if rng.random() < 0.45:
        # --new-summary
        d.section("HISAT2 summary stats:")
        if paired:
            disc = int(a0 * rng.uniform(0, 0.1))
            d.kv("Total pairs", str(total), indent="\t")
            d.kv("Aligned concordantly or discordantly 0 time", [str(a0 - disc), _p(a0 - disc, total)], sep=": ", indent="\t\t")
            d.line(f"\t\tAligned concordantly 1 time: {a1} {_p(a1, total)}", "kv", ["Aligned concordantly 1 time", str(a1), _p(a1, total)])
            d.line(f"\t\tAligned concordantly >1 times: {am} {_p(am, total)}", "kv", ["Aligned concordantly >1 times", str(am), _p(am, total)])
            d.line(f"\t\tAligned discordantly 1 time: {disc} {_p(disc, total)}", "kv", ["Aligned discordantly 1 time", str(disc), _p(disc, total)])
            mates = (a0 - disc) * 2
            m0, m1, mm = _mates(rng, mates)
            d.kv("Total unpaired reads", str(mates), indent="\t")
            for lab, n in (("Aligned 0 time", m0), ("Aligned 1 time", m1), ("Aligned >1 times", mm)):
                d.line(f"\t\t{lab}: {n} {_p(n, mates)}", "kv", [lab, str(n), _p(n, mates)])
            rate = 100.0 * (total * 2 - m0) / (total * 2)
        else:
            d.kv("Total reads", str(total), indent="\t")
            for lab, n in (("Aligned 0 time", a0), ("Aligned 1 time", a1), ("Aligned >1 times", am)):
                d.line(f"\t\t{lab}: {n} {_p(n, total)}", "kv", [lab, str(n), _p(n, total)])
            rate = 100.0 * (total - a0) / total
        d.kv("Overall alignment rate", f"{rate:.2f}%", indent="\t")
        return d

    d.line(f"{total} reads; of these:", "row", [str(total), "reads; of these:"])
    kind = "paired" if paired else "unpaired"
    d.line(f"  {total} (100.00%) were {kind}; of these:", "row", [str(total), "(100.00%)", f"were {kind}; of these:"])
    con = "concordantly " if paired else ""
    for lab, n in ((f"aligned {con}0 times", a0), (f"aligned {con}exactly 1 time", a1), (f"aligned {con}>1 times", am)):
        d.line(f"    {n} {_p(n, total)} {lab}", "row", [str(n), _p(n, total), lab])
    if paired:
        d.skip("    ----")
        d.line(f"    {a0} pairs aligned concordantly 0 times; of these:", "row",
               [str(a0), "pairs aligned concordantly 0 times; of these:"])
        disc = int(a0 * rng.uniform(0, 0.1))
        d.line(f"      {disc} {_p(disc, a0)} aligned discordantly 1 time", "row", [str(disc), _p(disc, a0), "aligned discordantly 1 time"])
        d.skip("    ----")
        left = a0 - disc
        d.line(f"    {left} pairs aligned 0 times concordantly or discordantly; of these:", "row",
               [str(left), "pairs aligned 0 times concordantly or discordantly; of these:"])
        mates = left * 2
        d.line(f"      {mates} mates make up the pairs; of these:", "row", [str(mates), "mates make up the pairs; of these:"])
        m0, m1, mm = _mates(rng, mates)
        for lab, n in (("aligned 0 times", m0), ("aligned exactly 1 time", m1), ("aligned >1 times", mm)):
            d.line(f"        {n} {_p(n, mates)} {lab}", "row", [str(n), _p(n, mates), lab])
        rate = 100.0 * (total * 2 - m0) / (total * 2)
    else:
        rate = 100.0 * (total - a0) / total
    d.line(f"{rate:.2f}% overall alignment rate", "row", [f"{rate:.2f}%", "overall alignment rate"])
    return d
