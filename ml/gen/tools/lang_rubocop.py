"""`rubocop [--format progress] [--format offenses]`: an inspecting line and
progress dots, offense lines `path:line:col: S: [Correctable] Cop: message`
with source excerpts, the files/offenses summary, and/or the offense-count
table."""
from lib import Doc, fake

TOOL = "rubocop"

COPS = [("Style/StringLiterals", "C", "Prefer single-quoted strings when you don't need string interpolation or special symbols.", True),
        ("Layout/LineLength", "C", "Line is too long. [{n}/120]", True),
        ("Style/FrozenStringLiteralComment", "C", "Missing frozen string literal comment.", True),
        ("Style/Documentation", "C", "Missing top-level documentation comment for `class {k}`.", False),
        ("Metrics/MethodLength", "C", "Method has too many lines. [{n}/10]", False),
        ("Metrics/AbcSize", "C", "Assignment Branch Condition size for call is too high. [<{a}, {b}, {c}> {n}.5/17]", False),
        ("Lint/UselessAssignment", "W", "Useless assignment to variable - `{v}`.", True),
        ("Lint/UnusedMethodArgument", "W", "Unused method argument - `{v}`.", True),
        ("Layout/TrailingWhitespace", "C", "Trailing whitespace detected.", True),
        ("Naming/MethodParameterName", "C", "Method parameter must be at least 3 characters long.", False),
        ("Security/Eval", "W", "The use of `eval` is a serious security risk.", False),
        ("Lint/Syntax", "F", "unexpected token kEND", False),
        ("Rails/OutputSafety", "C", "Tagging a string as html safe may be a security risk.", False),
        ("Style/GuardClause", "C", "Use a guard clause (`return unless {v}`) instead of wrapping the code inside a conditional expression.", True)]
SRC = ["    name = \"{v}\"", "  def call(a, b)", "class {k}", "    eval(params[:code])", "      x = compute(y) ",
       "    if {v}", "  def initialize(opts = {{}})", "    @{v} = opts.fetch(:{v}, nil)"]


def generate(rng):
    d = Doc()
    fmts = rng.choice([["progress"], ["progress"], ["offenses"], ["progress", "offenses"]])
    nfiles = rng.randint(1, 300)
    files = [rng.choice(["app/models", "app/controllers", "lib", "spec", "config", "app/jobs", "lib/tasks"]) + "/" +
             rng.choice([fake.word(rng), fake.name(rng, "_")]) + rng.choice([".rb", ".rb", "_spec.rb", ".rake"])
             for _ in range(rng.randint(1, min(nfiles, 8)))]
    offs = []
    for _ in range(rng.randint(0, 14)):
        cop, sev, msg, corr = rng.choice(COPS)
        msg = msg.format(n=rng.randint(11, 240), k=rng.choice(["User", "OrdersController", "Api::Client"]),
                         v=rng.choice(["result", "opts", "x", "user", "admin?", "tmp"]), a=rng.randint(1, 20),
                         b=rng.randint(1, 20), c=rng.randint(1, 20))
        offs.append((rng.choice(files), str(rng.randint(1, 400)), str(rng.randint(1, 80)), sev,
                     ("[Correctable]" if rng.random() < .7 else "[Unsafe Correctable]") if corr else None, cop, msg))
    if "progress" in fmts:
        d.skip(f"Inspecting {nfiles} file{'s' if nfiles != 1 else ''}")
        marks = ["."] * nfiles
        for o in offs:
            marks[rng.randrange(nfiles)] = o[3]
        s = "".join(marks)
        for i in range(0, len(s), 120):
            d.skip(s[i:i + 120])
        d.blank()
        if offs:
            d.section("Offenses:")
            d.blank()
            for path, ln, col, sev, tag, cop, msg in offs:
                text = f"{path}:{ln}:{col}: {sev}: " + (tag + " " if tag else "") + f"{cop}: {msg}"
                d.line(text, "row", [path, ln, col, sev, tag, cop, msg])
                if rng.random() < .8:
                    src = rng.choice(SRC).format(v=rng.choice(["result", "opts", "user"]), k=rng.choice(["User", "Report"]))
                    d.skip(src)
                    a = rng.randint(0, max(0, len(src) - 2))
                    d.skip(" " * a + "^" * rng.randint(1, max(1, len(src) - a)))
            d.blank()
        corr = sum(1 for o in offs if o[4])
        parts = [f"{nfiles} file{'s' if nfiles != 1 else ''} inspected",
                 f"{len(offs) or 'no'} offense{'s' if len(offs) != 1 else ''} detected"]
        if corr:
            parts.append(f"{corr} offense{'s' if corr != 1 else ''} autocorrectable")
        d.line(", ".join(parts), "row", parts)
    if "offenses" in fmts:
        if "progress" in fmts:
            d.blank()
        counts = {}
        for o in offs:
            key = (o[5], o[4])
            counts[key] = counts.get(key, 0) + 1
        if not counts:
            counts[(rng.choice(COPS)[0], None)] = rng.randint(1, 30)
        items = sorted(counts.items(), key=lambda kv: -kv[1])
        w = max(len(str(sum(counts.values()))), 2) + 2
        for (cop, tag), n in items:
            text = str(n).ljust(w) + cop + (" " + tag if tag else "")
            d.line(text, "row", [str(n), cop, tag])
        d.skip("--")
        tot = str(sum(counts.values()))
        nf = len(set(o[0] for o in offs)) or 1
        tail = f"Total in {nf} file{'s' if nf != 1 else ''}"
        d.line(tot.ljust(w) + tail, "row", [tot, tail, None])
        d.blank()
    return d
