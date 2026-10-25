"""SDKMAN! `sdk list <candidate>`: `=` banners around a title, then either
the Java vendor table (pipe-separated, no outer border, vendor shown once
per group) or a grid of versions with `> * +` markers, then a legend or
usage footer."""
from lib import Doc

TOOL = "sdk-list"

RULE = "=" * 80
VENDORS = [("Corretto", "amzn"), ("Gluon", "gln"), ("GraalVM CE", "graalce"), ("GraalVM Oracle", "graal"),
           ("Java.net", "open"), ("JetBrains", "jbr"), ("Liberica", "librca"), ("Liberica NIK", "nik"),
           ("Mandrel", "mandrel"), ("Microsoft", "ms"), ("Oracle", "oracle"), ("SapMachine", "sapmchn"),
           ("Semeru", "sem"), ("Temurin", "tem"), ("Tencent", "kona"), ("Trava", "trava"), ("Zulu", "zulu")]
OTHERS = {"Gradle": (8, 2), "Maven": (3, 3), "Kotlin": (1, 2), "Scala": (3, 2), "Groovy": (4, 3),
          "Spring Boot": (3, 3), "sbt": (1, 3), "Micronaut": (4, 3), "JBang": (0, 3), "Quarkus CLI": (3, 3)}


def jver(rng):
    m = rng.choice([8, 11, 17, 21, 22, 23])
    if m == 8:
        return f"8.0.{rng.randint(282, 402)}"
    return f"{m}.0.{rng.randint(1, 12)}" if rng.random() < .8 else str(m)


def java(d, rng):
    d.skip(RULE)
    d.skip(f"Available Java Versions for {rng.choice(['Linux 64bit', 'macOS ARM 64bit', 'macOS 64bit', 'Linux ARM 64bit'])}")
    d.skip(RULE)
    hdr = ["Vendor", "Use", "Version", "Dist", "Status", "Identifier"]
    w = [13, 3, 12, 7, 10]

    def render(c):
        return " " + " | ".join((c[i] or "").ljust(w[i]) for i in range(5)) + " | " + (c[5] or "")

    d.line(render(hdr), "header", hdr)
    d.skip("-" * 80)
    used = False
    for vendor, dist in sorted(rng.sample(VENDORS, rng.randint(1, 8))):
        vers = sorted({jver(rng) for _ in range(rng.randint(1, 5))}, key=lambda v: [int(x) for x in v.split(".")],
                      reverse=True)
        for i, v in enumerate(vers):
            ident = f"{v}-{dist}" + ("" if rng.random() < .95 else ".fx")
            st = rng.choice(["installed", "local only"]) if rng.random() < .15 else None
            use = None
            if st == "installed" and not used and rng.random() < .6:
                use, used = ">>>", True
            row = [vendor if i == 0 else None, use, v, dist, st, ident]
            d.line(render(row).rstrip(), "row", row)
    d.skip(RULE)
    if rng.random() < .3:
        d.skip("Omit Identifier to install default version 21.0.4-tem:")
        d.skip("    $ sdk install java")
        d.skip("Use TAB completion to discover available versions")
        d.skip("    $ sdk install java [TAB]")
        d.skip("Or install a specific version by Identifier:")
        d.skip("    $ sdk install java 21.0.4-tem")
        d.skip("Hit Q to exit this list view")
        d.skip(RULE)


def grid(d, rng):
    name = rng.choice(list(OTHERS))
    major, parts = OTHERS[name]
    d.skip(RULE)
    d.skip(f"Available {name} Versions")
    d.skip(RULE)
    vs = set()
    for _ in range(rng.randint(4, 40)):
        m = rng.randint(max(0, major - 3), major)
        v = [m, rng.randint(0, 12)] + [rng.randint(0, 9)] * (parts - 2)
        vs.add(".".join(map(str, v)) + (rng.choice(["-RC1", "-M2", "-rc-3"]) if rng.random() < .05 else ""))
    vs = sorted(vs, key=lambda s: [int(x) for x in s.split("-")[0].split(".")], reverse=True)
    rows = -(-len(vs) // 4)
    marks = {}
    for v in rng.sample(vs, min(len(vs), rng.randint(0, 3))):
        marks[v] = rng.choice(["*", "+"])
    if marks and rng.random() < .7:
        marks[next(iter(marks))] = "> *"
    for r in range(rows):
        cells = [vs[c * rows + r] for c in range(4) if c * rows + r < len(vs)]
        text = ""
        for v in cells:
            text += (" " + marks.get(v, "").rjust(3) + " " + v).ljust(20)
        d.line(text.rstrip(), "row", cells)
    d.skip(RULE)
    for sym, what in (("+", "local version"), ("*", "installed"), (">", "currently in use")):
        d.line(f"{sym} - {what}", "kv", [sym, what])
    d.skip(RULE)


def generate(rng):
    d = Doc()
    (java if rng.random() < .6 else grid)(d, rng)
    return d
