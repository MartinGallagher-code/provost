"""`gst-inspect-1.0 ELEMENT`: sectioned report: Factory/Plugin Details as
padded key/value pairs, the GObject hierarchy as a `+----` tree, pad
templates with caps fields, and Element Properties with indented details."""
from lib import Doc

TOOL = "gst-inspect-1.0"

ELEMENTS = [
    ("vorbisdec", "Vorbis audio decoder", "Codec/Decoder/Audio", "decode raw vorbis streams to float audio",
     "Benjamin Otte <otte@gnome.org>, Chris Lord <chris@openedhand.com>", "vorbis", "Vorbis plugin library",
     "gst-plugins-base", "GstAudioDecoder", "audio/x-vorbis", "audio/x-raw"),
    ("x264enc", "x264 H.264 Encoder", "Codec/Encoder/Video", "libx264-based H.264 video encoder",
     "Josef Zlomek <josef.zlomek@itonis.tv>, Mark Nauwelaerts <mnauw@users.sf.net>", "x264",
     "libx264-based H264 plugins", "gst-plugins-ugly", "GstVideoEncoder", "video/x-raw", "video/x-h264"),
    ("matroskademux", "Matroska demuxer", "Codec/Demuxer", "Demuxes Matroska/WebM streams into video/audio/subtitles",
     "GStreamer maintainers <gstreamer-devel@lists.freedesktop.org>", "matroska", "Matroska and WebM stream handling",
     "gst-plugins-good", "GstElement", "video/x-matroska", "ANY"),
    ("pulsesink", "PulseAudio Audio Sink", "Sink/Audio", "Plays audio to a PulseAudio server",
     "Lennart Poettering", "pulseaudio", "PulseAudio plugin library", "gst-plugins-good", "GstAudioBaseSink",
     "audio/x-raw", None),
    ("videoscale", "Video scaler", "Filter/Converter/Video/Scaler", "Resizes video",
     "Wim Taymans <wim.taymans@gmail.com>", "videoscale", "Resizes video", "gst-plugins-base",
     "GstVideoFilter", "video/x-raw", "video/x-raw"),
]
CHAIN = {"GstAudioDecoder": ["GstAudioDecoder"], "GstVideoEncoder": ["GstVideoEncoder"],
         "GstElement": [], "GstAudioBaseSink": ["GstBaseSink", "GstAudioBaseSink"],
         "GstVideoFilter": ["GstBaseTransform", "GstVideoFilter"]}
PROPS = [("name", "The name of the object", "readable, writable, 0x2000", 'String. Default: "{e}0"'),
         ("parent", "The parent of the object", "readable, writable, 0x2000", 'Object of type "GstObject"'),
         ("qos", "Handle Quality-of-Service events", "readable, writable", "Boolean. Default: {b}"),
         ("bitrate", "Bitrate in kbit/sec", "readable, writable, changeable only in NULL or READY state",
          "Unsigned Integer. Range: 1 - 2048000 Default: {n}"),
         ("sync", "Sync on the clock", "readable, writable", "Boolean. Default: {b}"),
         ("max-lateness", "Maximum number of nanoseconds that a buffer can be late before it is dropped (-1 unlimited)",
          "readable, writable", "Integer64. Range: -1 - 9223372036854775807 Default: {n}"),
         ("device", "The PulseAudio sink device to connect to", "readable, writable", "String. Default: null"),
         ("min-latency", "Minimum latency", "readable, writable", "Unsigned Integer64. Range: 0 - 18446744073709551615 Default: 0")]


