"""IEx `runtime_info()` / `runtime_info([:applications])` (Elixir): `## Topic`
headings over aligned `Key:  value` blocks, ending with the topic hints."""
from lib import Doc, fake

TOOL = "iex-runtime-info"


def _block(d, pairs):
    w = max(len(k) for k, _ in pairs) + 2
    w = max(w, 20)
    for k, v in pairs:
        d.line((k + ":").ljust(w) + v, "kv", [k, v])


def _mem(rng):
    return rng.choice([f"{rng.randint(1, 999)} KB", f"{rng.randint(1, 300)} MB", f"{rng.uniform(1, 9):.2f} GB",
                       f"{rng.randint(1, 99)} MB"])


def _uptime(rng):
    h, m, s = rng.randint(0, 900), rng.randint(0, 59), rng.randint(0, 59)
    parts = []
    if h >= 24:
        parts.append(f"{h // 24} day{'s' if h // 24 > 1 else ''}")
        h %= 24
    if h:
        parts.append(f"{h} hour{'s' if h > 1 else ''}")
    if m:
        parts.append(f"{m} minute{'s' if m > 1 else ''}")
    parts.append(f"{s} second{'s' if s != 1 else ''}")
    return parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " and " + parts[-1]


def _lim(rng, cap):
    n = rng.randint(10, cap // rng.choice([3, 20, 400]))
    return f"{n} / {cap} ({int(100 * n / cap)}% used)"


def generate(rng):
    d = Doc()
    topics = ["system", "memory", "limits"]
    extra = []
    if rng.random() < .3:
        extra = ["applications"]
    shown = topics + extra if extra and rng.random() < .5 else (extra if extra else topics)
    if rng.random() < .3:
        d.line("iex(1)> runtime_info" + (f"([{', '.join(':' + t for t in shown)}])" if shown != topics else ""), "skip")
    d.blank()
    otp = rng.choice([24, 25, 26, 27])
    if "system" in shown:
        d.section("## System and architecture")
        d.blank()
        sched = rng.choice([1, 2, 4, 8, 12, 16, 32])
        _block(d, [("Elixir version", f"1.{rng.randint(12, 17)}.{rng.randint(0, 9)}"),
                   ("Erlang/OTP version", str(otp)),
                   ("ERTS version", f"{otp - 12}.{rng.randint(0, 3)}.{rng.randint(0, 9)}"),
                   ("Compiled for", rng.choice(["x86_64-pc-linux-gnu", "aarch64-apple-darwin23.1.0",
                                                "x86_64-pc-linux-musl", "aarch64-unknown-linux-gnu", "win32"])),
                   ("Schedulers", str(sched)),
                   ("Schedulers online", str(rng.randint(1, sched)))])
        d.blank()
    if "memory" in shown:
        d.section("## Memory")
        d.blank()
        _block(d, [(k, _mem(rng)) for k in ("Atoms", "Binaries", "Code", "ETS", "Processes", "Total")])
        d.blank()
    if "limits" in shown:
        d.section("## Statistics / limits")
        d.blank()
        _block(d, [("Uptime", _uptime(rng)), ("Run queue", str(rng.choice([0, 0, 1, rng.randint(2, 40)]))),
                   ("Atoms", _lim(rng, 1048576)), ("ETS", _lim(rng, 8192)),
                   ("Ports", _lim(rng, 65536)), ("Processes", _lim(rng, 262144))])
        d.blank()
    if "applications" in shown:
        d.section("## Loaded OTP Applications")
        d.blank()
        apps = rng.sample(["asn1", "compiler", "crypto", "elixir", "iex", "kernel", "logger", "mix", "public_key",
                           "ssl", "stdlib", "telemetry", "phoenix", "plug", "ecto", "postgrex", "jason",
                           "cowboy", "ranch", "runtime_tools", "inets", "decimal", "db_connection"], rng.randint(4, 16))
        _block(d, [(a, fake.version(rng)) for a in sorted(apps)])
        d.blank()
    d.line(f"Showing topics:    [{', '.join(':' + t for t in shown)}]", "kv", ["Showing topics", f"[{', '.join(':' + t for t in shown)}]"])
    others = [t for t in ["system", "memory", "limits", "applications", "allocators"] if t not in shown]
    d.line(f"Additional topics: [{', '.join(':' + t for t in others)}]", "kv", ["Additional topics", f"[{', '.join(':' + t for t in others)}]"])
    d.blank()
    d.skip("To view a specific topic call runtime_info(topic)")
    d.blank()
    return d
