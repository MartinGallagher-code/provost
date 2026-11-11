# Held-out generalisation benchmark, round 4: 107 inputs nobody had parsed

**2026-10-20.** This round put 107 tool outputs through the current engine:
`VERSION` 2.1.0 plus the 2026-10-16 fix round, the 2026-10-20 engine-defect
fixes and the 2026-10-20 quality gate (CHANGELOG). None of the inputs appear in
the corpus, the holdout, round 1, round 2 or round 3. The set was built,
novelty-checked and frozen, with the sha256 of every input recorded and round
3's criteria copied over unchanged, before the first input was run. Each
result was then rated once in default mode and once under `--multi`.

**This is the first honest generalisation measurement of the 2026-10-16 fix
round and of the 2026-10-20 engine work.** Round 3's postscript measured the
fix round on inputs it had not been developed against, but round 3 has since
been named defect by defect. Round 4 measures the engine on inputs nobody had
looked at. It is also the baseline for the next planned change, which makes
`--multi` segmentation the default when the quality signals are weak, so every
input carries a `--multi` rating as well.

As in rounds 1 to 3, **the rating is a self-assessment by an agent. Treat it
as a screen, not a verdict.**

Everything is in the repo:

- the inputs:
  [`tests/benchmark/round4/inputs/`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/inputs)
- where each input came from:
  [`round4/manifest.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/manifest.tsv)
- the sha256 of every frozen input:
  [`round4/SHA256SUMS`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/SHA256SUMS)
- the criteria, reused unchanged and frozen before the run:
  [`round4/CRITERIA.md`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/CRITERIA.md)
- the rating for each input:
  [`round4/ratings.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/ratings.tsv)
- the novelty check:
  [`round4/novelty.py`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round4/novelty.py)
- the runner: `bash tests/benchmark/run.sh --round4`

## Headline

| | round 4 (n=107) | share | round 3 on 2.1.0 (n=107) | round 3 after the fix round | round 2 at first rating (n=109) |
|---|---:|---:|---:|---:|---:|
| PASS | 12 | **11%** | 21% | 21% | 16% |
| PARTIAL | 51 | **48%** | 42% | 45% | 47% |
| FAIL | 44 | **41%** | 37% | 35% | 38% |
| usable (PASS + PARTIAL) | 63 | **59%** | 63% | 65% | 62% |
| `--multi`, same scale | 12 / 64 / 31 | 11% / 60% / 29% (71% usable) | not rated | not rated | not rated |

**On output it has never seen, the current engine gets one input in nine
fully right, three in five are usable, and two in five come out wrong.**

