# The `columnar-specs` engine — how it works & how to add a tool

`extract/strategies/delimited/columnar-specs.sh` is a **data-driven columnar
parser**. Instead of a ~50-line bespoke `.sh` strategy per tool, each tool it
handles is **one declarative spec line** describing how to turn that command's
tabular text output into `entryN.field value` records. One engine, many tools.

> **Keep this document current.** Whenever you add a new transform or engine
> feature to support a strategy, update the relevant section here (the spec
> format table, the transform list, or the capability/limitation notes) in the
> same change. This is a required doc, like `CHANGELOG.md` and `HANDOFF.md`.

## Why it exists

Dozens of tools emit the same *shape* — a header row (or none) followed by
rows of whitespace- or pipe-delimited columns. Writing a hand-rolled awk
strategy for each is repetitive and grows the strategy count. The engine
absorbs that whole family: adding a tool is a one-line spec, and the tidy output
is **byte-for-byte identical** to the bespoke it replaces (verified at migration
time — see *Verification* below).

## The spec format

Each entry of the `_COLUMNAR_SPECS` array is a single TAB-separated string
(written with `$'…\t…'`):

```
name <TAB> detect <TAB> header_marker <TAB> delim <TAB> absorb <TAB> minreq <TAB> cols [<TAB> total]
```

| # | Field | Meaning |
|---|---|---|
| 1 | `name` | tool name, used only as the record label region |
| 2 | `detect` | `;`-separated tokens that must **all** be present for this spec to match the input (see *Detection*) |
| 3 | `header_marker` | skip every line up to **and including** the first line containing this substring (drops preamble + header row). `-` = headerless (start at line 1). Must not be empty. |
| 4 | `delim` | `ws` (split on whitespace) or `pipe` (split on `|`, trim each cell) |
| 5 | `absorb` | 0-based index of the column that soaks up overflow tokens when a row has more tokens than columns (`ws` only); `-1` = none |
| 6 | `minreq` | minimum token count for a row to be accepted (lets trailing columns be optional) |
| 7 | `cols` | comma-separated output column names, each optionally carrying a transform (see *Transforms*) |
| 8 | `total` | optional; `1` (default) appends a `total_entries N` record, `0` omits it — match whatever the bespoke did |

### Detection (field 2)

`detect` tokens are split on `;`. **All** must be satisfied for the spec to
match:

- a **plain token** is a substring that must appear anywhere in the input;
- a token written `re:PATTERN` requires **at least one line** to match the bash
  regex `PATTERN`. A single `re:` token keeps its spaces (it is not split on
  whitespace), so `re:^[^[:space:]]+ on .* type ` is one pattern.

Detection is **input-level, not per-row.** The engine has *no* per-row structural
guard yet — every non-blank row past the header with `≥ minreq` tokens becomes an
entry. If a tool's output contains footer/notes lines that would wrongly parse
(e.g. a `TOTAL:` summary, a "Restart …" note), a flat spec cannot yet exclude
them — those tools await a per-row guard transform (see *Limitations*).

**Detection must be specific.** Because every input is tried against every spec
(first match wins in generic mode), a too-greedy `detect` will *steal* other
tools' inputs. Example: `re:^([^|]*[|]){9}` ("≥9 pipes") wrongly matched wide
bordered SQL tables; the fix was to key on ipmitool's unique sensor-status field
`re:[|] *(ok|na|nc|cr) *[|]`. The corpus golden run (`tests/corpus/run.sh
--golden`) is the collision detector — a new spec that hijacks another tool shows
up there as a FAIL.

### Row handling (fields 3–6)

1. Blank lines are skipped.
2. Until `header_marker` is seen, lines are skipped (unless headerless `-`).
3. `pipe` rows must contain `|`; cells are split on `|` and trimmed.
   `ws` rows are split on runs of whitespace.
4. Rows with fewer than `minreq` tokens are skipped.
5. `ws` + `absorb ≥ 0` + (tokens > cols): the absorb column soaks the surplus
   tokens, **joined with `_`** (e.g. goose-status folds a multi-word timestamp
   `2026-01-10 12:00:00 +0000` → `2026-01-10_12:00:00_+0000`).

### Transforms (field 7 column suffixes)

