# Held-out generalisation benchmark, round 5: 107 inputs nobody had parsed

**2026-11-04 (PV-005).** Round 4 is spent. `--llm`, the tiny LM and the
auto-multi work were all measured on it and then worked against it. Every
open measurement in HANDOFF (0a, 0e, 0h, 0k) was waiting on a fresh unseen
set. This is that set, built and frozen before anything ran, and rated blind
for four readers:

- the default engine;
- `--multi`;
- the layout model on its own (`--model`'s labeller, the shipped 18-layer LM);
- `--llm` at first contact (Claude writes the template through the real API).

The engine is `main` @ a8c3d0c, provost 2.3.0.

As in rounds 1 to 4, **the ratings are a self-assessment by agents. Treat
them as a screen, not a verdict.**

Everything is in the repo:

- the inputs: `tests/benchmark/round5/inputs/`
- where each one came from: `round5/manifest.tsv`
- the freeze: `round5/SHA256SUMS`, committed in b0fd175 before the first run
- the criteria: `round5/CRITERIA.md` (round 4's, unchanged below a dated note)
- every rating, with each rater's reason: `round5/ratings.tsv`
- the novelty check: `round5/novelty.py`
- the templates `--llm` wrote and its API log: `round5/llm-templates-learn/`
- the runner: `bash tests/benchmark/run.sh --round5`

## Headline

| reader (n = 107) | PASS | PARTIAL | FAIL | usable | round 4 |
|---|---:|---:|---:|---:|---|
| **default engine** | 14 (13%) | 60 (56%) | 33 (31%) | **69%** | 12 / 51 / 44 (59%) |
| `--multi` | 14 (13%) | 59 (55%) | 34 (32%) | 68% | 12 / 64 / 31 (71%) |
| layout model alone (LM, model-first) | 10 (9%) | 23 (21%) | 74 (69%) | 31% | 5 / 30 / 72 (33%) |
| **`--llm`, first contact** | **96 (90%)** | 9 (8%) | 2 (2%) | **98%** | 66 / 30 / 11 (90%) |

**On output it has never seen, the engine gets about one input in eight fully
right, seven in ten usable, and three in ten wrong.**

That is the same picture as every earlier first rating. The FAIL share is ten
points under round 4's. At n = 107 the 95% margin on a share near 35% is
about ±9 points, so the drop is at the edge of noise and is not a measured
gain. The PASS share (13% against 11%, 21% and 16% in rounds 4, 3 and 2) has
not moved.

Measured head to head on the same inputs, **`--llm` is the one reader that
changes the answer**:
- it rates higher than the engine on 85 inputs, lower on 1, and the same on 21;
- it files 100 captures with a template it wrote and leaves 7 to the engine;
- 9 of its 11 non-PASS ratings are minor (one field glued, a line dropped);
- its 2 FAILs (`xmllint --shell`, z/OS `D A,L`) are captures it left to the
  engine, rated on the engine's output.

Round 4's first contact gave 66 PASS. This round gives 96 on fresh output.
`template.py`, the guide and the routing rules all changed after round 4
(HANDOFF 0j, 0k), so part of the rise is that work. Part may be the set:
round 5 is more tables (33 against 26) and fewer logs (12 against 19).

## Method

### The set: 65 captured, 42 reproduced

| | n | what |
|---|---:|---|
| **captured** (001–065) | 65 | real output of read-only commands run in the 2026-11-04 container, on scratch C, Rust, Go, Java, Python, Ruby, Perl, PHP and JS projects, a scratch 64 MiB ext4 image, a scratch `redis-server` on a private port and a scratch JVM: clang (`-dump-tokens`, clang-tidy diagnostics and `-list-checks`, clang-format `-dump-config`), gcc (`-Q --help=optimizers`, `-fstack-usage`, `-fopt-info-vec`, `-ftime-report`, `-fdump-tree-original`), LLVM (`llvm-bcanalyzer`, `llvm-nm -S`, `llvm-objdump -t`, `opt -debug-pass-manager`), nasm listing, readelf (`-V`, `-r`, `-Ws`), `ldd -v`, gdb (`info functions`, `info registers`), cachegrind, rustc (`--explain`, borrow errors, `--print target-cpus`), `cargo test` with a panic backtrace, Go (`test -json`, coverprofile, `tool objdump`, `-gcflags=-S`), JDK (`jcmd Compiler.codecache`, `jinfo -flags`, `-Xlog:class+load`, jshell), Python (pdb session, tracemalloc), pyright `--stats`, `ruff linter`, `flake8 --benchmark`, Ruby (`--dump=parsetree`, `ObjectSpace.count_objects`, `gem specification`), `perl -MO=Xref`, `php --rf`, Node (`-p process.config`, `--trace-opt`), redis-cli (`INFO commandstats`, `INFO persistence`, `MEMORY STATS`, `COMMAND DOCS`, `ZRANGE ... WITHSCORES`), `debugfs ls -l`, ffmpeg (`-encoders`, `-pix_fmts`, framemd5), `ffprobe -show_packets -of compact`, ImageMagick (`identify -verbose`, `-list format`), pandoc (native AST, `--list-extensions`), `jq --debug-dump-disasm`, `m4 --debug`, `make --trace`, `ninja -t graph`, `gpgconf --list-options`, `openssl list -digest-algorithms`, `xmllint --shell` |
| **reproduced** (101–142) | 42 | written by hand to each tool's documented format, for platforms the container does not have: Windows (`driverquery /v`, `netsh wlan show interfaces`, `ipconfig /displaydns`, `dism /get-features /format:table`, `net user`, `Get-NetAdapter`); macOS (`vm_stat`, `networksetup -listallhardwareports`, `softwareupdate --list`); network gear (Arista `show interfaces status`, Junos `show bgp summary`, Cisco `show environment all` and `show inventory`, FortiOS `get system status`, RouterOS `/ip route print`, Comware `display vlan all`, Nokia SR OS `show router interface`); storage and hypervisors (NetApp `volume show`, `esxcli storage core device list`, `vim-cmd vmsvc/getallvms`, `naviseccli getlun`, IBM SVC `lsvdisk`, Veritas `vxprint -ht`, Spectrum Protect `query node`); databases (Db2 `list tablespaces show detail`, SQL*Plus `SHOW SGA`, HANA `hdbsql`, cqlsh tracing); z/OS `D A,L`, CICS `CEMT INQUIRE TRANSACTION`, OpenVMS `SHOW SYSTEM`, Solaris `prstat` and `svcs -x`, AIX `lspv`, HP-UX `bdf`, IBM HMC `lssyscfg`; PBS `qstat -f`, `openstack hypervisor show`; `samtools coverage`, CheckM `qa`; Asterisk `sip show peers`; Postfix `qshape` |

By shape family the set is 33 tables, 15 lists / help / free text, 15
key/value records, 14 multi-section reports, 12 logs and diagnostics, 9
structured dumps and 9 key/value block reports.

- **Environment.** Every capture ran with `HOME=/home/dev`, `NO_COLOR=1` and
  `TERM=dumb`, from scratch directories under `/home/dev`, so no path needed
  scrubbing. Java tools ran with the container's `JAVA_TOOL_OPTIONS` (proxy
  settings) unset. No git command was run to make any input.
- **Truncation.** Several captures are cut with `| head -N`, as such output
  is usually pasted. The manifest records every exact command.
- **Reproductions.** Two subagents wrote 39 of them from documented formats
  (they wrote 42; three were dropped, below) and the session that ran the
  round wrote the other 3. None of them ran provost or looked at a parse. Values are invented, and addresses use the RFC 5737 /
  RFC 3849 ranges and `example.com`.
- **Choice.** No input was chosen, edited or dropped because of how provost
  might parse it.

### Novelty

`round5/novelty.py` is round 4's script, extended to round 4's inputs and its
second captures. It compares every input against all 4,281 existing inputs.

**Name screen.** Candidates were screened against all 4,105 existing name
stems before capture, and the novelty run found no clash in the final set.

**Content screen.** 16 captured candidates were dropped for sharing a format
with an earlier input:
- 14 because their 3-gram or line-set similarity was 0.15 or more (`llvm-size
  -A` against round 2's `size -A`, `jcmd VM.flags -all` against round 3's
  `PrintFlagsFinal`, `jstat -gcutil`, `jstat -class`, `strace -c`, valgrind
  memcheck and callgrind, `go test -bench`, `llc -time-passes`, `pstats`,
  `mkfs.ext4 -v`, `e2fsck -fnv`, `-XX:+PrintCommandLineFlags`, `clang -###`);
- 2 whose scores were lower (0.14) but which are the same format as an
  earlier input (`clang -E -dM` against round 3's `cpp -dM`, `php --rf`
  against round 4's `php --rc`).

On the same rule, four more were dropped (`jcmd GC.class_histogram` is
`jmap -histo`, `jcmd Thread.print` is jstack, and also lldb `image list` and
`php --re`). So were three reproductions (`diskutil list`, `SHOW ENGINE INNODB
STATUS`, `scontrol show node`), and `getent services` for a name clash.

**In the final set no input clashes by name.** The highest 3-gram similarity
is 0.11 (`samtools coverage` against a turbostat table: shared column words).
The highest line-set figure is 0.11 (`node --trace-opt` against a one-line
corpus input, `git rev-list --count`: a single shared normalised line).

**Nothing was tuned.** The only code change is `run.sh --round5`.

### Runs

Each reader ran once, after the freeze:

| reader | command | time |
|---|---|---|
| default + `--multi` | `run.sh --round5 --tidy -j 2` | 5 min 6 s |
| model | `model_round.sh --round5 OUT --lm DIR` | 9 min 24 s on 4 cores |
| `--llm` | `llm_round.sh --round5 OUT --learn --jobs 8` | 3 min 43 s |

For the model run, DIR is the `provost-model` 0.1.0 package's numpy export:
the 18-layer LM that `pip install provost[lm]` ships. The run is model-first,
as in round 4: no engine parse, no gate, no arbiter.

`--llm` made 105 API calls. Opus 5.5 answered 102; the refusal fallback
answered 3. They used 356,270 input and 143,053 output tokens, about $4.30
at the rates that put round 4's 108 calls at $5.20. It filed 100 captures by
a new template (none held) and left 7 to the engine.

**The quality gate** would hold 7 captures (round 4: 18). The rule is provost's
own: `_quality_exempt`, with coverage under 80 or consistency under 70. On
those 7 the readers rate:

| reader | PASS / PARTIAL / FAIL |
|---|---|
| engine | 0 / 1 / 6 |
| `--multi` | 0 / 4 / 3 |
| model | 0 / 1 / 6 |
| `--llm` | 6 / 1 / 0 |

### Rating, blind

The four readers made 428 outputs, and 346 of them are distinct (input,
output) pairs. An output identical to another reader's on the same input
counts once.

Each pair went on its own sheet: the input, then the output as tidy tables.
Nothing on the sheet tells the rater which reader made it:
- the reader is not named;
- the store's `#` / `capture` columns are stripped;
- dataset names and strategy banners are replaced by `--- dataset K ---`.

The sheets were shuffled and split among six subagent raters. Each read
`CRITERIA.md` first. Its round-5 note writes out the tie-break calls rounds 3
and 4 used, and adds that nothing extracted is a FAIL.

Every sheet was rated exactly once. I spot-checked a sample of calls against
their sheets, and they hold. One caveat stands as in round 4: the raters and
the template writer are the same model family.

## By family

| family | n | default | `--multi` | model | `--llm` |
|---|---:|---|---|---|---|
| aligned / fixed-width table | 33 | 6 / 20 / 7 | 6 / 20 / 7 | 4 / 10 / 19 | 32 / 1 / 0 |
| list, grid, help, free text | 15 | 3 / 7 / 5 | 3 / 7 / 5 | 3 / 2 / 10 | 14 / 0 / 1 |
| key/value record | 15 | 1 / 8 / 6 | 1 / 9 / 5 | 2 / 5 / 8 | 13 / 2 / 0 |
| multi-section report | 14 | 1 / 6 / 7 | 1 / 6 / 7 | 1 / 4 / 9 | 13 / 1 / 0 |
| log and diagnostic lines | 12 | 1 / 7 / 4 | 1 / 7 / 4 | 0 / 1 / 11 | 8 / 3 / 1 |
| structured data (trees, dumps) | 9 | 1 / 7 / 1 | 2 / 5 / 2 | 0 / 0 / 9 | 7 / 2 / 0 |
| key/value blocks | 9 | 1 / 5 / 3 | 0 / 5 / 4 | 0 / 1 / 8 | 9 / 0 / 0 |
| **captured** | 65 | 9 / 38 / 18 | 10 / 36 / 19 | 7 / 13 / 45 | 57 / 7 / 1 |
| **reproduced** | 42 | 5 / 22 / 15 | 4 / 23 / 15 | 3 / 10 / 29 | 39 / 2 / 1 |

## What it says about each open measurement

- **The engine (HANDOFF's honest picture):** 13% / 56% / 31%, 69% usable. No
  fix round has been measured since round 4's rating, so this is the 2.3.0
  engine's first contact with fresh output. It is no better at getting
  things fully right than any earlier round.
- **`--multi` and auto-multi (0a, 0d):**
  - It differs from the default on 13 inputs: 6 better, 7 worse.
  - Where the gate holds a capture, it moves 3 of the 7 from FAIL to PARTIAL.
  - That is the case auto-multi acts on, and the direction holds. The set
    is small (7, against round 4's 18).
- **The layout model (0c, 0h, 0q, 0r):**
  - Model-first it rates 10 / 23 / 74 and reads nothing on 18 captures.
  - It beats the engine on 13 inputs and loses on 51.
  - On the 7 gate-held captures it rates 0 / 1 / 6, no better than the
    engine.
  - Taking the better of engine and model on every input gives 19 / 64 / 24.
    That is the ceiling for any arbiter between them.
  - Round 4's conclusion stands: the labeller is a second reader at best,
    and on this set it did not rescue a held capture.
- **`--llm` (0i–0k):**
  - First contact on unseen output: 96 / 9 / 2, 98% usable.
  - Its 9 PARTIALs: 5 templates with a field glued, a frame split from its
    code line or a trailing block left unparsed; 4 captures it left to the
    engine, rated on the engine's output.
  - This is the measurement HANDOFF 0k step 3 asked for, made before the
    library or any template rework touched round 5.
  - The next honest `--llm` measurement is on second captures. Round 4's
    part 3 shows a template written from one capture does worse on the next.

## Round 5 is now seen

Every output has been read and rated, with a reason per input in
`ratings.tsv`, so round 5 is spent for every reader measured here. The next
honest number needs a round 6, built and frozen the same way before the next
change is measured.

## Addendum, 2026-11-10: the `--llm` judge on round 5's templates (PV-009)

The judge (CHANGELOG 2.6.0) reviews a template after `learn` and `repair`.
To measure it and nothing else, the 100 templates `--llm` kept on round 5
(`round5/llm-templates-learn/`, rated above) were reviewed on their own
inputs with `tests/benchmark/judge_round.sh --round5 OUT --jobs 8`: 74 PASS,
26 fix lists, every revision held (`round5/llm-judge/judge.tsv`, the 26
revised templates, the API log; 126 calls, about $3.70). `llm_round.sh` then
ran round 5 through the old and the revised templates; only those 26 outputs
changed. Each was put on a blind sheet as above and the 52 sheets split
among four subagent raters so that no rater saw both versions of an input:

| the 26 revised | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|
| before the review | 17 | 9 | 0 |
| after | **25** | 1 | 0 |

9 better, 1 worse (`postfix-qshape`: the revision moved the TOTAL row to its
own table without its label), 16 the same (`round5/llm-judge/ratings.tsv`).
The four template-filed inputs rated PARTIAL on 2026-11-04 that the judge
flagged all rate PASS after it; it did not flag the fifth. The re-rating also
put five outputs at PARTIAL that were rated PASS on 2026-11-04, so the same
outputs move between raters by about that much. On this document's ratings,
`--llm` first contact becomes 99 / 6 / 2.

Round 5 was rated before the judge was written, but it is a seen set now:
this is a before/after on fixed templates, not an unseen measurement. That
needs round 6.

