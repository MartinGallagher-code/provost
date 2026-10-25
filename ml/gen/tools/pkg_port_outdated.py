"""MacPorts `port outdated`: a heading sentence, then headerless rows
`name  installed < available` padded to fixed widths, with an optional
reason in parentheses."""
from lib import Doc

TOOL = "port-outdated"

PORTS = ["curl", "openssl3", "python311", "python312", "py311-pip", "py311-setuptools", "git", "gettext",
         "libiconv", "ncurses", "readline", "sqlite3", "zlib", "xz", "zstd", "libxml2", "ffmpeg", "x265",
         "harfbuzz", "freetype", "fontconfig", "cairo", "glib2", "gnutls", "nettle", "libidn2", "pcre2",
         "bash", "vim", "neovim", "tmux", "wget", "gmake", "cmake", "llvm-16", "clang-16", "ld64",
         "cctools", "perl5.34", "p5.34-locale-gettext", "ImageMagick", "ghostscript", "gnupg2", "pinentry-mac"]
REASONS = ["(platform darwin 21 != darwin 22)", "(platform darwin 22 != darwin 23)",
           "(version 1.2.3 < 1.2.4)", "(epoch 0 < 1)", "(requested variant +universal)"]


def ver(rng):
    return ".".join(str(rng.randint(0, 30)) for _ in range(rng.randint(2, 3)))


def bump(rng, v):
    p = v.split(".")
    i = rng.randrange(len(p))
    p[i] = str(int(p[i]) + rng.randint(1, 9))
    return ".".join(p[:i + 1] + ["0"] * (len(p) - i - 1))


def generate(rng):
    d = Doc()
    ports = sorted(rng.sample(PORTS, rng.randint(1, 16))) if rng.random() < .9 else []
    if rng.random() < .25 or not ports:
        d.skip("Warning: port definitions are more than two weeks old, consider updating them by running "
               "'port selfupdate'.")
    if not ports:
        d.skip("No installed ports are outdated.")
        return d
    d.skip("The following installed ports are outdated:")
    w1 = rng.choice([30, 30, 30, 40])
    for p in ports:
        v = ver(rng)
        var = rng.choice(["+universal", "+x11", "+quartz", "+ssl"]) if rng.random() < .1 else ""
        rev = rng.randint(0, 3)
        if rng.random() < .25:
            nv, nrev = v, rev + 1
        else:
            nv, nrev = bump(rng, v), 0
        cur, new = f"{v}_{rev}{var}", f"{nv}_{nrev}{var}"
        mid = f"{cur} < {new}"
        why = rng.choice(REASONS) if rng.random() < .1 else None
        text = p.ljust(w1) + " " + (mid.ljust(24) + " " + why if why else mid)
        d.line(text, "row", [p, cur, new, why])
    return d
