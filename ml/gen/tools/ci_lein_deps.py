"""`lein deps :tree`: optional Retrieving... download lines, then the
dependency tree as indented `[group/artifact "version"]` vectors (with
`:exclusions [...]` / `:scope "test"` options), optionally preceded by the
"Possibly confusing dependencies found" override report and suggested
exclusions."""
from lib import Doc

TOOL = "lein-deps"

TOP = [
    ("org.clojure/clojure", ["1.10.3", "1.11.1", "1.11.2", "1.12.0"],
     [("org.clojure/core.specs.alpha", "0.2.62"), ("org.clojure/spec.alpha", "0.3.218")]),
    ("cheshire", ["5.11.0", "5.12.0", "5.13.0"],
     [("com.fasterxml.jackson.core/jackson-core", "2.15.2"),
      ("com.fasterxml.jackson.dataformat/jackson-dataformat-cbor", "2.15.2"),
      ("com.fasterxml.jackson.dataformat/jackson-dataformat-smile", "2.15.2"), ("tigris", "0.1.2")]),
    ("clj-http", ["3.12.3", "3.13.0"],
     [("commons-codec", "1.15"), ("commons-io", "2.8.0"), ("org.apache.httpcomponents/httpclient", "4.5.13"),
      ("org.apache.httpcomponents/httpcore", "4.4.14"), ("potemkin", "0.4.5"), ("slingshot", "0.12.2")]),
    ("ring/ring-core", ["1.9.6", "1.10.0", "1.12.1"],
     [("crypto-equality", "1.0.1"), ("crypto-random", "1.2.1"), ("ring/ring-codec", "1.2.0"), ("commons-io", "2.11.0"),
      ("commons-fileupload", "1.5")]),
    ("compojure", ["1.7.0", "1.7.1"],
     [("clout", "2.2.1"), ("instaparse", "1.4.8"), ("medley", "1.4.0"), ("org.clojure/tools.macro", "0.1.5")]),
    ("com.github.seancorfield/next.jdbc", ["1.3.883", "1.3.909", "1.3.939"],
     [("camel-snake-kebab", "0.4.3"), ("org.clojure/java.data", "1.0.95")]),
    ("org.postgresql/postgresql", ["42.6.0", "42.7.3"], [("org.checkerframework/checker-qual", "3.31.0")]),
    ("metosin/reitit", ["0.6.0", "0.7.0"],
     [("metosin/reitit-core", "0.7.0"), ("metosin/reitit-ring", "0.7.0"), ("metosin/reitit-malli", "0.7.0"),
      ("metosin/reitit-swagger", "0.7.0")]),
    ("mount", ["0.1.17", "0.1.18"], []),
    ("com.taoensso/timbre", ["6.2.2", "6.5.0"], [("com.taoensso/encore", "3.62.1"), ("io.aviso/pretty", "1.4.4")]),
    ("aero", ["1.1.6"], []),
    ("hikari-cp", ["3.0.1"], [("com.zaxxer/HikariCP", "5.0.1")]),
]
DEV = [("ring/ring-mock", ["0.4.0"]), ("lambdaisland/kaocha", ["1.87.1366", "1.91.1392"]), ("criterium", ["0.4.6"])]
EXCL = ["[[org.clojure/clojure]]", "[org.clojure/clojure]", "[commons-logging]", "[[commons-codec]]"]


def vec(name, ver, opts=()):
    inner = f'{name} "{ver}"' + "".join(f" {k} {v}" for k, v in opts)
    cells = [name, f'"{ver}"'] + [x for kv in opts for x in kv]
    return f"[{inner}]", cells


def generate(rng):
    d = Doc()
    deps = rng.sample(TOP, rng.randint(2, len(TOP)))
    if rng.random() < .5:
        deps.sort(key=lambda t: t[0])
    chosen = {n: rng.choice(v) for n, v, _ in deps}
    if rng.random() < .3:
        for name, vers, _ in rng.sample(deps, rng.randint(1, len(deps))):
            g, _, a = name.rpartition("/")
            g = g or a
            v = chosen[name]
            for ext in rng.sample(["pom", "jar"], rng.randint(1, 2)):
                d.skip(f"Retrieving {g.replace('.', '/')}/{a}/{v}/{a}-{v}.{ext} from {rng.choice(['clojars', 'central'])}")
    if rng.random() < .25:
        d.skip("Possibly confusing dependencies found:")
        a1, a2 = vec("ring/ring-core", "1.10.0")[0], vec("commons-io", "2.11.0")[0]
        b1, b2 = vec("clj-http", "3.12.3")[0], vec("commons-io", "2.8.0", [(":exclusions", "[[org.clojure/clojure]]")])[0]
        d.line(f"{a1} -> {a2}", "row", ["ring/ring-core", '"1.10.0"', "commons-io", '"2.11.0"'])
        d.skip(" overrides")
        d.line(f"{b1} -> {b2}", "row", ["clj-http", '"3.12.3"', "commons-io", '"2.8.0"', ":exclusions", "[[org.clojure/clojure]]"])
        d.blank()
        d.skip("Consider using these exclusions:")
        t, c = vec("clj-http", "3.12.3", [(":exclusions", "[commons-io]")])
        d.line(t, "row", c)
        d.blank()
    tops = [(n, chosen[n], kids) for n, v, kids in deps]
    tops += [(n, rng.choice(v), []) for n, v in rng.sample(DEV, rng.randint(0, 2))]
    if rng.random() < .3:
        tops.append(("nrepl", "1.0.0", []))
        tops.append(("org.nrepl/incomplete", "0.1.0", []))
    for name, ver, kids in tops:
        opts = []
        if name in [n for n, _ in DEV] or name.startswith(("nrepl", "org.nrepl")):
            opts = [(":scope", '"test"')] if name not in ("nrepl", "org.nrepl/incomplete") else [(":exclusions", "[[org.clojure/clojure]]")]
        elif rng.random() < .15:
            opts = [(":exclusions", rng.choice(EXCL))]
        t, c = vec(name, ver, opts)
        d.line(" " + t, "row", c)
        for kname, kver in sorted(kids) if rng.random() < .7 else kids:
            kopts = [(":exclusions", rng.choice(EXCL))] if rng.random() < .2 else []
            t, c = vec(kname, kver, kopts)
            d.line("   " + t, "row", c)
            if rng.random() < .15:
                g = rng.choice([("org.clojure/tools.reader", "1.3.6"), ("riddley", "0.1.12"), ("borkdude/dynaload", "0.3.5"),
                                ("org.slf4j/slf4j-api", "2.0.9")])
                t, c = vec(*g)
                d.line("     " + t, "row", c)
    return d
