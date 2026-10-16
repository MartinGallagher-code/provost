# provost/extract — the extract engine

This directory holds provost's extract engine + all strategies. `provost` runs it
in-process (via the `--emit-meta` contract) to auto-detect the format of captured
output.

The engine sources cross-suite shared libraries (version, progress, pager, …)
from its sibling `../lib` — i.e. **`provost/lib/`**.

**This is first-party provost code — edit it here.** The tree was originally
imported from the Envoy suite's `EnvoyExtract/` project, but it is now maintained
in this repo directly; there is no live upstream sync. Add a new format-detection
strategy under `strategies/` with its sample + golden fixtures, then run the suite:

```bash
bash extract/tests/run_tests.sh     # strategy + engine suite
```

`tools/new_strategy.sh` and `tools/review_strategy.sh` scaffold and check a new
strategy.

## Layout

| Path | Purpose |
|---|---|
| `provost-extract` | engine entry point (invoked internally by `provost`) |
| `lib/` | engine libraries (dispatch, format, postprocess, …) |
| `strategies/` | the 264 format-detection strategies, in 15 category dirs (115 generic format parsers in `delimited/` + `structured/`) |
| `tools/` | strategy-authoring helpers (`new_strategy.sh`, `review_strategy.sh`) |
| `samples/` | sample inputs used by the strategy tests |
| `tests/` | the strategy + engine test suite (`bash tests/run_tests.sh`) |
| `../lib/` (`provost/lib/`) | shared suite libs the engine sources via `../lib` |

## Strategy count

264 strategy files (`ls strategies/*/*.sh | wc -l`): delimited 89, system 58,
network 31, structured 26, security 11, filesystem 8, build 8, misc 7,
database 6, hardware 6, packages 6, scientific 5, cloud 1, container 1,
profiling 1. Re-count after adding or removing one — the number is only true
when it is counted. Every strategy has a `## Sample:` file under `samples/`
and a golden under `tests/golden/`; `tests/verify_strategy_outputs.sh`
fails (rather than skips) when either is missing.

## Writing a strategy: keep detection cheap

Detection runs EVERY eligible strategy's `strategy_detect` on every capture
(see "Candidate ranking" below) — so a slow detector taxes every capture, not
just the ones it wins. Equal priorities are ordered by strategy name (byte
order), never by the category folder. Use the fast helpers from
`lib/_helpers.sh` instead of the slow idioms:

- `_fr_lines "$text"; for l in "${_FR_LINES[@]}"` rather than
  `while IFS= read -r l … done <<< "$text"` (a here-string is read one byte
  per syscall);
- `_fr_tok "$l"; a=("${_FR_TOK[@]}")` rather than `read -ra a <<< "$l"`;
- `_fr_modal` for a modal count — never a nested all-pairs loop;
- `[[ "$l" != *[![:space:]]* ]]` for a blank-line test, and no `$(…)` per line.

When acceptance needs a literal the input must contain, test the whole text for
it first (`[[ "$text" == *LIT* ]] || return 1`) — see the `PREFILTER (exact)`
comments in e.g. `strategies/delimited/box-table.sh`.

### Very large inputs

Above `_FR_SAMPLE_BYTES` (32 KB) detectors see a bounded SAMPLE of the input
(the first 120 / last 40 whole lines, byte-capped, plus MIDDLE WINDOWS — see
below), and a strategy that accepts the sample is re-run on the full text,
which alone decides acceptance and confidence (`lib/_discovery.sh`). So a
detector must never ACCEPT a sample it would reject in full — it cannot, the
full text re-decides — but it can falsely REJECT when its evidence is missing
from the sample; prefer evidence the head carries.

The middle windows exist so that evidence lying only mid-input still reaches
the detectors. Each is a CONTIGUOUS block of whole lines (at most 16 lines /
2 KB), in file order, never overlapping another window or the tail, so a
section title, a header and the rows under it arrive together:

- **even** windows — 4, opening at byte offsets 0, ¼, ½, ¾ of the body
  after the head (a representative slice of a uniform body; the first one
  continues the head);
- **novel** windows — up to 4, opening where a line *shape* first appears
  after the head (first non-blank byte class, field-count bucket, indent,
  which of `: = , |` TAB occur): a section, table or record block that only
  starts mid-input. A novel window opens up to 2 lines early (the title /
  header just above) and stretches to at most 32 lines while new shapes keep
  coming.
