# Held-out generalisation benchmark, round 3: 107 inputs nobody had parsed

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
