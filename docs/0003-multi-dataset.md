# 0003 — Multi-dataset extraction (`--multi`)

**Status: engine mode shipped (2026-08-04); glean capture adoption deliberately
deferred.**

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

## What was deliberately NOT done

**glean's capture pipeline still stores ONE dataset per capture.** The
`captures/<id>/` layout, `meta.tsv`, melt/analyze, and the corpus harness all
assume one tidy table per input; multi-dataset captures touch every one of
those surfaces (dataset naming, `show`/`export` addressing, review tooling).
That adoption should be its own change with its own review — the engine mode
is the building block, usable today by callers that want it
(`glean run -- iostat -x` piping through `envoy-extract --multi` by hand).

The corpus golden gate keeps running single-dataset (`--max-strategies 1`);
no goldens changed with this feature.

## Possible next steps

- `glean capture --multi` storing `dataset-N.tsv` siblings + a `datasets`
  meta key; `glean show <id>:<n>` addressing.
- Corpus: a `multi` manifest kind for inputs whose right answer is several
  tables (amdgpu-top, iostat family), gating each dataset against its own
  golden.
- Smarter section splitting (indentation-scoped sections, `Section:` headers)
  feeding the same group-extract-emit pipeline.
