"""e2fsprogs `filefrag -v FILE...`: filesystem type and file size lines, an
extent table with `a..b` ranges and colon-terminated columns, and an
`N extents found` footer per file. Without -v: one `path: N extents found`
line per file."""
from lib import Doc, fake

TOOL = "filefrag-v"

FSTYPES = ["ef53", "ef53", "ef53", "58465342", "9123683e", "2fc12fc1"]
FILES = ["/var/log/syslog", "/var/lib/mysql/ibdata1", "/home/{u}/Downloads/{w}.iso", "/srv/{w}/{w}.qcow2",
         "/var/lib/postgresql/16/main/base/16384/{n}", "/opt/{w}/data/{w}-{n}.db", "/tmp/{w}.tar.gz",
         "/home/{u}/.cache/{w}/index", "/var/cache/apt/archives/{w}_{n}_amd64.deb", "/boot/initrd.img-6.1.0-{n}-amd64"]


def _file(rng):
    return rng.choice(FILES).format(u=fake.user(rng), w=fake.word(rng), n=rng.randint(1, 99999))


def generate(rng):
    d = Doc()
    files = [_file(rng) for _ in range(rng.choice([1, 1, 1, 2, 3]))]
    if rng.random() < .2:
        for f in files + [_file(rng) for _ in range(rng.randint(1, 6))]:
            n = rng.choice([1, 1, 2, 3, rng.randint(4, 3000)])
            msg = f"{n} extent{'s' if n != 1 else ''} found"
            d.line(f"{f}: {msg}", "kv", [f, msg])
        return d
    bs = rng.choice([4096, 4096, 4096, 1024])
    for f in files:
        d.kv("Filesystem type is", rng.choice(FSTYPES))
        blocks = rng.choice([rng.randint(1, 64), rng.randint(64, 4096), rng.randint(4096, 2000000)])
        size = blocks * bs - rng.randint(0, bs - 1)
        val = f"{size} ({blocks} block{'s' if blocks != 1 else ''} of {bs} bytes)"
        d.line(f"File size of {f} is {val}", "kv", [f"File size of {f}", val])
        hdr = ["ext", "logical_offset", "physical_offset", "length", "expected", "flags"]
        d.line(" ext:     logical_offset:        physical_offset: length:   expected: flags:", "header", hdr)
        n = rng.choice([1, 1, 2, 3, rng.randint(4, 12)])
        cuts = sorted(rng.sample(range(1, blocks), min(n - 1, blocks - 1))) if blocks > 1 else []
        bounds = [0] + cuts + [blocks]
        phys = rng.randint(30000, 90000000)
        prev_end = None
        for i in range(len(bounds) - 1):
            lo, hi = bounds[i], bounds[i + 1] - 1
            ln = hi - lo + 1
            if prev_end is not None:
                phys = rng.randint(30000, 90000000) if rng.random() < .8 else prev_end + 1
            exp = str(prev_end + 1) if prev_end is not None and phys != prev_end + 1 else ""
            last = i == len(bounds) - 2
            flags = []
            if rng.random() < .1:
                flags.append("unwritten")
            if last:
                flags += ["last", "eof"]
            if rng.random() < .05 and not last:
                flags.append("shared")
            fl = ",".join(flags)
            lr = f"{lo:8d}..{hi:8d}".strip()
            pr = f"{phys:10d}..{phys + ln - 1:10d}".strip()
            text = f"{i:4d}: {lo:8d}..{hi:8d}: {phys:10d}..{phys + ln - 1:10d}: {ln:6d}: {exp:>10} {fl}".rstrip()
            if not exp and fl:
                text = f"{i:4d}: {lo:8d}..{hi:8d}: {phys:10d}..{phys + ln - 1:10d}: {ln:6d}:            {fl}"
            elif not exp and not fl:
                text = f"{i:4d}: {lo:8d}..{hi:8d}: {phys:10d}..{phys + ln - 1:10d}: {ln:6d}:"
            d.line(text, "row", [str(i), lr, pr, str(ln), exp or None, fl or None])
            prev_end = phys + ln - 1
        ne = len(bounds) - 1
        msg = f"{ne} extent{'s' if ne != 1 else ''} found"
        if rng.random() < .15:
            msg += f", perfection would be {max(1, ne // 3)} extent{'s' if max(1, ne // 3) != 1 else ''}"
        d.line(f"{f}: {msg}", "kv", [f, msg])
    return d