- every junction joins whole records, following the structure the head
  shows — group lines over indented children, or blank-separated records:
  an even window not touching the sample so far waits (≤ 16 lines) for a
  record start (not a blank line, not an indented child) or opens back at a
  blank line just above; a window that runs out of lines finishes the record
  in hand (its children / up to its closing blank line, ≤ 32 lines); the
  tail backs up to its record's group line / opening blank line; a blank
  line repeated at a junction is dropped. (Without this the extra junctions
  glued one group's line to another group's children — group-children then
  saw a duplicate key and rejected the sample.)

The sample is a superset of the head + tail one, so an evidence COUNT only
grows; a uniform body adds the even windows alone (its shapes are all in the
head). One awk pass builds it; knobs `_FR_SAMPLE_MID`, `_FR_SAMPLE_NOVEL`,
`_FR_SAMPLE_WIN`, `_FR_SAMPLE_WIN_BYTES`, `_FR_SAMPLE_LEAD` (both counts 0 =
the head + tail sample). Evidence can still be missed when its lines share
their shape with the head (or the four novel windows are spent earlier) and
no even window lands on it — keep such evidence a fallback, not the only
route. `tests/test_big_input_paths.sh` pins the sample's shape and
reproduces a middle-evidence false reject the windows fix.

A detector that decides on a SHARE of the lines it sees ("≥ 40% of lines are
`label: value`", "decline when one token count covers ≥ 60% of lines") can
also land on the wrong side of its threshold on the sample. While a detector
screens the sample the engine sets `_FR_SLACK` to `_FR_SAMPLE_SLACK` (15
percentage points; 0 for the full-text run), and every whole-text share
threshold widens by it in the ACCEPTING direction:

```bash
[[ $(( kv * 100 / nb )) -ge $(( 40 - ${_FR_SLACK:-0} )) ]] || return 1   # needed to accept
[[ $(( kv * 100 / nb )) -ge $(( 60 + ${_FR_SLACK:-0} )) ]] && return 1   # reason to decline
```

The screen only gets looser, never the decision: the full-text run still
decides, so slack can cost a full-text detect but never adds a wrong winner.
`_FR_DET_SAMPLE` is 1 during the same screen, for a check that only means
something on the whole text (proc-net-snmp's header/value pairing skips it on
the sample). A share over a fixed head window (the first 40 / 60 lines) needs
no slack — the sample's head is the full text's head. A new share-threshold
detector must follow the rule (`tests/test_big_input_paths.sh` reproduces the
false reject it prevents).

A JSON/XML document (first non-blank byte `{`, `[` or `<`) is still sampled for the
ordinary detectors, but the document grammars listed in `_FR_DOC_STRATEGIES`
(json, json-array, jsonl, xml, har, yaml, toml) always see it whole — cutting a
document makes it invalid. A plugin that parses whole documents belongs in that
list.

Above `_FR_BIG_BYTES` the hot generic parsers (`aligned-columns`, `csv`,
`syslog`, `equals`, `colons`, `block-records`, `json-array`) and the engine's
own passes switch to awk twins that are byte-identical to their bash loops
(a twin returns 3 to hand an input it cannot match exactly back to the bash
loop), and above `_FR_LANE_BYTES`
the result stays in a file to the end (the FILE LANE). Setting a knob to 0
forces its route on any input — `tests/test_big_input_paths.sh` and the
corpus proofs compare every route with the plain bash one. A new twin must
follow the same rule: same bytes, proven by forcing it over the corpus.

Values keep their spaces: sanitise field NAMES with `_clean_field`, and pass
values through `_clean_value` (never replace a value's spaces with `_`).

### Whitespace tables: the gutter grid

A strategy that splits an aligned table should not split on whitespace
tokens — a cell holding a space (`Number of message queues`, `Oct  2`) or an
empty cell shifts every later value. `_fr_gutter_grid NH RL [PREFIX]`
(lib/_helpers.sh) reads the table's lines on stdin and assigns cells by
character OFFSET: positions blank in the header and in every row are the
gutters between columns, a header label names the segment it sits in, and an
empty span is an empty cell. NH is the number of header lines (0 headerless,
1, or 2 with a group row whose words prefix the names below), RL=1 when a
`----  ----` / `==== ====` rule follows the header. It prints `PREFIX<N>.name
value` lines plus `total_entries N`, or NOTHING when the offsets cannot be
trusted (a TAB header over space rows, an unpadded single-spaced table, a
header repeated as data, misaligned cells …) — keep your old path as the
fallback. Offsets count CHARACTERS, not bytes: a UTF-8 character is one
column, a wide East Asian / emoji character two (what a terminal shows), and
when the offsets do not hold that way the grid retries with every character
one column (tools that pad by character count, such as Go's tabwriter). Cells
come back as the original bytes. aligned-columns (both routes), fixed-width and embedded-table
use it; `tests/test_gutter_grid.sh` pins its behaviour.

## Candidate ranking

`run_auto_strategies` (lib/_discovery.sh) picks the winner in two phases:

1. **Detect.** A `hints.tsv` row, when one matches, is still tried first. Then
   every eligible strategy's `strategy_detect` runs (deprecated, `--generic`
   and `--min-confidence` filters apply), and each one that fires becomes a
   candidate carrying its `_STRATEGY_CONFIDENCE`.
2. **Extract, best first.** Candidates are sorted by confidence (high first),
   then priority (low number first), then strategy name (byte order,
   `LC_ALL=C`), and tried in that order: detect is re-run to restore the
   strategy's detect-time state, then extract. A candidate whose extract is
   empty, or that trips the truncation guard, yields to the next one, so the
   winner always has output. `--max-strategies N` / `--first-match` stop after
   N / 1 candidates produced output. With one winner wanted, the first
   candidate to produce output is HELD when its line coverage is low, and the
   rescue parser gets a turn (see "Line coverage" below), or when its columns
   mix types, and the next candidates get a turn (see "Column-type
   consistency").

`--rank priority` (or `PROVOST_RANK=priority`) restores the historical single pass:
the first strategy in priority order whose detect passes and whose extract is
non-empty wins, and confidence is only compared to thresholds. `--strategy` and
`--replay` pin their own strategy set and always use that single pass. `--multi`
groups blocks by the same ranking (`_multi_detect_name` in lib/_dispatch.sh:
highest-confidence detector, ties by priority then name); being detect-only it
cannot fall through an empty extract, which the per-group extract then does.

**Pruning (exact).** With `--max-strategies 1` / `--first-match` (how provost
calls the engine), a detector whose confidence CEILING cannot beat the best
candidate found so far is skipped without being sourced. The ceiling is the
strategy's `## Confidence-Max: N` header, else the largest literal it assigns
to `_STRATEGY_CONFIDENCE` (and 50); a computed assignment without the header
makes the ceiling 100 — never pruned — so **a strategy that computes its
confidence must declare `## Confidence-Max`** or it forfeits the speed-up. If
the top candidate then extracts nothing, the whole pass is redone unpruned, so
the winner is always exactly the unpruned ranking (`_EAS_NOPRUNE=1` forces the
unpruned pass; `tests/test_rank.sh` pins it, and the corpus was checked
byte-for-byte in full and `--generic` mode). The coverage hold keeps this
exact without a redo: the held claim is the first candidate in rank order to
produce output, which no ceiling ever prunes, and the rescue does not depend
on the other candidates (`tests/test_coverage.sh` compares both runs). The
consistency hold does depend on them — its alternatives rank below the claim
— so when a claim is held for consistency after pruning, the pruned detectors
that could be an alternative (generic, not a catch-all, a ceiling inside the
window) are run then, and every candidate below the claim is tried in the
unpruned ranking's order (no full redo: that cost seconds per held input).
`tests/test_consistency.sh` compares both runs.

## Line coverage, the coverage hold and the rescue parser

Confidence says how sure a detector is of the FORMAT; it says nothing about
how much of the input the extract KEPT. A strategy that recognises one section
of a multi-section report — a `--version` banner over its algorithm lists, the
scalar lines of an environment dump over its path lists, the first block of a
report — claims the whole input at full confidence and drops the rest without
a trace, and the truncation guard (parse SIZE against input size) cannot see
it when the kept part is wide. So the engine measures a second signal:

- **Coverage** (`_parse_coverage`, lib/_discovery.sh) = the share of the
  input's non-blank lines that contributed to the parse: a line contributed
  when more than half of its significant tokens appear in the parse (field
  names count). Tokens split at blanks and `= : , ; |`, quotes, brackets and
  `_`; paths, URLs, dotted versions and dashed names stay whole, so a dropped
  `/home/dev/.conda/envs` is not vouched for by `home` and `envs` elsewhere
  (a dashed token still counts when each dash part is present — a
  `glibc-2.34-60.el9` cut into name and version). Lines the tool marks as
  comments (`#`, `;`) and lines without a token (rules, box art) are not
  counted. One awk pass, no parsing: it can only over-estimate, so a low value
  is conclusive. Measured on inputs up to `_FR_COV_BYTES` (128 KB) — a token
  set of a 10 MB capture costs seconds, and the reports this is for are small;
  above it coverage is `-` (not measured) and nothing changes.
- **Visible.** `--emit-meta` prints it as a 4th field
  (`__EXTRACT_META__<TAB>strategy<TAB>confidence<TAB>coverage`); `--explain`
  shows each matching candidate's `COV` and previews the hold below; `-d`
  logs it per candidate. `provost` records it in the capture's `meta.tsv`,
  prints it after the confidence, and says so when a capture is filed under
  60%.
- **Hold.** With one winner wanted (ranked, `--max-strategies 1` /
  `--first-match` — how provost calls the engine), the first candidate to
  produce output is HELD instead of stored when its coverage is below
  `_FR_COV_MIN` (60) and the input has at least `_FR_COV_MIN_LINES` (6)
  counted lines. Never held: a hint-routed or pinned (`-s`, `--replay`)
  strategy, a structured grammar (json / yaml / xml / toml), a catch-all
  (`text-lines`, `line-records`), a BESPOKE strategy (outside `delimited/` +
  `structured/`, plugins included — tool knowledge whose output is a
  deliberate summary, e.g. systemctl-status without its journal tail; a
  bespoke parse that loses data is fixed in the strategy, as gnu-version
  was), and a TABLE — a parse whose records (3 or more, of 2+ fields) share a
  field: its rows are the dataset, and what it dropped is a banner, a summary
  or another table (`--multi`), not rows a key/value parse could add without
  flattening the table into text.
- **Rescue.** A held claim is offered to the rescue parsers
  (`_FR_COV_RESCUERS`, today `kv-report`): one that covers at least
  `_FR_COV_GAIN` (25) points more wins; otherwise the held claim is stored
  byte for byte as before. Why not simply the next ranked candidate: every
  general parser "covers" a report it cannot read by scattering tokens over
  generic columns (aligned-columns, colons, vertical-line reach ~100%), and a
  corpus trial of that rule turned good parses into worse ones. Coverage says
  THAT lines were dropped, not which parse is right; the rescue parser is
  written for the shape that drops them.
- **`kv-report`** (strategies/structured, rescue only — it never competes in
  the ordinary ranking, where a key/value report is too common a shape to
  claim inputs from more specific parsers): every line of a key/value report
  becomes a row — `key: value` / `key = value` lines, a bare `Label:` over
  indented, bulleted or (apt-style) unindented items (one row per item, the
  label as key), wrapped values folded, path / URL lists as rows, titled
  sections (`**** GPU ****`, underlined titles, a title over deeper lines, a
  short block opener) in a `section` column, right-aligned keys recognised by
  their shared colon column, a `block` index when blank-separated blocks
  repeat their keys. A report that is one record (every key unique) comes out
  as one wide row (`section.key` columns), like the other single-record kv
  parsers; anything else as the long key/value table.

Knobs (internal, like `_FR_BIG_BYTES`): `_FR_COV_BYTES`, `_FR_COV_MIN` (0
disables the hold), `_FR_COV_GAIN`, `_FR_COV_MIN_LINES`, `_FR_COV_CATCHALL`,
`_FR_COV_RESCUERS`, `_FR_COV_FLOOR` (a rescue parser's confidence must reach
min(held confidence, 70)). The truncation guard keeps its own, older token
test (whitespace words) and its size gate; it is unchanged.


## Column-type consistency and the consistency hold

Coverage catches a parse that DROPS lines. A parse can also keep every line
and put values under the wrong headers — a date split over three columns, a
multi-word name spread over Name / Id / Version, a fixed-column cut through
`boost-algorithm`, a `Key:<TAB>value` report read as a two-column table — and
cover ~100%. A person sees at once that "column `Size` holds `Oct`, `2`,
`12:01`" is wrong; the engine measures the same thing:

- **Consistency** (`_FR_CONS_AWK`, lib/_discovery.sh; computed in the same awk
  pass as coverage, on the same inputs up to `_FR_COV_BYTES`). Every cell of a
  record stream (`<label><N>.<field> value`) is typed cheaply: integer,
  decimal, number with a unit (size, rate, duration, percent, `1,234`, `2
  weeks ago`), date / time / datetime, IP / CIDR / MAC / host:port, hex / hash
  / uuid, version, path / URL, flag, digits-and-punctuation (`8,1`, `0:0`),
  word, multi-word text, and rule / box-art debris; empty and null markers
  (`-`, `n/a`, `<none>`) are skipped. Types fall into FAMILIES a column may
  legitimately mix — numeric (integer, decimal, unit), version (version,
  integer, decimal), hex (hash, integer), time, address, digit-punctuation,
  and identifier/text (word, flag, path, hash, version, multi-word text) — so
  a name column of words and phrases, or a version column of `2.0` and
  `1.2.3`, is consistent, while numbers among words, words among numbers or
  times among sizes are not. A dotted quad counts as IPv4 and version, a
  dotted date (`2026.10.13`) as date and calendar version. A column's score is
  the share of its filled cells in its best family; a cell holding a WORD CUT
  IN HALF (an alphanumeric run of 3+ bytes, with a letter, that the input
  never prints — `lgorithm`) and a rule-debris cell count as mismatches. A
  column NAMED for a type (`Version`, `Size`, `PID`, `Created`, `Time` …)
  whose cells are of another family while another column holds that type is
  a header shifted against its cells, and is judged by its name. The parse's
  consistency is the cell-weighted mean over the JUDGED columns: those with
  3+ filled cells, except value columns of key/value lists (named `value`,
  `message`, `description`, `command` …, which are mixed by design). A
  column under 80% is an inconsistent ("mixed") column. No judged column →
  `-`.
- **Visible.** `--emit-meta` prints it as a 5th field
  (`__EXTRACT_META__<TAB>strategy<TAB>confidence<TAB>coverage<TAB>consistency`;
  batch `.meta` files too); `--explain` shows each candidate's `CONS` and
  previews the hold below; `-d` logs it with the number of mixed columns;
  `provost` records it as `consistency` in the capture's `meta.tsv`.
- **Hold.** With one winner wanted, the first candidate to produce output is
  HELD when it is a GENERIC parse (delimited/ + structured/, not json / yaml
  / xml / toml, not a catch-all, not hint-routed or pinned) with at least one
  mixed column and consistency under `_FR_CONS_MIN` (95). A claim held for
  coverage that no rescue replaces is checked the same way. The next ranked
  candidates down to `_FR_CONS_WINDOW` (20) confidence points below it are
  extracted in rank order; the first GENERIC, non-catch-all one that
  - is at least `_FR_CONS_GAIN` (5) points more consistent and itself at
    `_FR_CONS_MIN` or more, with fewer mixed columns,
  - keeps at least as many lines (coverage not lower), and
  - is judged on comparable evidence (at least half the claim's judged
    columns and a third of its judged cells),
  - adds no RECORDS (re-reading the same rows, or gathering key/value pairs
    into records, is a fix; a rule line, banner or multi-line cell turned
    into rows is the scatter a consistent-looking parse is made of), and
  - does not RELABEL: every column name both parses use holds the same type
    family in both (when two parses of one header disagree on what sits
    under `Stratum`, one has shifted the header against the cells, and
    nothing says it is the claim)
  replaces it; otherwise the held claim is stored byte for byte.
- **Why a hold and not a score.** Consistency alone favours parses that glue
  or scatter: two text columns, or every token of a prose line in its own
  column, are perfectly "consistent". So it never ranks; it only decides
  between a claim that visibly mixes types and a nearby candidate that keeps
  the same lines and types its columns at least as well on comparable
  evidence. A BESPOKE claim is never held: tool knowledge may legitimately
  mix types (lsof's NODE column holds `TCP` among inode numbers). On the
  corpus the hold swaps 12 generic-mode winners, almost all a fixed-column
  slicer (`vertical-line`, `fixed-width`) cutting words that the gutter grid
  (`aligned-columns`) reads whole, or `tsv` reading space padding or
  `Key:<TAB>value` blocks as columns.

Knobs (internal): `_FR_CONS_MIN` (0 disables the hold), `_FR_CONS_GAIN`,
`_FR_CONS_WINDOW`, `_FR_CONS_HOLD_BYTES` (32 KB: above it the hold — which
re-runs detection unpruned and extracts alternatives, seconds on a 100 KB
table — is skipped and the measure only reported); the measure itself is
bounded by `_FR_COV_BYTES` (`-` above it) and costs nothing there.

## Confidence rubric

Confidence is a **ranking** signal: it says how conclusive a detector's
evidence is, on one scale shared by every strategy. Priority is the
tie-breaker, i.e. *specificity* — when two strategies have equally conclusive
evidence, the more specific one (lower priority number) wins. Set
`_STRATEGY_CONFIDENCE` in `strategy_detect` by tier:

| Tier | Confidence | What earns it | Strategies |
|---|---|---|---|
| Bespoke, unmistakable | **95** | two or more anchors only that tool prints: an exact banner or title line plus its own header/fields (`INNODB MONITOR OUTPUT` + `History list length`, `Device Descriptor:` + `bLength` + `idVendor`, a zpool `pool:`/`config:` + `NAME STATE READ WRITE CKSUM`) | 38 per-tool strategies — see "Bespoke sub-tiers" below |
| Bespoke, strong signature | **92** | a tool-unique literal or layout (banner, header, fixed field set) only that tool prints | the default for a per-tool strategy outside `delimited/` + `structured/` (97 strategies) |
| Bespoke, distinctive | **88** | distinctive, but a sibling tool or a common format prints the same shape | 12 strategies — see below |
| Grammar | **85** | the whole input validates against a formal grammar, or a strict dialect of one | `json`, `json-array`, `jsonl`, `yaml`, `toml`, `xml`, `csv`, `tsv`, `har`; dialects that must outrank their grammar: `quoted-fields` (CSV), `dns-records` / `columnar-specs` (TSV-shaped), `colon-pairs` (YAML-shaped), `kv-pairs` (CSV-shaped); `pipe-table` / `bracket-log` at their strongest |
| Format-specific generic | **70–85**, default **80** | a distinctive syntax (box drawing, psql rules, dot leaders, tree glyphs, `KEY=VALUE` blocks, blank-line records …) | the other `delimited/` + `structured/` parsers at 80; `equals` 75 when ≥ 90% of lines are tight `KEY=VALUE`; `prefix-message` 72 / 80 / 84 by how much typed prefix its line grammar has (a dated timestamp or `file:line:col` 2 points, level / logger / code 1 …), less a third of the share of lines it does not explain; `help-columns` 82 (≥ 5 aligned entries) or 78. Weak-signature bespoke strategies whose detector is a shape heuristic rather than a tool-unique literal sit at or just under this default (`user-groups` 80, `pkg-config` 79). `kv-report` 70 is RESCUE ONLY — never ranked; it reports 70 when it replaces a held low-coverage claim (see "Line coverage") |
| General structure | **55–69**, scaled | a shape any tabular or kv output has (also `git-log`'s oneline branch, 64: a leading hex token) | `aligned-columns` 60–69 (the 40–75 header/consistency score mapped linearly); `colons` 55–60 by the share of `label: value` lines (40% → 55, 100% → 60); `numeric-lead-records` 60 |
| Catch-all | **≤ 60 (50–55)**, scaled | line structure only | `equals` (weak) 50–55 by the share of assignment lines; `line-records` 50–55 by the share of lines at the modal token count (60% → 50, 100% → 55), 50 for a one-token-per-line list, 51 for a single line; `text-lines` **50** — ranks last, still clears provost's default commit threshold (50) |

### Bespoke sub-tiers

Audited per detector on 2026-10-01 against the corpus. For each one the audit
counted how many inputs it fires on and how many of those it parses tidily
(manifest check), and read what its signature actually requires:

- **95, unmistakable** (38): `ansible-version`, `binnacle-agree`,
  `binnacle-logtriage`, `binnacle-netmesh`, `btrfs-filesystem-show`,
  `bundle-outdated`, `cassandra-nodetool-tpstats`, `doe-analyze`, `doe-info`,
  `doe-power`, `go-test`, `gpg-list-packets`, `iperf-pivot`, `iperf-summary`,
  `iwlist-scan`, `jmap-histo`, `keytool-list`, `lsusb-v`,
  `mariadb-innodb-status`, `mix-deps`, `multipath-ll`, `mx-check`,
  `mx-summarize`, `nft-list-ruleset`, `nodetool-status`, `perf-counters`,
  `proc-devices`, `proc-net-dev`, `proc-net-tcp`, `proc-slabinfo`,
  `resolvectl-query`, `semanage-boolean`, `systemd-analyze-security`,
  `tcpdump-summary`, `top-batch`, `vault-status`, `xfs-info`, `zpool-status`.
- **92, strong** (97): every other per-tool strategy. Its literal or layout is
  the tool's own, even when a closely related tool shares it (`proc-net-tcp`
  also reads `/proc/net/udp`; `iptables-nat` reads any `iptables -L`).
- **88, distinctive but shared** (12): `bcc-funccount`, `bpftrace`, `csvlook`
  (a markdown table has the same rule line), `fleet-host-lines` (a shape shared
  by several orchestrators), `flatpak-remotes`, `git-annex-list`,
  `git-log-graph`, `iperf3-intervals` (common column words), `lastb` (`last`
  prints the same login lines), `pnpm-why` (`pnpm list --depth` draws the same
  tree), `sslscan` (one alternative is just `Accepted` + `bits` + `TLS`),
  `sysstat` (the `(N CPU)` banner heads every sysstat tool, whose own
  strategies outrank it).
- **≤ 80, weak** — shape heuristics, not tool literals: `user-groups` 80 (any
  lone `name : words` line), `pkg-config` 79 (a name + prose line list; it
  yields to every format-specific generic parser at 80), and `git-log`'s
  oneline branch 64 (its full `commit <sha>` form stays 92).

When a detector misfires, **tighten its signature before lowering its
score**. The audit tightened 12 detectors so they stop firing on other tools'
output: `clickhouse-processlist` (column names in the top border — a plain
`┌───┬───┐` box is `box-table`'s; it fired on 55 inputs, 45 of them other
tools' box tables), `proc-net-snmp` (a `Proto:` header line paired with a
same-label value line of equal width, which is what extract needs — it fired on
137 inputs and extracted from 1), `git-log-graph` (a 7+ hex SHA after the `*`
node), `pkg-config` (an all-identifier column header separated only by column
gaps), `lastb` (no `still logged in` / `system boot`; a closing `(HH:MM)`),
`pnpm-why` (`dependencies:` must open a line), `fossil-timeline` (a bracketed
hex check-in hash), `dbmate-status` (a numeric migration version after the
checkbox), `terraform-plan-actions` (a dotted resource address before `will
be`), `sbt-dependencytree` (`+-` on an `[info]` line), `systemd-tmpfiles-cat-config`
(a `# /…/tmpfiles.d/….conf` header), `pipx-list` (`, installed using`).
Where an extract helper is shared with detect, tighten the detector only —
extraction keeps its tolerance.

Rules that keep the tiers honest:

- A score must be **evidence-based**: scale it by a measured share (lines that
  match, column consistency) when the detector already computes one, and never
  hand out a constant above the tier the evidence supports.
- **Nothing below 50 on a winning parse.** Under ranking a sub-50 score ranks
  below `text-lines`, which then claims (and files) the input anyway — so a
  "stay under provost's threshold" score only hands the input to a worse parse.
  (`colons` and weak `equals` were a flat 35 for that reason before ranking.)
- `aligned-columns` never drops below 60 on a table it detects: a header with
  consistent columns beats every catch-all and loose kv shape, and loses to any
  format-specific syntax.
- Ties are resolved by priority, so within a tier keep the priority order
  meaningful (more specific = lower number).
- Calibrate against the corpus: the confidence-ranked winner must pass the
  manifest tidy check, and match the golden unless demonstrably better, on the
  full and the `--generic` candidate sets (`tests/corpus/run.sh --golden`).
  Holdout and benchmark inputs are held-out checks — never fit on them.
