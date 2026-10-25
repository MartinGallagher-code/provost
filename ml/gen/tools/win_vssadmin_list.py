"""cmd `vssadmin list shadows` / `vssadmin list shadowstorage`: a two-line
banner, then shadow-copy sets as `Key: value` lines nested by indentation
(set -> copy -> properties), or storage associations with size + percent."""
from lib import Doc, fake

TOOL = "vssadmin-list"


def _guid(rng):
    return "{" + fake.uuid(rng) + "}"


def _when(rng):
    h = rng.randint(1, 12)
    return f"{rng.randint(1, 12)}/{rng.randint(1, 28)}/2026 {h}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {rng.choice(['AM', 'PM'])}"


def _vol(rng, letter=None):
    v = "\\\\?\\Volume" + _guid(rng) + "\\"
    return (f"({letter}:)" + v) if letter else v


def _gb(rng, hi=900):
    x = rng.uniform(0.1, hi)
    return f"{x:.3g} {rng.choice(['GB', 'GB', 'MB', 'TB'])}"


def generate(rng):
    d = Doc()
    d.skip(rng.choice(["vssadmin 1.1 - Volume Shadow Copy Service administrative command-line tool",
                       "vssadmin 1.1 - Volume Shadow Copy Service administrative command-line tool"]))
    d.skip(rng.choice(["(C) Copyright 2001-2013 Microsoft Corp.", "(C) Copyright 2001-2005 Microsoft Corp."]))
    d.blank()
    host = rng.choice(["DESKTOP-", "SRV-", "FS0"]) + fake.token(rng, 6).upper()
    host += rng.choice(["", ".corp.example.com"])
    if rng.random() < .1:
        d.skip("No items found that satisfy the query.")
        return d
    if rng.random() < .35:
        for letter in rng.sample(list("CDEF"), rng.randint(1, 3)):
            d.section("Shadow Copy Storage association")
            vol = _vol(rng, letter)
            d.kv("For volume", vol, indent="   ")
            d.kv("Shadow Copy Storage volume", vol if rng.random() < .8 else _vol(rng, "D"), indent="   ")
            for k in ["Used", "Allocated", "Maximum"]:
                v = f"{_gb(rng)} ({rng.randint(0, 20)}%)" if k != "Maximum" or rng.random() < .8 else "UNBOUNDED (100%)"
                d.kv(f"{k} Shadow Copy Storage space", v, indent="   ")
            d.blank()
        return d
    for _ in range(rng.randint(1, 4)):
        n = rng.choice([1, 1, 1, 2])
        when = _when(rng)
        d.kv("Contents of shadow copy set ID", _guid(rng))
        d.kv(f"Contained {n} shadow copies at creation time", when, indent="   ")
        for i in range(n):
            letter = rng.choice("CCCDE")
            d.kv("Shadow Copy ID", _guid(rng), indent="      ")
            ind = " " * 9
            d.kv("Original Volume", _vol(rng, letter), indent=ind)
            d.kv("Shadow Copy Volume", f"\\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy{rng.randint(1, 60)}", indent=ind)
            d.kv("Originating Machine", host, indent=ind)
            d.kv("Service Machine", host, indent=ind)
            if rng.random() < .3:
                d.kv("Exposed Name", rng.choice(["X:\\", "Z:\\", "\\\\" + host + "\\shadow$"]), indent=ind)
            d.kv("Provider", "'Microsoft Software Shadow Copy provider 1.0'", indent=ind)
            typ, attrs = rng.choice([
                ("ClientAccessibleWriters", "Persistent, Client-accessible, No auto release, Differential, Auto recovered"),
                ("ClientAccessible", "Persistent, Client-accessible, No auto release, No writers, Differential"),
                ("DataVolumeRollback", "Persistent, No auto release, Differential"),
                ("ApplicationRollback", "Persistent, No auto release, Differential, Auto recovered")])
            d.kv("Type", typ, indent=ind)
            d.kv("Attributes", attrs, indent=ind)
            d.blank()
    return d
