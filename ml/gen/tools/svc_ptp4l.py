"""linuxptp `ptp4l -m` log: monotonic-stamped lines, state transitions as
free text and fixed-layout servo lines (master offset / freq / path delay)."""
from lib import Doc, fake

TOOL = "ptp4l"

STATES = ["INITIALIZING", "LISTENING", "UNCALIBRATED", "SLAVE", "MASTER", "PRE_MASTER", "PASSIVE", "FAULTY"]
EVENTS = ["INITIALIZE", "RS_SLAVE", "RS_MASTER", "MASTER_CLOCK_SELECTED", "ANNOUNCE_RECEIPT_TIMEOUT_EXPIRES",
          "INIT_COMPLETE", "FAULT_DETECTED", "RS_GRAND_MASTER", "SYNCHRONIZATION_FAULT"]


def clockid(rng):
    h = fake.hexid(rng, 12)
    return f"{h[:6]}.fffe.{h[6:]}"


def generate(rng):
    d = Doc()
    t = rng.uniform(1, 900000)
    syslog = rng.random() < 0.3
    host = fake.host(rng).split(".")[0]
    pid = str(rng.randint(300, 60000))
    iface = rng.choice(["eth0", "eno1", "enp3s0", "ens1f0", "eth1"])
    dev = f"/dev/ptp{rng.randint(0, 3)}"
    nports = rng.choice([1, 1, 2])
    sec = rng.randint(0, 50000)

    def emit(msg_text, msg_cells):
        nonlocal t, sec
        t += rng.choice([0.0, 0.001, 0.002, rng.uniform(0.5, 1.2), 1.0])
        stamp = f"{t:.3f}"
        if syslog:
            sec += rng.choice([0, 1, 1, 2])
            ts = f"Apr {(sec // 86400) % 28 + 1:2d} {sec // 3600 % 24:02d}:{sec // 60 % 60:02d}:{sec % 60:02d}"
            text = f"{ts} {host} ptp4l[{pid}]: [{stamp}] {msg_text}"
            d.line(text, "row", [ts, host, "ptp4l", pid, f"[{stamp}]"] + msg_cells)
        else:
            text = f"ptp4l[{stamp}]: {msg_text}"
            d.line(text, "row", ["ptp4l", stamp] + msg_cells)

    def free(m):
        emit(m, [m])

    if rng.random() < 0.7:
        free(f"selected {dev} as PTP clock")
        for p in range(nports, -1, -1):
            free(f"port {p}: INITIALIZING to LISTENING on INIT_COMPLETE")
        if rng.random() < .6:
            free(f"port 1: new foreign master {clockid(rng)}-1")
            free(f"selected best master clock {clockid(rng)}")
            free("port 1: LISTENING to UNCALIBRATED on RS_SLAVE")
    servo = "s0"
    summary = rng.random() < 0.25
    for _ in range(rng.randint(3, 22)):
        r = rng.random()
        if r < 0.12:
            a, b = rng.sample(STATES, 2)
            free(f"port {rng.randint(1, nports)}: {a} to {b} on {rng.choice(EVENTS)}")
            continue
        if r < 0.16:
            free(rng.choice(["clockcheck: clock jumped forward or running faster than expected!",
                             "timed out while polling for tx timestamp",
                             "increasing tx_timestamp_timeout may correct this issue, but it is likely caused by a driver bug",
                             f"port 1: link down", f"port 1: link up",
                             f"port 1: received SYNC without timestamp",
                             f"driver rejected most general HWTSTAMP filter",
                             f"interface '{iface}' does not support requested timestamping mode"]))
            continue
        if summary:
            rms, mx = str(rng.randint(0, 900)), str(rng.randint(0, 2000))
            fr, frd = f"{rng.randint(-40000, 40000):+d}", str(rng.randint(0, 300))
            dl, dld = str(rng.randint(100, 20000)), str(rng.randint(0, 80))
            m = f"rms {rms:>4} max {mx:>4} freq {fr:>6} +/- {frd:>3} delay {dl:>5} +/- {dld:>3}"
            emit(m, ["rms", rms, "max", mx, "freq", fr, frd, "delay", dl, dld])
        else:
            off = str(rng.choice([rng.randint(-60, 60), rng.randint(-20000, 20000)]))
            fr = f"{rng.randint(-40000, 40000):+d}"
            pd = str(rng.randint(100, 20000))
            m = f"master offset {off:>7} {servo} freq {fr:>6} path delay {pd:>7}"
            emit(m, ["master offset", off, servo, "freq", fr, "path delay", pd])
            servo = {"s0": "s1", "s1": "s2"}.get(servo, "s2")
    return d
