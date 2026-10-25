"""Bower `bower list`: an optional `bower check-new` progress line, the
project root, then a box-drawing dependency tree of `name#version` with
annotations such as `(latest is 3.7.0)`, `extraneous` or `missing`."""
from lib import Doc

TOOL = "bower-list"

PKGS = ["jquery", "angular", "angular-route", "angular-animate", "angular-sanitize", "bootstrap", "lodash",
        "underscore", "backbone", "moment", "font-awesome", "requirejs", "d3", "modernizr", "normalize-css",
        "handlebars", "polymer", "webcomponentsjs", "es5-shim", "json3", "chart.js", "select2", "jquery-ui",
        "angular-bootstrap", "angular-ui-router", "ember", "knockout", "socket.io-client", "highlightjs"]


def ver(rng):
    return f"{rng.randint(0, 5)}.{rng.randint(0, 20)}.{rng.randint(0, 15)}"


def note(rng, v, online):
    r = rng.random()
    if r < .08:
        return "extraneous"
    if r < .13:
        return "missing"
    if r < .17:
        return f"incompatible with {v.split('.')[0]}.x"
    if online and r < .55:
        a, b, c = (int(x) for x in v.split("."))
        latest = f"{a + rng.randint(1, 2)}.{rng.randint(0, 20)}.{rng.randint(0, 9)}"
        if rng.random() < .3:
            return f"({a}.{b + rng.randint(1, 5)}.{rng.randint(0, 9)} available, latest is {latest})"
        return f"(latest is {latest})"
    return None


def tree(d, rng, prefix, depth, online, used):
    n = rng.randint(1, 5) if depth == 0 else rng.randint(1, 2)
    for i in range(n):
        last = i == n - 1
        name = rng.choice([p for p in PKGS if p not in used] or PKGS)
        used.add(name)
        v = ver(rng)
        kids = depth < 2 and rng.random() < (.35 if depth == 0 else .2)
        branch = ("└─" if last else "├─") + ("┬ " if kids else "─ ")
        atom = f"{name}#{v}"
        nt = note(rng, v, online)
        d.line(prefix + branch + atom + (" " + nt if nt else ""), "row", [atom, nt])
        if kids:
            tree(d, rng, prefix + ("  " if last else "│ "), depth + 1, online, used)


def generate(rng):
    d = Doc()
    online = rng.random() < .7
    if online:
        d.skip("bower check-new     Checking for new versions of the project dependencies...")
    proj = rng.choice(["myapp", "frontend", "dashboard", "site", "admin-ui", "webclient"])
    path = rng.choice(["/home/", "/Users/", "/var/www/"]) + rng.choice(["dev", "alice", "build", "app"]) + "/" + proj
    root = f"{proj}#{rng.choice(['0.0.0', '1.0.0', ver(rng)])}"
    d.line(f"{root} {path}", "row", [root, path])
    tree(d, rng, "", 0, online, set())
    return d
