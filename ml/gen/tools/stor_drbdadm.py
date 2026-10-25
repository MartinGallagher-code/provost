"""DRBD 9 `drbdadm status [--verbose --statistics]`: per resource an
indented tree (resource, local volumes, peer connections, peer volumes)
whose lines are runs of `key:value` pairs, resources separated by blanks."""
from lib import Doc, fake

TOOL = "drbdadm-status"


def _pairs(d, indent, lead, pairs):
    """lead: a bare name before the pairs, or None."""
    text = indent + ((lead + " ") if lead else "") + " ".join(f"{k}:{v}" for k, v in pairs)
    cells = ([lead] if lead else []) + [x for kv in pairs for x in kv]
    if not lead and len(pairs) == 1:
        d.line(text, "kv", cells)
    else:
        d.line(text, "row", cells)


def generate(rng):
    d = Doc()
    verbose = rng.random() < .35
    peers_all = [f"{rng.choice(['node', 'drbd', 'pve', 'storage', 'ha'])}-{c}" for c in "abc"] + [fake.host(rng).split(".")[0]]
    nres = rng.randint(1, 4)
    for r in range(nres):
        res = rng.choice(["r", "res", "vm-", "pvc-", "data", "mysql", "nfs"]) + str(r) if rng.random() < .7 else fake.word(rng) + str(r)
        if res.startswith("pvc-"):
            res = "pvc-" + fake.uuid(rng)
        role = rng.choice(["Primary", "Secondary", "Secondary"])
        lead = [("role", role)]
        if verbose:
            lead = [("node-id", str(rng.randint(0, 3)))] + lead + [("suspended", rng.choice(["no", "no", "user"]))]
            if rng.random() < .5:
                lead.append(("force-io-failures", "no"))
        elif rng.random() < .1:
            lead.append(("suspended", "user"))
        _pairs(d, "", res, lead)
        nvol = rng.choice([1, 1, 1, 2])
        for v in range(nvol):
            disk = rng.choice(["UpToDate"] * 6 + ["Inconsistent", "Outdated", "Diskless", "Attaching", "Negotiating"])
            pairs = [("disk", disk)]
            if verbose:
                pairs = [("volume", str(v)), ("minor", str(1000 + r * 2 + v))] + pairs + [("backing_dev", rng.choice(["/dev/vg0/" + res + f"_{v:05d}", "/dev/sdb1", "/dev/zvol/tank/" + res, "none"]))]
                pairs += [("quorum", rng.choice(["yes", "no"])), ("blocked", rng.choice(["no", "no", "upper"]))]
                d_line = pairs
                _pairs(d, "  ", None, d_line)
                stats = [("size", str(rng.randint(10, 999) * 1024 * 1024)), ("read", str(rng.randint(0, 9 ** 9))),
                         ("written", str(rng.randint(0, 9 ** 9))), ("al-writes", str(rng.randint(0, 99999))),
                         ("bm-writes", str(rng.randint(0, 999))), ("upper-pending", "0"), ("lower-pending", "0")]
                if rng.random() < .5:
                    stats += [("al-suspended", "no")]
                _pairs(d, "      ", None, stats)
            elif nvol > 1:
                _pairs(d, "  ", None, [("volume", str(v))] + pairs)
            else:
                if rng.random() < .15:
                    pairs.append(("open", rng.choice(["yes", "no"])))
                _pairs(d, "  ", None, pairs)
        for peer in rng.sample(peers_all, rng.randint(1, 2)):
            conn = rng.choice([None] * 6 + ["Connecting", "StandAlone", "NetworkFailure"])
            prole = rng.choice(["Secondary", "Primary"] if role == "Secondary" else ["Secondary"])
            pp = [("connection", conn)] if conn else [("role", prole)]
            if verbose and not conn:
                pp = [("node-id", str(rng.randint(0, 3))), ("connection", "Connected")] + pp + [("congested", "no"), ("ap-in-flight", "0"), ("rs-in-flight", "0")]
            _pairs(d, "  ", peer, pp)
            if conn:
                continue
            for v in range(nvol):
                repl = rng.choice(["Established"] * 5 + ["SyncSource", "SyncTarget", "PausedSyncS", "Off"])
                pd = rng.choice(["UpToDate"] * 5 + ["Inconsistent", "Outdated", "Diskless"])
                pairs = []
                if nvol > 1 or verbose:
                    pairs.append(("volume", str(v)))
                if verbose or repl != "Established":
                    pairs.append(("replication", repl))
                pairs.append(("peer-disk", pd))
                if repl.startswith("Sync"):
                    pairs.append(("done", f"{rng.uniform(0, 99.99):.2f}"))
                if verbose:
                    pairs += [("resync-suspended", rng.choice(["no", "no", "user", "dependency"]))]
                if rng.random() < .1:
                    pairs.append(("peer-client", "yes"))
                _pairs(d, "    ", None, pairs)
                if verbose:
                    _pairs(d, "        ", None, [("received", str(rng.randint(0, 9 ** 9))), ("sent", str(rng.randint(0, 9 ** 9))),
                                                  ("out-of-sync", str(rng.choice([0, 0, rng.randint(1, 99999)]))),
                                                  ("pending", "0"), ("unacked", "0")])
        d.blank()
    return d
