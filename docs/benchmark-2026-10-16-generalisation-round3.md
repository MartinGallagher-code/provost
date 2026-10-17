# Held-out generalisation benchmark, round 3: 107 inputs nobody had parsed

> **Later the same day:** the set was re-rated after a fix round that had
> never seen it. The rating went from 22 / 45 / 40 to 22 / 48 / 37. Round 3 is
> now a regression set, and the next honest number needs a round 4. See the
> [postscript](#postscript-2026-10-16-re-rated-after-a-fix-round-and-this-set-is-now-a-regression-measure).

**2026-10-16.** This round put 107 tool outputs through `provost` 2.1.0
(main at `eacc9fa`). None of them appear in the corpus, the holdout, round 1
or round 2. The set was built, novelty-checked and frozen, and round 2's
criteria were copied over unchanged, before the first input was run. Each
result was then rated once, in default mode.

**This is the first honest generalisation measurement of the 2026-10-14
parser work** (the gutter grid, banner handling, `prefix-message`,
`help-columns`, line coverage and the `kv-report` rescue). Round 2's
2026-10-14 re-rating measured those changes on inputs they had already been
checked against. This round measures them on inputs nobody had looked at.

As in rounds 1 and 2, **the rating is a self-assessment by an agent. Treat it
as a screen, not a verdict.**

Everything is in the repo:

- the inputs:
  [`tests/benchmark/round3/inputs/`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round3/inputs)
- where each input came from:
  [`round3/manifest.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round3/manifest.tsv)
- the criteria, reused unchanged and frozen before the run:
  [`round3/CRITERIA.md`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round3/CRITERIA.md)
- the rating for each input:
  [`round3/ratings.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round3/ratings.tsv)
- the novelty check:
  [`round3/novelty.py`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round3/novelty.py)
- the runner: `bash tests/benchmark/run.sh --round3`

## Headline

| | round 3 (n=107) | share | round 2 at first rating (n=109) | round 2 re-rated 2026-10-14 (seen set) |
|---|---:|---:|---:|---:|
| PASS | 22 | **21%** | 16% | 24% |
| PARTIAL | 45 | **42%** | 47% | 50% |
| FAIL | 40 | **37%** | 38% | 27% |
| usable (PASS + PARTIAL) | 67 | **63%** | 62% | 73% |

**On output it has never seen, provost 2.1.0 gets one input in five fully
right, nearly two in three are usable, and three in eight come out wrong.**

Compared with round 2 at its first rating, the PASS share is five points
higher and the FAIL share is the same. The sets are different and not
paired, and at n≈107 the 95% margin on a share near 20% is about ±8 points,
so the PASS gain is suggestive, not established. The FAIL share has not
moved.

The round-2 re-rating (24% PASS, 73% usable, 27% FAIL) does not carry over.
On unseen inputs the FAIL share is ten points higher than on the seen set.
That gap is roughly what fitting to the seen set was worth: the 2026-10-14
work fixed the specific round-2 failures it was checked against more
thoroughly than it fixed their pattern.

## Method

### The set: 64 captured, 43 reproduced

| | n | what |
|---|---:|---|
| **captured** (001–064) | 64 | real output of read-only commands run in the 2026-10-16 build container, on scratch projects, a scratch git repo and small ext4 image files made for the purpose: coreutils text tools (`ptx`, `join`, `pr`, `diff3`, `sort --debug`), `/proc` and `/sys`, binutils (`readelf -n`, `objdump -p`), gcc/clang/`cpp`, gdb and valgrind/callgrind, Go, rustc, javac/java, CMake/CTest, Python (`tokenize`, `doctest`, `trace`, `timeit`, `filecmp`, `locale`, `site`), pytest, flake8, pyright, coverage, Node (`node --test` in spec and TAP, `--prof-process`, `--v8-options`), npm, tsc, PHP, composer, Perl `prove`, Ruby `gem`, pip, poetry, uv, apt, git (`blame`, `range-diff`, `show-branch`, `status --porcelain=v2`, `verify-pack`), e2fsprogs, xz, OpenSSL, psql, tmux, bash, locale tools |
| **reproduced** (101–143) | 43 | written by hand to each tool's documented output format, for platforms the container does not have: PowerShell `Format-Table` (`Get-Service`, `Get-ChildItem`, `Get-HotFix`), `systeminfo`, `sc queryex`, `wevtutil`, `icacls`; macOS `system_profiler`, `launchctl`, `log show`, `pmset`; Cisco IOS (`show interfaces status`, `show cdp neighbors`, `show spanning-tree`, `show version`), Junos (`show route`, `show chassis hardware`), RouterOS; cqlsh, `lsnrctl`, SQL\*Plus `DESC`, ClickHouse `PrettyCompact`; `aws logs tail`, `doctl`, `az`; `kubectl cnpg status`, minikube, velero, `helm template`; GitHub Actions and Jenkins logs; Icinga 2, check_mk agent, `nagios -v`; z/OS JES2 job log, IBM i `WRKACTJOB`; R `summary(lm())`, MATLAB `whos`, HMMER `--tblout`; Minecraft and Source-engine servers; RFC 5424 syslog; an HL7 v2 message |

The set was chosen for shape diversity, before any input was run. It
deliberately includes the families round 2 found hard:

- aligned tables with spaces in cells, empty cells and two-word headers;
- non-ASCII cells: German, Polish, Cyrillic, Japanese and Chinese names, in
  both tables and logs;
- multi-section reports (16 inputs);
- banners, titles, echoed prompts and footers;
- diagnostics and logs with continuation lines;
- help text;
- key/value reports with lists, and nested indentation.

No input was chosen, edited or dropped because of how provost might parse it.

**Scrubbing (captured inputs).** Scratch paths became
`/home/dev/{project,web,prof,src,binpack}` and the scratch `HOME` became
`/home/dev`. Commands that would echo the container's proxy, CA-bundle or
token environment were run with those variables unset or with a clean
environment: `pip config debug` without `PIP_CERT`, and `coverage debug sys`
under `env -i`. Git identities in the scratch repo are invented
`example.com` names, one with non-ASCII characters, which is deliberate. The
container's hostname appears nowhere. The account is `root`, and it shows
only as psql's default user name. No environment dump, network address or
secret was captured. **Reproduced** inputs use invented values, the RFC 5737
documentation ranges and `example.com`. One CR-separated input (the HL7
message) and one backspace-overwritten progress log (`mke2fs`) are kept
byte-for-byte, because that is how those tools write to a file.

Several captures are truncated with `| head -N` or `sed -n 1,Np`, as such
output is usually pasted. The manifest records every exact command.

### Novelty: how "never seen" was checked

`round3/novelty.py` is round 2's script, extended to compare against round 2's
inputs as well. It compares every input with all 3,960 existing inputs:
`tests/corpus/inputs` (3,705), `tests/corpus/holdout/inputs` (80),
`tests/corpus/text-inputs` (16), round 1 (50) and round 2 (109). It checks
two things.

1. **Name.** No input's tool-and-mode stem matches an existing one (`_` and `-`
   treated as equal, case ignored). The pre-run screen caught five clashes
   among the first draft of reproductions, and all five were replaced:
   `kustomize build`, `istioctl proxy-status`, `argocd app get`,
   `logcli query` and `datadog-agent status`.
