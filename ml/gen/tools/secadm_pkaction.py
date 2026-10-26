"""polkit `pkaction` (bare action-id list) or `pkaction --verbose`: per
action an `action.id:` heading and two-space-indented, padded `key: value`
lines (empty icon, `annotation: key -> value`)."""
from lib import Doc

TOOL = "pkaction"

ACTIONS = [("org.freedesktop.login1.reboot", "Reboot the system", "Authentication is required to reboot the system.",
            "The systemd Project", "https://systemd.io", ("auth_admin_keep", "auth_admin_keep", "yes")),
           ("org.freedesktop.login1.power-off", "Power off the system", "Authentication is required to power off the system.",
            "The systemd Project", "https://systemd.io", ("auth_admin_keep", "auth_admin_keep", "yes")),
           ("org.freedesktop.systemd1.manage-units", "Manage system services or other units",
            "Authentication is required to manage system services or other units.", "The systemd Project",
            "https://systemd.io", ("auth_admin", "auth_admin", "auth_admin_keep")),
           ("org.freedesktop.NetworkManager.settings.modify.system", "Modify network connections for all users",
            "System policy prevents modification of network settings for all users", "NetworkManager",
            "https://networkmanager.dev/", ("auth_admin_keep", "yes", "yes")),
           ("org.freedesktop.packagekit.package-install", "Install signed package",
            "Authentication is required to install a package", "The PackageKit Project",
            "http://www.freedesktop.org/software/PackageKit/", ("auth_admin", "auth_admin", "auth_admin_keep")),
           ("org.freedesktop.policykit.exec", "Run a program as another user",
            "Authentication is needed to run a program as another user", "The polkit project",
            "https://github.com/polkit-org/polkit/", ("auth_admin", "auth_admin", "auth_admin")),
           ("org.freedesktop.udisks2.filesystem-mount", "Mount a filesystem",
            "Authentication is required to mount the filesystem", "The Udisks Project",
            "https://github.com/storaged-project/udisks", ("auth_admin", "auth_admin", "yes")),
           ("org.freedesktop.timedate1.set-time", "Set system time", "Authentication is required to set the system time.",
            "The systemd Project", "https://systemd.io", ("auth_admin_keep", "auth_admin_keep", "auth_admin_keep")),
           ("org.fedoraproject.config.firewall.auth", "Firewall configuration",
            "System policy prevents changing the firewall configuration", "FirewallD", "https://firewalld.org",
            ("no", "no", "auth_admin_keep")),
           ("org.libvirt.unix.manage", "Manage local virtualized systems",
            "System policy prevents management of local virtualized systems", "Libvirt Project", "https://libvirt.org",
            ("auth_admin_keep", "auth_admin_keep", "auth_admin_keep")),
           ("com.ubuntu.pkexec.synaptic", "Run Synaptic Package Manager",
            "Authentication is required to run the Synaptic Package Manager", "Synaptic", "", ("auth_admin", "auth_admin", "auth_admin"))]


def generate(rng):
    d = Doc()
    acts = rng.sample(ACTIONS, rng.randint(1, 6))
    if rng.random() < .3:
        for a in sorted(set(acts + rng.sample(ACTIONS, rng.randint(1, 4)))):
            d.line(a[0], "row", [a[0]])
        return d
    for aid, desc, msg, vendor, url, imp in acts:
        d.section(f"{aid}:", aid)
        pairs = [("description", desc), ("message", msg), ("vendor", vendor), ("vendor_url", url),
                 ("icon", "" if rng.random() < .8 else "system-reboot"),
                 ("implicit any", imp[0]), ("implicit inactive", imp[1]), ("implicit active", imp[2])]
        for k, v in pairs:
            text = f"  {(k + ':'):<19}{v}"
            d.line(text, "kv", [k, v] if v else [k])
        if aid.endswith(("reboot", "power-off")):
            other = aid + "-multiple-sessions"
            d.line(f"  {'annotation:':<19}org.freedesktop.policykit.imply -> {other}", "kv",
                   ["annotation", "org.freedesktop.policykit.imply", other])
        elif aid == "org.freedesktop.policykit.exec" or rng.random() < .15:
            d.line(f"  {'annotation:':<19}org.freedesktop.policykit.exec.path -> /usr/bin/pkexec", "kv",
                   ["annotation", "org.freedesktop.policykit.exec.path", "/usr/bin/pkexec"])
        d.blank()
    return d
