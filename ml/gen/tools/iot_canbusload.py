"""can-utils `canbusload can0@500000 ... [-t] [-b]`: per-interval blocks of
right-aligned per-interface counters (frames, bits, payload bits, load %),
an optional timestamp heading and an optional |XXX....| bargraph."""
from lib import Doc, fake

TOOL = "canbusload"


def generate(rng):
    d = Doc()
    ifs = []
    for i in range(rng.randint(1, 4)):
        name = rng.choice(["can", "can", "vcan", "slcan"]) + str(i)
        rate = rng.choice([125000, 250000, 500000, 500000, 1000000, 83333])
        ifs.append((name, rate))
    stamp = rng.random() < .6
    bars = rng.random() < .6
    mode = rng.choice(["worst case bitstuffing", "exact bitstuffing", "no bitstuffing"])
    nl = max(len(n) for n, _ in ifs)
    rl = max(len(str(r)) for _, r in ifs)
    load = {n: rng.uniform(0, 80) for n, _ in ifs}
    for blk in range(rng.randint(1, 6)):
        if stamp:
            t = fake.date(rng, "datetime") if blk == 0 else t[:-2] + f"{(int(t[-2:]) + 1) % 60:02d}"
            text = f"canbusload {t} ({mode})"
            d.line(text, "section", [text])
        for name, rate in ifs:
            pct = max(0, min(100, load[name] + rng.uniform(-6, 6)))
            bits = int(rate * pct / 100)
            frames = bits // rng.choice([111, 130, 64, 47]) if bits else 0
            payload = int(bits * rng.uniform(.3, .55))
            p = int(pct)
            text = " %*s@%-*d %5d %7d %6d %3d%%" % (nl, name, rl, rate, frames, bits, payload, p)
            if bars:
                x = p // 5
                text += " |" + "X" * x + "." * (20 - x) + "|"
            d.line(text, "row", [f"{name}@{rate}", str(frames), str(bits), str(payload), f"{p}%"])
        d.blank()
    return d
