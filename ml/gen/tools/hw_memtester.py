"""`memtester SIZE LOOPS`: version banner, allocation report, then a block
of `Test name : ok` lines per loop, and Done."""
from lib import Doc

TOOL = "memtester"

TESTS = ["Stuck Address", "Random Value", "Compare XOR", "Compare SUB", "Compare MUL", "Compare DIV",
         "Compare OR", "Compare AND", "Sequential Increment", "Solid Bits", "Block Sequential",
         "Checkerboard", "Bit Spread", "Bit Flip", "Walking Ones", "Walking Zeroes", "8-bit Writes", "16-bit Writes"]


def generate(rng):
    d = Doc()
    ver = rng.choice(["4.5.1", "4.6.0", "4.3.0", "4.5.0"])
    bits = rng.choice(["64-bit", "64-bit", "32-bit"])
    d.skip(f"memtester version {ver} ({bits})")
    d.skip(f"Copyright (C) 2001-{rng.choice([2012, 2020, 2024])} Charles Cazabon.")
    d.skip("Licensed under the GNU General Public License version 2 (only).")
    d.blank()
    d.line("pagesize is 4096", "kv", ["pagesize", "4096"])
    mask = "0xfffffffffffff000" if bits == "64-bit" else "0xfffff000"
    d.line(f"pagesizemask is {mask}", "kv", ["pagesizemask", mask])
    mb = rng.choice([64, 128, 256, 512, 1024, 2048, 4096, 8192, 15000])
    want = f"{mb}MB ({mb * 1048576} bytes)"
    d.line(f"want {want}", "kv", ["want", want])
    if rng.random() < 0.2:
        rest = "trying mlock ...over system memory limit, reducing..."
        d.line(f"got  {want}, {rest}", "kv", ["got", want, rest])
        mb = mb - rng.randint(1, mb // 4)
        want = f"{mb}MB ({mb * 1048576} bytes)"
    tail = rng.choices(["trying mlock ...locked.", "trying mlock ...failed: Operation not permitted"], [9, 1])[0]
    d.line(f"got  {want}, {tail}", "kv", ["got", want, tail])
    if tail.endswith("permitted"):
        d.skip("Continuing with unlocked memory; testing will be slower and less reliable.")
    loops = rng.choice([1, 1, 2, 3, 5, 0])
    tests = TESTS if rng.random() < 0.85 else TESTS[:rng.randint(4, len(TESTS))]
    w = max(len(t) for t in TESTS)
    bad = rng.random() < 0.15
    for lp in range(1, (loops or rng.randint(1, 3)) + 1):
        d.section(f"Loop {lp}/{loops}:" if loops else f"Loop {lp}:")
        for t in tests:
            pad = " " * rng.choice([0, 0, 9, 10])
            if bad and t.startswith("Compare") and rng.random() < 0.3:
                a = rng.randint(0, 2 ** 32 - 1)
                v = f"FAILURE: 0x{a:08x} != 0x{a ^ (1 << rng.randint(0, 31)):08x} at offset 0x{rng.randint(0, 2 ** 28):08x}."
            else:
                v = "ok"
            d.line(f"  {t.ljust(w)}: {v}{pad}", "kv", [t, v])
        d.blank()
    if loops:
        d.skip("Done.")
    return d
