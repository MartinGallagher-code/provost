# Design note 0002 — Tidy-first output, and spreadsheet-style names for nameless columns

- **Status:** Adopted
- **Date:** 2026-07-09
- **Branch:** `claude/project-state-assessment-5x589r`
- **Author:** scoped with Claude
- **Relates to:** [docs/columnar-specs-engine.md](columnar-specs-engine.md) (the migration
  machinery this note reframes the *goal* of)

---

## 1. Summary

Two connected decisions:

1. **Judge output on its own tidy/meaningful merits — not on byte-fidelity to a
   bespoke parser.** For most of this project the yardstick was "does the generic
   parser reproduce the hand-written per-tool parser's bytes exactly?" That yardstick
   makes the bespoke the source of truth and caps generic coverage at whatever the
   bespokes already did. We drop it. The question is now simply: *is the emitted table
   tidy (one row per record, columns cleanly separated, values intact) and usable?*

2. **Name genuinely-nameless columns `A,B,C…,Z,AA,BB,CC…` instead of `c1,c2,c3…`.**
   Same information, better affordance (details in §3).

Neither decision changes how any input is *parsed*. They change what we *measure* and
how we *label*. The practical payoff is that the ~12 generic parsers plus positional
labels already produce tidy, usable output for the overwhelming majority of tools, so
the bespoke-per-tool count can keep falling without chasing byte-parity.

---

## 2. Why drop byte-fidelity as the goal

The `columnar-specs` migration (doc 0001-era work, see the engine note) drove the
strategy count 407 → ~374 by re-expressing bespoke parsers as one-line declarative
specs, each verified **byte-identical** to the bespoke before retiring it. That
discipline was correct *for a migration* — it guaranteed no output changed. But as a
long-term goal it has a ceiling: it treats the bespoke as ground truth, so a generic
parser can never be judged *better* than the bespoke, only *equal*. A close audit put
the clean 1:1 ceiling at ~374 (173 strategies are generic multi-tool parsers that
can't be migrated 1:1 without regressing *other* tools; 158 have no corpus input to
verify against; the rest each need a bespoke engine feature).

The reframe: a tidy table with positional columns is a *good* result even when no
bespoke exists and even when it differs from the bespoke's bytes. Measuring against
"tidy + usable" instead of "byte-identical" removes the ceiling — the generic parsers
are allowed to be the answer.

### Goldens change role, not existence

We keep both golden sets (`extract/tests/golden/`, `tests/corpus/expected/`), but their
job changes from **spec** to **regression snapshot**. They no longer encode "the
bespoke's exact bytes are correct"; they encode "this is the current output — tell me
precisely if it moves." When we *intend* to improve output we regenerate them
(`run.sh --update-golden`, `verify_strategy_outputs.sh --update`); when output moves and
we *didn't* intend it, that diff is a caught bug. This note's own change exercised that:
the `c1→A` rename surfaced as a clean header-only diff on exactly 224 corpus + 17
extract goldens, which is how we proved it touched *only* labels and nothing else.

---

## 3. Nameless columns: `A,B,C` over `c1,c2,c3`

When a source genuinely has no column names (e.g. `aa-unconfined`, `ssh-keygen -l`,
`pacman -Qm`), glean must still label the columns it split out. It used to emit
`c1,c2,c3…`. It now emits `A,B,C…,Z,AA,BB,CC…` (repeated-letter convention past 26).

The information content is identical. The difference is affordance:

- `c1` reads as an **apologetic internal placeholder** — "we tried to name this and
  failed." It looks like a leaked implementation detail.
- `A` reads as the **universal spreadsheet convention** — every user already knows it
  means "unnamed column, in position 1; name it yourself if you want." It signals
  *intended positional labeling*, not *failed naming*.

Implementation: one helper, `_col_letter <1-based index>`, in `extract/lib/_helpers.sh`
(1→A … 26→Z, 27→AA, 28→BB …; self-tested through AAA), wired into the six generic
parsers that mint nameless labels (`aligned-columns`, `colon-fields`, `line-records`,
`text-lines`, `psql-table` header-fallback, `structured/tsv`), the five
`columnar-specs` `@line` specs, and 14 single-column columnar bespokes. Mawk-safe,
POSIX-ish, no new dependency.

