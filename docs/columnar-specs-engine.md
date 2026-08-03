# The `columnar-specs` engine — how it works & how to add a tool

`extract/strategies/delimited/columnar-specs.sh` is a **data-driven columnar
parser**. Instead of a ~50-line bespoke `.sh` strategy per tool, each tool it
handles is **one declarative spec line** describing how to turn that command's
tabular text output into `entryN.field value` records. One engine, many tools.

> **Keep this document current.** Whenever you add a new transform or engine
> feature to support a strategy, update the relevant section here (the spec
> format table, the transform list, or the capability/limitation notes) in the
> same change. This is a required doc, like `CHANGELOG.md` and `HANDOFF.md`.

## Dataset identity — the engine reports the matched tool name

`glean` names a dataset after the **reporting strategy**. To keep each migrated
tool its own dataset (so `mount | glean` → dataset `mount`, not `columnar-specs`,
and two different tools never collide into one dataset), `strategy_detect` sets
the global `_STRATEGY_REPORT_NAME` to the matched spec's tool name. The engine
(`extract/lib/_discovery.sh`) uses it for the dispatch winner, the `matched`
list, and the `STRAT-<name>` record label, falling back to the file's strategy
name when unset (it clears the global before each strategy's detect so a name
never leaks to the next). This must be set in `strategy_detect` (parent shell),
not `strategy_extract` (which runs in a command-substitution subshell, so its
globals would not propagate).

