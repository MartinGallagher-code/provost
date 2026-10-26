"""ImageMagick `identify -verbose`: an indented report of nested sections,
`Key: value` leaves, statistics lines with a normalised value in brackets."""
from lib import Doc, fake

TOOL = "identify-verbose"

FORMATS = [("JPEG", "JPEG (Joint Photographic Experts Group JFIF format)", "image/jpeg", "jpg"),
           ("PNG", "PNG (Portable Network Graphics)", "image/png", "png"),
           ("TIFF", "TIFF (Tagged Image File Format)", "image/tiff", "tif"),
           ("GIF", "GIF (CompuServe graphics interchange format)", "image/gif", "gif"),
           ("WEBP", "WEBP (WebP Image Format)", "image/webp", "webp")]


def generate(rng):
    d = Doc()
    fmt = rng.choice(FORMATS)
    fname = rng.choice(["IMG_", "DSC", "photo-", "scan_", "screenshot ", "logo"]) + str(rng.randint(1, 9999)) + "." + fmt[3]
    w, h = rng.randint(16, 6000), rng.randint(16, 6000)
    gray = rng.random() < .2
    alpha = fmt[0] in ("PNG", "WEBP", "GIF") and rng.random() < .5
    I = "  "
    if rng.random() < .5:
        d.section("Image:")
        d.kv("Filename", fname, indent=I)
    else:
        d.kv("Image", fname)
    d.kv("Format", fmt[1], indent=I)
    if rng.random() < .8:
        d.kv("Mime type", fmt[2], indent=I)
    d.kv("Class", "PseudoClass" if fmt[0] == "GIF" else "DirectClass", indent=I)
    d.kv("Geometry", f"{w}x{h}+0+0", indent=I)
    if rng.random() < .7:
        r = rng.choice([72, 96, 300, 240])
        d.kv("Resolution", f"{r}x{r}", indent=I)
        d.kv("Print size", f"{w / r:.5g}x{h / r:.5g}", indent=I)
    d.kv("Units", rng.choice(["PixelsPerInch", "Undefined", "PixelsPerCentimeter"]), indent=I)
    d.kv("Colorspace", "Gray" if gray else "sRGB", indent=I)
    d.kv("Type", "Grayscale" if gray else ("TrueColorAlpha" if alpha else rng.choice(["TrueColor", "Palette"])), indent=I)
    if rng.random() < .5:
        d.kv("Base type", "Undefined", indent=I)
    d.kv("Endianness", rng.choice(["Undefined", "LSB", "MSB"]), indent=I)
    depth = rng.choice([8, 8, 16])
    d.kv("Depth", f"{depth}-bit", indent=I)
    chans = ["Gray"] if gray else ["Red", "Green", "Blue"]
    if alpha:
        chans.append("Alpha")
    d.section(I + "Channel depth:")
    for c in chans:
        d.kv(c, f"{depth}-bit", indent=I * 2)
    d.section(I + "Channel statistics:")
    d.kv("Pixels", str(w * h), indent=I * 2)
    top = 2 ** depth - 1
    for c in chans + (["Overall"] if rng.random() < .3 else []):
        d.section(I * 2 + c + ":")
        mn, mx = rng.randint(0, 40), rng.randint(200, 255)
        mean, sd = rng.uniform(40, 200), rng.uniform(20, 90)
        stats = [("min", str(mn * top // 255), f"({mn / 255:.6g})"),
                 ("max", str(mx * top // 255), f"({mx / 255:.6g})"),
                 ("mean", f"{mean * top / 255:.6g}", f"({mean / 255:.6g})")]
        if rng.random() < .6:
            med = rng.uniform(40, 200)
            stats.append(("median", f"{med * top / 255:.6g}", f"({med / 255:.6g})"))
        stats.append(("standard deviation", f"{sd * top / 255:.6g}", f"({sd / 255:.6g})"))
        for k, a, b in stats:
            gap = rng.choice([" ", " ", "  "]) if k == "min" else " "
            d.line(f"{I * 3}{k}: {a}{gap}{b}", "kv", [k, a, b])
        for k in ("kurtosis", "skewness", "entropy"):
            d.kv(k, f"{rng.uniform(-2, 2):.6g}" if k != "entropy" else f"{rng.uniform(0.3, 1):.6g}", indent=I * 3)
    d.kv("Rendering intent", rng.choice(["Perceptual", "Undefined"]), indent=I)
    d.kv("Gamma", "0.454545", indent=I)
    if not gray and rng.random() < .7:
        d.section(I + "Chromaticity:")
        for k, v in [("red primary", "(0.64,0.33,0.03)"), ("green primary", "(0.3,0.6,0.1)"),
                     ("blue primary", "(0.15,0.06,0.79)"), ("white point", "(0.3127,0.329,0.3583)")]:
            d.kv(k, v, indent=I * 2)
    for k, v in [("Background color", rng.choice(["white", "srgb(255,255,255)", "gray(255)"])),
                 ("Border color", "srgb(223,223,223)"), ("Matte color", "grey74"),
                 ("Transparent color", "black")]:
        d.kv(k, v, indent=I)
    d.kv("Interlace", rng.choice(["None", "JPEG", "PNG"]), indent=I)
    d.kv("Intensity", "Undefined", indent=I)
    d.kv("Compose", "Over", indent=I)
    d.kv("Page geometry", f"{w}x{h}+0+0", indent=I)
    d.kv("Dispose", "Undefined", indent=I)
    d.kv("Iterations", "0", indent=I)
    d.kv("Compression", {"JPEG": "JPEG", "PNG": "Zip", "TIFF": rng.choice(["LZW", "None"]), "GIF": "LZW",
                         "WEBP": "WebP"}[fmt[0]], indent=I)
    if fmt[0] in ("JPEG", "WEBP", "PNG"):
        d.kv("Quality", str(rng.randint(60, 100)), indent=I)
    d.kv("Orientation", rng.choice(["TopLeft", "Undefined", "RightTop"]), indent=I)
    d.section(I + "Properties:")
    props = [("date:create", fake.date(rng, "iso").replace("Z", "+00:00")),
             ("date:modify", fake.date(rng, "iso").replace("Z", "+00:00"))]
    if fmt[0] == "JPEG":
        props += [("exif:Make", rng.choice(["Apple", "Canon", "NIKON CORPORATION", "SONY", "Google"])),
                  ("exif:Model", rng.choice(["iPhone 12 Pro", "Canon EOS 5D Mark IV", "NIKON D750", "Pixel 7"])),
                  ("exif:ExposureTime", f"1/{rng.choice([30, 60, 125, 250, 1000])}"),
                  ("exif:FNumber", f"{rng.choice([18, 28, 40, 56, 80])}/10"),
                  ("jpeg:colorspace", "2"), ("jpeg:sampling-factor", rng.choice(["2x2,1x1,1x1", "1x1,1x1,1x1"]))]
    if fmt[0] == "PNG":
        props += [("png:IHDR.bit-depth-orig", str(depth)), ("png:IHDR.color-type-orig", rng.choice(["2", "6", "3"])),
                  ("png:IHDR.interlace_method", "0 (Not interlaced)")]
    props.append(("signature", fake.hexid(rng, 64)))
    for k, v in rng.sample(props, len(props)):
        d.kv(k, v, indent=I * 2)
    if fmt[0] == "JPEG" and rng.random() < .7:
        d.section(I + "Profiles:")
        for p in rng.sample(["Profile-exif", "Profile-icc", "Profile-xmp", "Profile-iptc"], rng.randint(1, 3)):
            d.kv(p, f"{rng.randint(200, 70000)} bytes", indent=I * 2)
    d.section(I + "Artifacts:")
    d.kv("filename", fname, indent=I * 2)
    d.kv("verbose", "true", indent=I * 2)
    d.kv("Tainted", "False", indent=I)
    d.kv("Filesize", rng.choice([f"{rng.uniform(1, 999):.4g}KB", f"{rng.uniform(1, 30):.4g}MB",
                                 f"{rng.randint(100, 999)}B"]), indent=I)
    d.kv("Number pixels", f"{w * h / 1e6:.6g}M" if w * h > 1e6 else f"{w * h / 1e3:.6g}K", indent=I)
    if rng.random() < .7:
        d.kv("Pixels per second", f"{rng.uniform(1, 400):.5g}MB", indent=I)
    d.kv("User time", f"{rng.uniform(0, 3):.3f}u", indent=I)
    d.kv("Elapsed time", f"0:{rng.uniform(0, 9):06.3f}", indent=I)
    d.kv("Version", rng.choice(["ImageMagick 6.9.11-60 Q16 x86_64 2021-01-25 https://imagemagick.org",
                                "ImageMagick 7.1.1-21 Q16-HDRI aarch64 21593 https://imagemagick.org",
                                "ImageMagick 6.9.10-23 Q16 x86_64 20190101 https://imagemagick.org"]), indent=I)
    return d
