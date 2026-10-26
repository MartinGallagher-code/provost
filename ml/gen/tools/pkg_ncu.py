"""npm-check-updates `ncu`: a `Checking .../package.json` line, a progress
bar, then rows of `name  current  →  latest` (versions right-aligned),
optionally grouped under Patch/Minor/Major headings, and a closing hint."""
from lib import Doc

TOOL = "ncu"

PKGS = ["react", "react-dom", "@types/node", "@types/react", "typescript", "eslint", "prettier", "vite",
        "webpack", "webpack-cli", "axios", "lodash", "express", "jest", "ts-jest", "@babel/core",
        "@testing-library/react", "next", "tailwindcss", "postcss", "autoprefixer", "dotenv", "zod",
        "@typescript-eslint/parser", "@typescript-eslint/eslint-plugin", "eslint-config-prettier",
        "nodemon", "concurrently", "vitest", "@vitejs/plugin-react", "date-fns", "uuid", "chalk", "commander",
        "rimraf", "husky", "lint-staged", "mongoose", "pg", "sequelize", "@reduxjs/toolkit", "react-router-dom"]


def gen_pair(rng):
    a, b, c = rng.randint(0, 20), rng.randint(0, 40), rng.randint(0, 30)
    kind = rng.choice(["patch", "minor", "major"])
    if kind == "patch":
        n = (a, b, c + rng.randint(1, 9))
    elif kind == "minor":
        n = (a, b + rng.randint(1, 12), rng.randint(0, 9))
    else:
        n = (a + rng.randint(1, 3), rng.randint(0, 10), rng.randint(0, 9))
    pre = rng.choice(["^", "^", "^", "~", "", ">="])
    cur = f"{pre}{a}.{b}.{c}"
    new = f"{pre}{n[0]}.{n[1]}.{n[2]}"
    return kind, cur, new


def rows(d, rng, items):
    wn = max(len(p) for p, _, _, _ in items)
    wc = max(len(c) for _, _, c, _ in items)
    wv = max(len(n) for _, _, _, n in items)
    for p, _, cur, new in items:
        d.line(f" {p.ljust(wn)}  {cur.rjust(wc)}  →  {new.rjust(wv)}", "row", [p, cur, new])


def generate(rng):
    d = Doc()
    proj = rng.choice(["/home/dev/", "/Users/alice/src/", "C:\\Users\\bob\\code\\", "/srv/app/"])
    proj += rng.choice(["web", "api", "my-app", "dashboard", "cli-tool", "monorepo/packages/ui"])
    sep = "\\" if "\\" in proj else "/"
    upgrade = rng.random() < .25
    d.skip(f"{'Upgrading' if upgrade else 'Checking'} {proj}{sep}package.json")
    n = rng.randint(5, 60)
    d.skip(f"[====================] {n}/{n} 100%")
    d.blank()
    pkgs = rng.sample(PKGS, rng.randint(0, min(n, 16)))
    if not pkgs:
        d.skip("All dependencies match the latest package versions :)")
        return d
    items = [(p,) + gen_pair(rng) for p in pkgs]
    if rng.random() < .3:
        heads = {"patch": "Patch   Backwards-compatible bug fixes",
                 "minor": "Minor   Backwards-compatible features",
                 "major": "Major   Potentially breaking API changes"}
        first = True
        for k in ("patch", "minor", "major"):
            grp = sorted((i for i in items if i[1] == k), key=lambda i: i[0])
            if not grp:
                continue
            if not first:
                d.blank()
            first = False
            d.section(heads[k], heads[k])
            rows(d, rng, grp)
    else:
        rows(d, rng, sorted(items, key=lambda i: i[0].lstrip("@")))
    d.blank()
    if upgrade:
        d.skip("Run npm install to install new versions.")
    else:
        d.skip(f"Run ncu {'--target minor ' if rng.random() < .2 else ''}-u to upgrade package.json")
    return d
