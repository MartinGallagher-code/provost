<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Martin J. Gallagher -->

> **Round 4, 2026-10-20:** this file is round 3's `CRITERIA.md`, which is round
> 2's, reused unchanged for round 4 (107 inputs) so the rounds stay comparable.
> It was copied here, and the round-4 set frozen (sha256 of every input in
> `SHA256SUMS`), before the first round-4 input was run through the engine.
> Round 4 adds one recorded column, the `--multi` result rated on the same
> PASS / PARTIAL / FAIL scale, alongside rule 1's same / better / worse.
> Everything below this note is round 3's file from its first line after the
> licence header, byte for byte.

> **Round 3, 2026-10-16:** this file is round 2's `CRITERIA.md`, reused
> unchanged for round 3 (107 inputs) so the rounds stay comparable. It was
> copied here, and the round-3 set frozen, before the first round-3 input was
> run through the engine. Everything below this note is round 2's text,
> byte for byte.

# Round 2 rating criteria — fixed 2026-10-02, before any input was run

Copied unchanged from round 1 (`docs/benchmark-2026-08-12-generalisation.md`)
so the two rounds are comparable. Written here before the first of the 109
inputs was put through the engine.

| | |
|---|---|
| **PASS** | every piece of information in the input is present in the output **and** correctly structured: columns carry real names where the input supplies them, values sit under the right column, prose is not sliced one-column-per-word, nothing is dropped |
| **PARTIAL** | structure is broadly right but something is lost or mis-shaped: a header not applied, a line dropped, a value split or merged |
| **FAIL** | the output **misrepresents** the input: values under the wrong column names, a table shredded, or a substantial part missing |

Rules applied while rating:

1. Judged on **default mode** (`--max-strategies 1`, confidence ranking) — what
   `provost` does with no flags. `--multi` is recorded as `same` / `better` /
   `worse` relative to default, as in round 1.
2. The **priority** column rates the `--rank priority` result on the same
   scale. Where both rankings pick the same strategy the output is identical
   (checked by `cmp`), so the rating is copied.
3. Decoration is not information: banners such as `Oh no! 💥`, rule lines,
   box glyphs and blank lines may be dropped without penalty. A summary line
   that carries numbers (`Found 4 errors in 1 file`, `(7 rows affected)`) is
   information.
4. Where an input genuinely has no header, positional names (`A`, `B`, …) are
   the honest answer and are not marked down.
5. A free-text / help / diagnostic input passes if each logical record (one
   option, one diagnostic, one log event) lands as one row with its parts in
   stable columns; a record split across rows, or prose shredded
   word-per-column, is at best PARTIAL.
6. A multi-section input (several tables, or kv + table) passes in default
   mode only if every section survives; losing a whole section is FAIL if it
   is a substantial part of the input, PARTIAL otherwise.