| Column syntax | Effect |
|---|---|
| `name` | always emit the token verbatim |
| `~name` | **separator**: consume a token slot (keeping later columns aligned) but emit nothing — e.g. mount's `on`/`type` literals |
| `name@opt` | emit only if the cell is non-empty (optional trailing column) |
| `name@unwrap` | strip one layer of surrounding `()`/`[]`/`{}`/`""` — e.g. `(rw,relatime)` → `rw,relatime` |
| `name@between@L@R` | emit the substring between the first `L` and the next `R` (empty ⇒ skip) — e.g. ss `users:(("sshd",…))` → `sshd` |

## Recipe: migrate a bespoke into a spec

1. **Probe** the bespoke's output to learn its columns and edge cases:
   `mig.sh probe <name>` (dev harness; shows raw + tidy).
2. **Read** the bespoke `.sh` for any per-row filtering or value cleanup — if it
   does something the transforms above can't express, this tool is *not yet*
   migratable (add a transform first, or defer).
3. **Write** a spec line and add it to `_COLUMNAR_SPECS`.
4. **Verify byte-identical** against the bespoke, comparing record *content*
   (the `STRAT-<name>:N` label differs by design): `mig.sh check <name>` →
   must print `IDENTICAL`.
5. **Retire** the bespoke (`git rm extract/strategies/<cat>/<name>.sh`) and
   remove any dedicated `extract/tests/test_strategy_<name>.sh` (or repoint it at
   `columnar-specs`, as `mount` did).
6. **Run the gate** and fix regressions:
   - `tests/corpus/run.sh --golden` — catches detection collisions and
     generic-mode output changes. Where generic mode now (correctly) routes a
     tool through `columnar-specs` and the output improved, **regenerate** that
     tool's golden (`run.sh --update-golden` or write the single file) and
     confirm the new output is the better one.
   - `extract/tests/run_tests.sh`, `tests/smoke.sh`, `transform/tests/test_melt.sh`.

The `mig.sh` harness lives in the scratchpad (dev-only, not shipped).

## Recipe: add a new transform to the engine

1. Add the parsing/emit logic in `columnar-specs.sh` (`_cs_apply` for a
   per-column transform; the row loop in `strategy_extract` for row-level
   behavior; `_cs_matches` for detection features).
2. Keep it **mawk-safe / POSIX-ish bash** — no gawk-only features (CI covers this).
3. Add at least one migrated tool that exercises it, verified byte-identical.
4. **Update this document** — add the transform to the table above and note any
   new spec-field semantics.
5. Run the full gate.

## Capabilities & limitations (current)

**Handles:** header-skip or headerless tables; whitespace or pipe delimiters;
positional column maps; one overflow-absorb column; optional trailing columns via
`minreq`; the `~sep`, `@opt`, `@unwrap`, `@between` transforms; per-spec
`total_entries` control; substring and regex (`re:`) input detection.

**Does not yet handle** (tools needing these stay bespoke until the transform
lands — ranked by how many tools each would unlock):

- **per-row guard** — accept a row only if a cell matches a pattern / reject
  rows by prefix. Needed by tools with footer/note lines (`gsutil-ls-l`'s
  `TOTAL:`, `grafana-cli-plugins`'s trailing note) and the dig/nodetool family.
- **`@rest`** — a final column that keeps the remainder's *internal spaces*
  verbatim (the current `absorb` joins with `_`).
- **transpose / `vertical`** — first field on each line becomes the field *name*
  (key/value outputs folded into one wide record).
- **`@line`** — a single column capturing the whole trimmed line (dependency-tree
  / module-list tools).
- **`delim=tab`** — tab as a first-class delimiter (space-containing 2–3 col
  tables, e.g. the `git-*` family).
- **`@default@<val>`** — placeholder for a missing optional column.
- **`@split@<delim>`**, **`@keyword`** — split one token into two columns; locate
  a value by a preceding keyword.

## Tools currently migrated into the engine

zypper-search, buildah-containers, lsmem, ss-tulnp, smartctl-attributes, mount,
iostat-d, rabbitmqctl-list-queues, goose-status, ipmitool-sensor,
dpkg-get-selections. (See `_COLUMNAR_SPECS` for the authoritative list.)
