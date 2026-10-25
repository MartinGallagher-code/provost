"""`getfacl`: per-file `# file/owner/group` comment headers, then one ACL
entry per line (tag:qualifier:perms), optional `#effective:` annotations and
`default:` entries; files separated by blank lines."""
from lib import Doc, fake

TOOL = "getfacl"

GROUPS = "root wheel adm staff www-data docker sudo audit ssl-cert developers backup".split()


def perms(rng):
    return "".join(c if rng.random() < .6 else "-" for c in "rwx")


def entries(rng, prefix=""):
    out = [(prefix + "user", None, perms(rng))]
    named = []
    for _ in range(rng.choice([0, 0, 1, 1, 2, 3])):
        q = fake.user(rng) if rng.random() < .5 else str(rng.randint(1000, 60000))
        named.append((prefix + "user", q, perms(rng)))
    out += named
    out.append((prefix + "group", None, perms(rng)))
    gnamed = [(prefix + "group", rng.choice(GROUPS), perms(rng)) for _ in range(rng.choice([0, 1, 1, 2]))]
    out += gnamed
    if named or gnamed or rng.random() < .3:
        cls = [e[2] for e in named + gnamed] + [out[len(named) + 1][2]]
        union = "".join(c if any(x[k] != "-" for x in cls) else "-" for k, c in enumerate("rwx"))
        out.append((prefix + "mask", None, union if rng.random() < .7 else perms(rng)))
    out.append((prefix + "other", None, perms(rng)))
    return out


def masked(p, m):
    return "".join(a if a != "-" and b != "-" else "-" for a, b in zip(p, m))


def generate(rng):
    d = Doc()
    if rng.random() < .4:
        d.skip("getfacl: Removing leading '/' from absolute path names")
    numeric = rng.random() < .2
    omit = rng.random() < .15
    tabs = rng.random() < .5
    for i in range(rng.randint(1, 4)):
        if i:
            d.blank()
        path = fake.path(rng, root="").lstrip("/")
        if rng.random() < .4:
            path += rng.choice([".conf", ".log", ".key", ".pem", "/"]).rstrip("/")
        isdir = rng.random() < .4
        if not omit:
            d.line(f"# file: {path}", "kv", ["file", path])
            own = str(rng.randint(0, 1500)) if numeric else fake.user(rng)
            grp = str(rng.randint(0, 1500)) if numeric else rng.choice(GROUPS)
            d.line(f"# owner: {own}", "kv", ["owner", own])
            d.line(f"# group: {grp}", "kv", ["group", grp])
            if rng.random() < .15:
                fl = rng.choice(["-s-", "--t", "ss-", "s--"])
                d.line(f"# flags: {fl}", "kv", ["flags", fl])
        ents = entries(rng)
        if isdir and rng.random() < .6:
            ents += entries(rng, "default:")
        mask = {}
        for tag, q, p in ents:
            if tag.endswith("mask"):
                mask[tag.split(":")[0] if ":" in tag else ""] = p
        for tag, q, p in ents:
            text = f"{tag}:{q or ''}:{p}"
            cells = [tag, q, p]
            pre = "default" if tag.startswith("default:") else ""
            m = mask.get(pre)
            base = tag[len(pre) + 1:] if pre else tag
            if m and (q or base == "group"):
                eff = masked(p, m)
                if eff != p:
                    if tabs:
                        text = text + "\t" * max(1, (32 - len(text)) // 8 + 1) + f"#effective:{eff}"
                    else:
                        text = text + "  " + f"#effective:{eff}"
                    cells += ["effective", eff]
            d.line(text, "row", cells)
    if rng.random() < .5:
        d.blank()
    return d