---

## 4. What the re-score shows — and what it *doesn't*

A crude tidiness scorer (`score_one.sh`) classifies each tool's generic-mode output as
MEANINGFUL / GENERIC / BLOB / PARTIAL / EMPTY, where "generic" meant a column labeled
`cN`/`entryN`/a bare number. Re-scoring all 1040 corpus tools before vs after the
rename:

| Category   | Before (`c1,c2`) | After (`A,B,C`) |
|------------|:---:|:---:|
| MEANINGFUL | 780 | 1013 |
| GENERIC    | 148 | 7   |
| BLOB       | 92  | 0   |
| PARTIAL    | 19  | 19  |
| EMPTY      | 1   | 1   |

Transition matrix: **141 GENERIC→MEANINGFUL, 92 BLOB→MEANINGFUL, 807 unchanged, zero
regressions.**

**Read this honestly.** The 233-tool flip is *largely a labeling artifact*: the scorer
defined "meaningful" as "the label isn't `cN`," so renaming `cN`→`A` mechanically
reclassifies those columns without changing a single value. What the flip actually
reveals is that the metric was really measuring *"does glean emit an apologetic
placeholder,"* not *"are these columns semantically named."* Removing the placeholder
makes the metric go green — which is a fair signal that the placeholder was the thing
making the output *look* unfinished, but **not** a claim that 233 tools gained semantic
column names. (The 7 tools still scoring GENERIC emit *bare-numeric* keys from a
different path — `json` array-flattening and `indented-hierarchy` — outside this
change's scope.)

---

## 5. The trustworthy signal: an LLM-judge pass

Because the mechanical score can't tell "positionally labeled but tidy" from
"semantically named," we ran an independent LLM-judge validation over a deterministic
21-tool sample drawn from the tools that actually exercise the nameless-column path.
Three blind judges rated each on two orthogonal axes — **tidy** (one row per record,
clean split, values intact) and **usable** (could a user work with this table).
Aggregate: **13/21 tidy, 15/21 usable.**

The decisive finding is *why* the other cases fell short: **every** shortfall is an
orthogonal, pre-existing parser-routing issue that has nothing to do with column
labels —

- colon `key : value` blocks routed to `text-lines` instead of `colon-fields`
  (`chage-l`, `redis-info-memory`),
- a separator token kept as its own noise column (`docker-port`'s `->`,
  `getsebool-a`'s `-->`, `ip-netns-list`'s `(id: N)`),
- space-separated numeric blobs left unsplit (`proc-stat`),
- tree hierarchy flattened (`poetry-show-tree`), and ragged keyword fields (`tc-class`).

None of these are caused — or cured — by the `c1→A` rename; they are the genuine
remaining parser-quality tail. Where the split *is* sensible, the judges confirmed the
positional `A,B,C` output is fully usable (`gsutil-du`, `jq`, `pacman-Qm`,
`ssh-keygen-l`, `rustup-toolchain`, `vault-policy-list`, …).

So: the rename is a **pure affordance win** (same tidy structure, conventional labels,
zero regressions), and it usefully *separates* the "is it labeled well" question from
the "is it parsed well" question — the latter being where the real work remains.

---

## 6. Consequences / direction

1. **Stop chasing byte-parity.** Generic parsers + positional labels are an acceptable
   answer on their own merits. Retire bespokes when the generic output is tidy and
   usable, not only when it is byte-identical.
2. **Goldens are snapshots.** Regenerate freely on intended improvements; treat any
   *unintended* diff as a bug. The scorer is a coarse guard; goldens catch value-level
   drift the scorer can't.
3. **The real backlog is parser routing, not labeling.** The judge pass names the
   concrete tail: colon-block routing, separator-as-noise-column, numeric-blob
   splitting, tree modeling. These are the "meaningful" gaps worth closing next — and
   they are exactly the cases doc `HANDOFF.md`'s parse-wrong clusters already track.
4. **`A,B,C` is now the house convention** for any nameless column; use `_col_letter`
   rather than inventing a placeholder.
