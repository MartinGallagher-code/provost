"""tpm2-tools `tpm2_pcrread`: one indented heading per hash bank, then
`index: 0x<digest>` lines."""
from lib import Doc

TOOL = "tpm2_pcrread"

BANKS = {"sha1": 40, "sha256": 64, "sha384": 96, "sm3_256": 64}


def digest(rng, n):
    kind = rng.random()
    if kind < .15:
        return "0" * n
    if kind < .2:
        return "F" * n
    return "".join(rng.choice("0123456789ABCDEF") for _ in range(n))


def generate(rng):
    d = Doc()
    banks = rng.choice([["sha1", "sha256"], ["sha256"], ["sha1", "sha256", "sha384"], ["sha256", "sha384"],
                        ["sha1"], ["sha256", "sm3_256"]])
    if rng.random() < .5:
        pcrs = list(range(24))
    else:
        pcrs = sorted(rng.sample(range(24), rng.randint(1, 10)))
    lower = rng.random() < .1
    for b in banks:
        d.section(f"  {b}:", b)
        for i in pcrs:
            v = digest(rng, BANKS[b])
            if lower:
                v = v.lower()
            idx = f"{i:<2}"
            d.line(f"    {idx}: 0x{v}", "kv", [str(i), f"0x{v}"])
    return d
