"""SoX `soxi FILE...`: a `Key : value` block per file, a Comments list of
TAG=value lines, and a total line for several files."""
from lib import Doc, fake

TOOL = "soxi"

FMT = [("FLAC", "16-bit FLAC", "16-bit"), ("WAV", "16-bit Signed Integer PCM", "16-bit"),
       ("WAV", "24-bit Signed Integer PCM", "24-bit"), ("WAV", "32-bit Floating Point PCM", "25-bit"),
       ("MP3", "MPEG audio (layer I, II or III)", "16-bit"), ("OGG", "Vorbis", "16-bit"),
       ("AIFF", "16-bit Signed Integer PCM", "16-bit"), ("OPUS", "Opus", "16-bit")]
TAGS = ["Title", "Artist", "Album", "Date", "Tracknumber", "Genre", "Comment", "Encoder", "ALBUMARTIST",
        "REPLAYGAIN_TRACK_GAIN", "DISCNUMBER"]
WORDS = ["Blue", "Night", "Train", "River", "Song", "Of", "The", "Morning", "Electric", "Dreams", "Live", "Echo"]


def generate(rng):
    d = Doc()
    nfiles = rng.choice([1, 1, 1, 2, 3])
    total = 0
    for _ in range(nfiles):
        d.blank()
        ext = rng.choice(FMT)
        name = rng.choice(["", "", "audio/", "/home/alice/Music/"]) + \
            rng.choice(["take", "track", "mix", "song", "voice_memo"]) + f"{rng.randint(1, 30):02d}." + ext[0].lower()
        rate = rng.choice([44100, 48000, 96000, 22050, 16000, 8000])
        ch = rng.choice([1, 2, 2, 2, 6])
        secs = rng.uniform(0.5, 900)
        total += secs
        samples = int(secs * rate)
        dur = f"{int(secs // 3600):02d}:{int(secs % 3600 // 60):02d}:{secs % 60:05.2f}"
        rows = [("Input File", f"'{name}'"), ("Channels", str(ch)), ("Sample Rate", str(rate)),
                ("Precision", ext[2])]
        for k, v in rows:
            d.kv(k, v, sep=": ", key_width=15)
        vals = [dur, f"{samples} samples"]
        if rate == 44100 or rng.random() < .5:
            vals.append(f"{samples / 588:.1f} CDDA sectors" if rate == 44100 else f"~{samples / 588:.1f} CDDA sectors")
        text = "Duration".ljust(15) + ": " + " = ".join(vals)
        d.line(text, "kv", ["Duration"] + vals)
        size = samples * ch * 2 / rng.choice([1, 1.5, 4, 10])
        d.kv("File Size", (f"{size / 1e6:.1f}M" if size > 1e6 else f"{size / 1e3:.1f}k"), sep=": ", key_width=15)
        d.kv("Bit Rate", rng.choice([f"{rng.randint(64, 4608)}k", f"{rng.uniform(1, 9.9):.2f}M"]), sep=": ", key_width=15)
        d.kv("Sample Encoding", ext[1], sep=": ", key_width=15)
        if ext[0] in ("FLAC", "MP3", "OGG", "OPUS") and rng.random() < .7:
            d.line("Comments       : ", "section", ["Comments"])
            for tag in rng.sample(TAGS, rng.randint(1, 6)):
                val = " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 5))) if tag in (
                    "Title", "Artist", "Album", "Comment", "ALBUMARTIST", "Genre") else \
                    rng.choice([str(rng.randint(1, 20)), str(rng.randint(1970, 2026)), "-6.21 dB", "Lavf58.76.100"])
                d.line(f"{tag}={val}", "kv", [tag, val])
    if nfiles > 1:
        d.blank()
        dur = f"{int(total // 3600):02d}:{int(total % 3600 // 60):02d}:{total % 60:05.2f}"
        d.line(f"Total Duration of {nfiles} files: {dur}", "kv", [f"Total Duration of {nfiles} files", dur])
    return d