def generate(rng):
    d = Doc()
    e = rng.choice(ELEMENTS)
    ver = f"1.{rng.choice([16, 18, 20, 22, 24])}.{rng.randint(0, 6)}"
    d.section("Factory Details:")
    fac = [("Rank", rng.choice(["primary (256)", "secondary (128)", "none (0)", "marginal (64)"])),
           ("Long-name", e[1]), ("Klass", e[2]), ("Description", e[3]), ("Author", e[4])]
    if rng.random() < .3:
        fac.append(("Documentation", f"https://gstreamer.freedesktop.org/documentation/{e[5]}/{e[0]}.html"))
    for k, v in fac:
        d.kv(k, v, sep=" ", key_width=24, indent="  ")
    d.blank()
    d.section("Plugin Details:")
    pl = [("Name", e[5]), ("Description", e[6]),
          ("Filename", f"/usr/lib/{rng.choice(['x86_64-linux-gnu/', 'aarch64-linux-gnu/', ''])}gstreamer-1.0/libgst{e[5]}.so"),
          ("Version", ver), ("License", rng.choice(["LGPL", "GPL"])), ("Source module", e[7])]
    if rng.random() < .6:
        pl.append(("Source release date", f"20{rng.randint(19, 25)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"))
    pl.append(("Binary package", rng.choice([f"GStreamer {e[7].split('-')[-1].title()} Plugins (Ubuntu)",
                                             f"GStreamer {e[7].split('-')[-1].title()} Plug-ins source release",
                                             "Arch Linux GStreamer 1.0 package"])))
    pl.append(("Origin URL", rng.choice(["https://launchpad.net/distros/ubuntu/+source/" + e[7] + "1.0",
                                         "https://www.archlinux.org/", "Unknown package origin"])))
    for k, v in pl:
        d.kv(k, v, sep=" ", key_width=24, indent="  ")
    d.blank()
    chain = ["GObject", "GInitiallyUnowned", "GstObject", "GstElement"] + CHAIN[e[8]]
    cls = "Gst" + e[0][0].upper() + e[0][1:]
    if cls.lower() not in [c.lower() for c in chain]:
        chain.append(cls)
    for i, c in enumerate(chain):
        text = c if i == 0 else " " * (1 + 6 * (i - 1)) + "+----" + c
        d.line(text, "row", [c])
    if rng.random() < .3:
        d.blank()
        d.section("Implemented Interfaces:")
        iface = rng.choice(["GstPreset", "GstTagSetter", "GstStreamVolume", "GstChildProxy"])
        d.line("  " + iface, "row", [iface])
    d.blank()
    d.section("Pad Templates:")
    for direction, caps in (("SINK", e[9]), ("SRC", e[10])):
        if caps is None:
            continue
        name = direction.lower()
        d.kv(f"{direction} template", f"'{name}'", indent="  ")
        d.kv("Availability", rng.choice(["Always", "Always", "Sometimes"]), indent="    ")
        d.section("    Capabilities:")
        d.line("      " + caps, "row", [caps])
        if caps.endswith("raw"):
            fields = [("format", rng.choice(["F32LE", "{ (string)I420, (string)NV12, (string)YV12 }", "S16LE"])),
                      ("width", "[ 1, 2147483647 ]"), ("height", "[ 1, 2147483647 ]"),
                      ("framerate", "[ 0/1, 2147483647/1 ]")] if caps.startswith("video") else \
                     [("format", rng.choice(["F32LE", "S16LE", "{ (string)S16LE, (string)S32LE }"])),
                      ("rate", "[ 1, 2147483647 ]"), ("channels", "[ 1, 256 ]"), ("layout", "interleaved")]
            for k, v in fields[:rng.randint(1, 4)]:
                d.line(" " * (22 - len(k)) + k + ": " + v, "kv", [k, v])
        d.blank()
    d.skip("Element has no clocking capabilities." if rng.random() < .7 else "Element provides a clock")
    d.skip("Element has no URI handling capabilities.")
    d.blank()
    d.section("Pads:")
    for direction, caps in (("SINK", e[9]), ("SRC", e[10])):
        if caps is None:
            continue
        d.kv(direction, f"'{direction.lower()}'", indent="  ")
        d.kv("Pad Template", f"'{direction.lower()}'", indent="    ")
    d.blank()
    d.section("Element Properties:")
    props = PROPS[:2] + rng.sample(PROPS[2:], rng.randint(1, 5))
    for i, (k, desc, flags, typ) in enumerate(props):
        if i and rng.random() < .3:
            d.blank()
        d.line(f"  {k:<20}: {desc}", "kv", [k, desc])
        d.kv("flags", flags, indent=" " * 24)
        t = typ.format(e=e[0], b=rng.choice(["true", "false"]), n=rng.randint(0, 20000000))
        d.line(" " * 24 + t, "cont", [t])
    d.blank()
    return d
