"""openSUSE `snapper list` / `snapper list-configs`: a pipe-separated table
with a `---+---` rule (ASCII or box-drawing), right-aligned numbers and
plenty of empty cells."""
import datetime

from lib import Doc, fake

TOOL = "snapper-list"

DESCS = ["first root filesystem", "zypp(zypper)", "zypp(packagekitd)", "timeline", "boot",
         "before update", "after install of nginx", "yast sw_single", "rollback backup of #12",
         "writable copy of #7", "", "", "kernel-default 6.4.0-150600"]


def _render(cells, widths, right, bar):
    out = []
    for i, (c, w) in enumerate(zip(cells, widths)):
        c = c or ""
        out.append(" " + (c.rjust(w) if i in right else c.ljust(w)) + " ")
    return bar.join(out)[1:].rstrip()


def _emit(d, header, rows, right, uni):
    bar = "│" if uni else "|"
    widths = [max(len(r[i] or "") for r in [header] + rows) for i in range(len(header))]
    d.line(_render(header, widths, right, bar), "header", header)
    if uni:
        d.skip("┼".join("─" * (w + 2) for w in widths)[1:])
    else:
        d.skip("+".join("-" * (w + 2) for w in widths)[1:])
    for r in rows:
        d.line(_render(r, widths, right, bar), "row", [c if c else None for c in r])


def _date(t, style, tz):
    if style == "iso":
        return t.strftime("%Y-%m-%d %H:%M:%S")
    if style == "12h":
        return t.strftime("%a %d %b %Y %I:%M:%S %p ") + tz
    return t.strftime("%a %b ") + f"{t.day:2d}" + t.strftime(" %H:%M:%S %Y")


def generate(rng):
    d = Doc()
    uni = rng.random() < .5
    if rng.random() < .2:
        rows = [["root", "/"]]
        for name, sub in rng.sample([("home", "/home"), ("srv", "/srv"), ("var", "/var"), ("data", "/data"),
                                     ("opt", "/opt"), ("docker", "/var/lib/docker")], rng.randint(0, 4)):
            rows.append([name, sub])
        _emit(d, ["Config", "Subvolume"], rows, (), uni)
        return d
    style = rng.choice(["iso", "12h", "12h", "c"])
    tz = rng.choice(["CET", "UTC", "CEST", "EST", "PDT"])
    t = datetime.datetime(rng.randint(2021, 2025), rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59))

    def when():
        nonlocal t
        t += datetime.timedelta(seconds=rng.choice([rng.randint(20, 400), rng.randint(3600, 86400 * 9)]))
        return _date(t, style, tz)
    used = rng.random() < .6
    header = ["#", "Type", "Pre #", "Date", "User"] + (["Used Space"] if used else []) + ["Cleanup", "Description", "Userdata"]
    right = {2} | ({5} if used else set())
    rows = [["0", "single", None, None, "root"] + ([None] if used else []) + [None, "current", None]]
    n = 0
    active = rng.randint(1, 3)
    for _ in range(rng.randint(2, 14)):
        n += rng.randint(1, 3)
        kind = rng.choice(["single", "pre", "pre", "single"])
        user = rng.choice(["root", "root", "root", fake.user(rng)])
        def sz():
            return f"{rng.uniform(1, 999):.2f} {rng.choice(['KiB', 'MiB', 'MiB', 'GiB'])}"
        mark = ""
        if n == active:
            mark = rng.choice(["*", "-", "+"])
        clean = rng.choice(["number", "number", "timeline", "", "important"])
        desc = rng.choice(DESCS)
        udata = rng.choice(["", "", "important=yes", "important=no", f"user={fake.user(rng)}"])
        rows.append([str(n) + mark, kind, None, when(), user] + ([sz()] if used else []) + [clean or None, desc or None, udata or None])
        if kind == "pre":
            pre = n
            n += 1
            rows.append([str(n), "post", str(pre), when(), user] + ([sz()] if used else []) + [clean or None, desc or None, udata or None])
    _emit(d, header, rows, right, uni)
    return d
