"""macOS `log show` (default style): filter/notice prose, an aligned header
whose message column has no name, one event per line (process split from the
message), a rule and per-type counter footer lines."""
from lib import Doc, fake

TOOL = "log-show"

PROCS = {
    "kernel": ["(AppleACPIPlatform) AppleACPICPU: ProcessorId=1 LocalApicId=0 Enabled",
               "(IOUSBHostFamily) USB device disconnected", "Sandbox: mdworker_shared(812) deny(1) file-read-data /Users",
               "(AppleBCMWLANCore) setPOWER: powerState 1", "memorystatus: killing_idle_process pid 412 [cloudd]"],
    "WindowServer": ["(SkyLight) [com.apple.SkyLight:default] Display 1 is now online",
                     "(CoreDisplay) [com.apple.CoreDisplay:Display] Brightness changed to 0.53"],
    "mDNSResponder": ["[com.apple.mDNSResponder:Default] [R1234] getaddrinfo start -- hostname: <mask.hash: 'x'>",
                      "[com.apple.mDNSResponder:Default] Network change detected"],
    "bluetoothd": ["(CoreBluetooth) [com.apple.bluetooth:Server] Connection established", "Scanning stopped"],
    "locationd": ["[com.apple.locationd.Core:Client] client authorization changed"],
    "sharingd": ["[com.apple.sharing:AirDrop] AirDrop discovery started"],
    "trustd": ["(Security) [com.apple.securityd:ocsp] OCSP response valid"],
    "com.apple.WebKit.Networking": ["(CFNetwork) [com.apple.CFNetwork:Summary] Task <ABCD>.<1> summary for task success"],
    "loginwindow": ["-[LoginWindowController loginWindowDidReceiveScreenLock:] | screen locked"],
    "softwareupdated": ["[com.apple.SoftwareUpdate:SUOSUScheduler] Scan scheduled in 3600 seconds"],
}
TYPES = ["Default", "Default", "Default", "Info", "Debug", "Error", "Fault"]


def generate(rng):
    d = Doc()
    procs = rng.sample(sorted(PROCS), rng.randint(1, 4))
    if rng.random() < .6:
        p = procs[0]
        d.skip(f'Filtering the log data using "process == "{p}""' if len(procs) == 1
               else f'Filtering the log data using "subsystem BEGINSWITH "com.apple""')
    info = rng.random() < .4
    if not info:
        d.skip("Skipping info and debug messages, pass --info and/or --debug to include.")
    hdr = f"{'Timestamp':<31} {'Thread':<10} {'Type':<11} {'Activity':<20} {'PID':<6} {'TTL':<4} "
    d.line(hdr, "header", ["Timestamp", "Thread", "Type", "Activity", "PID", "TTL", None, None])
    y, mo, dd = rng.randint(2022, 2026), rng.randint(1, 12), rng.randint(1, 28)
    tz = rng.choice(["-0700", "-0800", "+0000", "+0100", "-0400"])
    t = rng.randint(0, 80000)
    counts = {k: 0 for k in ("Default", "Info", "Debug", "Error", "Fault")}
    acts = 0
    pids = {p: (0 if p == "kernel" else rng.randint(80, 9000)) for p in procs}
    for _ in range(rng.randint(2, 25)):
        p = rng.choice(procs)
        typ = rng.choice(TYPES if info else [x for x in TYPES if x not in ("Info", "Debug")])
        counts[typ] += 1
        t += rng.randint(0, 120)
        stamp = f"{y}-{mo:02d}-{dd:02d} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}.{rng.randint(0, 999999):06d}{tz}"
        thread = f"0x{rng.randint(0x100, 0xfffff):x}"
        act = "0x0" if rng.random() < .6 else f"0x{rng.randint(0x1000, 0xfffff):x}"
        acts += act != "0x0"
        pid = str(pids[p])
        ttl = "0" if rng.random() < .8 else str(rng.choice([3, 7, 14, 30]))
        msg = rng.choice(PROCS[p])
        text = f"{stamp} {thread:<10} {typ:<11} {act:<20} {pid:<6} {ttl:<4} {p}: {msg}"
        d.line(text, "row", [stamp, thread, typ, act, pid, ttl, p, msg])
    d.skip("-" * 116)
    lp = [(k, str(counts[k])) for k in counts]
    text = "Log      - " + ", ".join(f"{k + ':':<12}{v:>8}" for k, v in lp)
    d.line(text, "kv", ["Log"] + [x for p in lp for x in p])
    ap = [("Create", str(acts)), ("Transition", "0"), ("Actions", "0")]
    text = "Activity - " + ", ".join(f"{k + ':':<12}{v:>8}" for k, v in ap)
    d.line(text, "kv", ["Activity"] + [x for p in ap for x in p])
    return d
