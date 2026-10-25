"""`metaflac --list FILE`: one `METADATA block #N` heading per block, indented
`key: value` fields, and seek points / Vorbis comments as nested lines."""
from lib import Doc, fake

TOOL = "metaflac"

TAGS = ["TITLE", "ARTIST", "ALBUM", "DATE", "TRACKNUMBER", "TRACKTOTAL", "GENRE", "ALBUMARTIST",
        "COMPOSER", "DISCNUMBER", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK", "MUSICBRAINZ_TRACKID",
        "ISRC", "COMMENT", "ENCODER"]
WORDS = ["Midnight", "City", "Lights", "Paper", "Moon", "静かな", "Over", "Hills", "Sunday", "Morning", "Reprise",
         "Radio", "Edit", "Symphony", "No.", "5", "in", "C", "Minor", "Allegro"]


def generate(rng):
    d = Doc()
    ind = "  "
    rate = rng.choice([44100, 48000, 88200, 96000, 192000])
    bps = rng.choice([16, 16, 24])
    ch = rng.choice([2, 2, 1, 6])
    total = rng.randint(rate * 20, rate * 900)
    blocks = ["STREAMINFO"]
    if rng.random() < .3:
        blocks.append("APPLICATION")
    if rng.random() < .85:
        blocks.append("SEEKTABLE")
    blocks.append("VORBIS_COMMENT")
    if rng.random() < .3:
        blocks.append("CUESHEET")
    if rng.random() < .8:
        blocks.append("PADDING")
    tnum = {"STREAMINFO": 0, "PADDING": 1, "APPLICATION": 2, "SEEKTABLE": 3, "VORBIS_COMMENT": 4, "CUESHEET": 5}
    for i, b in enumerate(blocks):
        d.section(f"METADATA block #{i}")
        d.kv("type", f"{tnum[b]} ({b})", indent=ind)
        d.kv("is last", "true" if i == len(blocks) - 1 else "false", indent=ind)
        if b == "STREAMINFO":
            d.kv("length", "34", indent=ind)
            bs = rng.choice([4096, 4608, 1152])
            for k, v in [("minimum blocksize", f"{bs} samples"), ("maximum blocksize", f"{bs} samples"),
                         ("minimum framesize", f"{rng.randint(10, 3000)} bytes"),
                         ("maximum framesize", f"{rng.randint(5000, 30000)} bytes"),
                         ("sample_rate", f"{rate} Hz"), ("channels", str(ch)), ("bits-per-sample", str(bps)),
                         ("total samples", str(total)), ("MD5 signature", fake.hexid(rng, 32))]:
                d.kv(k, v, indent=ind)
        elif b == "APPLICATION":
            d.kv("length", str(rng.randint(20, 400)), indent=ind)
            d.kv("application ID", rng.choice(["41544348", "52494646", "46696361"]), indent=ind)
            d.section(ind + "data contents:")
            d.skip(ind + rng.choice(["Flac File", "RIFF....WAVEfmt ", "<?xml version=\"1.0\"?>"]))
        elif b == "SEEKTABLE":
            n = rng.randint(1, 12)
            d.kv("length", str(n * 18), indent=ind)
            d.kv("seek points", str(n), indent=ind)
            off = 0
            for p in range(n):
                sn, so = p * 10 * rate // 4096 * 4096, off
                off += rng.randint(500000, 2500000)
                text = f"{ind}  point {p}: sample_number={sn}, stream_offset={so}, frame_samples={4096 if p < n - 1 or rng.random() < .7 else 0}"
                fs = text.rsplit("=", 1)[1]
                d.line(text, "row", [f"point {p}", "sample_number", str(sn), "stream_offset", str(so),
                                     "frame_samples", fs])
        elif b == "VORBIS_COMMENT":
            tags = rng.sample(TAGS, rng.randint(0, 10))
            vendor = rng.choice(["reference libFLAC 1.3.2 20170101", "reference libFLAC 1.4.3 20230623",
                                 "Lavf58.29.100", "reference libFLAC 1.2.1 20070917"])
            d.kv("length", str(rng.randint(40, 900)), indent=ind)
            d.kv("vendor string", vendor, indent=ind)
            d.kv("comments", str(len(tags)), indent=ind)
            for j, t in enumerate(tags):
                if t in ("TRACKNUMBER", "TRACKTOTAL", "DISCNUMBER"):
                    v = str(rng.randint(1, 20))
                elif t == "DATE":
                    v = str(rng.randint(1960, 2026))
                elif t.startswith("REPLAYGAIN"):
                    v = f"{rng.uniform(-12, 3):+.2f} dB" if t.endswith("GAIN") else f"{rng.uniform(0.3, 1):.6f}"
                elif t == "MUSICBRAINZ_TRACKID":
                    v = fake.uuid(rng)
                elif t == "ISRC":
                    v = f"GB{fake.token(rng, 3).upper()}{rng.randint(1000000, 9999999)}"
                else:
                    v = " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 6)))
                d.line(f"{ind}  comment[{j}]: {t}={v}", "row", [f"comment[{j}]", t, v])
        elif b == "CUESHEET":
            d.kv("length", str(rng.randint(400, 2000)), indent=ind)
            d.kv("media catalog number", str(rng.randint(10**12, 10**13 - 1)), indent=ind)
            d.kv("lead-in", "88200", indent=ind)
            d.kv("is CD", "true", indent=ind)
            d.kv("number of tracks", str(rng.randint(2, 20)), indent=ind)
        else:
            d.kv("length", str(rng.choice([4096, 8192, 1024, rng.randint(100, 70000)])), indent=ind)
    return d