2. **Content.** The script computes the Jaccard similarity of normalised line
   sets and of word 3-gram sets (lowercased, digit runs mapped to `0`,
   whitespace collapsed). Before the set was frozen, five more candidates
   were dropped as close relatives:
   - a PostgreSQL `EXPLAIN ANALYZE` plan: 3-gram 0.25 against the corpus's
     psql explain tree;
   - `SHOW ENGINE INNODB STATUS`: 0.22 against the corpus's MariaDB InnoDB
     status;
   - Cisco `show ip bgp summary`: the same layout as the corpus's FRR
     `show bgp summary`, 0.14;
   - `cmp -l`: 1.00 against `pidof`, because both are pure digit runs once
     digits are normalised;
   - `e2fsck -fnv`: 0.18 against `e2fsck-summary`.

**In the final set no input clashes by name, and the highest 3-gram
similarity is 0.14** (`check_mk_agent` against a corpus meminfo capture,
because the agent output embeds a short meminfo section). The next highest
are 0.08 and 0.06, and 105 of the 107 inputs are at 0.06 or below. The
highest line-set figures are 0.18: `diff3` shares lines such as
`port = 0` with an INI fixture, and `helm template` shares YAML label lines
with `kustomize build`. A further 0.17 is the same meminfo section. These
are shared boilerplate, not shared content.