This is no better than any earlier first rating. The PASS share is ten points
below round 3's and five below round 2's. The FAIL share is four points above
round 3's at 2.1.0 and six above round 3's re-rating. The sets are different
and not paired, and at n≈107 the 95% margin on a share near 40% is about ±9
points, so the FAIL rise is within noise. The PASS drop (21% to 11%) is
larger than the ±7-point margin on a share near 15%, so it is probably real
for this kind of set. Part of it is the set: round 4 has fewer simple key/value records (7
against 10) and no box tables, which were round 3's easiest families. Part of
it may be the rater: one agent applied the six rules strictly throughout (see
[Rating](#rating)). Neither explains away the main finding. **The fix round's
gains on round 2 and round 3 did not carry over to fresh output.**

Under `--multi` the same inputs score 12 / 64 / 31. Segmentation turns 14
default FAILs into PARTIALs and costs two inputs one grade each. It makes no
input fully right that was not already right, apart from one.

## Method

### The set: 65 captured, 42 reproduced

| | n | what |
|---|---:|---|
| **captured** (001–065) | 65 | real output of read-only commands run in the 2026-10-20 build container, on scratch C, Java, Go, Python, Ruby, Perl, PHP and JS projects, a scratch 64 MiB ext4 image, a scratch `redis-server` on a private port and a scratch JVM: LLVM and clang (`-ast-dump`, `-fdump-record-layouts`, `-ftime-report`, `llvm-mca`, `llvm-readobj`, `llvm-dwarfdump`, `llc -mattr=help`, `diagtool tree`), lldb, gcov, gprof, valgrind helgrind, bison, CMake `--trace-source`, ninja `-d stats`, `go build -x`, `go doc`, golangci-lint, JDK tools (`javap`, `jstack`, `jcmd VM.metaspace`, `jhsdb jmap`, `-Xlog:gc*`, `jfr`, `jlink`), Python modules (`ast`, `pickletools`, `pyclbr`, `zipfile`, `pydoc`, warnings, chained tracebacks), pytest `-rA`, pygmentize, `ruby --dump=insns`, `bundle env`, `perl -MO=Concise`, podchecker, `php --rc`, `composer list`, `node --trace-gc`, `bun test`, `redis-cli --bigkeys` and `--stat`, `pg_test_fsync`, `pg_test_timing`, `postgres --describe-config`, `e2freefrag`, `fc-match -v`, `gio info`, `infocmp`, `stty -a`, `dircolors -p`, `xmllint --debug`, `zipdetails`, `prtstat`, `systemd-analyze syscall-filter`, `systemd-delta`, `tmux show-options`, `vim --startuptime`, `apt-get -s` |
| **reproduced** (101–142) | 42 | written by hand to each tool's documented output format, for platforms the container does not have: Windows (`tasklist /v`, `whoami /priv`, `schtasks /query /fo LIST /v`, `bcdedit /enum`, `gpresult /r`, `quser`, robocopy log); macOS (`diskutil info`, `ioreg`, `mdls`, `xcrun simctl list`); network gear (Junos `show interfaces terse`, Cisco `show mac address-table` and `show processes cpu sorted`, Huawei `display interface brief`, PAN-OS `show session all`, RouterOS `/interface print detail`, F5 `tmsh show ltm pool`); databases (Teradata BTEQ, Informix `onstat -d`, SQL Server `sp_who2`, Sybase `sp_helpdb`, Firebird `SHOW TABLE`); AIX `errpt` and `lsattr -El`, HP-UX `ioscan`, z/OS IDCAMS `LISTCAT`, IBM i `WRKSYSSTS`; Grid Engine `qhost`, HTCondor `condor_q`, Kraken 2 report, Picard metrics; `juju status`, `kops validate cluster`, kubelet klog; TeamCity and GitLab CI logs; `apcaccess`, HPE `ssacli`; Rails log, Zeek `conn.log`; TeamSpeak ServerQuery |

The set was chosen for shape diversity before any input was run:

- aligned tables with spaces in cells, empty cells, two-word headers and
  grouped two-row headers;
- non-ASCII cells: German, Polish, Czech, Russian, Japanese and French names,
  in tables, logs, key/value reports and trees;
- multi-section reports (24 inputs);
- banners, titles, echoed prompts, legends and footers;
- diagnostics and logs with continuation lines (19);
- help text and grouped lists;
- key/value reports with lists, and nested indentation (trees by indentation,
  by connector glyphs and by braces).

No input was chosen, edited or dropped because of how provost might parse it.
Two Windows reproductions follow their tools' real quirks on purpose:
`schtasks /fo LIST` repeats a task block once per trigger, and robocopy writes
tab-indented file lines.

**Scrubbing (captured inputs).** Scratch paths became `/home/dev/{src,ledger,
tally,pricing,cart,slug,inventory,work}`, the Go build cache became
`/home/dev/.cache/go-build`, and the scratch `HOME` became `/home/dev`. Every
Java tool ran with the container's `JAVA_TOOL_OPTIONS` (proxy settings) unset.
No environment dump, network address of the container, hostname or secret was
captured; one capture (`gio info`) shows the root filesystem's mount options.
One scrub artefact was found after the freeze and left in place: in the CMake
trace (009) the scratch path reads `/home/dev/srcm`, because the replacement
for `.../w/c` also matched `.../w/cm`. It changes no shape. **No git command
was run to make any input.** **Reproduced** inputs use invented values, the
RFC 5737 documentation ranges and `example.com`. One reproduction (the GitLab
log) keeps the CR and ANSI erase codes that GitLab writes into raw job logs.

Several captures are truncated with `| head -N`, as such output is usually
pasted. The manifest records every exact command.

### Novelty: how "never seen" was checked

`round4/novelty.py` is round 3's script, extended to compare against round 3's
inputs as well. It compares every input with all 4,067 existing inputs:
`tests/corpus/inputs` (3,705), `tests/corpus/holdout/inputs` (80),
`tests/corpus/text-inputs` (16), round 1 (50), round 2 (109) and round 3
(107). It checks the tool-and-mode name stem and the Jaccard similarity of
normalised line sets and word 3-gram sets.

Tools were picked from what the corpus and earlier rounds do not use. A
name screen of the candidate list against all 4,006 existing stems removed
14 candidates before any was captured: `capsh --print`, `ldconfig -p`, a LAMMPS
log, BLAST tabular, bowtie2 and STAR summaries, FastQC, LDIF, `exim -bp`,
`knife node list`, LSF `bjobs`, `zipinfo`, CDO `sinfo` and OpenVPN status all
had a corpus entry. 58 of the 107 inputs come from a tool whose name begins no
existing input. The other 49 are a new mode of a tool that appears elsewhere
(`clang -ftime-report` against `clang -Wall`, `python -m pickletools` against
other `python -m` modules) or a new tool behind a known platform prefix
(`windows-`, `macos-`, `cisco-`, `zos-`).

Before the set was frozen, the content screen over 114 candidates dropped
one close relative, and six more were dropped for balance:

- `make --debug=b -n`: 3-gram 0.14 against round 2's `gpg --version`, all of
  it from the shared GNU licence banner;
- `debugfs ls -l`, `update-alternatives --get-selections`, `pkg-config
  --list-all`, `opt -print-passes`, `jdeps -verbose:class` and `corelist -a`
  were dropped to keep the captured share near 60% and the tool list varied
  (three of them are new modes of tools round 2 or 3 already used).

**In the final set no input clashes by name, and the highest 3-gram
similarity is 0.09** (`pg_test_timing` against a corpus `xfs_db freesp`
histogram, and the Picard metrics against a turbostat table: shared column
words). The next highest are 0.07 and 0.06, and 104 of the 107 inputs are at
0.06 or below. **The highest line-set figure is 0.07** (pytest `-rA` against
round 3's `pytest --setup-plan`, which share the session-header lines, and
HP-UX `ioscan` against a tinymembench capture). These are shared boilerplate,
not shared content.

**Nothing was tuned.** No engine, strategy, hint or parser file was touched.
The only code change in this round is to the benchmark runner (`run.sh
--round4`).

### Run

One run, after the freeze: `bash tests/benchmark/run.sh --round4 --tidy -j 2`.
It took 7 min 3 s on a shared 4-core box. Default mode (`--max-strategies 1`,
confidence ranking) was melted to the tidy table and rated. `--multi` was
melted per dataset and rated on the same scale. `--rank priority` was recorded:
it picks a different winner on 9 inputs and gives byte-identical output (`cmp`)
on the other 98. The default `.meta` files give line coverage (4th field) and
column-type consistency (5th).

**The quality gate.** `provost` holds a capture for triage when its winner is
a generic parser (under `extract/strategies/{delimited,structured}`, except
json, json-array, jsonl, yaml, xml, toml and har) and it keeps under 80% of
the lines or its columns are under 70% type-consistent (`_quality_exempt`, the
defaults). `run.sh` calls the engine directly, so the gate does not run; the
`gate_held` column applies the rule to each input's `.meta`. 106 of the 107
winners are generic; the one exempt winner is `yaml`. No input was no-match or
under the confidence threshold.

### Rating

Each input was rated PASS, PARTIAL or FAIL from the input and its default
tidy table, strictly by `CRITERIA.md` and its six rules, which are round 2's
words byte for byte. Where a call could go either way, it was made the way
round 3 made the comparable call:

- a first data row promoted to the header is PARTIAL;
- a non-data line (banner, prompt, title, legend, page header) promoted to
  the header, with values then under its words, is FAIL;
- sections glued into one cell, or records flattened into one wide record
  whose column names are built from content, are FAIL;
- a free-text fallback that keeps every line is PARTIAL.

Round 4 needed four calls round 3 did not:

- a dropped prose footer with no numbers (a usage hint) is PARTIAL, not PASS:
  rule 3 lets decoration go, not sentences;
- a value altered in place (double quotes stripped from inside a text) is
  PARTIAL;
- a tree kept as depth / name / parent, with the node's own fields unsplit, is
  PARTIAL; with atomic node names it can PASS;
- a `--multi` output in which a substantial dataset puts values under the
  wrong column names is FAIL, even if other datasets are right.

The `--multi` output was judged as a whole: every dataset melted and read
together against the input, with rule 6 (every section must survive) applied
across the datasets. `ratings.tsv` gives a one-line reason for every input.

## Results

### By shape family, default against `--multi`

| family | n | default PASS / PARTIAL / FAIL | usable | `--multi` | usable | multi better / worse | round 3 on 2.1.0, usable | round 3 after the fix round, usable |
|---|---:|---|---:|---|---:|---|---:|---:|
| aligned / fixed-width table | 26 | 7 / 10 / 9 | 65% | 6 / 12 / 8 | 69% | 1 / 1 | 67% | 70% |
| multi-section report | 24 | 0 / 12 / 12 | **50%** | 1 / 17 / 6 | **75%** | **7 / 0** | 25% | 25% |
| log and diagnostic lines | 19 | 1 / 10 / 8 | 58% | 1 / 10 / 8 | 58% | 1 / 1 | 54% | 63% |
| list, grid, help text, free text | 11 | 2 / 6 / 3 | 73% | 2 / 7 / 2 | 82% | 1 / 0 | 71% | 71% |
| structured data (trees, dumps) | 10 | 0 / 8 / 2 | 80% | 0 / 8 / 2 | 80% | 0 / 0 | 33% | 33% |
| key/value blocks (several records) | 10 | 0 / 3 / 7 | **30%** | 0 / 8 / 2 | **80%** | **5 / 0** | 82% | 82% |
| single key/value record | 7 | 2 / 2 / 3 | **57%** | 2 / 2 / 3 | 57% | 0 / 0 | 100% | 100% |

- **Key/value output no longer generalises.** Round 3's best families were
  key/value: no single record failed and only two of eleven multi-record
  inputs did. Here three of seven single records fail and seven of ten
  multi-record inputs do. The failing records are near-misses for a
  key/value grammar: a `name = value` list with multi-line arrays, a
  semicolon-separated `name = value` line, and a report whose keys contain
  spaces above an indented attributes block. Of the seven failing block sets,
  three are claimed by `block-records`, two lose their first line to the
  header, and `yaml` and `tsv` claim one each.
- **Multi-section reports are the only family that improved**, from 25% to
  50% usable, but still with no PASS. Eight of its 12 PARTIALs are
  `text-lines` fallbacks that keep every line and split nothing.
- **Whitespace tables and log lines are unchanged** within noise: 65% and 58%
  usable, against 67% and 54% in round 3.
- Structured data looks better (80%) only because this round's ten are mostly
  indentation and connector trees, which `indent-tree` keeps as depth /
  parent. None passes; the fields inside each node are never split.

### By category and provenance

| category | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| language tooling | 24 | 2 | 16 | 6 |
| build | 16 | 1 | 6 | 9 |
| system (desktop, Windows, macOS admin) | 15 | 1 | 9 | 5 |
| database | 10 | 1 | 6 | 3 |
| storage | 7 | 2 | 2 | 3 |
| network (Junos, Cisco, Huawei, PAN-OS, RouterOS, F5) | 7 | 0 | 2 | 5 |
| test / lint | 6 | 0 | 3 | 3 |
| mainframe / legacy Unix | 5 | 1 | 1 | 3 |
| scientific / HPC | 4 | 2 | 1 | 1 |
| k8s | 3 | 1 | 1 | 1 |
| shell, CI, logs | 2 each | 0 | 1 each | 1 each |
| package manager, data format, monitoring, game server | 1 each | 1 (monitoring) | 1 (data format) | 2 |

By provenance: **captured** inputs scored 5 PASS, 37 PARTIAL and 23 FAIL (65%
usable). **Reproduced** inputs scored 7 PASS, 14 PARTIAL and 21 FAIL (50%
usable). Network-gear output is again the weakest category: 0 PASS of 7, as
in round 3. Three of its five FAILs start with an echoed device prompt.

### What passes

These 12 came out fully right:

- **tables:** AIX `errpt`, Grid Engine `qhost`, `whoami /priv`, `redis-cli
  --stat` (grouped header kept as a title), the `jfr summary` event table
  (with its key/value header carried on every row), Python's `zipfile -l`;
- **headerless tab data:** the Kraken 2 report, indentation of the taxon name
  kept;
- **key/value:** `apcaccess status`, `diskutil info`;
- **help and trees:** `composer list`, `diagtool tree` (indent-tree);
- **logs:** kubelet klog (`prefix-message` with the multi-line `err=<` block
  as detail).

Every one of them is a single, well-delimited shape with real column names,
or one honest key/value record. No multi-section report, key/value block set
or structured dump passes in default mode.

## Top failure patterns

These are directions for parser work, not a punch list. Fixing them against
these files would turn round 4 into a second corpus. Validate any fix against
fresh inputs. The 44 FAILs fall into five patterns.

### 1. Nested or sectioned text flattened into one record or sparse rows (17 FAIL)

`block-records` (8 wins, 8 FAIL), `indented-hierarchy` (4 wins, 4 FAIL),
`protobuf-text`, `kv-pairs`, `grouped-rows`, `yaml` and `equals` read a
report of nested or repeated blocks as one record. Column names are built
from content lines (a thread header, a controller line, a log sentence, a job
row's first words); repeated keys get `_2`, `_3` suffixes; the block's identity
(function, file, member, drive, client) is dropped; lists become a single
token. This was round 3's pattern 2 and is now the largest. Ten of the 17 are
under 80% coverage, so the gate holds them.

### 2. A non-data line becomes the header (15 FAIL)

The line above the data is promoted to the header and every value then sits
under its words: an echoed device or SQL prompt (five inputs), a tool banner,
a report or page title, a block title, a legend, a comment heading, a status
line, or the first log line of a different kind. Fourteen of the 15 cover 95%
or more of the lines and none is held by the gate. This is round 3's pattern
1, still unsolved for prompts, legends and page headers; three of the 15 are
network gear.

### 3. One section claimed, the rest dropped (6 FAIL)

`embedded-table`, `indented-colon-groups` and `vertical-line` keep one table
(or two lists) and drop everything else, at 20% to 60% coverage. All six are
held by the gate, and `--multi` recovers three of them to PARTIAL.

### 4. Fixed-column slicing or a wrong split (4 FAIL)

`vertical-line` still cuts values mid-word when a row is wider than the
header layout (two inputs, plus the result table of a third, which sits in
pattern 3). `kv-report` splits a `name = value; name = value` line at the
first `=`. `key-value` glues a whole bytecode listing into one cell.

### 5. Whitespace-table alignment (2 FAIL)

Empty cells shift the rest of a row one column left, and two-word headers are
split into one-word columns; and five stacked tables are read under the first
table's header.

### The PARTIAL ceiling

Of the 51 PARTIALs, 18 are `text-lines` fallbacks that keep every line and
split nothing: test runners, CI logs, compiler reports, GC logs, an interface
table behind a legend, three tab-separated tables under titles. Round 3 had
11. Five more keep a tree as depth / parent (or attribute rows) without
splitting the node's fields, three promote the first record to the header,
and two emit key/value blocks as one long list with no record id. Most of the
remaining 23 keep every record but merge or split a value, drop a footer,
title or comment header, or leave a real header unapplied.

## Coverage, consistency and confidence against quality

| winning confidence | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 85 | 11 | 1 | 6 | 4 |
| 80–84 | 36 | 5 | 8 | 23 |
| 60–79 | 39 | 6 | 17 | 16 |
| < 60 | 21 | 0 | 20 | 1 |

**A confident claim of 80 or more is wrong 57% of the time (27 of 47).** In
round 3 it was 40% at 2.1.0 and 33% after the fix round. The `< 60` band is
again almost all honest `text-lines` PARTIALs.

| line coverage | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 95% | 82 | 12 | 48 | 22 |
| 80–94% | 7 | 0 | 2 | 5 |
| 60–79% | 7 | 0 | 1 | 6 |
| < 60% | 11 | 0 | 0 | 11 |

| column-type consistency | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| 100 | 56 | 10 | 33 | 13 |
| 95–99 | 10 | 1 | 6 | 3 |
| 80–94 | 19 | 0 | 9 | 10 |
| 70–79 | 8 | 0 | 2 | 6 |
| < 70 | 0 | – | – | – |
| not judged (`-`) | 14 | 1 | 1 | 12 |

**Coverage is again the reliable one-way signal.** No input below 95%
passes, all 11 below 60% fail, and 17 of the 18 below 80% fail. **Consistency separates more weakly**: below 95, 16
of 27 fail (59%, against 41% overall), but no winner here reads under 70, so
the consistency half of the gate never fires. 12 of the 14 inputs whose
consistency reads `-` (no column judged) fail: it is what a one-record
flattening reads. Neither signal sees
misplacement that keeps every line and every column uniform: 22 FAILs cover
95% or more, and 8 FAILs read 95 or more on both signals, all of them a
non-data header or a wrong split.

## The quality gate's effect

| | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| held (generic winner, cov < 80 or cons < 70) | **18** | **0** | **1** | **17** |
| filed | 89 | 12 | 50 | 27 |

**The gate holds 18 captures: 17 FAIL, 1 PARTIAL, no PASS.** It would keep
17 of the 44 FAILs (39%) out of the store, at the cost of one PARTIAL (a
terminfo entry that drops its boolean flags, at 79% coverage). That matches
its design evidence on rounds 2 and 3 (18 of 48 FAILs, no PASS). All 18 are
held for coverage.

By pattern, it holds all 6 of pattern 3 (one section claimed), 10 of 17 of
pattern 1 (flattened records), 1 of 4 of pattern 4, and **none of the 15
non-data-header FAILs or the 2 table-alignment FAILs**. Those keep every line
and every column uniform, so neither signal moves. The 27 FAILs the gate files
are therefore mostly misplacement, which the store cannot tell from a good
parse.

Under `--multi` the 18 held inputs score 0 / 9 / 9: eight of the 17 held
FAILs become PARTIAL and the held PARTIAL stays PARTIAL. If every held
capture were segmented instead of triaged, the round would score 12 / 59 / 36
(66% usable, against 59%).

## Default against `--multi`

| | n | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|---:|
| default | 107 | 12 | 51 | 44 | 59% |
| `--multi` | 107 | 12 | 64 | 31 | **71%** |

`--multi` files more than one dataset for 48 inputs. For 57 it gives one
dataset byte-identical to the default table, and for 2 one dataset that
differs. Rated on the same scale, it is **better on 15 inputs, worse on 2 and
the same on 90**:

- **better:** 14 FAIL → PARTIAL and 1 PARTIAL → PASS. Seven are multi-section
  reports and five are key/value block sets; the rest are a table, a thread
  dump and a config database. In each, segmentation stops a flattener from
  swallowing the report: every section survives as its own dataset, even if
  many datasets are line-per-row or word-split.
- **worse:** a build-command trace, where a comment line becomes the header
  of every command (PARTIAL → FAIL), and a table whose key/value header
  swallows the table's header line (PASS → PARTIAL).
- **it rarely reaches PASS.** The one new PASS is a metrics file whose
  comment header the default drops. Segmented datasets are usually smaller
  versions of the same defects: first records promoted to headers, word-split
  rows, bespoke parsers (`pkg-config`, `version-line`, `git-annex-list`)
  claiming a generic segment and labelling it with their own column names.

Per family, `--multi` would help most where the default flattens: **multi-
section reports** (50% → 75% usable, 7 better, 0 worse) and **key/value
blocks** (30% → 80%, 5 better, 0 worse). It is neutral on logs and
diagnostics, structured data and single records, slightly positive on lists,
and neutral-to-slightly-negative on whitespace tables (one better, one worse).
Of the inputs where it would hurt, both have strong signals in default mode
(coverage 100, consistency 100). Of the 15 it improves, 8 are held by the
gate. So segmenting **when the quality signals are weak** would have taken
8 of the 15 gains and neither loss on this set. The other 7 gains read 83%
coverage or more and 84 or more on consistency (or `-`), so a trigger on the
gate's thresholds misses them; catching them would need another cue, such as
a single record with content-built column names, an unjudged consistency, or
a known flattener winning.

## Engine findings

These are outside the ratings, and none was fixed here: this round is
measurement only.

- **`tsv` strips double quotes from inside values** (two inputs). A tab file
  whose text fields contain `"name"` comes out with `name`. This is silent
  value alteration, not misplacement.
- **`vertical-line` still slices at fixed character positions** (three
  inputs). Values in a row wider than the header layout are cut mid-word.
  Round 3 reported the same mechanism; the 2026-10-16 decline rules do not
  reach these shapes.
- **`bracket-log` labels any leading bracket `timestamp`** (a pid:isolate tag,
  a change type, a progress percentage, a resource index). The field is split
  correctly but misnamed.
- **Bespoke parsers claim generic segments under `--multi`.** `pkg-config`,
  `version-line` and `git-annex-list` win small segments of unrelated reports
  and label them with their own column names (name / description, name /
  version, flags / path). In default mode the same parsers do not win.
- **`yaml` claims a `name: description` list at confidence 85** and is exempt
  from the gate as a strict grammar, though the input is not YAML (one
  input). The exemption assumes a strict parser declines what it cannot read.
- **A header built across a gutter can come out with its words reordered**
  (one input, `embedded-table`), the same defect round 3 reported for
  `aligned-columns`.

## Reproducing

```bash
bash tests/benchmark/run.sh --round4 --tidy -j 2 /tmp/r4   # ~7 min on a shared 4-core box
python3 tests/benchmark/round4/novelty.py                   # re-check novelty after adding inputs
( cd tests/benchmark/round4/inputs && sha256sum -c ../SHA256SUMS )   # the frozen set is unchanged
```

The script prints one line per input: strategy and confidence, line coverage,
consistency, input and output line counts, the number of `--multi` datasets,
and the priority-mode winner when it differs. Nothing is asserted. Rate each
input's `NAME.tidy` and `NAME.multi.tidy` against `round4/CRITERIA.md`, or
read the diff against `round4/ratings.tsv`.

## When this set retires

Round 4 is a generalisation measure only until someone works its patterns.
The planned change it was built to baseline (segmentation by default when the
signals are weak) does not touch any parser, so it can be measured here
honestly once: run `run.sh --round4` after it lands and compare with the
`multi_rating` and `rating` columns. Report that delta as the change's
generalisation number.

The first fix round that touches the patterns above makes round 4 a
regression set, as rounds 1 to 3 became. That round should, in the same
commit:

- update `ratings.tsv` with new columns, keeping these;
- add a postscript here with the re-rating;
- stop quoting round 4's numbers as generalisation;
- develop the fixes against new examples and the corpus, running round 4
  only at the end.

**This report already names inputs and defects.** Anyone tuning a parser
should work from the pattern descriptions and fresh inputs, not from these
files. The next honest generalisation number after a parser fix round needs a
**round 5**: built, novelty-checked against rounds 1–4 and the corpus, frozen,
and rated on the same criteria before anyone parses it.

## Postscript, 2026-10-20: the automatic `--multi` fallback, measured once

The auto-multi change was built without seeing round 4. Before the quality
gate holds a weak parse, it segments the input and files the parts only if
every part passes the gate and together they keep materially more. Each
round-4 input was then captured once through the real CLI
(`provost --sync`, one fresh store per input). The `--multi` ratings above
stand for what segmentation files.

| | gate alone (before) | with auto-multi |
|---|---:|---:|
| held for triage | 18 | 15 |
| segmented and filed | 0 | 3 |

**What changed:**
- **026** (jcmd VM metaspace): FAIL → PARTIAL, 14 parts keeping 96%.
- **106** (F5 tmsh pool stats): FAIL → PARTIAL, 12 parts keeping 100%.
- **048** (pytest `-ra` report): it was held, and is now filed as 5 parts that
  are still a FAIL. That is worse than holding it, because a wrong table
  reached the store.

**What stayed held (15):**
- 8 whose `--multi` output is also a FAIL, correctly declined.
- 6 whose `--multi` output would have been a PARTIAL. These are missed
  rescues.
- 1 PARTIAL either way.

**Verdict:** a small net gain on unseen input. Two rescues out of a possible
eight, against one wrong table that the gate alone would have held. The
guards were chosen on rounds 2 and 3, where they rescued 3 of 26. On fresh
data they are conservative, and the per-part gate let one bad split through.
Round 4 has now been looked at for this change, so any further tuning of the
guards against it would not be an honest measure. Re-measuring needs a round
5.

*2026-11-10 (PV-013):* the guards were retuned on this round, which was
already spent for auto-multi, and then measured once on round 5. On round 4
the change files 5 rescues (003, 026, 029, 106, 137) and no wrong table: 048
is held. On round 5 it files 1 rescue of 3 and no wrong table. See the
postscript to `docs/benchmark-2026-11-04-generalisation-round5.md`.


## Postscript, 2026-10-22: the layout-model fallback, measured once

The learned layout model (`--model`, `PROVOST_MODEL=1`;
`docs/model-2026-10-22-layout-steps1-2.md`) was built and tuned without ever
reading round 4. When the gate still holds a capture after auto-multi, it
offers its own table, which is filed only if it passes the same gate. Every
round-4 input was captured once through the real CLI with and without
`--model` (one fresh store per input). Nothing else changed: the two runs
differ only where the model acted.

| | without the model | with the model |
|---|---:|---:|
| held for triage | 15 | 14 |
| filed by the model | — | 1 |

**What it filed:** **023** (infocmp terminfo) at coverage 100%. Every line
becomes a row, and the capability lists stay as text, one per physical line.
That is PARTIAL by rule 5: a record split across rows, with all information
present. The engine's own parse, held at 79%, was also rated PARTIAL.

**What it declined (14):**
- 13 failed its shape check: they are mixed multi-section reports, not one
  table or one key/value record;
- 1 table fell short of the coverage gate.

None reached the 600-line limit.

**Verdict:** safe but rarely useful as a whole-document fallback. It made one
PARTIAL rescue and filed no wrong table. What the gate still holds is almost
all mixed reports, which this fallback deliberately leaves alone. The model
would have to work section by section, inside auto-multi's segments, to reach
them. It stays off by default.
