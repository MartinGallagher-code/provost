"""GNU PSPP text output (`pspp -O box=ascii`): one or more boxed tables, each
under a centred title, with `+---+` rules and `|` column separators;
numbers right-aligned, stub labels left-aligned, empty cells left blank."""
from lib import Doc, fake

TOOL = "pspp"

VARS = ["height", "weight", "age", "income", "score", "bmi", "systolic", "diastolic", "reaction_time", "iq", "hours",
        "salary", "rt_ms", "anxiety", "depression", "gpa", "yield", "temp"]


def _table(d, rng, title, header, rows, numeric_from):
    ncol = len(header)
    width = [max(len(header[c] or ""), *(len(r[c] or "") for r in rows)) for c in range(ncol)]
    rule = "+" + "+".join("-" * w for w in width) + "+"
    total = len(rule)
    d.section(title.center(total).rstrip(), title)
    d.skip(rule)

    def render(cells, head=False):
        out = []
        for c, v in enumerate(cells):
            v = v or ""
            if head:
                out.append(v.center(width[c]))
            elif c >= numeric_from:
                out.append(v.rjust(width[c]))
            else:
                out.append(v.ljust(width[c]))
        return "|" + "|".join(out) + "|"
    d.line(render(header, True), "header", [h if h else None for h in header])
    d.skip(rule)
    for r in rows:
        d.line(render(r), "row", [v if v else None for v in r])
    d.skip(rule)


def _descriptives(d, rng):
    vs = rng.sample(VARS, rng.randint(1, 6))
    n = rng.randint(10, 2000)
    rows = []
    for v in vs:
        mu = rng.uniform(1, 500)
        sd = mu * rng.uniform(0.02, 0.4)
        nn = n - rng.choice([0, 0, rng.randint(0, 9)])
        rows.append([v, str(nn), f"{mu:.2f}", f"{sd:.2f}", f"{mu - 2.5 * sd:.2f}", f"{mu + 2.6 * sd:.2f}"])
    valid = min(int(r[1]) for r in rows) - rng.randint(0, 3)
    rows.append(["Valid N (listwise)", str(valid), None, None, None, None])
    if rng.random() < 0.7:
        rows.append(["Missing N (listwise)", str(n - valid), None, None, None, None])
    hdr = [None, "N", "Mean", rng.choice(["Std Dev", "Std. Deviation"]), "Minimum", "Maximum"]
    _table(d, rng, "Descriptive Statistics", hdr, rows, 1)


def _frequencies(d, rng):
    var, cats = rng.choice([("sex", ["f", "m"]), ("group", ["control", "treatment"]),
                            ("smoker", ["no", "yes"]), ("region", ["north", "south", "east", "west"]),
                            ("education", ["primary", "secondary", "tertiary", "postgraduate"]),
                            ("likert_q3", ["1", "2", "3", "4", "5"])])
    counts = [rng.randint(1, 400) for _ in cats]
    miss = rng.choice([0, 0, rng.randint(1, 30)])
    tot = sum(counts) + miss
    valid = sum(counts)
    rows, cum = [], 0.0
    for i, (c, k) in enumerate(zip(cats, counts)):
        vp = 100.0 * k / valid
        cum += vp
        rows.append(["Valid" if i == 0 else None, c, str(k), f"{100.0 * k / tot:.1f}", f"{vp:.1f}", f"{cum:.1f}"])
    if miss:
        rows.append(["Missing", rng.choice([".", "System", "99"]), str(miss), f"{100.0 * miss / tot:.1f}", None, None])
    rows.append(["Total", None, str(tot), "100.0", None, None] if miss else ["Total", None, str(tot), "100.0", "100.0", None])
    hdr = [None, None, "Frequency", "Percent", "Valid Percent", "Cumulative Percent"]
    _table(d, rng, var, hdr, rows, 2)


def _ttest_stats(d, rng):
    vs = rng.sample(VARS, rng.randint(1, 4))
    rows = []
    for v in vs:
        n = rng.randint(8, 900)
        mu = rng.uniform(1, 300)
        sd = mu * rng.uniform(0.05, 0.5)
        rows.append([v, str(n), f"{mu:.2f}", f"{sd:.2f}", f"{sd / n ** 0.5:.2f}"])
    _table(d, rng, "One-Sample Statistics", [None, "N", "Mean", "Std. Deviation", "S.E. Mean"], rows, 1)
    if rng.random() < 0.6:
        tv = rng.choice([0, 50, 100])
        d.blank()
        rows2 = []
        for v, n, mu, sd, se in rows:
            t = (float(mu) - tv) / max(float(se), 0.01)
            md = float(mu) - tv
            rows2.append([v, f"{t:.2f}", str(int(n) - 1), f"{rng.uniform(0, 0.05) if abs(t) > 2 else rng.uniform(0.05, 1):.3f}",
                          f"{md:.2f}", f"{md - 1.96 * float(se):.2f}", f"{md + 1.96 * float(se):.2f}"])
        _table(d, rng, f"One-Sample Test (Test Value = {tv})", [None, "t", "df", "Sig. (2-tailed)", "Mean Difference",
                                                                "Lower", "Upper"], rows2, 1)


def generate(rng):
    d = Doc()
    makers = [_descriptives, _frequencies, _ttest_stats]
    picks = [rng.choice(makers) for _ in range(rng.randint(1, 3))]
    for i, f in enumerate(picks):
        if i:
            d.blank()
        f(d, rng)
    return d
