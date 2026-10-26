"""`microk8s status`: a running line, HA key/values, then an addons tree of
enabled/disabled lists, each addon padded to a column and followed by a
`# (repo) description` comment."""
from lib import Doc, fake

TOOL = "microk8s-status"

ADDONS = [("cert-manager", "core", "Cloud native certificate management"),
          ("cis-hardening", "core", "Apply CIS K8s hardening"),
          ("community", "core", "The community addons repository"),
          ("dashboard", "core", "The Kubernetes dashboard"),
          ("dns", "core", "CoreDNS"),
          ("gpu", "core", "Alias to nvidia add-on"),
          ("ha-cluster", "core", "Configure high availability on the current node"),
          ("helm", "core", "Helm - the package manager for Kubernetes"),
          ("helm3", "core", "Helm 3 - the package manager for Kubernetes"),
          ("host-access", "core", "Allow Pods connecting to Host services smoothly"),
          ("hostpath-storage", "core", "Storage class; allocates storage from host directory"),
          ("ingress", "core", "Ingress controller for external access"),
          ("kube-ovn", "core", "An advanced network fabric for Kubernetes"),
          ("mayastor", "core", "OpenEBS MayaStor"),
          ("metallb", "core", "Loadbalancer for your Kubernetes cluster"),
          ("metrics-server", "core", "K8s Metrics Server for API access to service metrics"),
          ("minio", "core", "MinIO object storage"),
          ("observability", "core", "A lightweight observability stack for logs, traces and metrics"),
          ("prometheus", "core", "Prometheus operator for monitoring and logging"),
          ("rbac", "core", "Role-Based Access Control for authorisation"),
          ("registry", "core", "Private image registry exposed on localhost:32000"),
          ("rook-ceph", "core", "Distributed Ceph storage using Rook"),
          ("storage", "core", "Alias to hostpath-storage add-on, deprecated"),
          ("argocd", "community", "Argo CD is a declarative continuous deployment for Kubernetes."),
          ("cilium", "community", "SDN, fast with full network policy"),
          ("istio", "community", "Core Istio service mesh services"),
          ("knative", "community", "Knative Serverless and Event Driven Applications"),
          ("linkerd", "community", "Linkerd is a service mesh for Kubernetes and other frameworks"),
          ("openebs", "community", "OpenEBS is the open-source storage solution for Kubernetes"),
          ("traefik", "community", "traefik Ingress controller")]


def generate(rng):
    d = Doc()
    if rng.random() < 0.1:
        d.line("microk8s is not running. Use microk8s inspect for a deeper inspection.", "kv",
               ["microk8s", "is not running. Use microk8s inspect for a deeper inspection."])
        return d.line("Hint: microk8s is not running, use microk8s start", "kv",
                      ["Hint", "microk8s is not running, use microk8s start"])
    old = rng.random() < 0.25
    d.line("microk8s is running", "kv", ["microk8s", "is running"])
    ha = rng.random() < 0.4
    d.kv("high-availability", "yes" if ha else "no")
    nodes = [f"{fake.ip(rng)}:19001" for _ in range(3 if ha else 1)] if rng.random() < .7 else ["127.0.0.1:19001"]
    d.kv("datastore master nodes", " ".join(nodes), indent="  ")
    standby = "none" if not ha or rng.random() < .5 else f"{fake.ip(rng)}:19001"
    d.kv("datastore standby nodes", standby, indent="  ")
    d.section("addons:")
    pool = [a for a in ADDONS if not old or a[1] == "core"]
    chosen = rng.sample(pool, rng.randint(6, len(pool)))
    en = sorted([a for a in chosen if rng.random() < .3 or a[0] in ("dns", "ha-cluster")])
    dis = sorted([a for a in chosen if a not in en])
    width = 20 if old else max(20, max(len(a[0]) for a in chosen) + 1)
    for title, group in (("enabled", en), ("disabled", dis)):
        if not group:
            continue
        d.section(f"  {title}:")
        for name, repo, desc in group:
            if old:
                d.line(f"    {name.ljust(width)} # {desc}", "row", [name, desc])
            else:
                d.line(f"    {name.ljust(width)} # ({repo}) {desc}", "row", [name, f"({repo})", desc])
    return d
