"""strongSwan `swanctl --list-sas`: one IKE SA per block, indented lines for
endpoints, algorithms and timers, then nested CHILD_SA blocks with traffic
counters and traffic selectors (tree / indented output)."""
from lib import Doc, fake

TOOL = "swanctl-list-sas"

IKE_ALGS = ["AES_CBC-256/HMAC_SHA2_256_128/PRF_HMAC_SHA2_256/ECP_256",
            "AES_GCM_16-256/PRF_HMAC_SHA2_384/CURVE_25519",
            "AES_CBC-128/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048",
            "CHACHA20_POLY1305/PRF_HMAC_SHA2_256/CURVE_25519"]
ESP_ALGS = ["AES_GCM_16-256", "AES_CBC-256/HMAC_SHA2_256_128", "AES_CBC-128/HMAC_SHA1_96/MODP_2048",
            "CHACHA20_POLY1305"]


def _ident(rng):
    return rng.choice([f"{fake.word(rng)}.strongswan.org", fake.host(rng), fake.ip(rng),
                       f"C=CH, O=strongSwan, CN={fake.word(rng)}.example.com", f"{fake.user(rng)}@example.org"])


def _net(rng):
    return f"10.{rng.randint(0, 255)}.{rng.choice(['0.0/16', str(rng.randint(0, 255)) + '.0/24'])}"


def generate(rng):
    d = Doc()
    for n in range(rng.randint(1, 3)):
        name = rng.choice(["gw-gw", "rw", "home", "site-to-site", f"{fake.word(rng)}-vpn", "net-net", "roadwarrior"])
        uid = f"#{rng.randint(1, 400)}"
        state = rng.choice(["ESTABLISHED", "ESTABLISHED", "ESTABLISHED", "CONNECTING", "REKEYING"])
        spi_i, spi_r = fake.hexid(rng, 16) + "_i", fake.hexid(rng, 16) + "_r"
        if rng.random() < .5:
            spi_i += "*"
        else:
            spi_r += "*"
        d.line(f"{name}: {uid}, {state}, IKEv2, {spi_i} {spi_r}", "row", [name, uid, state, "IKEv2", spi_i, spi_r])
        for side in ("local", "remote"):
            ident = _ident(rng)
            port = rng.choice(["500", "4500", "4500"])
            ep = f"{fake.ip(rng)}[{port}]"
            d.line(f"  {side.ljust(6)} '{ident}' @ {ep}", "kv", [side, ident, ep])
            if side == "remote" and rng.random() < .3:
                vip = f"10.{rng.randint(0, 9)}.{rng.randint(0, 9)}.{rng.randint(1, 254)}"
                eap = fake.user(rng)
                d.line(f"  {side.ljust(6)} EAP: '{eap}'", "kv", [side, "EAP", eap])
                d.line(f"  {side.ljust(6)} vips: {vip}", "kv", [side, "vips", vip])
        alg = rng.choice(IKE_ALGS)
        d.line("  " + alg, "row", [alg])
        est = f"established {rng.randint(1, 80000)}s ago"
        timers = [est]
        if rng.random() < .8:
            timers.append(f"rekeying in {rng.randint(10, 86000)}s")
        if rng.random() < .3:
            timers.append(f"reauth in {rng.randint(1000, 90000)}s")
        d.line("  " + ", ".join(timers), "row", timers)
        for c in range(rng.randint(1, 3)):
            cname = rng.choice(["net-net", "host-host", name, f"{fake.word(rng)}-child", "rw"])
            cuid = f"#{rng.randint(1, 900)}"
            reqid = str(rng.randint(1, 60))
            mode = rng.choice(["TUNNEL", "TUNNEL", "TRANSPORT"])
            esp = "ESP:" + rng.choice(ESP_ALGS)
            cells = [cname, cuid, "reqid", reqid, "INSTALLED", mode]
            text = f"  {cname}: {cuid}, reqid {reqid}, INSTALLED, {mode}"
            if rng.random() < .3:
                text += "-in-UDP"
                cells[-1] = mode + "-in-UDP"
            text += f", {esp}"
            cells.append(esp)
            d.line(text, "row", cells)
            t = [f"installed {rng.randint(1, 3500)}s ago", f"rekeying in {rng.randint(10, 3500)}s",
                 f"expires in {rng.randint(3500, 4000)}s"]
            if rng.random() < .2:
                t = t[:1]
            d.line("    " + ", ".join(t), "row", t)
            for direction in ("in", "out"):
                spi = fake.hexid(rng, 8)
                mag = rng.choice([10 ** 3, 10 ** 6, 10 ** 9])
                byt = f" {rng.randint(0, mag):>6} bytes"
                pk = f" {rng.randint(0, mag // 900 + 1):>5} packets"
                cells = [direction, spi, byt.strip(), pk.strip()]
                text = f"    {direction.ljust(3)} {spi},{byt},{pk}"
                if rng.random() < .8:
                    ago = f"{rng.randint(0, 600)}s ago"
                    text += f", {ago:>8}"
                    cells.append(ago)
                d.line(text, "row", cells)
            for side in ("local ", "remote"):
                nets = [_net(rng) for _ in range(rng.choice([1, 1, 1, 2]))]
                d.line(f"    {side} " + " ".join(nets), "kv", [side.strip()] + nets)
    return d
