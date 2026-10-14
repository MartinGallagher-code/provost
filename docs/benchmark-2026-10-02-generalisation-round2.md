# Held-out generalisation benchmark, round 2: 109 inputs nobody had seen

**2026-10-02.** This round put 109 tool outputs through `provost`. None of them
appear in the corpus, the holdout or round 1. Each result was rated on the
round-1 scale, and the scale was written down before the first input ran.
Round 1 stopped measuring generalisation once the engine had been fitted to its
fifty files (see the postscript to
[round 1](benchmark-2026-08-12-generalisation.md)). This round is the fresh
set that postscript asked for.

Everything is in the repo:

- the inputs:
  [`tests/benchmark/round2/inputs/`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round2/inputs)
- where each input came from:
  [`round2/manifest.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round2/manifest.tsv)
- the criteria, fixed before the run:
  [`round2/CRITERIA.md`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round2/CRITERIA.md)
- the rating for each input:
  [`round2/ratings.tsv`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round2/ratings.tsv)
- the novelty check:
  [`round2/novelty.py`](https://github.com/MartinGallagher-code/provost/blob/main/tests/benchmark/round2/novelty.py)
- the runner: `bash tests/benchmark/run.sh --round2`

## Headline

| | round 2 (n=109) | share | round 1 at first rating (n=50) | corpus `--golden` gate |
|---|---:|---:|---:|---:|
| PASS | 17 | **16%** | 46% | — |
| PARTIAL | 51 | **47%** | 24% | — |
| FAIL | 41 | **38%** | 30% | — |
| usable (PASS + PARTIAL) | 68 | **62%** | 70% | 96.7% "tidy" (3582/3706) |

**On output it has never seen, provost gets one input in six fully right.
Three in five are usable with some repair, and nearly two in five come out
wrong.** The corpus figure of 96.7% measures something else. It counts how
much tuning work has been done, and its "tidy" test is a shape check: the
right number of rows and at least the right number of columns. At least six of
this round's FAILs have exactly the right number of rows and at least the
right number of columns, so a shape check would pass them: `lsipc`,
`winget list`, PowerShell `Get-Volume`, `pg_lsclusters`, `gzip -lv` and
`openssl ecparam -list_curves`. In every one of them the values sit under the
wrong headers.

Round 2 is harder than round 1. It was chosen for shape diversity, and 13 of
its inputs are multi-section reports, compared with a handful in round 1. It
also includes Windows and macOS formats. The rating also counts some defects
as PARTIAL that a lenient reader might wave through: a dropped title banner, a
`(7 rows affected)` footer kept as a data row, a key whose value is empty
disappearing. Both effects lower the PASS share. Neither changes the FAIL
share much: a FAIL here means the output misrepresents the input.

## Method

### The set: 67 captured, 42 reproduced

| | n | what |
|---|---:|---|
| **captured** (001–067) | 67 | real output from commands run in the 2026-10-02 build container, read-only. Covers coreutils/util-linux, procps, `/proc`, binutils, gcc, go, rustc, cargo, node/npm, python (mypy, ruff, black, pytest, unittest, cProfile, dis, importtime, `http.server`), ruby/rake/gem, perl, php/composer, openssl, gpg, java/jar, apt/dpkg, PostgreSQL client tools, strace, curl and others |
| **reproduced** (101–142) | 42 | written by hand to match each tool's documented output format, for tools or platforms the container does not have: SQL Server `sqlcmd`, Oracle SQL\*Plus, DB2, `pg_controldata`, `mongostat`; AWS `--output table`, gcloud, IBM Cloud, OpenStack; `kubectl explain` / `--raw /readyz` / audit log / Prometheus exposition; `choco`, `winget`, `opkg`; `ipconfig /all`, `route print`, `scutil --dns`; `diskutil`, `wmic`, `Get-Volume`; Nagios, monit, pm2, ffmpeg; mocha, rspec, phpunit, tsc, nyc, surefire; IIS W3C, Apache error, PostgreSQL, Log4j, logfmt; JSON, NDJSON, YAML, CSV with BOM and CRLF, reST grid table, a mainframe print report |

**Scrubbing (captured inputs).** The container hostname, the service-account
user name, scratch-directory paths and the proxy CA-bundle path were replaced
with neutral values: `svc`, `/home/dev/project`, `/etc/ssl/certs/ca-bundle.crt`
and `/srv/data/...`. The one line that echoed the hostname (strace's `read`)
now reads `db1`. The JVM's `Picked up JAVA_TOOL_OPTIONS` proxy line was
removed. Inputs that would have shown container secrets (environment, network
addresses) were not captured. **Reproduced** inputs use invented values, the
RFC 5737 documentation ranges for IP addresses, and `example.com`.

Several inputs are truncated with `| head -N` to keep them reviewable, which is
how such output usually gets pasted. The manifest records the exact command.

### Novelty: how "never seen" was checked

1. **By name.** No input's tool-and-mode stem matches any file in
   `tests/corpus/inputs`, `tests/corpus/holdout/inputs`,
   `tests/corpus/text-inputs` or `tests/benchmark/inputs` (`_` and `-` treated
   as equal). The check caught three collisions, which were dropped before
   rating: `getent services` (the corpus has `getent_services`),
   `helm status`, and `node -p process.versions` (the corpus has
   `node-versions`). Four close relatives were also replaced: `az vm list-sizes`,
   which differed only in format, `aws cloudformation list-stacks`, whose table
   form is already in the corpus, `kubectl get pods -A -o wide`, which is
   covered by `kubectl-get-pods-all-namespaces` plus `-wide`, and
   `ls -l --time-style`.
2. **By content.** `novelty.py` compares every input with all 3,853 existing
   inputs on two measures after normalisation (lowercase, digits mapped to `0`,
   whitespace collapsed): the Jaccard similarity of their line sets, and the
   Jaccard similarity of their word 3-gram sets. The highest 3-gram similarity
   in the final set is **0.20**: `factor` against `pidof`, and once digits are
   normalised, both are runs of `0 0 0`. 100 of the 109 inputs are ≤ 0.06.
   The highest line-set figures (0.38 for `node-os-cpus`, 0.33 for `od-hex`)
   come from shared lines that are only punctuation or numbers (`{`, `},`,
   `000015`). They are not shared content.
3. **No hints were added and nothing was tuned.** Every input was added before
   its parse was looked at. Engine, strategies and `hints.tsv` are at main
   `20f4dfa`, unchanged.

### Runs

Each input went through the engine three ways, exactly as `provost` calls it:

- **default**: `-f tsv --max-strategies 1`, the confidence ranking, then
  melted to the tidy table (`run.sh --tidy` writes `NAME.tidy`);
- **`--multi`**: `--multi -f tsv --max-strategies 1`, the flags at
  `provost:776`. Each dataset is melted separately into `NAME.multi.tidy`;
- **`--rank priority`**: the ranking used before calibration, in which the
  first detecting strategy in priority order wins.

`run.sh --round2` runs all 109 inputs in about 4½ minutes on a busy 4-core box.
The two single-dataset modes use the engine's `--batch --batch-out` fast path,
which sources the strategy tree once per job slot rather than once per input.
`--multi` runs per input in a job pool, and it is most of the wall time.

### Rating

Each result was rated PASS, PARTIAL or FAIL against what a careful human would
call the tidy dataset, using the scale in `CRITERIA.md`, which is unchanged
from round 1. Six application rules were written down beside the scale before
rating began. Two matter most. A free-text fallback that keeps every line, one
column wide, is PARTIAL. Round 1 rated `git log --stat` and Java properties the
same way after its fixes. Losing a substantial section is FAIL. As in round 1,
**this is a self-assessment by an agent. Treat it as a screen, not a verdict.**

## Results

### By shape family

| family | n | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|---:|
| aligned / fixed-width table | 21 | 4 | 7 | 10 | 52% |
| list, grid, help text, free text | 20 | 0 | 13 | 7 | 65% |
| log and diagnostic lines | 20 | 3 | 14 | 3 | 85% |
| multi-section report | 13 | 0 | 2 | 11 | **15%** |
| single key/value record | 11 | 3 | 6 | 2 | 82% |
| key/value blocks (several records) | 10 | 0 | 5 | 5 | 50% |
| structured data (JSON/YAML/CSV/NDJSON) | 8 | 4 | 2 | 2 | 75% |
| box / rule-drawn table | 6 | 3 | 2 | 1 | 83% |

The pattern is clear. **Formats with explicit syntax are mostly right**: JSON,
YAML, CSV with BOM and CRLF, NDJSON, logfmt, Unicode box tables, the `psql`-style
OpenStack table. **Whitespace tables are a coin flip.** Ten of the 21 FAIL, and
every one of those failures comes from the same cause: a cell containing a
space. **Multi-section reports almost always fail.** Eleven of the 13 FAIL,
because a strategy claims one section and silently drops the others.

### By category

| category | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| system (`/proc`, util-linux, procps) | 14 | 2 | 8 | 4 |
| language tooling | 12 | 2 | 3 | 7 |
| build | 12 | 1 | 8 | 3 |
| test / lint | 11 | 1 | 7 | 3 |
| package manager | 8 | 1 | 3 | 4 |
| text utilities | 8 | 0 | 4 | 4 |
| database | 7 | 3 | 3 | 1 |
| logs | 6 | 1 | 4 | 1 |
| crypto | 5 | 1 | 0 | 4 |
| data format | 5 | 1 | 3 | 1 |
| monitoring | 5 | 1 | 1 | 3 |
| network | 4 | 0 | 3 | 1 |
| cloud | 4 | 2 | 1 | 1 |
| storage (macOS/Windows) | 3 | 0 | 0 | 3 |
| k8s | 3 | 1 | 1 | 1 |
| shell | 2 | 0 | 2 | 0 |

By provenance: **captured** inputs scored 8 PASS, 32 PARTIAL and 27 FAIL
(60% usable). **Reproduced** inputs scored 9 PASS, 19 PARTIAL and 14 FAIL (67%
usable). The hand-written reproductions are not noticeably easier or harder
than real captures, which is some evidence that they are faithful.

### What passes

These 17 came out fully right:

- tables: `proc/net/protocols` (26 columns, including a y/n matrix),
  `proc/self/maps` (empty path cells stay in place), `mongostat` (`*0`, `2|0`,
  and a two-token time), `pm2 list` and `node console.table` (Unicode boxes),
  the OpenStack table (multi-value Networks cell), `opkg list-installed`;
- key/value: `pg_config`, `pg_controldata` (apostrophes in keys),
  `perl -V:` (one record);
- structured data: single-line JSON from `cmake -E capabilities`, the CSV
  (BOM, CRLF, quoted thousands, an embedded comma), gcloud YAML, NDJSON audit
  events, logfmt (21 keys unioned across events);
- lines: `md5sum -c` (`labeled-records`), `ruff --statistics`.

## Top failure patterns: the next parser work

These patterns were left unfixed on purpose: fixing them against these files
would turn this set into a second corpus. The patterns are listed as directions
for future work. Do not treat them as a punch list against these inputs, and
validate any fix against fresh inputs.

### 1. Column boundaries come from whitespace tokens, not header offsets (13 inputs, 10 FAIL)

Any cell containing a space breaks an aligned table. That covers multi-word
descriptions, multi-word names, multi-token dates and two-word headers.

- **`lsipc`** (025): `Number of message queues` is split one word per column,
  so LIMIT, USED and USE% hold the words `of`, `message` and
  `queues 32000 0 0.00%`.
- **`winget list`** (140): `Microsoft Visual Studio Code (User)` spreads over
  the Name, Id, Version and Available columns.
- **`ps -eo pid,lstart`** (048): PID absorbs `Fri Oct`, and ELAPSED merges with
  COMMAND.
- **`gzip -lv`** (021): the date `Oct  2` shifts every later value one column
  to the left.
- **`pg_lsclusters`** (040): `Data directory` and `Log file` become the names
  `Data` and `directory`, so the log path ends up under `directory`.
- **`lslogins`** (026): five headers merge into one column, and the empty
  LAST-LOGIN column makes it worse.
- **PowerShell `Get-Volume`** (131): right-aligned `SizeRemaining`/`Size` are
  cut at the wrong offset.
- **cProfile** (051): the repeated `percall` header collapses into one column,
  so a value is lost and the rest shift.
- **`diff -y`** (013): empty tab fields collapse, and the right-hand values
  are lost.

`aligned-columns` won 33 of the 109 inputs and passed only 4 of them. Its
header row already gives the character offset where each column starts.
Assigning cells by those offsets, the way round 1's sparse-table fix did, is the
most valuable single change this round points to.

### 2. Multi-section reports: one section claimed, the rest dropped (11 inputs, all FAIL)

A strategy recognises one section with high confidence, extracts it, and
discards the rest without any signal.

- **`gpg --version`** (019): `gnu-version` (confidence 92) keeps the banner
  and drops the five supported-algorithm lists, which are the substance of the
  output.
- **`apt-cache showpkg`** (001): `kv-under-group` keeps the Versions block and
  drops the 28-line Reverse Depends list.
- **`pip debug --verbose`** (043): 13 scalar lines are kept and the 26-line
  vendored-library list is dropped, 65% of the input.
- **`gem env`** (016): the scalars are kept, and the PLATFORMS, GEM PATHS and
  SHELL PATH lists are dropped.
- **`update-alternatives --query`** (064): only the Slaves lists survive.
- **`kubectl explain`** (113): the GROUP/KIND/VERSION/FIELD header is dropped,
  and **`vim --version`** (065) loses its version line.
- **phpunit** (128): a few `x: y` fragments are harvested and the test
  identities are lost.
- **`diskutil list`** (106), **`route print`** (133) and **ffmpeg** (107): whole
  sections or tables are glued into one cell.

The truncation guard from round 1 caught none of these. It compares the size of
the parse with the input, and these parses are large enough to clear it because
they are wide. It needs a coverage measure instead: the share of input lines
that contributed at least one value.

`--multi` rescues part of this family. It improved 17 inputs, and 10 of those
were default-mode FAILs: `gpg --version` gets its algorithm lists back,
`route print` gets a clean IPv4 table, `apt-cache showpkg` gets its Reverse
Depends, cProfile gets its banner and a table without the column shift, and
`unittest -v` gets a clean test table. It made 7 inputs worse. Round 1 reached
the same conclusion: segmentation belongs closer to the default.

### 3. A banner or title becomes the header, or keeps the table from being found (12 inputs)

- **`gcc -Q --help=warnings`** (015) and **`readelf -l`** (058): a prose banner
  becomes the header and is shredded one word per column.
- **`go tool pprof -top`** (017): `File: calc.test` becomes the header, and
  each row's five numbers and function name land in one cell.
- **IIS W3C** (110): `#Fields:` becomes the first column name, so every value
  sits one column to the left of its name.
- **Mainframe report** (117): the page header becomes the column names.
- **`choco list`** (103): `Chocolatey v2.3.0` becomes the column names.
- **`bash set -o`** (004) and **`python -m dis`** (052): the first data row
  becomes the header.
- **IBM Cloud** (109) and **nyc** (124): a `Retrieving... / OK` banner or a
  `---|---` rule keeps an otherwise plain table from being detected.

nyc is the clearest case. `--multi` parses the same single block with
`pipe-table` at confidence 80, while default mode falls back to `text-lines` at
50. The same strategy gets a different detection result depending on the path.

### 4. Line-oriented diagnostics fall back to one column of whole lines (13 inputs, all PARTIAL)

`mypy` (`file:line: error: msg [code]`), `tsc` (`file(l,c): error TSnnnn:`),
Log4j and PostgreSQL logs (timestamp, level, thread, then message plus
continuation lines), `unittest -v`, `curl -v` (`*`/`>`/`<` markers),
`cargo --list`, `make --help`, `factor`, `od`, monit and the surefire counters
all come out as `text-lines`. Nothing is lost, but nothing is split either. No
generic parser handles "a fixed prefix grammar followed by free text", and
continuation lines are never attached to the record above them. Round 1's
"dropped-line" cluster was the opposite failure; the round-1 fixes turned it
into this one.

### 5. Wrong strategy, wrong delimiter (17 inputs)

A format-level parser claims input it does not understand:

- `toml` claims `composer config --list` from one `Set X=1` banner line, and
  all 37 `[key] value` settings are lost (010);
- `equals` splits strace at the `=` inside `st_mode=` (063);
- `vertical-line` cuts pytest output at a fixed character column (049);
- `yaml` reads `wmic`'s `C:` drive letter as a mapping key (141);
- `csv` splits Prometheus samples at the commas inside `{...}` (132);
- `semicolon-values` splits Nagios perfdata (122);
- `colons` collapses fifteen `openssl list` records into one row (037) and
  turns a JS object literal into bracket debris (032);
- `colon-fields` splits `APT::Key::...` keys at every `::` (002);
- `gpgconf --list-components` is genuinely colon-delimited, but it is split on
  spaces instead (020).

### 6. Indentation that carries meaning is stripped (5 inputs)

`comm` (009) is the extreme case: which column a word is in is the entire
output, and that information is gone. `namei -l` (030) loses which symlink each
sub-walk resolves, the calendar (050) loses the weekday of its first week,
mocha (119) loses suite nesting, and nyc loses directory nesting.

### Smaller clusters

- **Empty values dropped:** DB2's `Comment =` and `Alternate server ... =`,
  and JSON `assignees: []`.
- **Section labels dropped:** `ipcs -l` section titles, `scutil` `resolver #N`,
  `ipconfig` adapter headings.
- **Footers kept as data rows:** `(7 rows affected)` and `5 rows selected.`.
- **A multi-line reST cell loses its second line.**

## Confidence ranking against priority ranking

**On these 109 unseen inputs, confidence ranking and calibration changed
nothing.** `--rank priority` picked the same winning strategy as the default
ranking on all 109, and the output was byte-identical on all 109.

The reason is not that only one strategy matched. Running every detector
(`_EAS_NOPRUNE=1 -d`) shows that 98 of the 109 inputs had two or more
candidates, typically four or five. But the candidate with the highest
confidence was also the one with the best priority in 108 of the 109. The
calibrated confidences (format parsers 80–85, `aligned-columns` 62–69,
`line-records` 50–55, `text-lines` 50) follow the priority order almost
exactly. The one input where they disagreed was `objdump -d` (034):
`columnar-specs` (85) led on confidence and `key-value` led on priority.
`columnar-specs` extracted nothing, so both rankings fell through to
`key-value`.

In 19 inputs the top candidate fell through, extracting nothing or tripping the
truncation guard. In both modes the next candidate won.

Confidence is also a weak predictor of quality:

| winning confidence | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 85 | 17 | 5 | 7 | 5 |
| 80–84 | 34 | 6 | 14 | 14 |
| 60–79 | 36 | 5 | 13 | 18 |
| < 60 | 22 | 1 | 17 | 4 |

A confident claim of 80 or more is still wrong 37% of the time (19 of 51).
Every input scored at least 50, so with the default `PROVOST_MIN_CONFIDENCE=50`
all 109 commit and none goes to triage. The low-confidence band is mostly honest
`text-lines` PARTIALs, so the threshold does catch "unparsed", but it does not
catch "parsed wrong". Calibration made the ranking principled. It does not yet
tell a right parse from a wrong one, and the coverage measure suggested in
pattern 2 is the obvious second signal.

## Two engine findings outside the ratings

- **`--batch` skips text that ends in three or more newlines as if it were
  binary.** The batch loop in `lib/_dispatch.sh` tests "file size minus the
  bytes `$(<file)` returns > 2". Command substitution strips trailing newlines,
  so `size -A`, the mocha output and the `Get-Volume` output were silently
  skipped. No corpus input currently ends that way, so the corpus `--golden`
  fast path is unaffected today. `run.sh` redoes any input the batch left
  without output, one input at a time. Not fixed here: this round is
  measurement only.
- **`--multi` can parse a single block better than default mode does.** nyc
  gets `pipe-table` instead of `text-lines`, and `diff` gets `line-records`
  instead of `vertical-line`. The block-level detection path and the
  whole-input path disagree on identical text.

## Reproducing

```bash
bash tests/benchmark/run.sh --round2 /tmp/r2          # ~4-5 min on 4 cores
bash tests/benchmark/run.sh --round2 --tidy /tmp/r2   # + melted .tidy / .multi.tidy
python3 tests/benchmark/round2/novelty.py             # re-check novelty after adding inputs
```

The script prints one summary line per input: strategy and confidence, input
and output line counts, the number of `--multi` datasets, and the priority-mode
winner when it differs. Nothing is asserted. Read the diff against
`round2/ratings.tsv`.

## When this set retires

When the next fix round works these clusters, update `ratings.tsv` in the same
commit and add a postscript here, as round 1 did. From then on the set measures
regression, not generalisation. The next honest generalisation number needs a
round 3 that nobody has parsed.

## Postscript, 2026-10-14: patterns 1–4 were worked, and this set is now a regression measure

A fix round worked failure patterns 1 to 4 (CHANGELOG, the three 2026-10-14 engine
entries):

- **Pattern 1, whitespace tables.** A gutter grid (`_fr_gutter_grid` in
  `extract/lib/_helpers.sh`) assigns cells by character offset. It is used by
  `aligned-columns`, `fixed-width` and `embedded-table`. A cell holding a
  space, an empty cell and a two-word header no longer shift the values after
  them.
- **Pattern 3, banners.** `aligned-columns` recognises some banners, titles
  and W3C `#Fields:` directives. Result-set footers are dropped. `pipe-table`
  now reads bare tables drawn with `---|---` rules in default mode.
- **Pattern 4, line diagnostics.** Two new generic parsers:
  `prefix-message`, for diagnostics and logs (typed prefix fields, then the
  message, with continuation lines attached), and `help-columns`, for
  `--help` pages and command lists.
- **Pattern 2, multi-section reports.** The engine now measures line
  coverage: the share of input lines that contributed to the parse. When a
  claim covers less than 60%, the engine holds it and tries a key/value-report
  rescue (`kv-report`). `gnu-version` now keeps the whole report.
- **Regression guards.** Three guards were added after the first round-2 run
  exposed misreads.

The work was developed against new examples and the corpus. Round 2 was run
only at the end of each change. Even so, the set has now been looked at, so
the numbers below are not a generalisation result.

Ratings were redone on the final engine in default mode, with the same
criteria and the same six rules. In 87 of the 109 inputs the default tidy
output is byte-identical to 2026-10-02 (checked with `cmp`), so those ratings
carry over. The other 22 were re-rated from the input and both outputs.
`ratings.tsv` keeps the original columns and adds `strategy_1014`,
`conf_1014`, `cov_1014`, `rating_1014` and `note_1014`.

### Headline

| | 2026-10-02 | share | 2026-10-14 | share |
|---|---:|---:|---:|---:|
| PASS | 17 | 16% | 26 | **24%** |
| PARTIAL | 51 | 47% | 54 | **50%** |
| FAIL | 41 | 38% | 29 | **27%** |
| usable (PASS + PARTIAL) | 68 | 62% | 80 | **73%** |

Of the 22 changed outputs:

- 9 became PASS: 5 from FAIL and 4 from PARTIAL.
- 7 went from FAIL to PARTIAL.
- 6 changed but kept their PARTIAL rating.

**No default-mode output got worse.**

| family (only those that moved) | n | 10-02 PASS / PARTIAL / FAIL | usable | 10-14 PASS / PARTIAL / FAIL | usable |
|---|---:|---|---:|---|---:|
| aligned / fixed-width table | 21 | 4 / 7 / 10 | 52% | 7 / 9 / 5 | 76% |
| list, grid, help text, free text | 20 | 0 / 13 / 7 | 65% | 1 / 14 / 5 | 75% |
| log and diagnostic lines | 20 | 3 / 14 / 3 | 85% | 5 / 13 / 2 | 90% |
| multi-section report | 13 | 0 / 2 / 11 | 15% | 0 / 4 / 9 | 31% |
| single key/value record | 11 | 3 / 6 / 2 | 82% | 4 / 5 / 2 | 82% |
| key/value blocks | 10 | 0 / 5 / 5 | 50% | 2 / 5 / 3 | 70% |

Structured data (8) and box tables (6) are unchanged.

### What changed, input by input

**FAIL to PASS (5):**

- `lsipc` (025), `ps -eo lstart` (048) and `pg_lsclusters` (040): the gutter
  grid keeps a multi-word description, a five-token date and two two-word
  headers as one cell or label each.
- `gem env` (016) and `pip debug` (043): `kv-report` keeps every scalar and
  every list as rows. The only things dropped are a title with no content and
  the debugging disclaimer.

**PARTIAL to PASS (4):**

- `bash set -o` (004): the first option is no longer taken for the header.
- mypy (029) and Log4j (115): `prefix-message` splits the typed fields, and
  for Log4j it attaches the stack trace to its event.
- `rake -T` (056): `help-columns` splits name and description at the `#`.

**FAIL to PARTIAL (7):**

- `gcc -Q --help=warnings` (015): the banner is no longer the header, but the
  first option is.
- `gpg --version` (019): every section is kept, but the licence is cut to
  `GNU`.
- `lslogins` (026): the values are right, but the empty LAST-LOGIN column is
  merged into the header `PWD-DENY_LAST-LOGIN`.
- cProfile (051): no value is dropped or shifted, but the second `percall`
  is merged with the filename, and the call-count banner is still dropped.
- `python -m dis` (052): the columns are stable, but the first instruction is
  still the header and offset and opname stay merged.
- IIS W3C (110): every record is under the right names, but the second
  block's directives are shredded data rows.
- phpunit (128): every line is kept, but each error spans four to five rows.

**Changed, still PARTIAL (6):**

- `cargo --list` (007) and `make --help` (027): one entry each lands whole in
  `description`.
- `choco list` (103): the banner is a data row rather than the header.
- IBM Cloud (109): the table is exact, but the banner that names the account
  and user is dropped.
- nyc (124): the table is exact, but the indentation that shows nesting is
  stripped.
- PostgreSQL log (130): timestamp and pid are split and continuation lines
  are attached, but user@db and severity stay inside `message`.

### What still fails, by pattern

1. **Whitespace tables.** Fixed: `lsipc`, `ps`, `pg_lsclusters` (PASS) and
   `lslogins`, cProfile (PARTIAL). Byte-identical and still FAIL:
   - `winget list` (140): the input has non-ASCII bytes, and the grid
     withdraws on those.
   - `gzip -lv` (021).
   - PowerShell `Get-Volume` (131).
   - `diff -y` (013).

   The footers of `sqlcmd` (137) and SQL\*Plus (138) are still data rows, even
   though footer handling was part of this round.
2. **Multi-section reports.** Four of the 11 FAILs moved: `gem env`,
   `pip debug`, `gpg --version` and phpunit. Seven still FAIL:
   - `apt-cache showpkg` (001): a table claim, which is exempt from the hold,
     at 43% coverage.
   - `update-alternatives` (064): 70%.
   - `kubectl explain` (113): 91%.
   - `vim --version` (065), `diskutil` (106), `route print` (133) and
     ffmpeg (107): their sections are glued into cells rather than dropped.
     Coverage stays near 100%, so the hold never fires. Segmentation is
     still the tool for these.
3. **Banners.** Still FAIL:
   - `readelf -l` (058).
   - `go tool pprof -top` (017).
   - the mainframe report (117): the page header is still the column names.

   Partly fixed: gcc, dis, IIS, choco and IBM Cloud, as listed above.
4. **Line diagnostics.** Fixed: mypy, Log4j and `rake`. Improved but PARTIAL:
   PostgreSQL, `cargo` and `make`. Byte-identical and still `text-lines`:
   - tsc (139): improves under `--multi` only.
   - `unittest -v` (055).
   - `curl -v` (011).
   - `factor` (014).
   - `od` (035).
   - monit (121).
   - surefire (118), as `aligned-columns`.
5. **Wrong strategy, wrong delimiter.** Not worked, and unchanged except
   `rake`:
   - `composer config` (010) is still claimed by `toml` from one banner line.
     Coverage reads 2%, but `toml` is exempt from the hold.
   - strace (063), pytest (049), Prometheus (132), Nagios (122), the
     `openssl list` records (037) and the JS literal (032) are as before.
6. **Indentation.** Not worked: `comm`, `namei`, the calendar, mocha and nyc
   are as before.

`--rank priority` no longer matches the default on every input. It differs
on five. On four of them (`gem env`, `pip debug`, `rake -T`, phpunit) the
priority-mode output is byte-identical to the 2026-10-02 default. The rescue
does not run under priority ranking, and priority order still gives
`rake -T` to `pkg-config`. On the fifth, the Apache error log (101), priority mode
now picks `prefix-message` over `bracket-log`. The `prio_rating` column was
not redone; for those four inputs the old rating still applies. `--multi`
output changed on 27 inputs, and the `multi` column was not redone either.

### Line coverage against rating

The final engine reports coverage as the 4th field of `--emit-meta`, so the
`.meta` files give it for every input:

| line coverage | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 95% | 90 | 26 | 45 | 19 |
| 80–94% | 11 | 0 | 6 | 5 |
| 60–79% | 5 | 0 | 2 | 3 |
| < 60% | 3 | 0 | 1 | 2 |

The three inputs below the 60% threshold are `composer config` (2%, FAIL),
`apt-cache showpkg` (43%, FAIL) and `go test -v` (52%, PARTIAL: the failure
messages are dropped). All three are bad parses. None of them is rescued,
because `toml`, tables and bespoke strategies are exempt from the hold.
provost now prints a low-coverage note for each of them.

The same inputs by confidence, for comparison with the 2026-10-02 table:

| winning confidence | n | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|---:|
| ≥ 85 | 17 | 6 | 7 | 4 |
| 80–84 | 38 | 9 | 19 | 10 |
| 60–79 | 38 | 10 | 17 | 11 |
| < 60 | 16 | 1 | 11 | 4 |

**Coverage separates bad parses better than confidence does, but only in one
direction.** No input below 97% coverage is a PASS. Of the 19 inputs below
95%, 10 are FAIL, against 27% across the whole set. Confidence has no band
like that: a claim of 80 or more is still wrong a quarter of the time (14 of
55). But coverage misses most FAILs. 19 of the 29 cover 95% or more, because
what is left in the FAIL column is mostly misplacement: values under the
wrong header, sections glued into a cell, prose shredded across columns.
Those parses keep every token. Coverage measures whether lines were dropped,
not whether a parse is right. At the 60% threshold it catches 2 of the 29
FAILs.

### What these numbers are now

From this round on, **round 2 is a regression set on seen inputs, not a
generalisation measure.** The fixes were developed elsewhere, but every
change was checked here at the end, and this postscript lists defects input
by input. Any further work on the remaining defects would be fitted to these
files. 24% PASS and 73% usable is what provost does on these 109 inputs
today. It does not say what provost does on output it has never seen.
`run.sh --round2` still works unchanged; re-run it and read the diff against
`ratings.tsv` to catch regressions.

The next honest generalisation number needs a **round 3**: a fresh set
nobody has parsed, chosen and novelty-checked before its first run, and
rated on the same criteria.
