"""Gloo Edge `glooctl check`: progress lines `Checking <resource>... OK`
(or `N Errors!`), the odd klog throttling line interleaved, skip notices,
and a summary: `No problems detected.` or an `Error: N errors occurred:`
list of tab-indented `* ...` items."""
from lib import Doc, fake

TOOL = "glooctl-check"

OLD = ["deployments", "pods", "upstreams", "upstream groups", "auth configs", "rate limit configs",
       "VirtualHostOptions", "RouteOptions", "secrets", "virtual services", "gateways", "proxies"]
NEW = ["Deployments", "Pods", "Upstreams", "UpstreamGroups", "AuthConfigs", "RateLimitConfigs",
       "VirtualHostOptions", "RouteOptions", "Secrets", "VirtualServices", "Gateways", "Proxies"]


def generate(rng):
    d = Doc()
    new = rng.random() < 0.5
    names = list(NEW if new else OLD)
    if rng.random() < .3:
        names = names[:rng.randint(4, len(names))]
    ns = rng.choice(["gloo-system", "gloo-system", "gloo", fake.word(rng) + "-gw"])
    errs = []
    klog_at = rng.randrange(len(names)) if rng.random() < .35 else -1
    if new and rng.random() < .5:
        d.skip("Checking Gloo Edge in namespace " + ns + "...")
    for i, res in enumerate(names):
        if i == klog_at:
            mm, dd = rng.randint(1, 12), rng.randint(1, 28)
            stamp = f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}.{rng.randint(0, 999999):06d}"
            pid = str(rng.randint(1000, 99999))
            src = rng.choice(["request.go:668", "request.go:690", "request.go:697"])
            wait = f"{rng.uniform(1, 9):.6f}".rstrip("0")
            msg = (f"Waited for {wait}s due to client-side throttling, not priority and fairness, request: GET:"
                   f"https://{fake.ip(rng)}:443/apis/gateway.solo.io/v1/namespaces/{ns}/{res.lower().replace(' ', '')}?limit=500")
            d.line(f"I{mm:02d}{dd:02d} {stamp}   {pid} {src}] {msg}", "row", [f"I{mm:02d}{dd:02d}", stamp, pid, src, msg])
        bad = rng.random() < .1
        if bad:
            n = rng.randint(1, 3)
            res_word = "Error!" if n == 1 and new else "Errors!"
            d.line(f"Checking {res}... {n} {res_word}", "kv", [f"Checking {res}", f"{n} {res_word}"])
            for _ in range(n):
                errs.append(rng.choice([
                    f"Pod {fake.word(rng)}-{fake.hexid(rng, 10)}-{fake.token(rng, 5)} in namespace {ns} is not ready! "
                    f"Message: containers with unready status: [{fake.word(rng)}]",
                    f"Found rejected virtual service by '{ns}': default {fake.name(rng)} (Reason: 2 errors occurred:"
                    f"\t* domain conflict: other virtual services that belong to the same Gateway as {fake.word(rng)} "
                    f"have the same domain: [*])",
                    f"Found upstream with warnings by '{ns}': {ns} {fake.word(rng)}-{fake.word(rng)}-{rng.choice([80, 8080, 443])} "
                    f"(Reason: no endpoints found)",
                    f"Deployment {fake.word(rng)} in namespace {ns} is not available! Message: Deployment does not have "
                    f"minimum availability."]))
        else:
            d.line(f"Checking {res}... OK", "kv", [f"Checking {res}", "OK"])
    if new:
        d.skip("Skipping Gloo Instance check -- Gloo Federation not detected.")
        if rng.random() < .5:
            d.line("Checking Kubernetes Gateway Integration... OK", "kv", ["Checking Kubernetes Gateway Integration", "OK"])
    if not errs:
        d.skip("No problems detected.")
    else:
        d.skip(f"Error: {len(errs)} error{'s' if len(errs) > 1 else ''} occurred:")
        for e in errs:
            d.line(f"\t* {e}", "row", [e])
        d.blank()
    return d
