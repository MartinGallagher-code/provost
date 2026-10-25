"""mp3gain: either the tab-delimited `-o` table (File, MP3 gain, dB gain,
...) with an "Album" summary row, or the default per-file report of
`Recommended "Track" ...: value` lines and the album totals."""
from lib import Doc

TOOL = "mp3gain"

WORDS = ["Intro", "Weightless", "Stay", "Gold", "Running", "Up", "That", "Hill", "Clocks", "Hurt", "Wonderwall",
         "Karma", "Police", "No", "Surprises", "Lucky", "Sea", "Of", "Love"]


def fname(rng, i):
    return rng.choice(["", "", "CD1/"]) + f"{i:02d} " + rng.choice(["- ", ""]) + \
        " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 4))) + ".mp3"


def generate(rng):
    d = Doc()
    n = rng.randint(1, 14)
    album = n > 1 and rng.random() < .8
    tracks = []
    for i in range(1, n + 1):
        db = rng.uniform(-12, 6)
        tracks.append((fname(rng, i), round(db / 1.5), f"{db:.6f}", f"{rng.uniform(5000, 40000):.6f}",
                       str(rng.randint(180, 230)), str(rng.randint(80, 179))))
    if rng.random() < .55:
        hdr = ["File", "MP3 gain", "dB gain", "Max Amplitude", "Max global_gain", "Min global_gain"]
        d.line("\t".join(hdr), "header", hdr)
        rows = [[t[0], str(t[1]), t[2], t[3], t[4], t[5]] for t in tracks]
        if album:
            adb = sum(float(t[2]) for t in tracks) / n
            rows.append(['"Album"', str(round(adb / 1.5)), f"{adb:.6f}", max(t[3] for t in tracks),
                         max(t[4] for t in tracks), min(t[5] for t in tracks)])
        for r in rows:
            d.line("\t".join(r), "row", r)
        return d
    for t in tracks:
        d.section(t[0])
        if rng.random() < .1:
            d.skip(f"{t[0]} is not a layer III file")
            continue
        for k, v in [('Recommended "Track" dB change', t[2]), ('Recommended "Track" mp3 gain change', str(t[1])),
                     ("Max PCM sample at current gain", t[3]), ("Max mp3 global gain field", t[4]),
                     ("Min mp3 global gain field", t[5])]:
            d.kv(k, v)
        if t[1] and rng.random() < .15:
            d.skip(f"WARNING: some clipping may occur with mp3 gain change {t[1]}")
        d.blank()
    if album:
        adb = sum(float(t[2]) for t in tracks) / n
        d.kv('Recommended "Album" dB change for all files', f"{adb:.6f}")
        d.kv('Recommended "Album" mp3 gain change for all files', str(round(adb / 1.5)))
    return d
