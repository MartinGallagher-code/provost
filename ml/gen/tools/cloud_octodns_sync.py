"""octoDNS `octodns-sync`: fixed-layout log lines (timestamp, [thread], level,
logger, method: message) followed by a starred plan block per zone and provider."""
from lib import Doc, fake

TOOL = "octodns-sync"


def generate(rng):
    d = Doc()
    tid = str(rng.randint(100000000000, 140737488355327))
    y, mo, dd = rng.randint(2021, 2026), rng.randint(1, 12), rng.randint(1, 28)
    h, m, s = rng.randint(0, 23), rng.randint(0, 50), rng.randint(0, 50)
    ver = f"{rng.randint(0, 1)}.{rng.randint(0, 9)}.{rng.randint(0, 9)}"
    zones = [f"{fake.word(rng)}.{rng.choice(['com', 'org', 'io', 'net'])}." for _ in range(rng.randint(1, 3))]
    src = rng.choice(["config", "yaml", "zones"])
    tgt = rng.choice(["route53", "cloudflare", "ns1", "powerdns", "gcore", "azure"])
    tcls = {"route53": "Route53Provider", "cloudflare": "CloudflareProvider", "ns1": "Ns1Provider",
            "powerdns": "PowerDnsProvider", "gcore": "GCoreProvider", "azure": "AzureProvider"}[tgt]
    tick = [s]

    def log(logger, method, msg, level="INFO", cells=None):
        tick[0] += rng.choice([0, 0, 0, 1])
        ts = f"{y}-{mo:02d}-{dd:02d}T{h:02d}:{m + tick[0] // 60:02d}:{tick[0] % 60:02d}"
        if isinstance(msg, str):
            body = msg
            cells = cells or [msg]
        else:  # list of (key, value) pairs joined by ', '
            body = ", ".join(f"{k}={v}" for k, v in msg)
            cells = [x for kv in msg for x in kv]
        if method:
            text = f"{ts}  [{tid}] {level.ljust(5)} {logger} {method}: {body}"
            d.line(text, "row", [ts, tid, level, logger, method] + cells)
        else:
            text = f"{ts}  [{tid}] {level.ljust(5)} {logger} {body}"
            d.line(text, "row", [ts, tid, level, logger] + cells)

    cfg = rng.choice(["config/production.yaml", "./config.yaml", "octodns/" + fake.word(rng) + ".yaml"])
    log("Manager", "__init__", f"config_file={cfg} (octoDNS {ver})", cells=["config_file", cfg, f"(octoDNS {ver})"])
    log("Manager", "_config_executor", [("max_workers", str(rng.choice([1, 1, 4, 8])))])
    if rng.random() < .6:
        log("Manager", "_config_include_meta", [("include_meta", rng.choice(["False", "True"]))])
    log("Manager", "__init__", f"provider={src} (octodns.provider.yaml {ver})", cells=["provider", src, f"(octodns.provider.yaml {ver})"])
    pv = fake.version(rng)
    log("Manager", "__init__", f"provider={tgt} (octodns_{tgt} {pv})", cells=["provider", tgt, f"(octodns_{tgt} {pv})"])
    dry = rng.random() < .75
    log("Manager", "sync", [("eligible_zones", "[]"), ("eligible_targets", "[]"), ("dry_run", str(dry)),
                            ("force", "False"), ("plan_output_fh", "<stdout>")])
    plans = []
    for z in zones:
        log("Manager", "sync", f"  zone={z}", cells=["zone", z])
        log("Manager", "sync", f"  sources=['{src}'] -> targets=['{tgt}']", cells=["sources", f"['{src}']", "targets", f"['{tgt}']"])
        nrec = rng.randint(2, 40)
        log(f"YamlProvider[{src}]", "populate", f"  found {nrec} records, exists=False", cells=[f"found {nrec} records", "exists", "False"])
        log(f"{tcls}[{tgt}]", "plan", f"desired={z}", cells=["desired", z])
        if rng.random() < .3:
            log(f"{tcls}[{tgt}]", "plan", "No changes")
            continue
        changes = []
        for _ in range(rng.randint(1, 5)):
            verb = rng.choice(["Create", "Create", "Delete"])
            typ = rng.choice(["A", "AAAA", "CNAME", "TXT"])
            cls = {"A": "ARecord", "AAAA": "AaaaRecord", "CNAME": "CnameRecord", "TXT": "TxtRecord"}[typ]
            fq = f"{rng.choice(['www', 'api', 'mail', fake.word(rng)])}.{z}"
            val = {"A": f"['{fake.ip(rng)}']", "AAAA": f"['{fake.ip(rng, v6=True)}']",
                   "CNAME": f"{fake.word(rng)}.example.net.", "TXT": f"['v=spf1 include:{fake.word(rng)}.com -all']"}[typ]
            changes.append((verb, cls, typ, str(rng.choice([60, 300, 3600])), fq, val))
        cr = sum(1 for c in changes if c[0] == "Create")
        de = len(changes) - cr
        summ = [("Creates", str(cr)), ("Updates", "0"), ("Deletes", str(de)), ("Existing Records", str(nrec))]
        log(f"{tcls}[{tgt}]", "plan", [("  Creates", str(cr)), ("Updates", "0"), ("Deletes", str(de)),
                                       ("Existing Records", str(nrec))])
        plans.append((z, changes, summ))
    if plans:
        tick[0] += 1
        ts = f"{y}-{mo:02d}-{dd:02d}T{h:02d}:{m + tick[0] // 60:02d}:{tick[0] % 60:02d}"
        d.line(f"{ts}  [{tid}] INFO  Plan", "row", [ts, tid, "INFO", "Plan"])
        star = "*" * 80
        for z, changes, summ in plans:
            d.skip(star)
            d.line(f"* {z}", "section", [z])
            d.skip(star)
            d.line(f"* {tgt} ({tcls})", "section", [f"{tgt} ({tcls})"])
            for verb, cls, typ, ttl, fq, val in changes:
                text = f"*   {verb} <{cls} {typ} {ttl}, {fq}, {val}> ({src})"
                d.line(text, "row", [verb, cls, typ, ttl, fq, val, src])
            text = "*   Summary: " + ", ".join(f"{k}={v}" for k, v in summ)
            d.line(text, "row", ["Summary"] + [x for kv in summ for x in kv])
        d.skip(star)
    if not dry:
        log("Manager", "sync", f"  {sum(len(p[1]) for p in plans)} total changes")
    return d
