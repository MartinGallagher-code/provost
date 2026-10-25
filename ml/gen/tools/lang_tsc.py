"""`tsc --noEmit --pretty false --extendedDiagnostics`: optional compiler
error lines `file(line,col): error TSnnnn: message`, then aligned
`Key:   value` diagnostics with right-aligned values."""
from lib import Doc, fake

TOOL = "tsc"

ERRS = [("TS2322", "Type 'string' is not assignable to type 'number'."),
        ("TS2345", "Argument of type 'undefined' is not assignable to parameter of type 'string'."),
        ("TS2339", "Property '{p}' does not exist on type '{t}'."),
        ("TS2304", "Cannot find name '{p}'."),
        ("TS2307", "Cannot find module '{m}' or its corresponding type declarations."),
        ("TS7006", "Parameter '{p}' implicitly has an 'any' type."),
        ("TS2531", "Object is possibly 'null'."),
        ("TS18048", "'{p}' is possibly 'undefined'."),
        ("TS6133", "'{p}' is declared but its value is never read."),
        ("TS2554", "Expected 2 arguments, but got 1.")]


def _t(rng):
    return f"{rng.uniform(0, 4) if rng.random() < .8 else rng.uniform(4, 60):.2f}s"


def generate(rng):
    d = Doc()
    if rng.random() < .55:
        for _ in range(rng.randint(1, 10)):
            code, msg = rng.choice(ERRS)
            msg = msg.format(p=rng.choice(["user", "id", "props", "ctx", "data", "e", "config"]),
                             t=rng.choice(["Request", "{}", "UserDto", "Window & typeof globalThis"]),
                             m=rng.choice(["lodash", "@acme/ui", "./utils", "../types/api"]))
            f = rng.choice(["src", "src/components", "src/lib", "test", "packages/core/src"]) + "/" + \
                rng.choice([fake.word(rng), fake.name(rng, "")]) + rng.choice([".ts", ".tsx"])
            pos = f"{rng.randint(1, 800)},{rng.randint(1, 90)}"
            d.line(f"{f}({pos}): error {code}: {msg}", "row", [f, pos, "error", code, msg])
    ext = rng.random() < .7
    files = rng.randint(1, 4000)
    pairs = [("Files", str(files))]
    lines = [("Lines of Library", rng.randint(9000, 60000)), ("Lines of Definitions", rng.randint(0, 300000)),
             ("Lines of TypeScript", rng.randint(10, 400000)), ("Lines of JavaScript", rng.choice([0, 0, rng.randint(1, 9000)])),
             ("Lines of JSON", rng.choice([0, rng.randint(1, 5000)])), ("Lines of Other", 0)]
    if ext:
        pairs += [(k, str(v)) for k, v in lines]
    else:
        pairs.append(("Lines", str(sum(v for _, v in lines))))
    pairs += [("Identifiers", str(rng.randint(1000, 3000000))), ("Symbols", str(rng.randint(1000, 2000000))),
              ("Types", str(rng.randint(100, 900000))), ("Instantiations", str(rng.randint(0, 9000000))),
              ("Memory used", f"{rng.randint(40000, 4000000)}K")]
    if ext:
        pairs += [("Assignability cache size", str(rng.randint(0, 500000))), ("Identity cache size", str(rng.randint(0, 9000))),
                  ("Subtype cache size", str(rng.randint(0, 90000))), ("Strict subtype cache size", str(rng.randint(0, 90000))),
                  ("I/O Read time", _t(rng)), ("Parse time", _t(rng)), ("ResolveModule time", _t(rng)),
                  ("ResolveTypeReference time", _t(rng)), ("ResolveLibrary time", _t(rng)),
                  ("Program time", _t(rng)), ("Bind time", _t(rng)), ("Check time", _t(rng))]
        if rng.random() < .4:
            pairs += [("transformTime time", _t(rng)), ("commentTime time", _t(rng)), ("I/O Write time", _t(rng)),
                      ("printTime time", _t(rng)), ("Emit time", _t(rng))]
        else:
            pairs += [("Emit time", "0.00s")]
    else:
        pairs += [("I/O read", _t(rng)), ("I/O write", "0.00s"), ("Parse time", _t(rng)), ("Bind time", _t(rng)),
                  ("Check time", _t(rng)), ("Emit time", _t(rng))]
    pairs.append(("Total time", _t(rng)))
    kw = max(len(k) for k, _ in pairs) + 1 + rng.choice([1, 2])
    vw = max(len(v) for _, v in pairs) + rng.choice([0, 1, 2])
    for k, v in pairs:
        d.line((k + ":").ljust(kw) + v.rjust(vw), "kv", [k, v])
    return d
