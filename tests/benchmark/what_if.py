#!/usr/bin/env python3
"""What each generalisation option would have scored on rounds 4 and 5.

Reproduces every figure in docs/0004-generalisation-approach.md (PV-006)
from the frozen, already-rated sheets: round4/ratings.tsv,
round4/ratings-learn-cleanup.tsv, round4/ratings-variants-learn-cleanup.tsv
and round5/ratings.tsv. Nothing is run or re-rated; each option is a
counterfactual that takes, per input, the rating another reader already got
on it. Stdlib only:

    python3 tests/benchmark/what_if.py

Every line is PASS / PARTIAL / FAIL out of the inputs counted. "held" means
the rule would send the capture to triage instead of filing it; "filed
wrong" is the FAIL share of what it would still file.
"""

import collections
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
STRATEGIES = os.path.join(HERE, "..", "..", "extract", "strategies")
GRADE = {"FAIL": 0, "PARTIAL": 1, "PASS": 2}
# provost's _quality_exempt: only generic parsers are gated, minus these.
EXEMPT = {"json", "json-array", "jsonl", "yaml", "xml", "toml", "har", "llm-template"}


def load(rel):
    with open(os.path.join(HERE, rel), encoding="utf-8") as fh:
        rows = [line for line in fh if not line.startswith("##")]
    return list(csv.DictReader(rows, delimiter="\t"))


def num(text):
    return int(text) if text.isdigit() else None


def tally(grades):
    c = collections.Counter(grades)
    return f"{c['PASS']:3d} / {c['PARTIAL']:3d} / {c['FAIL']:3d}  of {len(grades)}"


def gated(r):
    s = r["strategy"]
    if s in EXEMPT:
        return False
    return any(os.path.exists(os.path.join(STRATEGIES, d, s + ".sh"))
               for d in ("delimited", "structured"))


def cov_under_95(r):
    c = num(r["cov"])
    return c is not None and c < 95


def unjudged(r):
    return num(r["cons"]) is None


def cons_under_95(r):
    s = num(r["cons"])
    return s is not None and s < 95


HOLD_RULES = [
    ("now: cov<80 or cons<70", lambda r: r["gate_held"] == "yes"),
    ("cov<95 or cons unjudged",
     lambda r: gated(r) and (cov_under_95(r) or unjudged(r))),
    ("cov<95 or cons<95 or unjudged",
     lambda r: gated(r) and (cov_under_95(r) or unjudged(r) or cons_under_95(r))),
]
WIDEST = HOLD_RULES[-1][1]


def line(label, grades):
    print(f"  {label:44s} {tally(grades)}")


def report(name, rows, llm=None, llm_second=None):
    print(f"== {name} (n={len(rows)})")
    held = [r for r in rows if r["gate_held"] == "yes"]
    line("baseline: default engine", [r["rating"] for r in rows])
    line("gate now holds", [r["rating"] for r in held])

    print(" A. --multi on weak signals")
    line("--multi on every input", [r["multi_rating"] for r in rows])
    better = sum(GRADE[r["multi_rating"]] > GRADE[r["rating"]] for r in rows)
    worse = sum(GRADE[r["multi_rating"]] < GRADE[r["rating"]] for r in rows)
    print(f"  {'  --multi better / worse than default':44s} {better} / {worse}")
    line("--multi where the gate holds",
         [r["multi_rating"] if r["gate_held"] == "yes" else r["rating"] for r in rows])
    line("--multi where cov<95 or cons<95 or unjudged",
         [r["multi_rating"] if WIDEST(r) else r["rating"] for r in rows])

    print(" B. signals choose between the readers the engine has (ceilings)")
    line("best of default and --multi",
         [max(r["rating"], r["multi_rating"], key=GRADE.get) for r in rows])
    if "model_rating" in rows[0]:
        line("best of engine and layout model",
             [max(r["rating"], r["model_rating"], key=GRADE.get) for r in rows])
    line("coverage under 95", [r["rating"] for r in rows if cov_under_95(r)])
    line("coverage 95 or more", [r["rating"] for r in rows if not cov_under_95(r)])
    line("coverage and consistency both 95 or more",
         [r["rating"] for r in rows
          if not cov_under_95(r) and num(r["cons"]) is not None and num(r["cons"]) >= 95])

    print(" C. narrow the claim: hold for triage (generic winners only)")
    for label, rule in HOLD_RULES:
        h = [r["rating"] for r in rows if rule(r)]
        f = [r["rating"] for r in rows if not rule(r)]
        wrong = collections.Counter(f)["FAIL"]
        print(f"  {label:32s} held {tally(h)} | filed wrong {wrong} of {len(f)}"
              f" ({100 * wrong / len(f):.0f}%)")

    print(" D. a reader that is not the engine")
    if "model_rating" in rows[0]:
        line("layout model where the gate holds", [r["model_rating"] for r in held])
        line("layout model on every input", [r["model_rating"] for r in rows])
    if llm is None:
        llm = {r["id"]: r["llm_rating"] for r in rows}
    line("--llm where the gate holds", [llm[r["id"]] for r in held])
    line("--llm as the fallback for held captures",
         [llm[r["id"]] if r["gate_held"] == "yes" else r["rating"] for r in rows])
    line("--llm where cov<95 or cons<95 or unjudged",
         [llm[r["id"]] if WIDEST(r) else r["rating"] for r in rows])
    line("--llm first, every input (first contact)", [llm[r["id"]] for r in rows])
    if llm_second:
        line("--llm, second capture of each tool", [llm_second[r["id"]] for r in rows])
    print()


def ratings_by_id(rel):
    return {r["id"]: r["rating"] for r in load(rel)}


report("round 4", load("round4/ratings.tsv"),
       llm=ratings_by_id("round4/ratings-learn-cleanup.tsv"),
       llm_second=ratings_by_id("round4/ratings-variants-learn-cleanup.tsv"))
report("round 5", load("round5/ratings.tsv"))
