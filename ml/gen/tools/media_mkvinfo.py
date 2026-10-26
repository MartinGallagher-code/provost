"""mkvinfo (MKVToolNix): the Matroska element tree, `+`/`|` indentation marks
the depth; containers are headings, leaves are `Name: value`."""
from lib import Doc, fake

TOOL = "mkvinfo"

APPS = ["mkvmerge v{v}.0.0 ('{n}') 64-bit", "Lavf{a}.{b}.100", "HandBrake 1.{b}.2 2023{a:02d}0100",
        "mkvmerge v{v}.0.0 ('{n}') 32-bit"]
NAMES = ["Too Much", "Sentimental Journey", "Rapid Rise", "Elevator Love Letter", "Ich bin nur ein Lied"]
TITLES = ["The Long Way Home", "Episode 4", "Holiday 2019", "Concert - Live at the Roundhouse", "S02E07",
          "Untitled", "Nature Documentary Part 1 (Remastered Director's Cut)"]


def _dur(rng):
    return f"{rng.randint(0, 2):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}.{rng.randint(0, 999999999):09d}"


def generate(rng):
    d = Doc()

    def node(depth, name, value=None):
        pre = ("|" + " " * (depth - 1) + "+ ") if depth else "+ "
        if value is None:
            d.line(pre + name, "section", [name])
        else:
            d.line(pre + name + ": " + value, "kv", [name, value])

    node(0, "EBML head")
    for k, v in [("EBML version", "1"), ("EBML read version", "1"), ("Maximum EBML ID length", "4"),
                 ("Maximum EBML size length", "8"), ("Document type", rng.choice(["matroska", "webm"])),
                 ("Document type version", str(rng.choice([2, 4]))), ("Document type read version", "2")]:
        node(1, k, v)
    node(0, "Segment", f"size {rng.randint(10**6, 10**10)}")
    if rng.random() < .7:
        node(1, "Seek head (subentries will be skipped)")
    if rng.random() < .6:
        node(1, "EBML void", f"size {rng.randint(100, 5000)}")
    node(1, "Segment information")
    node(2, "Timestamp scale", "1000000")
    node(2, "Multiplexing application", f"libebml v1.{rng.randint(3, 4)}.{rng.randint(0, 5)} + libmatroska v1.{rng.randint(5, 7)}.{rng.randint(0, 4)}")
    node(2, "Writing application", rng.choice(APPS).format(v=rng.randint(40, 80), n=rng.choice(NAMES),
                                                          a=rng.randint(1, 60), b=rng.randint(0, 9)))
    node(2, "Duration", _dur(rng))
    if rng.random() < .6:
        node(2, "Date", fake.date(rng, "datetime") + " UTC")
    if rng.random() < .5:
        node(2, "Title", rng.choice(TITLES))
    node(2, "Segment UID", " ".join(f"0x{rng.randint(0, 255):02x}" for _ in range(16)))
    node(1, "Tracks")
    ntr = rng.randint(1, 5)
    for t in range(ntr):
        kind = "video" if t == 0 else rng.choice(["audio", "audio", "subtitles"])
        node(2, "Track")
        node(3, "Track number", f"{t + 1} (track ID for mkvmerge & mkvextract: {t})")
        node(3, "Track UID", str(rng.randint(1, 2**63)))
        node(3, "Track type", kind)
        if rng.random() < .5:
            node(3, "Lacing flag", "0")
        if kind == "video":
            codec = rng.choice(["V_MPEG4/ISO/AVC", "V_MPEGH/ISO/HEVC", "V_VP9", "V_AV1"])
            node(3, "Codec ID", codec)
            if rng.random() < .7:
                node(3, "Codec's private data", f"size {rng.randint(30, 3000)}"
                     + (f" (H.264 profile: {rng.choice(['High', 'Main'])} @L{rng.choice(['4.0', '4.1', '5.1'])})"
                        if codec.endswith("AVC") else ""))
            fps = rng.choice([("00:00:00.041708333", "23.976"), ("00:00:00.040000000", "25"),
                              ("00:00:00.033366666", "29.970")])
            node(3, "Default duration", f"{fps[0]} ({fps[1]} frames/fields per second for a video track)")
            node(3, "Language", rng.choice(["und", "eng"]))
            node(3, "Video track")
            w, h = rng.choice([(1920, 1080), (1280, 720), (3840, 2160), (720, 576), (1920, 800)])
            node(4, "Pixel width", str(w))
            node(4, "Pixel height", str(h))
            if rng.random() < .6:
                node(4, "Display width", str(w))
                node(4, "Display height", str(h))
        elif kind == "audio":
            node(3, "Codec ID", rng.choice(["A_AAC", "A_AC3", "A_EAC3", "A_DTS", "A_OPUS", "A_FLAC", "A_VORBIS"]))
            if rng.random() < .5:
                node(3, "Default flag", rng.choice(["0", "1"]))
            node(3, "Language", rng.choice(["eng", "ger", "fre", "jpn", "spa"]))
            if rng.random() < .4:
                node(3, "Name", rng.choice(["Stereo", "Surround 5.1", "Commentary", "Director's commentary"]))
            node(3, "Audio track")
            node(4, "Sampling frequency", rng.choice(["48000", "44100", "96000"]))
            node(4, "Channels", rng.choice(["2", "6", "8"]))
            if rng.random() < .5:
                node(4, "Bit depth", rng.choice(["16", "24"]))
        else:
            node(3, "Codec ID", rng.choice(["S_TEXT/UTF8", "S_TEXT/ASS", "S_HDMV/PGS", "S_VOBSUB"]))
            node(3, "Language", rng.choice(["eng", "ger", "fre", "dut"]))
            if rng.random() < .5:
                node(3, "Forced display flag", rng.choice(["0", "1"]))
    if rng.random() < .5:
        node(1, "Chapters")
        for c in range(rng.randint(1, 4)):
            node(2, "Edition entry") if c == 0 else None
            node(3, "Chapter atom")
            node(4, "Chapter UID", str(rng.randint(1, 2**40)))
            node(4, "Chapter time start", _dur(rng))
            node(4, "Chapter display")
            node(5, "Chapter string", f"Chapter {c + 1:02d}")
            node(5, "Chapter language", "eng")
    if rng.random() < .5:
        node(1, "Tags")
    for _ in range(rng.randint(0, 2)):
        node(1, "Cluster")
    return d
