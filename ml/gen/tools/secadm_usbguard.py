"""`usbguard list-devices` (and `list-devices --blocked`): one device per
line, `N: target` then space-separated attribute/value pairs with quoted
values and `{ ... }` interface sets."""
from lib import Doc, fake

TOOL = "usbguard"

DEVICES = [("1d6b:0002", "xHCI Host Controller", "09:00:00"), ("1d6b:0003", "xHCI Host Controller", "09:00:00"),
           ("046d:c52b", "USB Receiver", "{ 03:01:01 03:01:02 03:00:00 }"),
           ("8087:0026", "", "{ e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 }"),
           ("0bda:5634", "Integrated_Webcam_HD", "{ 0e:01:00 0e:02:00 0e:02:00 0e:02:00 }"),
           ("05ac:12a8", "iPhone", "{ 06:01:01 ff:fe:02 ff:fd:01 }"),
           ("0781:5583", "Ultra Fit", "08:06:50"), ("1050:0407", "YubiKey OTP+FIDO+CCID",
                                                    "{ 03:01:01 03:00:00 0b:00:00 }"),
           ("2109:2817", "USB2.0 Hub", "{ 09:00:01 09:00:02 }"), ("0951:1666", "DataTraveler 3.0", "08:06:50"),
           ("04f2:b6dd", "Chicony USB2.0 Camera", "{ 0e:01:00 0e:02:00 }"),
           ("138a:0097", "", "ff:00:00"), ("0a5c:5834", "5880", "{ fe:00:00 0b:00:00 ff:00:00 }")]


def b64(rng):
    import string
    al = string.ascii_letters + string.digits + "+/"
    return "".join(rng.choice(al) for _ in range(43)) + "="


def generate(rng):
    d = Doc()
    blocked_only = rng.random() < .2
    with_label = rng.random() < .15
    root_hashes = {}
    ports = []
    n = rng.randint(2 if blocked_only else 1, 12)
    nroot = rng.choice([1, 2, 2, 3, 4])
    devs = [DEVICES[k % 2] for k in range(nroot)] + [rng.choice(DEVICES[2:]) for _ in range(n)]
    for i, (vid, name, ifs) in enumerate(devs, 1):
        target = "allow" if i <= nroot else rng.choice(["allow", "allow", "allow", "block", "reject"])
        if i <= nroot:
            bus = len(root_hashes) + 1
            serial = f"0000:{rng.choice(['00', '01', '02', '3a'])}:{rng.choice(['14', '0d', '00'])}.{rng.randint(0, 3)}"
            port = f"usb{bus}"
            parent = b64(rng)
            h = b64(rng)
            root_hashes[port] = h
            ports.append(port)
        else:
            serial = rng.choice(["", "", fake.hexid(rng, rng.choice([12, 16, 20])).upper(), str(rng.randint(10 ** 6, 10 ** 9))])
            p = rng.choice(ports)
            port = f"{p[3:]}-{rng.randint(1, 8)}" + (f".{rng.randint(1, 4)}" if rng.random() < .2 else "")
            parent = root_hashes[p]
            h = b64(rng)
        if blocked_only and i > nroot and target == "allow":
            target = "block"
        if blocked_only and target == "allow":
            continue
        conn = rng.choice(["hotplug", "hardwired", "unknown", ""]) if not vid.startswith("1d6b") else ""
        q = lambda v: f'"{v}"'
        pairs = [("id", vid), ("serial", q(serial)), ("name", q(name)), ("hash", q(h)),
                 ("parent-hash", q(parent)), ("via-port", q(port)), ("with-interface", ifs),
                 ("with-connect-type", q(conn))]
        if with_label:
            pairs.append(("label", q(rng.choice(["", "", "keyboard", "trusted-token", "docking station"]))))
        text = f"{i}: {target} " + " ".join(f"{k} {v}" for k, v in pairs)
        cells = [str(i), target]
        for k, v in pairs:
            cells += [k, v if v != '""' else None]
        d.line(text, "row", cells)
    return d
