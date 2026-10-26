"""Fleet (osquery manager) `fleetctl get hosts|labels|packs`: tablewriter
pipe tables with `+---+` rules, centred upper-case headers and left-aligned
cells (empty cells stay blank)."""
from lib import Doc, fake

TOOL = "fleetctl"


def hosts(rng):
    hdr = ["UUID", "HOSTNAME", "PLATFORM", "OSQUERY", "STATUS"]
    rows = []
    for _ in range(rng.randint(1, 12)):
        u = fake.uuid(rng).upper() if rng.random() < .7 else rng.choice(["4C4C4544-00", "EC2"]) + fake.uuid(rng).upper()[11:]
        rows.append([u, fake.host(rng).split(".")[0] if rng.random() < .6 else fake.host(rng),
                     rng.choice(["ubuntu", "rhel", "darwin", "windows", "debian", "amzn", "centos", "chrome"]),
                     rng.choice(["5.10.2", "5.11.0", "5.9.1", "4.9.0", "5.12.1"]),
                     rng.choice(["online", "online", "online", "offline", "mia", "new"])])
    return hdr, rows


def labels(rng):
    hdr = ["ID", "NAME", "DESCRIPTION", "QUERY"]
    base = [("All Hosts", "All hosts which have enrolled in Fleet", "SELECT 1;"),
            ("macOS", "All macOS hosts", "SELECT 1 FROM os_version WHERE platform = 'darwin';"),
            ("Ubuntu Linux", "All Ubuntu hosts", "SELECT 1 FROM os_version WHERE platform = 'ubuntu';"),
            ("CentOS Linux", "All CentOS hosts", "SELECT 1 FROM os_version WHERE platform = 'centos' OR name LIKE '%centos%'"),
            ("MS Windows", "All Windows hosts", "SELECT 1 FROM os_version WHERE platform = 'windows';"),
            ("Red Hat Linux", "All Red Hat Enterprise Linux hosts", "SELECT 1 FROM os_version WHERE name LIKE '%red hat%'"),
            ("All Linux", "All Linux distributions", "SELECT 1 FROM osquery_info WHERE build_platform LIKE '%ubuntu%' OR build_distro LIKE '%centos%';"),
            ("SELinux enforcing", "", "SELECT 1 FROM selinux_settings WHERE key = 'enforce' AND value = '1';"),
            ("Disk encryption off", "Hosts without FileVault or LUKS", "SELECT 1 FROM disk_encryption WHERE encrypted = 0;"),
            ("sshd root login", "PermitRootLogin yes", "SELECT 1 FROM augeas WHERE path = '/etc/ssh/sshd_config' AND label = 'PermitRootLogin' AND value = 'yes';")]
    pick = base[:rng.randint(2, 7)] + rng.sample(base[7:], rng.randint(0, 3))
    return hdr, [[str(i), n, desc, q] for i, (n, desc, q) in enumerate(pick, 1)]


def packs(rng):
    hdr = ["NAME", "PLATFORM", "DESCRIPTION", "DISABLED"]
    names = [("incident-response", "", "Useful for incident response investigations"),
             ("ossec-rootkit", "linux,darwin", "Rootkit detection checks"),
             ("osquery-monitoring", "", "Monitor osquery itself"),
             ("hardware-monitoring", "linux", "USB devices, PCI devices and TPM state"),
             ("it-compliance", "darwin", "IT compliance queries"),
             ("vuln-management", "", "Installed packages for vulnerability tracking"),
             ("unwanted-chrome-extensions", "", ""),
             ("windows-hardening", "windows", "Windows security baseline")]
    return hdr, [[n, p, ds, rng.choice(["false", "false", "true"])] for n, p, ds in rng.sample(names, rng.randint(1, 7))]


def generate(rng):
    d = Doc()
    hdr, rows = rng.choice([hosts, hosts, labels, packs])(rng)
    n = len(hdr)
    w = [max(len(x) for x in [hdr[c]] + [r[c] for r in rows]) + 2 for c in range(n)]
    rule = "+" + "+".join("-" * x for x in w) + "+"
    d.skip(rule)
    d.line("|" + "|".join(hdr[c].center(w[c]) for c in range(n)) + "|", "header", hdr)
    d.skip(rule)
    for r in rows:
        d.line("|" + "|".join((" " + r[c]).ljust(w[c]) for c in range(n)) + "|", "row", [v or None for v in r])
    d.skip(rule)
    return d
