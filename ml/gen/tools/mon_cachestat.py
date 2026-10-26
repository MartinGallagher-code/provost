"""Page-cache hit statistics, `cachestat [-T] [interval]`: bcc's version
(right-aligned HITS MISSES DIRTIES HITRATIO BUFFERS_MB CACHED_MB, optional
TIME column) or the older perf-tools/ftrace one with its banner line."""
from lib import Doc

TOOL = "cachestat"


def generate(rng):
    d = Doc()
    flavour = rng.choice(["bcc", "bcc", "ftrace"])
    stamp = flavour == "bcc" and rng.random() < .4
    n = rng.randint(2, 25)
    step = rng.choice([1, 1, 2, 5])
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    buf = rng.randint(1, 900)
    cached = rng.randint(50, 60000)
    if flavour == "ftrace":
        d.skip(f"Counting cache functions... Output every {step} seconds.")
        hdr = ["HITS", "MISSES", "DIRTIES", "RATIO", "BUFFERS_MB", "CACHE_MB"]
        widths = [8, 8, 8, 8, 12, 10]
    else:
        hdr = ["HITS", "MISSES", "DIRTIES", "HITRATIO", "BUFFERS_MB", "CACHED_MB"]
        widths = [8, 8, 8, 8, 12, 10]
    if stamp:
        hdr = ["TIME"] + hdr
        widths = [8] + widths

    def render(cells):
        out = []
        for i, (c, w) in enumerate(zip(cells, widths)):
            out.append(c.ljust(w) if stamp and i == 0 else c.rjust(w))
        return " ".join(out).rstrip()

    d.line(render(hdr), "header", hdr)
    load = rng.choice([10, 1000, 100000])
    for i in range(n):
        hits = rng.randint(0, load)
        miss = rng.randint(0, load // rng.choice([1, 5, 50, 1000]) + 1)
        dirt = rng.randint(0, load // 20 + 1)
        ratio = 100.0 * hits / (hits + miss) if hits + miss else 0.0
        cached = max(0, cached + rng.randint(-20, 40))
        rs = f"{ratio:.2f}%" if flavour == "bcc" else f"{ratio:.1f}%"
        vals = [str(hits), str(miss), str(dirt), rs, str(buf), str(cached)]
        if stamp:
            t = h * 3600 + m * 60 + s + i * step
            vals = [f"{t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"] + vals
        d.line(render(vals), "row", vals)
    if flavour == "ftrace" and rng.random() < .5:
        d.line("^C", "skip")
        d.skip("Ending tracing...")
    return d
