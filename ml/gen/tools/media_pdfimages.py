"""poppler `pdfimages -list`: one row per image with right-aligned numbers,
under a fixed header and a dashed rule."""
from lib import Doc

TOOL = "pdfimages-list"

HEAD = "page   num  type   width height color comp bpc  enc interp  object ID x-ppi y-ppi size ratio"
COLS = ["page", "num", "type", "width", "height", "color", "comp", "bpc", "enc", "interp", "object ID",
        "x-ppi", "y-ppi", "size", "ratio"]


def _size(rng):
    n = rng.choice([rng.randint(50, 999), rng.uniform(1, 999)])
    if isinstance(n, int):
        return f"{n}B"
    u = rng.choice(["K", "K", "M"])
    return (f"{n:.1f}" if n < 100 else f"{int(n)}") + u


def generate(rng):
    d = Doc()
    d.line(HEAD, "header", COLS)
    d.skip("-" * len(HEAD))
    num, obj = 0, rng.randint(4, 30)
    for page in range(1, rng.randint(1, 12) + 1):
        for _ in range(rng.choice([0, 1, 1, 1, 2, 3])):
            kind = rng.choice(["image", "image", "image", "smask", "mask", "stencil"])
            if kind in ("smask", "mask", "stencil") or rng.random() < .3:
                color, comp = "gray", 1
            else:
                color, comp = rng.choice([("rgb", 3), ("rgb", 3), ("cmyk", 4), ("index", 1), ("icc", 3)])
            bpc = 1 if kind in ("mask", "stencil") else rng.choice([8, 8, 8, 1, 4, 16])
            enc = rng.choice(["jpeg", "image", "jbig2", "ccitt", "jpx", "flate"]) if bpc != 1 else rng.choice(["ccitt", "jbig2", "image"])
            w, h = rng.randint(16, 5000), rng.randint(16, 7000)
            ppi = rng.choice([72, 96, 150, 200, 300, 600, rng.randint(10, 2400)])
            ppy = ppi if rng.random() < .8 else rng.randint(10, 2400)
            obj += rng.randint(1, 20)
            ratio = rng.choice([f"{rng.randint(1, 99)}%", f"{rng.uniform(0, 9.9):.1f}%", f"{rng.randint(100, 300)}%"])
            row = [f"{page:4d}", f"{num:5d}", f"{kind:<6s}", f"{w:5d}", f"{h:5d}", f"{color:<5s}", f"{comp:4d}",
                   f"{bpc:3d}", f"{enc:<5s}", f"{rng.choice(['no', 'yes']):<3s}", f"{obj:6d} {0:2d}",
                   f"{ppi:5d}", f"{ppy:5d}", f"{_size(rng):>5s}", f"{ratio:>3s}"]
            d.line(" ".join(row), "row", [c.strip() for c in row])
            num += 1
    return d
