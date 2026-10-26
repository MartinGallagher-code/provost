"""tpm2-tools `tpm2_pcrread`: one block per hash bank, PCR index: digest.
Sometimes the old tpm2_pcrlist layout (Bank/Algorithm header, PCR_NN: bytes)."""
from lib import Doc

TOOL = "tpm2_pcrread"

BANKS = [("sha1", 40, "TPM_ALG_SHA1(0x0004)"), ("sha256", 64, "TPM_ALG_SHA256(0x000b)"),
         ("sha384", 96, "TPM_ALG_SHA384(0x000c)"), ("sm3_256", 64, "TPM_ALG_SM3_256(0x0012)")]


def digest(rng, n, idx, used):
    if idx in used:
        return "".join(rng.choice("0123456789ABCDEF") for _ in range(n))
    if 17 <= idx <= 22 and rng.random() < 0.7:
        return "F" * n
    return "0" * n


def generate(rng):
    d = Doc()
    banks = [b for b in BANKS if rng.random() < (0.9 if b[0] in ("sha1", "sha256") else 0.25)] or [BANKS[1]]
    if rng.random() < 0.5:
        pcrs = list(range(24))
    else:
        pcrs = sorted(rng.sample(range(24), rng.randint(1, 10)))
    used = set(range(0, 10)) | {14} if rng.random() < 0.8 else set(rng.sample(range(16), 6))
    old = rng.random() < 0.25
    for name, n, alg in banks:
        if old:
            d.kv("Bank/Algorithm", alg)
            for p in pcrs:
                h = digest(rng, n, p, used).lower()
                v = " ".join(h[i:i + 2] for i in range(0, len(h), 2))
                d.line(f"PCR_{p:02d}: {v}", "kv", [f"PCR_{p:02d}", v])
            d.blank()
        else:
            d.section(f"  {name}:")
            for p in pcrs:
                v = "0x" + digest(rng, n, p, used)
                d.line(f"    {str(p).ljust(2)}: {v}", "kv", [str(p), v])
    return d
