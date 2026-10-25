"""e2fsprogs `e4defrag -c DIR|FILE`: a fragmentation report: a ranked table
of the most fragmented files (long paths wrap their numbers onto the next
line), then tab-separated totals, a score legend and a verdict."""
from lib import Doc, fake

TOOL = "e4defrag-c"


def _path(rng, root):
    leaf = rng.choice([f"{fake.word(rng)}.log", f"{fake.hexid(rng, 40).upper()}", f"{fake.word(rng)}-{rng.randint(1, 999)}.db",
                       "system.journal", f"user-1000@{fake.hexid(rng, 32)}-{fake.hexid(rng, 16)}.journal~",
                       f"{fake.word(rng)}.sqlite", f"places.sqlite-wal", f"{fake.word(rng)}.qcow2", "ibdata1"])
    mids = rng.sample([".cache", "mozilla", "firefox", fake.hexid(rng, 8) + ".default-release", "cache2", "entries",
                       fake.word(rng), "journal", fake.hexid(rng, 32), "lib", "mysql", "images", "log"], rng.randint(0, 4))
    return "/".join([root.rstrip("/")] + mids + [leaf])


def generate(rng):
    d = Doc()
    target = rng.choice(["/home", "/var", "/", "/srv/" + fake.word(rng), "/home/" + fake.user(rng), "/var/lib/" + fake.word(rng)])
    single = rng.random() < .2
    if single:
        target = _path(rng, target)
    hdr = "<File>" if single else "<Fragmented files>"
    d.line(f"{hdr:<40}{'now':>10}/{'best':<10}{'size/ext':>9}", "header", [hdr, "now/best", "size/ext"])
    n = 1 if single else rng.randint(1, 5)
    tot_now = tot_best = 0
    for i in range(n):
        p = target if single else _path(rng, target)
        now = rng.choice([rng.randint(2, 20), rng.randint(20, 400), rng.randint(400, 9000)])
        best = max(1, now // rng.choice([1, 2, 5, 10, 50, now]))
        size = rng.choice([4, 4, 8, 12, 32, rng.randint(1, 5000)])
        nb = f"{now}/{best}"
        nums = f"{now:>8}/{best:<8}{size:>9} KB"
        lead = p if single else f"{i + 1}. {p}"
        if len(lead) > 37:
            d.line(lead, "row", [p, None, None])
            d.line(" " * 40 + nums, "cont", [nb, f"{size} KB"])
        else:
            d.line(f"{lead:<40}{nums}", "row", [p, nb, f"{size} KB"])
        tot_now += now
        tot_best += best
    files_extra = rng.randint(0, 50000)
    tot_now += files_extra
    tot_best += int(files_extra * rng.uniform(0.85, 1.0))
    d.blank()
    score = rng.choice([0, 0, 1, 2, rng.randint(3, 30), rng.randint(31, 55), rng.randint(56, 100)])
    d.line(f" Total/best extents\t\t\t\t{tot_now}/{tot_best}", "kv", ["Total/best extents", f"{tot_now}/{tot_best}"])
    avg = f"{rng.choice([rng.randint(4, 999), rng.randint(1000, 90000)])} KB"
    d.line(f" Average size per extent\t\t\t{avg}", "kv", ["Average size per extent", avg])
    d.line(f" Fragmentation score\t\t\t\t{score}", "kv", ["Fragmentation score", str(score)])
    d.skip(" [0-30 no problem: 31-55 a little bit fragmented: 56- needs defrag]")
    what = "This file" if single else "This directory"
    verdict = "does not need defragmentation." if score <= 55 else "needs defragmentation."
    d.skip(f" {what} ({target}) {verdict}")
    d.skip(" Done.")
    return d
