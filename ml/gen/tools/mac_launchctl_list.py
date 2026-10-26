"""macOS `launchctl list`: a tab-separated PID / Status / Label table with `-`
for jobs that aren't running."""
from lib import Doc, fake

TOOL = "launchctl-list"

APPLE = ["SafariHistoryServiceAgent", "Finder", "Dock.agent", "cloudphotod", "bird", "cfprefsd.xpc.agent",
         "coreservices.uiagent", "trustd.agent", "mdworker.shared", "sharingd", "nsurlsessiond",
         "WindowServer", "AirPlayUIAgent", "photoanalysisd", "knowledge-agent", "Spotlight",
         "ContextStoreAgent", "notificationcenterui.agent", "universalaccessd", "tccd", "lsd",
         "assistantd", "siriknowledged", "CallHistoryPluginHelper", "UserEventAgent-Aqua", "passd"]
OTHER = ["com.openssh.ssh-agent", "com.docker.helper", "org.mozilla.firefox.ShipIt", "com.google.keystone.agent",
         "homebrew.mxcl.postgresql@16", "com.microsoft.update.agent", "us.zoom.updater",
         "com.dropbox.DropboxMacUpdate.agent", "io.tailscale.ipn.macsys.login-item-helper"]


def generate(rng):
    d = Doc()
    d.line("PID\tStatus\tLabel", "header", ["PID", "Status", "Label"])
    for _ in range(rng.randint(3, 30)):
        r = rng.random()
        if r < .55:
            label = "com.apple." + rng.choice(APPLE)
        elif r < .8:
            label = rng.choice(OTHER)
        elif r < .9:
            label = f"application.com.apple.{rng.choice(['Terminal', 'Safari', 'Preview', 'TextEdit'])}.{rng.randint(1000000, 99999999)}.{rng.randint(1000000, 99999999)}"
        else:
            label = f"0x{fake.hexid(rng, 12)}.anonymous.{rng.choice(['zsh', 'bash', 'Code Helper', 'login'])}"
        running = rng.random() < .45
        pid = str(rng.randint(90, 99999)) if running else "-"
        status = "0" if rng.random() < .8 else str(rng.choice([-9, -15, 1, 78, 127, -6, 2]))
        d.line(f"{pid}\t{status}\t{label}", "row", [pid, status, label])
    return d
