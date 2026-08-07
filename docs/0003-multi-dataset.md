# 0003 — Multi-dataset extraction (`--multi`)

**Status: engine mode shipped (2026-08-04); glean capture adoption shipped
(2026-08-07) — `glean --multi` / `GLEAN_MULTI=1`.**

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

`glean --multi` (also `glean run --multi`, or `GLEAN_MULTI=1`) files every
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
  each row gets its own provenance line, so `glean source N` still returns the
  whole original input. There is one `output.txt`, one commit, one tag.
- `meta.tsv` keeps its existing keys (`strategy`, `confidence`, `dataset`
  become comma-joined) and adds `datasets` (how many) and `dataset_rows`
  (`name:#a..b,…`) when there is more than one.
- A dataset below the confidence threshold is **dropped rather than queued**:
  it is a fragment of an input whose other parts did match, and the whole input
  is stored with the capture regardless. If NO dataset clears the bar the
  capture falls back to the single path, so an unmatched input still reaches
  the `unsorted` triage queue.

`iostat -x` under `glean --multi` files three datasets — the uname banner, the
avg-cpu kv block, and the Device table — where the default capture keeps only
the table. Covered by 7 checks in `tests/smoke.sh` (65 passing).

The corpus golden gate keeps running single-dataset (`--max-strategies 1`);
no goldens changed with this feature.

## Possible next steps

- **Smarter section splitting.** Blank lines are the only boundary today, so an
  input whose sections are marked by indentation or a `Section:` header still
  reads as one block: `proc-slabinfo` (a `# name …` comment header over a
  table, no blank lines) and `kubectl describe` (handled whole by
  `describe-report`) both stay single under `--multi`. Splitting on a *shape
  change* — or on `Section:` headers — would feed the same
  group-extract-emit pipeline and is the highest-value follow-up.
- **Leave-unparsed as a first-class outcome.** A banner or comment run
  currently either finds a weak parse (`version-line` on the uname line) or is
  dropped by the threshold. A `text` dataset kind that keeps such a block
  verbatim, labelled, would match the reviewer's "just left unparsed" case
  exactly.
- Corpus: a `multi` manifest kind for inputs whose right answer is several
  tables (amdgpu-top, iostat family), gating each dataset against its own
  golden.
