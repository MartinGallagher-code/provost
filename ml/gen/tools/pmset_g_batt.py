"""macOS `pmset -g batt` and `pmset -g`: a status line, then key/value settings."""
from lib import Doc, fake

TOOL = "pmset-g"


def generate(rng):
    d = Doc()
    src = rng.choice(["AC Power", "Battery Power"])
    d.line(f"Now drawing from '{src}'", "kv", ["Now drawing from", src])
    for i in range(rng.randint(1, 2)):
        pct = f"{rng.randint(3, 100)}%"
        state = rng.choice(["charging", "discharging", "charged", "AC attached; not charging"])
        left = rng.choice(["(no estimate)", f"{rng.randint(0, 9)}:{rng.randint(0, 59):02d} remaining"])
        ident = f"InternalBattery-{i}"
        pid = f"(id={rng.randint(1000000, 99999999)})"
        text = f" -{ident} {pid}\t{pct}; {state}; {left} present: true"
        d.line(text, "row", [ident, pid, pct, state, left, "present:", "true"])
    if rng.random() < 0.7:
        d.section("System-wide power settings:")
        d.section("Currently in use:")
        pairs = [(k, str(rng.randint(0, 180)) if rng.random() < .7 else rng.choice(["0", "1"]))
                 for k in rng.sample(["standby", "Sleep On Power Button", "hibernatefile", "powernap",
                                      "networkoversleep", "disksleep", "sleep", "hibernatemode",
                                      "ttyskeepawake", "displaysleep", "tcpkeepalive", "lowpowermode",
                                      "womp"], rng.randint(4, 10))]
        w = max(len(k) for k, _ in pairs) + rng.randint(1, 6)
        for k, v in pairs:
            d.line(" " + k.ljust(w) + v, "kv", [k, v])
    return d