> `free` intentionally stays bespoke: it is the smoke suite's canonical
> end-to-end example (reconciliation, provenance, variants), and migrating it —
> though byte-identical on its sample — perturbs those `glean`-level tests.

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
name <TAB> detect <TAB> header_marker <TAB> delim <TAB> absorb <TAB> minreq <TAB> cols [<TAB> total [<TAB> rowre [<TAB> prefix]]]
```

| # | Field | Meaning |
|---|---|---|
| 1 | `name` | tool name, used only as the record label region |
| 2 | `detect` | `;`-separated tokens that must **all** be present for this spec to match the input (see *Detection*) |
| 3 | `header_marker` | skip every line up to **and including** the first line containing this substring (drops preamble + header row). `-` = headerless (start at line 1). Must not be empty. |
| 4 | `delim` | `ws` (split on whitespace) or `pipe` (split on `|`, trim each cell) |
| 5 | `absorb` | 0-based index of the column that soaks up overflow tokens (joined with `_`) when a row has more tokens than columns (`ws` only); `-1` = none |
| 6 | `minreq` | minimum token count for a row to be accepted (lets trailing columns be optional) |
| 7 | `cols` | comma-separated output column names, each optionally carrying a transform (see *Transforms*) |
| 8 | `total` | optional; `1` (default) appends a `total_entries N` record, `0` omits it — match whatever the bespoke did |
| 9 | `rowre` | optional **per-row accept regex**: a row is processed only if its raw line matches this bash regex. The engine's per-row structural guard, for outputs with footer/note lines that survive the `minreq` filter (e.g. gsutil `TOTAL:`, grafana's trailing note, a `--- ---` rule row). Empty ⇒ every row past the header. To use `rowre` with the default total, set field 8 to `1` explicitly. |
| 10 | `prefix` | optional record-name prefix (default `entry`). Some bespokes label records `jobN` (crontab) / `commitN` (git-log) instead of `entryN` — set this to match byte-for-byte. To use it, fill fields 8 and 9 explicitly. |

### Detection (field 2)

`detect` tokens are split on `;`. **All** must be satisfied for the spec to
match:

- a **plain token** is a substring that must appear anywhere in the input;
- a token written `re:PATTERN` requires **at least one line** to match the bash
  regex `PATTERN`. A single `re:` token keeps its spaces (it is not split on
  whitespace), so `re:^[^[:space:]]+ on .* type ` is one pattern.

**JSON guard.** Before any spec is tried, the engine declines inputs that
`_is_json` classifies as JSON — which includes any text whose first non-blank
line starts with `[` or `{`. So a tool whose output opens with a bracketed
section header (e.g. `php -m`'s `[PHP Modules]`) can **not** be detected by
`columnar-specs` and must stay bespoke. (Symptom: `strategy_extract` works when
the file is sourced alone but the engine reports "No fields extracted", because
the standalone shell lacks `_is_json`.)

Detection is **input-level, not per-row.** Beyond the `rowre` accept guard, the
engine has no per-cell structural guard — every non-blank row past the header with `≥ minreq` tokens becomes an
entry. If a tool's output contains footer/notes lines that would wrongly parse
(e.g. a `TOTAL:` summary, a "Restart …" note), a flat spec cannot yet exclude
them — those tools await a per-row guard transform (see *Limitations*).

**Detection must be specific.** Because every input is tried against every spec
(first match wins in generic mode), a too-greedy `detect` will *steal* other
tools' inputs. Two real examples that the corpus golden run (`tests/corpus/run.sh
--golden`, the collision detector) caught as FAILs:

- `re:^([^|]*[|]){9}` ("≥9 pipes") wrongly matched wide bordered SQL tables;
  fixed by keying on ipmitool's unique sensor-status field
  `re:[|] *(ok|na|nc|cr) *[|]`.
- `re: @ [0-9]` (grafana plugin `name @ version`) wrongly matched CPU-info files
  (`… CPU @ 2.80GHz`); fixed by keying on grafana's header `installed plugins`.

Note a structural limitation: `re:` means **"at least one line matches"**, which
is *weaker* than the guard many bespokes use ("**every** non-blank line matches
this shape"). Tools whose only signature is a shape shared with other tools —
e.g. `composer show`'s `vendor/pkg version description`, which collides with
`docker images`, `go list -m`, `apt list`, crictl/nerdctl image lists — cannot be
told apart by a one-line detect and **stay bespoke** until an *all-lines-match*
detect mode is added. Attempting `composer-show` as a spec hijacked 13 other
tools; it was reverted.

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
| `name@rest` | **terminal** column: soaks every remaining token from its slot, joined with **single spaces** (verbatim internal spacing, unlike `absorb`'s `_`) — e.g. arp-scan's `vendor` = `Raspberry Pi Foundation`. No column may follow it. |
| `name@line` | **sole-column** mode: the value is the whole **trimmed** line (no tokenizing) — for single-column list outputs (module lists, cfg dumps). Use `cols` = one `@line` column; `delim`/`absorb`/`minreq` are ignored for the value. Combine with `header_marker` and `rowre` to drop headers / sub-section lines. |

## Recipe: migrate a bespoke into a spec

0. **Check where the bespoke lives first.** A strategy under
   `strategies/delimited/` or `strategies/structured/` is a **generic multi-tool parser**, not a
   per-tool bespoke — it wins *other* corpus inputs too (e.g. `getconf` also
   tidies `docker-diff` and `nats-stream-ls`). Migrating one 1:1 reproduces only
   its own input and silently regresses the others (the golden run catches it as
   failures on *unrelated* tools). Do **not** migrate generic strategies.
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
positional column maps; one overflow-absorb column; a terminal space-preserving
`@rest` column; optional trailing columns via `minreq`; a per-row accept guard
(`rowre`); the `~sep`, `@opt`, `@unwrap`, `@between`, `@rest` transforms; per-spec
`total_entries` control; substring and regex (`re:`) input detection.

**Does not yet handle** (tools needing these stay bespoke until the feature
lands — ranked by how many tools each would unlock):

- **all-lines-match detect** — require *every* non-blank data line to match a
  shape (not just one). Needed to safely migrate tools whose signature is a
  shape shared with others (`composer-show`, and much of the package/image-list
  family) without hijacking them.
- **transpose / `vertical`** — first field on each line becomes the field *name*
  (key/value outputs folded into one wide record).
- **line prefix strip** — an `@line` variant that strips a leading token/prefix
  (go-list keeps only the first token; cabal-freeze strips `constraints:`; the
  tree tools `systemd-cgls`/`fwupdmgr` strip box-drawing `├─` characters).
- **`delim=tab`** — tab as a first-class delimiter (space-containing 2–3 col
  tables, e.g. the `git-*` family).
- **`@default@<val>`** — placeholder for a missing optional column.
- **mid-row multi-token column** — a fixed-width value with internal spaces that
  is *not* the last column (e.g. nodetool's `145.23 GiB` load); `@rest` only
  covers the terminal column, `absorb` joins with `_`.
- **stateful / continuation rows** — values inherited from a previous row
  (`fuser -v`), or mixed record shapes in one output (`aws s3 ls` objects vs
  `PRE` prefixes).
- **`@split@<delim>`**, **`@keyword`** — split one token into two columns; locate
  a value by a preceding keyword.

## Tools currently migrated into the engine

zypper-search, buildah-containers, lsmem, ss-tulnp, smartctl-attributes, mount,
iostat-d, rabbitmqctl-list-queues, goose-status, ipmitool-sensor,
dpkg-get-selections, gsutil-ls-l, grafana-cli-plugins, bq-ls, arp-scan,
apache2ctl-modules, dub-list, lstopo-no-graphics, lshw-network,
route-6, snap-connections, networkctl-lldp, memcached-stats,
es-cat-allocation, bundle-list, nethogs, slabtop, objdump-headers,
iptables-save, ldconfig-p, perf-top, turbostat, traceroute, crontab,
git-remote, w-sessions, dpkg-list, tar-listing, beegfs.
(See `_COLUMNAR_SPECS` for the authoritative list.)