**Nothing was tuned.** No engine, strategy, hint or parser file was touched.
The only code change in this round is to the benchmark runner
(`run.sh --round3`, plus the cosmetic fix in [Engine findings](#engine-findings)).

### Runs

One run, after the freeze, on this engine:
`bash tests/benchmark/run.sh --round3 --tidy -j 2`. It took 9 min 38 s on a
shared 4-core box. Default mode (`--max-strategies 1`, confidence ranking) was
melted to the tidy table and rated. `--rank priority` and `--multi` were
recorded alongside it. The default `.meta` files give line coverage as the
4th field.

### Rating

Each input was rated PASS, PARTIAL or FAIL from the input and its default
tidy table, strictly by `CRITERIA.md` and its six rules. Those are round 2's
words, byte for byte. Where a call could go either way, it was made the way
round 2 made the comparable call:

- a first data row promoted to the header is PARTIAL (as `set -o`);
- a dropped banner or footer that carries a number is PARTIAL (as
  `readelf -d` and `sqlcmd`);
- sections glued into one cell are FAIL (as `diskutil` and `route print`);
- a free-text fallback that keeps every line is PARTIAL.

`ratings.tsv` gives a one-line reason for every input.

## Results

### By shape family

| family | n | PASS | PARTIAL | FAIL | usable | round 2, 10-02 usable | round 2, 10-14 usable (seen) |
|---|---:|---:|---:|---:|---:|---:|---:|
| aligned / fixed-width table | 27 | 8 | 10 | 9 | 67% | 52% | 76% |
| log and diagnostic lines | 24 | 4 | 9 | 11 | **54%** | 85% | 90% |
| multi-section report | 16 | 0 | 4 | 12 | **25%** | 15% | 31% |
| list, grid, help text, free text | 14 | 2 | 8 | 4 | 71% | 65% | 75% |
| key/value blocks (several records) | 11 | 1 | 8 | 2 | 82% | 50% | 70% |
| single key/value record | 10 | 6 | 4 | 0 | **100%** | 82% | 82% |
| structured data (YAML, var_dump, HL7) | 3 | 0 | 1 | 2 | 33% | 75% | 75% |
| box / rule-drawn table | 2 | 1 | 1 | 0 | 100% | 83% | 83% |

- **Key/value output generalises well.** No single-record input failed, and
  only two of eleven multi-record inputs did.
- **Whitespace tables improved on unseen input**, from 52% to 67% usable and
  from 4 to 8 PASSes. That is less than the seen set showed (76%).
- **Multi-section reports still fail three times in four.**
- **The log/diagnostic family is the surprise.** Compiler-style diagnostics
  pass: `prefix-message` won 5 inputs and passed 4. But this family also
  holds the test-runner reports (node `--test` in spec and TAP, `pytest
  --setup-plan`, `doctest -v`, pyright, `prove`), CI logs and `nagios -v`.
  Round 2 had few of those, and most of them FAIL here. Round 2's 85–90% did
  not measure this kind of line output.
- The structured-data family is too small (3) to read anything into. The
  three are multi-document YAML, PHP `var_dump` and HL7, none of which is
  JSON, CSV or single-document YAML.

### By category

| category | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| language tooling | 17 | 2 | 7 | 8 |
| build | 13 | 6 | 3 | 4 |
| system (`/proc`, `/sys`, Windows/macOS admin) | 12 | 5 | 6 | 1 |
| test / lint | 11 | 1 | 4 | 6 |
| network (Cisco, Junos, RouterOS) | 7 | 0 | 3 | 4 |
| text utilities | 7 | 1 | 5 | 1 |
| database | 5 | 1 | 3 | 1 |
| storage | 5 | 0 | 2 | 3 |
| package manager | 4 | 3 | 1 | 0 |
| k8s | 4 | 1 | 1 | 2 |
| cloud | 3 | 1 | 0 | 2 |
| logs | 3 | 0 | 3 | 0 |
| monitoring | 3 | 0 | 1 | 2 |
| scientific | 3 | 1 | 1 | 1 |
| shell | 2 | 0 | 2 | 0 |
| CI | 2 | 0 | 1 | 1 |
| mainframe / IBM i | 2 | 0 | 1 | 1 |
| game servers | 2 | 0 | 1 | 1 |
| crypto | 1 | 0 | 0 | 1 |
| data format | 1 | 0 | 0 | 1 |

By provenance: **captured** inputs scored 15 PASS, 27 PARTIAL and 22 FAIL
(66% usable). **Reproduced** inputs scored 7 PASS, 18 PARTIAL and 18 FAIL (58%
usable). Cisco, Junos and RouterOS output, which no earlier round or corpus
entry covers, is 0 PASS out of 7.

### What passes

These 22 came out fully right:

- **diagnostics:** clang `-Wall` (notes as their own rows, code frames in
  `detail`), `go build -gcflags=-m`, `javac -Xlint:all`, rustc warnings;
- **help and command lists:** `gem help commands`, `npm run`, `psql --help`;
- **tables:**
  - `apt-cache madison` and `go tool cover -func`;
  - `join` with `-e EMPTY`;
  - PowerShell `Get-Service` and `Get-HotFix`: multi-word cells, `...`
    truncations, empty cells and two-token dates all in place;
  - `launchctl list`, `az vm list-usage` and MATLAB `whos`;
  - the minikube box table;
- **key/value:** `gcc -print-search-dirs`, `locale -k LC_TIME`,
  `poetry config --list`, `/sys/.../node0/meminfo`,
  `tsc --extendedDiagnostics`, `system_profiler SPHardwareDataType`.

Several of these are exactly what the 2026-10-14 work targeted, and they
pass on inputs it was never checked against:

- `prefix-message` passed 4 of its 5 wins;
- `help-columns` passed 3 of 5, and its other 2 are PARTIAL;
- the gutter grid behind `fixed-width` gets two of the three PowerShell
  tables right.

## Top failure patterns

These are directions for parser work, not a punch list. Fixing them against
these files would turn round 3 into a second corpus. Validate any fix against
fresh inputs.

### 1. A non-table line becomes the header of an aligned table (11 inputs, 10 FAIL)

The line above a whitespace table is promoted to its header. It may be a
banner, an echoed CLI prompt, a legend, a status line or the table's first
record. Its words become column names, and every value then sits under the
wrong name.

- `composer check-platform-reqs` (006): `No vendor dir present, ...`.
- `objdump -p` (034): `/usr/bin/xz: file format elf64-x86-64` sits over
  three sections.
- Cisco `show interfaces status` (112) and Junos `show route` (117): the
  prompt or the first port line.
- Jenkins console (131): `Started by user ...`.
- `srcds status` (141): `hostname: ...`.
- RouterOS (114): the flags legend.
- HL7 (143): the MSH segment, split at spaces instead of `|`.
- `git status --porcelain=v2` (019): a `# branch.head` comment line.
- `/proc/self/numa_maps` (042) and `tmux list-keys` (061, PARTIAL): the
  first record.

Round 2's banner fix recognises some banner shapes. It does not generalise to
prompts, legends or `key: value` status lines, and it does not ask whether
the candidate header's words line up with the columns below it.

### 2. Nested or sectioned text flattened into one wide record or one cell (16 inputs, 11 FAIL)

`indented-hierarchy`, `protobuf-text`, `colons` and `gnu-version` claim
nested or multi-section text and emit a single record. Column names are
built from content lines, such as
`TAP_version_13.ok_1_-_is_zero...duration_ms`, a file path repeated five
times, or a stack frame. Tables inside the report become one cell.

- Flattened into one record: node `--test` in spec (030) and TAP (031),
  pyright (046), `callgrind_annotate` (003), `trace --listfuncs` (055),
  `helm template` (129, four YAML documents merged), the check_mk agent
  (133).
- Glued into a cell: `node --prof-process` (029, five tables, one cell
  each), `xz -lvv` (064, two nested tables), `nagios -v` (134, twenty
  `Checked N` counts in one `notes` cell).

`--multi` rescues part of this pattern again: `--prof-process`, the spec
reporter and `readelf -n` all come out better segmented.

### 3. One section of a report claimed, the rest dropped, often by fixed-column slicing (10 inputs, 9 FAIL)

A table strategy or a bespoke parser claims one section and drops the rest
without any warning in default mode:

- Cisco `show spanning-tree` (115, cov 38): the root/bridge block is lost.
- `kubectl cnpg status` (126, cov 75): the cluster summary is lost.
- R `summary(lm())` (137, cov 31): 5 coefficient rows survive, out of seven
  sections.
- JES2 job log (135, cov 28).
- `pytest --fixtures` (047, cov 31) and `--setup-plan` (048, cov 27):
  `pytest-summary` claims these at confidence 95.

`vertical-line` slices at fixed character columns on three more: `git
show-branch` (018), `patch --verbose` (036) and `lsnrctl status` (120).

Line coverage sees all of these. Seven of them are under 60%. But the
claiming strategies (tables, `vertical-line`, bespoke parsers) are exempt
from the low-coverage hold, so nothing is rescued. This is the same
mechanism round 2 found with `toml` and `composer config`.

### 4. A wrong strategy or delimiter, including silent data loss (8 inputs, 7 FAIL)

A parser claims the input from a superficial cue.

- `java -XX:+PrintFlagsFinal` (023): `json` claims it from the leading
  `[Global flags]`, extracts nothing, and nothing else is tried. **There is
  no output at all.**
- `aws logs tail` (123): `tsv` keeps the first two tab fields of every line.
  Every application message, every request id and most REPORT fields are
  dropped. **Coverage reads 100.**
- `python -m tokenize` (054): `csv` splits at the commas inside `1,0-1,6`.
- `git blame` (016): `git-log` claims it and drops the boundary commits.
- `doctest -v` (049): `key-value` splits at a colon inside source code.
- `icacls` (107): splits at the drive-letter colon.
- `openssl list -providers` (035): a nested parameter list is read as a
  second provider.
- `mke2fs` (028, PARTIAL): `pkg-config` splits off the first word as a
  package name.

### 5. Whitespace tables with two-word headers or wide right-aligned cells (6 inputs, 3 FAIL)

The gutter grid fixed the round-2 cases, but not these.

- `doctl compute droplet list` (124): the two-word headers are split into
  words. The split creates two columns each named `Public` and `IPv4`, and
  the melt keeps the later one, so the IP addresses vanish from the tidy
  table.
- PowerShell `Get-ChildItem` (102): the date is glued to `Mode`, and a
  7-digit right-aligned Length loses its first digit (1204736 becomes
  204736).
- `readelf -n` (056): `Data size` splits.

PARTIAL:

- `pr` (040): two-word item cells.
- `uv python list` (063): `<download available>`.
- `cpp -dM` (008): multi-word values.

### The PARTIAL ceiling

Of the 45 PARTIALs, 33 fall into five clusters that keep every value but
never form the records:

- `text-lines` fallbacks: 11. Examples are the bash help grid, `flake8`,
  gdb, `prove`, `cdp neighbors`, `WRKACTJOB`, `hmmscan`, RFC 5424 syslog
  and the Icinga objects. Round 2's pattern 4 fixed compiler-style lines.
  The other line grammars remain.
- records split across rows: 8 (`ctest`, `--v8-options`, `diff3`,
  `python -m site`).
- key/value blocks emitted as one long key/value list with no record id or
  parent key: 5 (`sc queryex`, `wevtutil`, `systeminfo`, velero,
  `pip config debug`).
- result-set footers or section headings dropped: 6.
- typed prefix fields left inside the message: 3 (`[thread/LEVEL]`,
  `##[error]`).

## Confidence and coverage against quality

| winning confidence | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 85 | 13 | 4 | 4 | 5 |
| 80–84 | 52 | 14 | 17 | 21 |
| 60–79 | 24 | 3 | 9 | 12 |
| < 60 | 18 | 1 | 15 | 2 |

**A confident claim of 80 or more is wrong 40% of the time (26 of 65).** On
round 2's seen set it was 25%, and at round 2's first rating 37%. The
`< 60` band is again mostly honest `text-lines` PARTIALs. With the default
`PROVOST_MIN_CONFIDENCE=50`, every input that produced output committed.

| line coverage | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 95% | 73 | 21 | 34 | 18 |
| 80–94% | 17 | 1 | 8 | 8 |
| 60–79% | 9 | 0 | 3 | 6 |
| < 60% (incl. 1 with no output) | 8 | 0 | 0 | 8 |

**Coverage is again the better one-way signal.**

- Only one input below 95% passes: `system_profiler`, at 92%, which drops
  only content-free headings.
- All 8 inputs below 60% are FAIL, against 2 of 29 FAILs caught at that
  threshold in round 2.
- 22 of the 34 inputs below 95% are FAIL, against 37% across the whole set.
- But 18 of the 40 FAILs cover 95% or more. Misplacement keeps every token,
  so coverage cannot see it: banner-as-header, flattened records, wrong
  delimiters. `aws logs tail` reads 100% while dropping most of its fields,
  because coverage counts lines, not fields.

Neither signal tells a right parse from a wrong one. Coverage below 60% is
now a reliable "this is wrong", and the hold does not act on it for the
strategies that cause it.

## Confidence ranking against priority ranking

`--rank priority` picked a different winner on 11 of the 107 inputs. Round 2
had 0 at its first rating and 5 on the seen set. On the other 96 the output
was byte-identical (`cmp`).

On those 11, the default was better on 9:

- the `kv-report` rescue (`ctest`, `--v8-options`, `show version`) beat
  `block-records`, which drops most lines under priority ranking;
- `help-columns` beat `block-records` on `localedef`, `npm run` and `psql`;
- `prefix-message` beat `embedded-table` and `protobuf-text` on javac and
  rustc;
- `equals` beat `aligned-columns` on `locale -k`.

Priority was better on 2:

- the Minecraft log, where `prefix-message` splits `[thread/LEVEL]` and
  `bracket-log` does not;
- `numa_maps`, where `git-log` keeps the first record and `aligned-columns`
  promotes it to the header.

Under priority ranking the set scores **18 PASS / 42 PARTIAL / 47 FAIL**.
Calibrated confidence and the rescue are therefore worth about four PASSes and
seven fewer FAILs on unseen input. This is the first round where the ranking
measurably matters.

`--multi` was better than default on 19 inputs, 13 of them default-mode FAILs.
It was worse on 6, and the same on 82, 59 of which give a byte-identical
single dataset. Round 1 and round 2 both concluded that segmentation belongs
closer to the default, and that still holds.

## Engine findings

These are outside the ratings, and none was fixed here: this round is
measurement only.

- **A `json` near-miss leaves no fallback.** A text input whose first line is
  `[Section]` (023) is claimed by `json`. It extracts nothing, and the engine
  reports `No fields extracted` instead of trying the next candidate.
  `--multi` returns nothing as well. It is the only input in the round with
  no output.
- **`tsv` truncates rows to the first row's width without any signal** (123).
  Coverage is line-based, so it reads 100%.
- **Duplicate column names lose data in the melt** (124). When a two-word
  header is split, two columns can get the same name. `-f plain` keeps both
  values, and the melted tidy table keeps only the later one. The same
  happens when `helm template`'s documents are merged into one record (129).
- **A right-aligned value wider than its header loses leading characters**
  under `fixed-width` (102): 1204736 becomes 204736. This is silent value
  corruption, not misplacement.
- **`gnu-version` emits a field that is not in the input** (134):
  `warranty 0`.
- **`aligned-columns` drops or reorders words in a cell** that spans a gutter
  (114: two words of a comment are missing).
- **Bespoke strategies at high confidence claim near-miss inputs at very low
  coverage and are not held.** `pytest-summary` claimed (95) the
  `--fixtures` and `--setup-plan` reports at 31% and 27%. This is the round-2
  `toml` case again.
- **Runner fix (cosmetic).** `run.sh`'s summary printed the `--multi` dataset
  count as `0` twice when there were no datasets, because `grep -c` prints
  `0` and exits 1, so `|| echo 0` fired as well. Fixed in this commit. The
  benchmark outputs are unaffected.

## Reproducing

```bash
bash tests/benchmark/run.sh --round3 --tidy -j 2 /tmp/r3   # ~10 min on a shared 4-core box
python3 tests/benchmark/round3/novelty.py                   # re-check novelty after adding inputs
```

The script prints one line per input: strategy and confidence, line coverage,
input and output line counts, the number of `--multi` datasets, and the
priority-mode winner when it differs. Nothing is asserted. Rate each input's
`NAME.tidy` against `round3/CRITERIA.md`, or read the diff against
`round3/ratings.tsv`.

## When this set retires

Round 3 is a generalisation measure only until someone works its patterns.
The first fix round that touches the clusters above makes it a regression
set, as rounds 1 and 2 became. That round should do four things in the same
commit:

- update `ratings.tsv`;
- add a postscript here with the re-rating;
- stop quoting round 3's numbers as generalisation;
- develop the fixes against new examples and the corpus, running round 3
  only at the end, as the 2026-10-14 round did.

**This report already names inputs and defects one by one.** Anyone tuning a
parser should work from the pattern descriptions and fresh inputs, not from
these files. The next honest generalisation number needs a **round 4**:
built, novelty-checked against rounds 1–3 and the corpus, frozen, and rated
on the same criteria before anyone parses it.

## Postscript, 2026-10-16: re-rated after a fix round, and this set is now a regression measure

After the rating above, a fix round worked round 2's remaining patterns
(CHANGELOG, the three 2026-10-16 engine entries):

- **Column-type consistency.** Every parse now gets a third quality signal:
  the share of its cells whose type fits their column (the 5th `--emit-meta`
  field). A generic claim with a mixed column and consistency under 95 is
  held. A more consistent nearby candidate replaces it, but only under guards:
  it must reach 95, keep as many lines, add no records and relabel nothing.
- **Whitespace tables.** The gutter grid reads UTF-8 cells by character, and
  it handles loose headers, one crossing row and headerless tables with soft
  gutters. `aligned-columns` gained a headerless-by-segment mode, decorated
  titles, print-report page headers and ASA control. Footers and the prompt
  after them are cut in every table reader.
- **Format parsers decline what they do not read.** `toml`, `equals`,
  `vertical-line`, `yaml`, `csv`, `semicolon-values`, `colons`,
  `colon-fields` and `indented-hierarchy` each refuse a near-miss shape they
  used to claim. `json` reads JavaScript and Python object literals.
- **Sections and indentation.** A new `section-tables` strategy gives titled
  tables one table with a `section` column. `key-value` keeps labels that
  contain colons and itemises lists. `kv-report` reads `+name` / `-name`
  feature grids. `indent-tree` keeps a text outline as `depth` / `parent` /
  `name`.
- The pre-rename names were removed. That does not touch parsing.

**The fix round's agents never saw round 3.** The set was built, frozen and
rated on 2.1.0 first, and the fixes were developed against the corpus,
round 2's postscript and new examples. So this before/after is an honest
generalisation delta: it measures what the round's changes do to output
nobody tuned them for.

The final engine ran `run.sh --round3 --tidy` once. In 93 of the 107 inputs
the default tidy output is byte-identical to the 2.1.0 run (checked with
`cmp`), so those ratings carry over. The other 14 were re-rated from the
input and both outputs, with the same criteria and the same six rules.
`ratings.tsv` keeps the original columns and adds `strategy_1016`,
`conf_1016`, `cov_1016`, `cons_1016`, `rating_1016` and `note_1016`.
`--rank priority` and `--multi` were not re-rated: their output changed on 12
and 13 inputs.

### Headline

| | 2.1.0 | share | after the fix round | share |
|---|---:|---:|---:|---:|
| PASS | 22 | 21% | 22 | **21%** |
| PARTIAL | 45 | 42% | 48 | **45%** |
| FAIL | 40 | 37% | 37 | **35%** |
| usable (PASS + PARTIAL) | 67 | 63% | 70 | **65%** |

**On round 3 the fix round turned three FAILs into PARTIALs and made no new
PASS.** Of the 14 changed outputs, 3 moved from FAIL to PARTIAL, and 11
changed without moving: 7 PARTIAL and 4 FAIL. **No default-mode output got
worse.** Three points of FAIL share is well inside the ±8-point margin.

On round 2, the set the fixes were aimed at, the same engine moved 19 of 109
ratings, as the next section of the round-2 report shows. That set went from
24% to 32% PASS and from 27% to 10% FAIL. The gap between the two sets is the
size of the fit: the round's changes fixed round 2's specific failures far
more thoroughly than they fixed the patterns behind them.

| family (only those that moved) | n | 2.1.0 PASS / PARTIAL / FAIL | usable | after | usable |
|---|---:|---|---:|---|---:|
| aligned / fixed-width table | 27 | 8 / 10 / 9 | 67% | 8 / 11 / 8 | 70% |
| log and diagnostic lines | 24 | 4 / 9 / 11 | 54% | 4 / 11 / 9 | 63% |

The other six families are unchanged: multi-section reports are still
0 / 4 / 12 (25% usable). By provenance, captured inputs are 15 / 28 / 21
(67% usable) and reproduced inputs 7 / 20 / 16 (63%, up from 58%).

### What changed, input by input

**FAIL to PARTIAL (3):**

- `aws logs tail` (123): the consistency hold replaced the `tsv` claim
  (consistency 86) with `prefix-message` (100). Every field `tsv` dropped is
  back, and the traceback is attached to its event, but log stream, level and
  request id stay inside `message`. This is the only round-3 input where the
  hold changed the winner.
- PowerShell `Get-ChildItem` (102): the table is exact. Date and time sit
  together, and 1204736 keeps its first digit. Only the `Directory:` title
  that names the folder is dropped.
- `doctest -v` (049): the failure report, the untested items and the totals
  are rows of their own, not glued onto `Got`. Two examples' source is still
  split at a colon, and each example spans three or four rows.

**Changed, still PARTIAL (7):**

- `php var_dump` (037): `indent-tree` keeps the nesting as depth/parent, but
  each key is still on a different row from its value.
- Icinga 2 objects (132): `indent-tree` keeps object membership and nesting,
  but `key = value` is never split.
- `pip config debug` (038): each config file is its own row. The variants are
  empty-valued rows, and settings still lose their file.
- `tmux list-keys` (061): headerless now, so the first binding stays in the
  data, but the command is split over three columns.
- `systeminfo` (104): `IP address(es)` is no longer glued onto a value.
  Nesting is still lost.
- `wevtutil` (106): one description is joined whole. The events are still not
  records.
- velero (128): one key keeps a trailing `:`. Nothing else changed.

**Changed, still FAIL (4):**

- `node --prof-process` (029): three of the five tables give one row per
  line, but no row is split into columns. Two tables are still one cell each.
- `numa_maps` (042): the first record is still the header, and the rest of
  each line is now one glued cell.
- pyright (046): `indented-hierarchy` now declines. `aligned-columns` takes
  the second banner line as the header and shreds every diagnostic word by
  word.
- JES2 job log (135): `vertical-line` now declines, and coverage goes from 28
  to 100. But `aligned-columns` takes the letter-spaced banner as the header.
  Its repeated letters make duplicate column names, so the melt drops and
  reorders tokens. Consistency reads 72, and the hold finds no replacement.

### What still fails, by pattern

The 37 FAILs, by the patterns of the report above:

1. **A non-table line becomes the header (12 FAIL, was 10).** All ten are
   still FAIL: `composer` (006), `git status --porcelain=v2` (019),
   `objdump -p` (034), `numa_maps` (042), Cisco `show interfaces status`
   (112), RouterOS (114), Junos `show route` (117), Jenkins (131), `srcds`
   (141) and HL7 (143). Pyright (046) and the JES2 log (135) joined them. Both
   used to be claimed by a parser that now declines, and `aligned-columns`
   takes their banner as the header. `tmux` (061) is PARTIAL for a new reason.
   The round's banner work recognises decorated titles, `Label: value`
   comments and page headers. It does not recognise prompts, legends,
   letter-spaced banners or a first record.
2. **Nested or sectioned text flattened (10 FAIL, was 11).** All are
   unchanged except pyright, which moved to pattern 1: `callgrind_annotate`
   (003), `cmake -LAH` (005), `--prof-process` (029), node `--test` spec (030)
   and TAP (031), `trace --listfuncs` (055), `xz -lvv` (064), `helm template`
   (129), check_mk (133) and `nagios -v` (134). `section-tables` does not
   match any round-3 input (`--explain`). The multi-section family is still
   0 / 4 / 12, and `--prof-process`'s five titled tables still do not come
   out as tables.
3. **One section claimed, the rest dropped (8 FAIL, was 9).** `git
   show-branch` (018), `patch --verbose` (036), `pytest --fixtures` (047) and
   `--setup-plan` (048), `show spanning-tree` (115), `lsnrctl` (120),
   `cnpg status` (126) and `summary(lm())` (137) are byte-identical. The JES2
   log left this pattern for pattern 1. Tables, `vertical-line` and bespoke
   parsers are still exempt from the coverage hold.
4. **Wrong strategy or delimiter (5 FAIL, was 7).** `aws logs tail` and
   `doctest` were fixed. Still FAIL: `git blame` (016), `tokenize` (054),
   `openssl list -providers` (035) and `icacls` (107). So is
   `java -XX:+PrintFlagsFinal` (023): `json` still claims it, extracts
   nothing, and **there is still no output at all.**
5. **Two-word headers and wide cells (2 FAIL, was 3).** `Get-ChildItem` was
   fixed. Still FAIL: `doctl` (124), which still loses its IP addresses to
   duplicate column names in the melt, and `readelf -n` (056).

Of the engine findings above, two are fixed on these inputs: the
right-aligned value that lost a digit (102), and the silent `tsv` truncation
(123), which the consistency hold caught. `json` leaving no fallback (023),
duplicate names in the melt (124, and now 135), `gnu-version`'s invented
`warranty` field (134) and `pytest-summary` claiming at 27–31% coverage
(047, 048) all remain.

### Consistency and coverage against rating (after the fix round)

| column-type consistency | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| 100 | 61 | 16 | 31 | 14 |
| 95–99 | 10 | 1 | 6 | 3 |
| 80–94 | 10 | 0 | 7 | 3 |
| < 80 | 10 | 1 | 1 | 8 |
| not judged (`-`, incl. the no-output input) | 16 | 4 | 3 | 9 |

| line coverage | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 95% | 75 | 21 | 36 | 18 |
| 80–94% | 16 | 1 | 9 | 6 |
| 60–79% | 9 | 0 | 3 | 6 |
| < 60% (incl. 1 with no output) | 7 | 0 | 0 | 7 |

**Consistency separates in one direction only, like coverage.**

- Below 80, 8 of 10 inputs are FAIL. Below 95, 11 of 20 are FAIL (55%,
  against 35% overall).
- The one PASS under 80 is MATLAB `whos` (76). Its likely mixed column is
  `Size`: the name says size, but the cells are dimensions (`412x6`).
- But 17 of the 37 FAILs score 95 or more, and 9 more are not judged. A
  banner taken as the header, sections glued into a cell and a record
  flattened into columns all keep each column internally uniform.
  Consistency, like coverage, cannot see misplacement that is uniform.
- **The hold rarely acts.** `--explain` shows it holding 11 of the run's
  default claims and replacing one (123). Of the 10 it left standing, 7 are
  FAIL, 2 PARTIAL and 1 PASS. Eight of the ten have no candidate within 20
  points at all. On `srcds` (141) the only candidate cannot be judged. On
  `cnpg` (126) the record guard rejected an `aligned-columns` parse that
  scores 100, because it splits the rows further.

Coverage still catches dropped lines and nothing else. Every input below 60%
fails. Only one input below 95% passes (`system_profiler`, 92%). 18 FAILs
cover 95% or more. The two signals overlap little. An input that covers
under 60%, scores under 80 on consistency, or gives no output is a FAIL in 12
of 14 cases, but those 14 hold only 12 of the 37 FAILs. Where both signals
read 95 or more (56 inputs), 10 are still FAIL.

By confidence, a claim of 80 or more is wrong 33% of the time (21 of 63).
At 2.1.0 the figure was 40%.

### What these numbers are now

**Round 3 has now been measured after a fix round.** The fix agents never saw
it, so the before/after above (22 / 45 / 40 to 22 / 48 / 37) is an honest
generalisation delta for this round's changes. It is small: three FAILs
became PARTIALs, and the PASS count did not move.

**From here on, round 3 is seen.** This postscript names its remaining
defects input by input, and any work on them would be fitted to these files.
From now on it is a regression set, like rounds 1 and 2: re-run
`run.sh --round3` and read the diff against `ratings.tsv`. Do not quote
21% / 65% / 35% as what provost does on unseen output.

The next honest generalisation number needs a **round 4**: a fresh set that
is built, novelty-checked against rounds 1–3 and the corpus, frozen, and
rated on the same criteria before anyone parses it.
