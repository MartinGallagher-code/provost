"""QUAST `report.txt`: a prose preamble, then a left-aligned table whose rows
are multi-word metric names (`# contigs (>= 1000 bp)`, `GC (%)`) and whose
columns are assemblies; reference-based rows appear only with a reference."""
from lib import Doc, fake

TOOL = "quast"

THRESHOLDS = [0, 1000, 5000, 10000, 25000, 50000]


def _nx(lens, total, frac):
    acc = 0
    for i, ln in enumerate(lens):
        acc += ln
        if acc >= total * frac:
            return ln, i + 1
    return None, None


def _assembly(rng, genome, gc_ref, minc, ref):
    n_all = rng.choice([rng.randint(1, 30), rng.randint(30, 600), rng.randint(600, 4000)])
    n_all = max(1, min(n_all, genome // (minc * 4)))
    sigma = rng.uniform(0.6, 1.8)
    raw = [rng.lognormvariate(0, sigma) for _ in range(n_all)]
    scale = genome * rng.uniform(0.85, 1.12) / sum(raw)
    lens = sorted((max(minc // 3 or 1, int(x * scale)) for x in raw), reverse=True)
    c = {}
    for t in THRESHOLDS:
        c[f"# contigs (>= {t} bp)"] = str(sum(1 for x in lens if x >= t))
    for t in THRESHOLDS:
        c[f"Total length (>= {t} bp)"] = str(sum(x for x in lens if x >= t))
    main = [x for x in lens if x >= minc] or lens[:1]
    tl, cnum, largest = sum(main), len(main), main[0]
    c["# contigs"] = str(cnum)
    c["Largest contig"] = str(largest)
    c["Total length"] = str(tl)
    if ref:
        c["Reference length"] = str(genome)
    c["GC (%)"] = f"{gc_ref + rng.uniform(-0.6, 0.6):.2f}"
    if ref:
        c["Reference GC (%)"] = f"{gc_ref:.2f}"
    n50, l50 = _nx(main, tl, 0.5)
    n90, l90 = _nx(main, tl, 0.9)
    ng50, lg50 = _nx(main, genome, 0.5)
    ng90, lg90 = _nx(main, genome, 0.9)
    dash = lambda v: "-" if v is None else str(v)
    sq = sum(x * x for x in main)
    c["N50"] = str(n50)
    if ref:
        c["NG50"] = dash(ng50)
    c["N90"] = str(n90)
    if ref:
        c["NG90"] = dash(ng90)
    c["auN"] = f"{sq / tl:.1f}"
    if ref:
        c["auNG"] = f"{sq / genome:.1f}"
    c["L50"] = str(l50)
    if ref:
        c["LG50"] = dash(lg50)
    c["L90"] = str(l90)
    if ref:
        c["LG90"] = dash(lg90)
        mis = rng.randint(0, min(60, cnum * 2))
        c["# misassemblies"] = str(mis)
        c["# misassembled contigs"] = str(min(mis, cnum))
        c["Misassembled contigs length"] = str(sum(main[:min(mis, cnum)]) if mis and rng.random() < .5 else
                                               int(tl * rng.uniform(0, 0.3)) if mis else 0)
        c["# local misassemblies"] = str(rng.randint(0, 80))
        c["# scaffold gap ext. mis."] = str(rng.randint(0, 5))
        c["# scaffold gap loc. mis."] = str(rng.randint(0, 5))
        c["# unaligned mis. contigs"] = str(rng.randint(0, 5))
        ua, up = rng.randint(0, min(40, cnum)), rng.randint(0, min(30, cnum))
        c["# unaligned contigs"] = f"{ua} + {up} part"
        c["Unaligned length"] = str(rng.randint(0, tl // 20))
        c["Genome fraction (%)"] = f"{rng.uniform(70, 99.99):.3f}"
        c["Duplication ratio"] = f"{rng.uniform(1.0, 1.08):.3f}"
    c["# N's per 100 kbp"] = rng.choice(["0.00", "0.00", f"{rng.uniform(0, 400):.2f}"])
    if ref:
        c["# mismatches per 100 kbp"] = f"{rng.uniform(0, 300):.2f}"
        c["# indels per 100 kbp"] = f"{rng.uniform(0, 80):.2f}"
        c["Largest alignment"] = str(int(largest * rng.uniform(0.6, 1.0)))
        c["Total aligned length"] = str(int(tl * rng.uniform(0.9, 0.999)))
        k = rng.uniform(0.5, 1.0)
        for name, base in (("NA50", n50), ("NGA50", ng50), ("NA90", n90), ("NGA90", ng90)):
            c[name] = str(int(base * k)) if base and rng.random() < 0.95 else "-"
        c["auNA"] = f"{sq / tl * k:.1f}"
        c["auNGA"] = f"{sq / genome * k:.1f}"
        for name, nk, lk in (("LA50", "NA50", "L50"), ("LGA50", "NGA50", "LG50"), ("LA90", "NA90", "L90"),
                             ("LGA90", "NGA90", "LG90")):
            c[name] = str(int(c[lk]) + rng.randint(0, 9)) if c[nk] != "-" and c[lk] != "-" else "-"
    return c


def generate(rng):
    d = Doc()
    minc = rng.choice([500, 500, 200, 1000, 300])
    d.skip(f'All statistics are based on contigs of size >= {minc} bp, unless otherwise noted (e.g., "# contigs (>= 0 bp)" '
           f'and "Total length (>= 0 bp)" include all contigs).')
    d.blank()
    asm = rng.sample(["contigs", "scaffolds", "spades_contigs", "megahit_final", "flye_assembly", "canu.contigs",
                      "shasta_Assembly", "hifiasm.p_ctg", "velvet_k31", "unicycler", "SKESA", "raven_out", "polished_medaka"],
                     rng.choice([1, 1, 2, 2, 3, 4]))
    ref = rng.random() < 0.55
    genome = rng.choice([rng.randint(1_500_000, 7_000_000), rng.randint(10_000_000, 150_000_000), rng.randint(4_000, 60_000)])
    gc_ref = rng.uniform(25, 70)
    cols = [_assembly(rng, genome, gc_ref, minc, ref) for _ in asm]
    shown = [t for t in THRESHOLDS if t in (0, 1000) or rng.random() < 0.8]
    keys = [k for k in cols[0]
            if not (k.startswith(("# contigs (>=", "Total length (>=")) and int(k.split(">= ")[1].split()[0]) not in shown)]
    if rng.random() < 0.3:
        keys = [k for k in keys if not k.startswith("au")]
    rows = [[k] + [c[k] for c in cols] for k in keys]
    d.table(["Assembly"] + asm, rows, gap=rng.choice([1, 2, 2]) if len(asm) > 1 else 2)
    return d
