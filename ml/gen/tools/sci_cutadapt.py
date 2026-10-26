"""cutadapt report: a version banner, run lines, `=== Summary ===` with
right-aligned counts, then one `=== Adapter ===` section per adapter with a
`Key: value;` line, base composition kvs and a tab-separated length table."""
from lib import Doc, fake

TOOL = "cutadapt"

ADAPTERS = ["AGATCGGAAGAGC", "AGATCGGAAGAGCACACGTCTGAACTCCAGTCA", "AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT",
            "CTGTCTCTTATACACATCT", "TGGAATTCTCGGGTGCCAAGG", "AAAAAAAAAA", "GATCGTCGGACT", "CCTTAAGG"]


def _c(n):
    return f"{n:,}"


def _pct(a, b):
    return f"({100.0 * a / b:.1f}%)" if b else "(0.0%)"


def generate(rng):
    d = Doc()
    ver = rng.choice(["4.4", "4.9", "3.5", "2.10", "4.2", "5.0"])
    py = rng.choice(["3.10.12", "3.8.10", "3.11.6", "3.12.4", "3.9.18"])
    d.skip(f"This is cutadapt {ver} with Python {py}")
    paired = rng.random() < 0.4
    adapters = rng.sample(ADAPTERS, rng.randint(1, 2 if not paired else 2))
    params = []
    for i, a in enumerate(adapters):
        params += [rng.choice(["-a", "-g"]) if i == 0 or not paired else "-A", a]
    q = rng.random() < 0.4
    minlen = rng.random() < 0.5
    if q:
        params += ["-q", str(rng.choice([20, 30, 15]))]
    if minlen:
        params += ["-m", str(rng.choice([18, 20, 25, 30, 36]))]
    cores = rng.choice([1, 4, 8, 16])
    params += ["-j", str(cores)]
    stem = rng.choice(["SRR", "ERR", "sample_", "S"]) + str(rng.randint(1, 9999999))
    if paired:
        params += ["-o", f"{stem}_1.trimmed.fq.gz", "-p", f"{stem}_2.trimmed.fq.gz", f"{stem}_1.fastq.gz", f"{stem}_2.fastq.gz"]
    else:
        params += ["-o", f"{stem}.trimmed.fastq.gz", f"{stem}.fastq.gz"]
    d.kv("Command line parameters", " ".join(params))
    d.skip(f"Processing {'paired-end' if paired else 'single-end'} reads on {cores} core{'s' if cores > 1 else ''} ...")
    n = rng.choice([rng.randint(1000, 99999), rng.randint(100000, 9999999), rng.randint(10 ** 7, 9 * 10 ** 7)])
    secs = n * rng.uniform(2e-6, 4e-5)
    us = secs / n * 1e6
    mpm = n / secs * 60 / 1e6
    vals = [f"{secs:.3f} s", f"{us:.3f} µs/read", f"{mpm:.2f} M reads/minute"]
    d.line(f"Finished in {vals[0]} ({vals[1]}; {vals[2]}).", "kv", ["Finished in"] + vals)
    d.blank()
    d.section("=== Summary ===")
    d.blank()
    W = 40
    unit = "read pairs" if paired else "reads"

    def line(key, num, pct=None, indent=""):
        text = (indent + key + ":").ljust(W) + num.rjust(12) + (f" {pct}" if pct else "")
        d.line(text, "kv", [key, num] + ([pct] if pct else []))
    line(f"Total {unit} processed", _c(n))
    with_ad = []
    if paired:
        for r in (1, 2):
            k = int(n * rng.uniform(0.05, 0.6))
            with_ad.append(k)
            line(f"Read {r} with adapter", _c(k), _pct(k, n), indent="  ")
    else:
        k = int(n * rng.uniform(0.05, 0.9))
        with_ad.append(k)
        line("Reads with adapters", _c(k), _pct(k, n))
    short = int(n * rng.uniform(0, 0.05)) if minlen else 0
    if minlen:
        line(f"{'Pairs' if paired else 'Reads'} that were too short", _c(short), _pct(short, n))
    written = n - short
    line(f"{'Pairs' if paired else 'Reads'} written (passing filters)", _c(written), _pct(written, n))
    d.blank()
    rl = rng.choice([50, 75, 100, 101, 150, 151, 250])
    bp = n * rl * (2 if paired else 1)

    def bpl(key, v, pct=None, indent=""):
        num = _c(v) + " bp"
        text = (indent + key + ":").ljust(W - 10) + num.rjust(22) + (f" {pct}" if pct else "")
        d.line(text, "kv", [key, num] + ([pct] if pct else []))
    bpl("Total basepairs processed", bp)
    if paired:
        bpl("Read 1", bp // 2, indent="  ")
        bpl("Read 2", bp // 2, indent="  ")
    qt = int(bp * rng.uniform(0, 0.03)) if q else 0
    if q:
        bpl("Quality-trimmed", qt, _pct(qt, bp))
        if paired:
            bpl("Read 1", qt // 2, indent="  ")
            bpl("Read 2", qt - qt // 2, indent="  ")
    tw = int((bp - qt) * rng.uniform(0.88, 0.995))
    bpl("Total written (filtered)", tw, _pct(tw, bp))
    if paired:
        bpl("Read 1", tw // 2, indent="  ")
        bpl("Read 2", tw - tw // 2, indent="  ")

    for i, a in enumerate(adapters):
        d.blank()
        if paired:
            d.section(f"=== {'First' if i == 0 else 'Second'} read: Adapter {i + 1} ===")
        else:
            d.section(f"=== Adapter {i + 1} ===")
        d.blank()
        typ = rng.choice(["regular 3'", "regular 3'", "regular 5'", "anchored 5'", "variable 5'/3'"])
        times = with_ad[min(i, len(with_ad) - 1)]
        vals = [a, typ, str(len(a)), f"{times} times"]
        d.line(f"Sequence: {a}; Type: {typ}; Length: {len(a)}; Trimmed: {times} times", "row",
               ["Sequence", vals[0], "Type", vals[1], "Length", vals[2], "Trimmed", vals[3]])
        d.blank()
        d.kv("Minimum overlap", str(rng.choice([3, 3, 1, 5])))
        d.section("No. of allowed errors:")
        L = len(a)
        if L < 10:
            d.kv(f"1-{L} bp", "0")
        elif L < 20:
            d.line(f"1-9 bp: 0; 10-{L} bp: 1", "row", ["1-9 bp", "0", f"10-{L} bp", "1"])
        else:
            d.line(f"1-9 bp: 0; 10-19 bp: 1; 20-{L} bp: 2", "row", ["1-9 bp", "0", "10-19 bp", "1", f"20-{L} bp", "2"])
        d.blank()
        if typ == "regular 3'":
            d.section("Bases preceding removed adapters:")
            parts = [rng.uniform(10, 40) for _ in range(4)]
            other = rng.choice([0.0, 0.0, rng.uniform(0, 3)])
            s = sum(parts) / (100 - other)
            for b, v in zip("ACGT", parts):
                d.kv(b, f"{v / s:.1f}%", indent="  ")
            d.kv("none/other", f"{other:.1f}%", indent="  ")
            d.blank()
        d.section("Overview of removed sequences")
        hdr = ["length", "count", "expect", "max.err", "error counts"]
        d.line("\t".join(hdr), "header", hdr)
        cnt = times
        maxlen = rng.randint(min(L + 2, 12), max(L + 3, min(rl, 60)))
        for ln in range(3, maxlen + 1):
            c = int(cnt * rng.uniform(0.05, 0.6)) if ln < maxlen else cnt
            cnt -= c
            c = max(c, 0)
            exp = n / (4 ** ln) if ln <= 20 else 0.0
            err = min(ln // 10, 2) if L >= 10 else 0
            errs = [c]
            if err:
                e1 = int(c * rng.uniform(0, 0.2))
                errs = [c - e1, e1] + ([int(e1 * rng.uniform(0, .3))] if err == 2 else [])
            ec = " ".join(str(x) for x in errs)
            if exp >= 0.1:
                es = f"{exp:.1f}"
            else:
                es = f"{exp:.1f}"
            row = [str(ln), str(c), es, str(err), ec]
            d.line("\t".join(row), "row", row)
            if cnt <= 0:
                break
    return d
