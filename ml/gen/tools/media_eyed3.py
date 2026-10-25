"""eyeD3 FILE: per file a path line with its size, an audio-info line, the
tag version heading, `key: value` fields (two per line for track/disc) and
dashed rules between blocks."""
from lib import Doc

TOOL = "eyeD3"

ARTISTS = ["Radiohead", "The National", "Nina Simone", "Daft Punk", "Bon Iver", "Fleetwood Mac", "Kraftwerk",
           "Sigur Rós", "Various Artists", "Massive Attack"]
WORDS = ["Teardrop", "Pink", "Moon", "Holocene", "Dreams", "Computer", "Love", "Fake", "Plastic", "Trees",
         "Around", "The", "World", "Night", "Bloodbuzz", "Ohio", "Feeling", "Good", "(Remastered)", "Live"]
GENRES = [("Rock", 17), ("Electronic", 52), ("Jazz", 8), ("Pop", 13), ("Alternative", 20), ("Ambient", 26),
          ("Soundtrack", 24)]
RULE = "-" * 80


def title(rng, n=4):
    return " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, n)))


def generate(rng):
    d = Doc()
    for f in range(rng.choice([1, 1, 2, 3])):
        art = rng.choice(ARTISTS)
        alb = title(rng, 3)
        tn, tt = rng.randint(1, 14), rng.randint(14, 20)
        t = title(rng, 5)
        path = rng.choice(["", "music/", f"/home/bob/Music/{art}/{alb}/"]) + f"{tn:02d} - {t}.mp3"
        size = f"[ {rng.uniform(1, 15):.2f} MB ]"
        d.line(path.ljust(79 - len(size)) + " " + size, "row", [path, size])
        d.skip(RULE)
        secs = rng.randint(30, 900)
        tm = f"{secs // 60:02d}:{secs % 60:02d}"
        mp = rng.choice(["MPEG1, Layer III", "MPEG2, Layer III", "MPEG2.5, Layer III"])
        br = rng.choice(["128 kb/s", "192 kb/s", "256 kb/s", "320 kb/s", "~211 kb/s", "~245 kb/s"])
        hz = rng.choice(["44100 Hz", "48000 Hz", "22050 Hz"])
        mode = rng.choice(["Joint stereo", "Stereo", "Mono"])
        d.line(f"Time: {tm}\t{mp}\t[ {br} @ {hz} - {mode} ]", "row", ["Time", tm, mp, br, hz, mode])
        d.skip(RULE)
        if rng.random() < .1:
            d.skip("No ID3 v1.x/v2.x tag found!")
            continue
        d.section(f"ID3 v{rng.choice(['2.3', '2.4', '1.1'])}:")
        d.kv("title", t)
        d.kv("artist", art)
        d.kv("album", alb)
        if rng.random() < .4:
            d.kv("album artist", rng.choice(ARTISTS))
        if rng.random() < .3:
            d.kv("composer", rng.choice(["Thom Yorke", "Johann Sebastian Bach", "Matt Berninger, Aaron Dessner"]))
        if rng.random() < .7:
            d.kv("recording date", rng.choice([str(rng.randint(1960, 2026)), f"{rng.randint(1960, 2026)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"]))
        trk = f"{tn}/{tt}" if rng.random() < .7 else str(tn)
        if rng.random() < .6:
            disc = f"{rng.randint(1, 2)}/2"
            d.line(f"track: {trk}\t\tdisc: {disc}", "row", ["track", trk, "disc", disc])
        else:
            d.kv("track", trk)
        if rng.random() < .8:
            g = rng.choice(GENRES)
            d.kv("genre", f"{g[0]} (id {g[1]})" if rng.random() < .8 else g[0])
        if rng.random() < .3:
            d.kv("BPM", str(rng.randint(60, 180)))
        if rng.random() < .3:
            d.kv("Publisher/label", rng.choice(["XL Recordings", "4AD", "Warp Records", "Parlophone"]))
        if rng.random() < .5:
            sz = f"{rng.randint(4000, 900000)} bytes"
            mime = rng.choice(["image/jpeg", "image/png"])
            d.line(f"FRONT_COVER Image: [Size: {sz}] [Type: {mime}]", "row",
                   ["FRONT_COVER Image", "Size", sz, "Type", mime])
            d.skip("Description: ")
        if rng.random() < .3:
            d.blank()
            g = f"{rng.uniform(-12, 2):.2f} dB"
            d.line(f"UserTextFrame: [Description: replaygain_track_gain]", "row",
                   ["UserTextFrame", "Description", "replaygain_track_gain"])
            d.line(g, "cont", [g])
        d.skip(RULE)
    return d
