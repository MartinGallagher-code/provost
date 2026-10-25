"""`colima start` (and `colima status`): logrus TTY log lines,
`LEVEL[secs] message` with the message padded to 44 columns before any
`context=vm` field; status lines carry `key: value` messages. Non-TTY runs
use logfmt `time=... level=... msg=...` instead."""
from lib import Doc, fake

TOOL = "colima-start"


def generate(rng):
    d = Doc()
    tty = rng.random() < 0.75
    profile = rng.choice(["default", "default", "k8s", fake.word(rng), "x86"])
    runtime = rng.choice(["docker", "docker", "containerd", "incus"])
    vmtype = rng.choice(["qemu", "vz"])
    user = rng.choice(["alice", "bob", "dev", "mgallagher", "runner"])
    t = [0]
    stamp = f"{rng.randint(2023, 2026)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}T{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:"
    sec0 = rng.randint(0, 20)

    def log(level, msg, ctx=None, key=None, val=None):
        if tty:
            lv = {"info": "INFO", "warning": "WARN", "error": "ERRO", "fatal": "FATA"}[level]
            secs = f"[{t[0]:04d}]"
            body = msg
            cells = [lv, secs]
            if key is not None:
                cells += [key, val]
            else:
                cells.append(msg)
            text = f"{lv}{secs} {body}"
            if ctx:
                text = f"{lv}{secs} {body:<44} context={ctx}"
                cells += ["context", ctx]
            d.line(text, "row", cells)
        else:
            ts = stamp + f"{min(59, sec0 + t[0]):02d}Z"
            esc = msg.replace('"', '\\"')
            text = f'time="{ts}" level={level} msg="{esc}"'
            cells = ["time", ts, "level", level, "msg", esc]
            if ctx:
                text += f" context={ctx}"
                cells += ["context", ctx]
            d.line(text, "row", cells)
        t[0] += rng.choice([0, 0, 0, 1, 1, 2, 5])

    if rng.random() < 0.35:  # colima status
        if rng.random() < 0.15:
            log("fatal", "error retrieving current runtime: empty value")
            log("info", f"colima{'' if profile == 'default' else ' [profile=' + profile + ']'} is not running")
            return d
        log("info", f"colima{'' if profile == 'default' else ' [profile=' + profile + ']'} is running using "
            + ("macOS Virtualization.Framework" if vmtype == "vz" else "QEMU"))
        pairs = [("arch", rng.choice(["aarch64", "x86_64"])), ("runtime", runtime),
                 ("mountType", rng.choice(["sshfs", "virtiofs", "9p"]))]
        if rng.random() < .4:
            pairs.append(("address", fake.ip(rng)))
        pairs.append(("socket", f"unix:///Users/{user}/.colima/{profile}/{runtime}.sock"))
        if rng.random() < .3:
            pairs.append(("kubernetes", "enabled"))
        for k, v in pairs:
            log("info", f"{k}: {v}", key=k, val=v)
        return d

    log("info", "starting colima" + ("" if profile == "default" else f" [profile={profile}]"))
    log("info", f"runtime: {runtime}" + ("+k3s" if rng.random() < .2 else ""))
    if rng.random() < 0.3:
        log("warning", "dns: using DNS from host network", ctx="vm")
    log("info", "creating and starting ...", ctx="vm")
    if rng.random() < 0.3:
        log("info", "downloading disk image ...", ctx="vm")
    if rng.random() < 0.1:
        log("error", "error starting vm: error at 'starting': exit status 1", ctx="vm")
        return d
    if rng.random() < 0.4:
        log("info", "provisioning ...", ctx=runtime)
    log("info", "starting ...", ctx=runtime)
    if rng.random() < 0.3:
        log("info", "starting ...", ctx="kubernetes")
        log("info", "provisioning ...", ctx="kubernetes")
        log("info", "updating config ...", ctx="kubernetes")
        log("info", "Switched to context \"colima\".", ctx="kubernetes")
    log("info", "done")
    return d
