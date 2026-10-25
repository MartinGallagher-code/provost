"""Carvel `kapp ls [-A]`: a target-cluster banner, an `Apps in ...` heading,
a padded table (cells carry trailing spaces), a legend of column
abbreviations, a count footer and `Succeeded`."""
from lib import Doc, fake

TOOL = "kapp-ls"


def generate(rng):
    d = Doc()
    url = rng.choice(["https://127.0.0.1:6443", f"https://127.0.0.1:{rng.randint(30000, 65000)}",
                      f"https://{fake.ip(rng)}:6443", f"https://{fake.hexid(rng, 32).upper()}.gr7.us-east-1.eks.amazonaws.com"])
    node = rng.choice(["kind-control-plane", "minikube", f"ip-10-0-{rng.randint(0, 255)}-{rng.randint(1, 254)}.ec2.internal",
                       f"gke-{fake.word(rng)}-default-pool-{fake.hexid(rng, 8)}-{fake.token(rng, 4)}"])
    more = rng.random() < .5
    nodes = f"(nodes: {node}" + (f", {rng.randint(1, 30)}+)" if more else ")")
    d.line(f"Target cluster '{url}' {nodes}", "kv", ["Target cluster", f"'{url}'", nodes])
    d.blank()
    all_ns = rng.random() < 0.35
    ns = rng.choice(["default", "kapp-controller", "apps", fake.word(rng)])
    d.section("Apps in all namespaces" if all_ns else f"Apps in namespace '{ns}'")
    d.blank()
    n = rng.randint(0, 8)
    rows = []
    for _ in range(n):
        name = rng.choice([fake.name(rng), "simple-app", "kc", "cert-manager", fake.word(rng) + ".app",
                           f"{fake.word(rng)}-ctrl", "contour", "pkg-" + fake.word(rng) + "-" + fake.hexid(rng, 6)])
        nss = rng.choice(["default", "(cluster)", "(cluster),kapp-controller", f"{fake.word(rng)}", "default,kube-system",
                          f"(cluster),{fake.word(rng)},{fake.word(rng)}", "-"])
        lcs = rng.choice(["true", "true", "true", "false", "-"])
        lca = "-" if lcs == "-" else rng.choice(
            [f"{rng.randint(1, 59)}s", f"{rng.randint(1, 59)}m", f"{rng.randint(1, 23)}h", f"{rng.randint(1, 300)}d"])
        row = ([rng.choice(["default", ns, "kapp-controller", fake.word(rng)])] if all_ns else []) + [name, nss, lcs, lca]
        rows.append(row)
    header = (["Namespace"] if all_ns else []) + ["Name", "Namespaces", "Lcs", "Lca"]
    if rows:
        w = [max(len(x) for x in [header[c]] + [r[c] for r in rows]) for c in range(len(header))]
        render = lambda cells: "".join(v.ljust(w[c]) + "  " for c, v in enumerate(cells))  # noqa: E731
        d.line(render(header), "header", header)
        for r in rows:
            d.line(render(r), "row", r)
        d.blank()
    d.kv("Lcs", "Last Change Successful")
    d.kv("Lca", "Last Change Age")
    d.blank()
    d.skip(f"{n} apps")
    d.blank()
    d.skip("Succeeded")
    return d
