"""Slurm `sshare -a` (and `-l`): fair-share tree as a fixed-width table with a
dashed rule; account rows are indented by depth and leave User blank."""
from lib import Doc, fake

TOOL = "sshare"

ACCOUNTS = ("physics chemistry biology astro climate genomics cfd materials ml-research "
            "engineering neuro hep geo math statistics bioinfo").split()


def _fmt_usage(rng, total):
    return str(rng.randint(0, max(1, total)))


def generate(rng):
    d = Doc()
    long = rng.random() < 0.35
    tres = long and rng.random() < 0.6
    cols = [("Account", 20, "l"), ("User", 10, "r"), ("RawShares", 10, "r"), ("NormShares", 11, "r"),
            ("RawUsage", 11, "r")]
    if long:
        cols.append(("NormUsage", 11, "r"))
    cols += [("EffectvUsage", 13, "r"), ("FairShare", 10, "r")]
    if long:
        cols.append(("LevelFS", 10, "r"))
    if tres:
        cols += [("GrpTRESMins", 30, "l"), ("TRESRunMins", 30, "l")]
    names = [c[0] for c in cols]

    def render(vals):
        out = []
        for (name, w, al), v in zip(cols, vals):
            v = v or ""
            out.append(v.ljust(w) if al == "l" else v.rjust(w))
        return " ".join(out)

    d.line(render(names) + " ", "header", names)
    d.skip(" ".join("-" * w for _, w, _ in cols) + " ")

    total = rng.randint(10 ** 6, 10 ** 10)
    rows = []

    def account_row(name, depth, shares, norm, usage, eff):
        r = {"Account": " " * depth + name, "User": None, "RawShares": shares,
             "NormShares": f"{norm:.6f}", "RawUsage": str(usage), "EffectvUsage": f"{eff:.6f}"}
        if long:
            r["NormUsage"] = f"{eff:.6f}"
        if rng.random() < 0.4:
            r["FairShare"] = None
        else:
            r["FairShare"] = f"{rng.uniform(0, 1):.6f}"
        if long:
            r["LevelFS"] = rng.choice([f"{rng.uniform(0.1, 20):.6f}", "inf", f"{rng.uniform(0.5, 2):.6f}"])
        return r

    def user_row(acct, user, depth):
        usage = rng.randint(0, total // 20)
        eff = usage / total
        r = {"Account": " " * depth + acct, "User": user, "RawShares": rng.choice(["1", "1", "parent", str(rng.randint(1, 100))]),
             "NormShares": f"{rng.uniform(0, 0.2):.6f}", "RawUsage": str(usage), "EffectvUsage": f"{eff:.6f}",
             "FairShare": f"{rng.uniform(0, 1):.6f}"}
        if long:
            r["NormUsage"] = f"{eff:.6f}"
            r["LevelFS"] = rng.choice([f"{rng.uniform(0.1, 50):.6f}", "inf"])
        return r

    rows.append(account_row("root", 0, None, 0.0, total, 1.0))
    if rng.random() < 0.7:
        rows.append(user_row("root", "root", 1))
    for acct in rng.sample(ACCOUNTS, rng.randint(1, 5)):
        shares = str(rng.randint(1, 1000))
        rows.append(account_row(acct, 1, shares, rng.uniform(0, 0.5), rng.randint(0, total // 3), rng.uniform(0, 0.5)))
        sub = None
        if rng.random() < 0.3:
            sub = acct[:6] + "-" + rng.choice(["gpu", "lab", "proj", "ext"])
        for user in rng.sample(fake.USERS[:8] + ["jsmith", "mkhan", "lwei", "tnguyen", "a.rossi"], rng.randint(0, 4)):
            rows.append(user_row(acct, user, 2))
        if sub:
            rows.append(account_row(sub, 2, str(rng.randint(1, 100)), rng.uniform(0, 0.1), rng.randint(0, total // 10), rng.uniform(0, 0.1)))
            for user in rng.sample(["alice", "bob", "zoe", "kim", "omar"], rng.randint(1, 3)):
                rows.append(user_row(sub, user, 3))
    for r in rows:
        if tres:
            r["GrpTRESMins"] = rng.choice([None, None, f"cpu={rng.randint(1000, 9999999)}"])
            r["TRESRunMins"] = (f"cpu={rng.randint(0, 99999)},mem={rng.randint(0, 9999999)},energy=0,"
                                f"node={rng.randint(0, 99)},billing={rng.randint(0, 99999)}")
            if len(r["TRESRunMins"]) > 30:   # sshare truncates a too-wide field and marks it with +
                r["TRESRunMins"] = r["TRESRunMins"][:29] + "+"
        vals = [r.get(n) for n in names]
        text = render(vals) + " "
        cells = [v.strip() if v else None for v in vals]
        d.line(text, "row", cells)
    return d
