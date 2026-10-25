"""lsdvd: libdvdread chatter, a `Disc Title:` line, one comma-separated
`Key: value` line per title, optional tab-indented audio/chapter/subtitle
lines under each title, and `Longest track:`."""
from lib import Doc

TOOL = "lsdvd"

LANGS = [("en", "English"), ("fr", "Francais"), ("de", "Deutsch"), ("es", "Espanol"), ("it", "Italiano"),
         ("xx", "Unknown"), ("ja", "Japanese")]


def pairs_line(d, prefix, pairs, tail=""):
    text = prefix + ", ".join(f"{k}: {v}" for k, v in pairs) + tail
    cells = []
    for k, v in pairs:
        cells += [k, v]
    d.line(text, "row", cells)


def dur(rng, hmax=2):
    return f"{rng.randint(0, hmax):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}.{rng.randint(0, 999):03d}"


def generate(rng):
    d = Doc()
    if rng.random() < .7:
        d.skip(f"libdvdread: Using libdvdcss version 1.4.{rng.randint(0, 3)} for DVD access")
    if rng.random() < .2:
        d.skip("libdvdread: Attempting to retrieve all CSS keys")
        d.skip(f"libdvdread: Found {rng.randint(10, 80)} VTS's")
        d.skip(f"libdvdread: Elapsed time {rng.randint(0, 9)}")
    d.kv("Disc Title", rng.choice(["THE_MATRIX", "SEASON_2_DISC_1", "AMELIE", "DVDVOLUME", "LOTR_FOTR_D1",
                                   "BBC_PLANET_EARTH_3", "WALLACE_GROMIT"]))
    opts = {k for k in "acsx" if rng.random() < .3}
    ntitles = rng.randint(1, 20)
    longest, best = 1, -1
    pal = rng.random() < .5
    for t in range(1, ntitles + 1):
        length = dur(rng)
        if length > str(best):
            best, longest = length, t
        nch, nau, nsp = rng.randint(1, 40), rng.randint(0, 8), rng.randint(0, 32)
        text = (f"Title: {t:02d}, Length: {length} Chapters: {nch:02d}, Cells: {nch + rng.randint(0, 3):02d}, "
                f"Audio streams: {nau:02d}, Subpictures: {nsp:02d}")
        cells = ["Title", f"{t:02d}", "Length", length, "Chapters", f"{nch:02d}", "Cells", text.split("Cells: ")[1][:2],
                 "Audio streams", f"{nau:02d}", "Subpictures", f"{nsp:02d}"]
        d.line(text, "row", cells)
        if "x" in opts:
            pairs_line(d, "\t", [("VTS", f"{rng.randint(1, 9):02d}"), ("TTN", f"{rng.randint(1, 3):02d}"),
                                 ("FPS", "25.00" if pal else "29.97"), ("Format", "PAL" if pal else "NTSC"),
                                 ("Aspect ratio", rng.choice(["16/9", "4/3"])), ("Width", "720"),
                                 ("Height", "576" if pal else "480"), ("DF", rng.choice(["Letterbox", "?", "Pan&Scan"]))])
        if "a" in opts:
            for a in range(1, min(nau, 4) + 1):
                lg = rng.choice(LANGS)
                pairs_line(d, "\t", [("Audio", str(a)), ("Language", f"{lg[0]} - {lg[1]}"),
                                     ("Format", rng.choice(["ac3", "dts", "lpcm", "mpeg1"])),
                                     ("Frequency", "48000"), ("Quantization", rng.choice(["drc", "16bit"])),
                                     ("Channels", str(rng.choice([2, 6]))), ("AP", "0"),
                                     ("Content", rng.choice(["Undefined", "Normal", "Comments1"])),
                                     ("Stream id", f"0x{0x80 + a - 1:x}")])
        if "c" in opts:
            for c in range(1, min(nch, 5) + 1):
                pairs_line(d, "\t", [("Chapter", f"{c:02d}"), ("Length", dur(rng, 0)), ("Start Cell", f"{c:02d}")])
        if "s" in opts:
            for s in range(1, min(nsp, 3) + 1):
                lg = rng.choice(LANGS)
                pairs_line(d, "\t", [("Subtitle", f"{s:02d}"), ("Language", f"{lg[0]} - {lg[1]}"),
                                     ("Content", "Undefined"), ("Stream id", f"0x{0x20 + s - 1:x}")], tail=", ")
        if opts and rng.random() < .5:
            d.blank()
    d.kv("Longest track", f"{longest:02d}")
    if rng.random() < .5:
        d.blank()
    return d
