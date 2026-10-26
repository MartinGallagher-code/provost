"""Semtech LoRa gateway `lora_pkt_fwd`: `INFO: [up] ...` log lines between
periodic `##### <date> #####` status reports: `### [UPSTREAM] ###`
sections of `# key: value` lines, some holding several pairs."""
from lib import Doc, fake

TOOL = "lora_pkt_fwd"


def log(d, rng, lvl, tag, msg):
    d.line(f"{lvl}: [{tag}] {msg}", "row", [lvl, f"[{tag}]", msg])


def logs(d, rng):
    for _ in range(rng.randint(0, 5)):
        c = rng.random()
        if c < .35:
            log(d, rng, "INFO", "down", f"PULL_ACK received in {rng.randint(8, 400)} ms")
        elif c < .65:
            log(d, rng, "INFO", "up", f"PUSH_ACK received in {rng.randint(8, 400)} ms")
        elif c < .8:
            log(d, rng, "INFO", "down", f"PULL_RESP received  - token[{rng.randint(0, 255)}:{rng.randint(0, 255)}] :)")
        elif c < .9:
            log(d, rng, "WARNING", "down", "ignored out-of sync PULL_ACK packet")
        else:
            log(d, rng, "WARNING", "up", "ignored out-of sync PUSH_ACK packet")


def kv(d, k, v):
    d.line(f"# {k}: {v}", "kv", [k, v])


def report(d, rng, when, v2, gps):
    d.line(f"##### {when} #####", "section", [when])
    d.line("### [UPSTREAM] ###", "section", ["UPSTREAM"])
    rx = rng.randint(0, 200)
    ok = rng.randint(0, rx) if rx else 0
    kv(d, "RF packets received by concentrator", str(rx))
    if rx:
        po = 100.0 * ok / rx
        pf = 100.0 - po
        a, b, c = f"{po:.2f}%", f"{pf:.2f}%", "0.00%"
    else:
        a = b = c = "0.00%"
    d.line(f"# CRC_OK: {a}, CRC_FAIL: {b}, NO_CRC: {c}", "row", ["CRC_OK", a, "CRC_FAIL", b, "NO_CRC", c])
    kv(d, "RF packets forwarded", f"{ok} ({ok * rng.randint(14, 60)} bytes)")
    dg = rng.randint(1, 4) if ok else rng.randint(0, 1)
    kv(d, "PUSH_DATA datagrams sent", f"{dg} ({dg * rng.randint(200, 900) if dg else 0} bytes)")
    kv(d, "PUSH_DATA acknowledged", rng.choice(["100.00%", "100.00%", "0.00%", "66.67%", "50.00%"]))
    d.line("### [DOWNSTREAM] ###", "section", ["DOWNSTREAM"])
    pull = rng.randint(2, 4)
    kv(d, "PULL_DATA sent", f"{pull} ({rng.choice(['100.00', '100.00', '50.00', '0.00'])}% acknowledged)")
    rsp = rng.randint(0, 3)
    kv(d, "PULL_RESP(onse) datagrams received", f"{rsp} ({rsp * rng.randint(150, 300)} bytes)")
    kv(d, "RF packets sent to concentrator", f"{rsp} ({rsp * rng.randint(12, 33)} bytes)")
    kv(d, "TX errors", str(rng.choice([0, 0, 0, 1])))
    if v2:
        if rng.random() < .7:
            kv(d, "TX rejected (collision packet)", f"{rng.choice(['0.00', '0.00', '33.33'])}% (req:{rsp}, rej:0)")
            kv(d, "TX rejected (collision beacon)", f"0.00% (req:{rsp}, rej:0)")
            kv(d, "TX rejected (too late)", f"0.00% (req:{rsp}, rej:0)")
            kv(d, "TX rejected (too early)", f"0.00% (req:{rsp}, rej:0)")
        kv(d, "BEACON queued", "0")
        kv(d, "BEACON sent so far", "0")
        kv(d, "BEACON rejected", "0")
        d.line("### [JIT] ###", "section", ["JIT"])
        d.skip("src/jitqueue.c:448:jit_print_queue(): INFO: [jit] queue is empty")
        if rng.random() < .5:
            kv(d, "SX1301 time (PPS)", str(rng.randint(10 ** 8, 4 * 10 ** 9)))
    d.line("### [GPS] ###", "section", ["GPS"])
    if gps:
        age = str(rng.randint(0, 2))
        d.line(f"# Valid time reference (age: {age} sec)", "kv", ["Valid time reference", "age", f"{age} sec"])
        la, lo, al = f"{rng.uniform(-60, 65):.5f}", f"{rng.uniform(-170, 170):.5f}", f"{rng.randint(-5, 900)}"
        d.line(f"# GPS coordinates: latitude {la}, longitude {lo}, altitude {al} m", "row",
               ["GPS coordinates", "latitude", la, "longitude", lo, "altitude", f"{al} m"])
    elif rng.random() < .5:
        d.skip("# GPS sync is disabled")
    else:
        age = str(rng.randint(10 ** 6, 2 * 10 ** 9))
        d.line(f"# Invalid time reference (age: {age} sec)", "kv", ["Invalid time reference", "age", f"{age} sec"])
        d.line("# Manual GPS coordinates: latitude 0.00000, longitude 0.00000, altitude 0 m", "row",
               ["Manual GPS coordinates", "latitude", "0.00000", "longitude", "0.00000", "altitude", "0 m"])
    d.skip("##### END #####")


def generate(rng):
    d = Doc()
    v2 = rng.random() < .5
    gps = rng.random() < .4
    when = fake.date(rng, "datetime")
    tz = rng.choice(["GMT", "UTC"])
    h, m, s = map(int, when[11:].split(":"))
    if rng.random() < .3:
        d.skip("*** Beacon Packet Forwarder for Lora Gateway ***" if v2 else "*** Basic Packet Forwarder for Lora Gateway ***")
        ver = rng.choice(['2.0.0', '1.4.1', '2.1.0'])
        d.line(f"Version: {ver}", "kv", ["Version", ver])
    for _ in range(rng.randint(1, 3)):
        logs(d, rng)
        d.blank()
        report(d, rng, f"{when[:11]}{h:02d}:{m:02d}:{s:02d} {tz}", v2, gps)
        s += 30
        m = (m + s // 60) % 60
        s %= 60
    logs(d, rng)
    return d
