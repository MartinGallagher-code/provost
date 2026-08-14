# 0003 — Multi-dataset extraction (`--multi`)

**Status: engine mode shipped (2026-08-04); provost capture adoption shipped
(2026-08-07) — `provost --multi` / `PROVOST_MULTI=1`.**

## The problem

The extract engine's model is one winner per input: strategies compete in
priority order and the first to produce output defines *the* dataset. That is
right for most captures, but some reports genuinely hold **several datasets**:

- `iostat -x` prints an **avg-cpu kv block** *and* a **Device table**. The
  one-winner model keeps the table and drops avg-cpu (the round-9 decision).
- `kubectl describe deployment` holds top-level kv *and* a Conditions table
  *and* an Events table (now handled single-dataset by `describe-report`,
  which welds all three shapes into one wide row-set — lossless but wide).
- `amdgpu-top` is two unrelated tables; the corpus marked it honest-⏳ because
  either choice drops half the data.

The reviewer's design note (2026-08-03): *"an input may deserve MULTIPLE
outputs — for instance a key/value in the same input with a table."*

## The engine mode

`envoy-extract --multi` (conflicts: `--batch`, `--stream`, `--chain`,
`--replay`, `--strategy`, `--interactive`):

1. **Split** the preprocessed input on blank-line boundaries into blocks.
2. **Detect-only pass** per block over the priority-sorted strategy list
   (same filters as auto-detection: `--generic` dirs, deprecation) — each
   block gets a would-be winner name, or none.
3. **Group** consecutive blocks that share BOTH the winner name AND shape
   (modal token count ±1). Name alone is too coarse — iostat's avg-cpu block
   and Device table both detect `aligned-columns`, but at 6–7 vs 16 tokens
   per row they are different datasets. A blank-separated record stream
   (`Package:` blocks) shares name *and* shape, so it re-forms and extracts
   as ONE dataset (block-records needs its blank lines back). A nameless
   block (banner, stray chrome) joins the open group.
4. **Extract** each group independently through the FULL pipeline — hints,
   auto-detection, dedup — exactly as if it were its own input.
5. **Emit** each surviving dataset behind a separator on stdout:

   ```
   __DATASET__ <TAB> n <TAB> strategy <TAB> confidence
   <fields in the -f format>
   ```

   Groups that extract nothing are skipped.

`iostat -x` under `--multi` yields three datasets: the uname banner
(`version-line`), the avg-cpu block, and the Device table — nothing dropped.

Tests: `extract/tests/test_multi_mode.sh` (three-dataset split, record-stream
re-forming, separator format, flag conflicts).

## The capture adoption (2026-08-07)

`provost --multi` (also `provost run --multi`, or `PROVOST_MULTI=1`) files every
dataset an input holds. The rationale, in the reviewer's words: *"one input may
have different types of data — some that fits well as key/value (possibly with
different delimiters), some that fits well into a table, and some that is just
left unparsed (headers or comments) — all from a single input."*

`_ingest` now builds a **list** of datasets and loops over it; the ordinary
one-winner capture is simply the N=1 case, so nothing about the default path
changed. Per capture:

- Each dataset is melted and stored through the normal `_store_append`, so it
  **accumulates across captures, reconciles, and splits into variants** exactly
  like a single-dataset one. Two parts of one input that parse the same way but
  differ in shape land in `NAME` and `NAME.v2` — the store's existing rule does
  the disambiguation, no special naming needed.
- **One capture, N datasets.** Row ids (#N) run consecutively across them and
  each row gets its own provenance line, so `provost source N` still returns the
  whole original input. There is one `output.txt`, one commit, one tag.
- `meta.tsv` keeps its existing keys (`strategy`, `confidence`, `dataset`
  become comma-joined) and adds `datasets` (how many) and `dataset_rows`
  (`name:#a..b,…`) when there is more than one.
- A dataset below the confidence threshold is **dropped rather than queued**:
  it is a fragment of an input whose other parts did match, and the whole input
  is stored with the capture regardless. If NO dataset clears the bar the
  capture falls back to the single path, so an unmatched input still reaches
  the `unsorted` triage queue.

`iostat -x` under `provost --multi` files three datasets — the uname banner, the
avg-cpu kv block, and the Device table — where the default capture keeps only
the table. Covered by 7 checks in `tests/smoke.sh` (65 passing).

## Comment runs: split, and left unparsed (2026-08-07)

Blank lines were the only boundary, which missed a common shape: a `#`-led
legend sitting *directly above* a table with no blank line between it and the
data (`/proc/slabinfo`'s `# name <active_objs> …`). That legend is neither part
of the table nor a table of its own.

A maximal run of `#`-led lines now splits its block into
`[before][comments][after]`, and a comment group never merges with the data on
either side. Such a group is emitted **verbatim** as a `text` dataset — one
`text` column with one ROW per line, confidence 100 — rather than force-fitted to a parser
that would invent columns out of prose, and rather than dropped. This is the
reviewer's "some data that is just left unparsed (headers or comments)" case as
a first-class outcome.

`/proc/slabinfo` under `--multi` now yields three datasets — the
`slabinfo - version: 2.1` banner as kv, the legend as `text`, and the table —
where it previously read as one block. Covered by
`extract/tests/test_multi_mode.sh` (6 checks).

The corpus golden gate keeps running single-dataset (`--max-strategies 1`);
no goldens changed with this feature.

## Sections: why a bare `Header:` is NOT a boundary (tried, reverted 2026-08-07)

The obvious next boundary looks like the section header. `kubectl describe` has
no blank line anywhere: a top-level kv block runs straight into `Conditions:`
and `Events:`, each a bare `Header:` at column 0 over an indented table. Adding
"a bare `Header:` whose next line is indented opens a sub-block" was
implemented and it did split that input three ways — and made the result
**worse**:

| | whole input | split into sections |
|---|---|---|
| kubectl-describe-deployment | `describe-report` @85, all three shapes parsed together | `protobuf-text` @80 (mangled keys), `aligned-columns` @70, `indented-hierarchy` @65 (Message column shredded) |

The cause is ordering: splitting happens *before* detection, so a strategy
written to handle the sections **together** never sees the whole input.
`describe-report` exists precisely because those sections belong to one report
(it slices each `Section:` table at its `----` separator positions). Dedenting
the section bodies first does not rescue it — `fixed-width` then wins on Events
and truncates values to the `----` widths.

Guards that were considered and rejected:

- *"Don't split if a bespoke strategy claims the whole block."* `describe-report`
  lives in `strategies/delimited/`, so it is classified GENERIC — the
  generic/bespoke line does not separate these cases.
- *"Don't split if any strategy detects the whole block."* Far too broad:
  `colons` detects almost any kv-ish block, so this suppresses nearly every
  useful split.
- *"Split only when the sections detect different strategies."* True for
  kubectl-describe as well (three different winners), so it does not
  discriminate.

The distinguishing fact — that `describe-report` already accounts for every
section while `iostat` accounts for only the Device table — is not visible from
any signal the engine currently has. Note that this costs the `iostat` family
nothing: its sections are already separated by BLANK LINES, so they split
before a section rule would ever apply.

A future attempt needs a **coverage measure**: how much of the input's content
the whole-block parse actually accounts for, compared with the sum of the
section parses. Split only when the whole-block parse leaves data on the floor.
That is a real piece of work, not a heuristic tweak.

## Possible next steps

- **Coverage-driven section splitting** (see above) — the principled version of
  the reverted experiment.
- Corpus: a `multi` manifest kind for inputs whose right answer is several
  tables (amdgpu-top, iostat family), gating each dataset against its own
  golden.
