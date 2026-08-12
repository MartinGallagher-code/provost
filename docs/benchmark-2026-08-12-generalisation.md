# Held-out generalisation benchmark — 50 unseen inputs

**2026-08-12.** Fifty tool outputs the engine has never been tuned against, run
through `glean` in its default mode and rated against criteria written down
before the first input was executed.

Everything here lives in the repo: inputs in
[`tests/benchmark/inputs/`](../tests/benchmark/inputs), the runner in
[`tests/benchmark/run.sh`](../tests/benchmark/run.sh), the per-input ratings and
notes in [`tests/benchmark/ratings.tsv`](../tests/benchmark/ratings.tsv).

## Why this exists, and why it is not a gate

`tests/corpus/` answers "did this change break something that used to work".
It cannot answer the question that actually matters for a tool like this:
**what happens the first time glean meets an output nobody wrote a parser for?**
Every corpus entry has been looked at, argued over, and in many cases had a hint
row or a strategy written for it. The corpus score is therefore a measure of
how much work has been done, not of how well the engine generalises.

So: fifty inputs with no hint row, no strategy, no golden, no prior review.
Fourteen came from public documentation and sample data on the internet (tokei
and scc summaries, rclone `about`, borg `list` in both forms, three nmap scans,
an ASCII table with a decorative header and footer, a quoted CSV, `/etc/hosts`,
an INI file, an `arp -a` table). Thirty-six are live outputs captured from this
machine, chosen for shape variety rather than convenience: aligned tables with
and without headers, colon and equals key/value, JSON, TSV, hierarchies, box
drawings, two-row headers, and multi-record logs.

**There is deliberately no pass/fail gate.** A gate would invite fitting the
engine to these fifty files, and the moment that happens they stop measuring
generalisation and start measuring memorisation — exactly the property that
makes the corpus number an unreliable answer to this question. Re-run the
script after a change and read the diff.

## The criteria, fixed before running anything

Written to `CRITERIA.md` before the first input was executed, so that a
disappointing result could not be quietly reclassified into a better one.

| | |
|---|---|
| **PASS** | every piece of information in the input is present in the output **and** correctly structured: columns carry real names where the input supplies them, values sit under the right column, prose is not sliced one-column-per-word, nothing is dropped |
| **PARTIAL** | structure is broadly right but something is lost or mis-shaped: a header not applied, a line dropped, a value split or merged |
| **FAIL** | the output **misrepresents** the input: values under the wrong column names, a table shredded, or a substantial part missing |

Judged on default mode — what `glean` does with no flags — with `--multi` noted
where it differs.

One caveat that should stay attached to every number below: **this is a
self-assessment by the same agent that wrote the engine.** It is a screen, not a
verdict. The human review rounds remain the real measure, and the two disagree
often enough to matter.

## Result

| | count | share |
|---|---:|---:|
| PASS | 23 | 46% |
| PARTIAL | 12 | 24% |
| FAIL | 15 | 30% |

**Roughly seven in ten unseen inputs come out usable; three in ten come out
wrong.** That is a materially worse picture than the corpus suggests, and the
gap is the point of running this.

The honest one-line answer to "how well would we do on any given new benchmark
output" is: *a well-behaved aligned table or key/value output will almost
certainly be right; anything with decoration, a two-row header, empty columns,
or more than one kind of content in it is a coin flip.*

### What passes reliably

Every clean single-shape input passed, and several passed on details that are
easy to get wrong: `free -w`'s short Swap row stays short rather than being
padded (13); `lscpu -e` keeps `L1d:L1i:L2:L3` as a column name without splitting
it at its colons (10); `ps` keeps `%CPU` and `%MEM` as names and does not split
`COMMAND` at its slashes (15); `dpkg -l` correctly discards a four-line legend
and a `+++-===` rule as decoration while keeping all twelve packages (29);
`/proc/meminfo` keeps `Active(anon)` whole and keeps `kB` attached to its number
(51); the quoted CSV with spaces after its commas parses to nine named columns
(38).

Where an input genuinely has no header — `getent passwd`, `du`, `wc`,
`/etc/hosts` — the generic `A`/`B`/`C` names are the honest answer and were
rated PASS, not marked down.

### The 27 defects, clustered

The failures are not fifty separate problems. They are nine, and the top four
account for 15 of the 27.

| cluster | n | what happens |
|---|---:|---|
| **truncation** | 4 | a strategy claims the input and emits a fraction of it |
| **banner** | 3 | a leading or trailing line with no `key:` is dropped |
| **box-rules** | 3 | `─`/`━` rule lines are not recognised, so the table never parses |
| **dropped-line** | 3 | a detail line outside the main record is discarded |
| **blank-column** | 2 | empty columns collapse; values land under the wrong names |
| **csv-on-date** | 2 | `Mon, 2016-02-15` reads as 2-field CSV and splits inside the timestamp |
| **group-header** | 2 | a two-row header defeats the column split |
| **dropped-unit** | 2 | a unit or a time component is silently discarded |
| *(one each)* | 6 | empty-value, kv-harvest, merged-column, multi-kv-line, no-header, two-word-header |

**Truncation is the worst of these and should be fixed first**, because it is
the only cluster that is both silent and catastrophic. `git log --stat` goes in
at 40 lines and comes out at 3 (27). `java -XshowSettings` goes in at 24 and
comes out at 2 (42). `apt-cache policy` goes in at 14 and comes out at 4 (47).
In each case a strategy — `git-log-stat`, `indented-hierarchy` — detected with
high confidence, claimed the whole input, and then produced almost nothing, with
no signal to the user that anything was missing. A parse dramatically shorter
than its input is a reliable tell, and the engine currently does not look for it.

**The blank-column cluster is the most insidious**, because the output looks
perfectly tidy while being wrong. `lsblk -f` (11) prints eight columns of which
five are empty on every row; the surviving values are assigned to the first
names in the header rather than to their own, so filesystem sizes appear under
`FSTYPE` and mountpoints under `LABEL`. `lsof` (34) is the same defect and
worse — `TID` and `TASKCMD` are empty throughout, so `USER` lands under `TID`,
`FD` under `TASKCMD`, and the pathname is smeared across four columns. Nothing
about the output betrays the error. Fixing this means using the header's
character offsets rather than counting whitespace-separated fields.

**`--multi` already fixes three of the fifteen failures** (25, 27, 37) and never
made one worse. The ASCII table with a decorative header and footer (37) is the
cleanest demonstration: default mode shreds the `### header ###` one word per
column and never applies `col1 col2`, while `--multi` returns three datasets
with a correct two-column table in the middle. That is an argument for
segmentation being closer to the default than it currently is.

### Two defects worth calling out individually

**`openssl ciphers -v` (30)** loses the cipher name from every row. The
`inline-kv` strategy harvests the `Kx=`/`Au=`/`Enc=`/`Mac=` pairs and discards
the rest of the line — which means it discards the row's identity and its TLS
version, i.e. the entire point of the output. A strategy that harvests pairs out
of a line should be required to account for what it left behind.

**`locale` (17)** drops `LANG=`, `LANGUAGE=` and `LC_ALL=` because their values
are empty. A variable that is set-but-empty and a variable that does not exist
are different facts, and the output makes them identical. Twelve of fifteen rows
are correct; the three that vanish are the three a reader would most want to
check.

## What this says about the two known engine limitations

The scoring work earlier this cycle named two limits. This benchmark bears both
out and adds a third.

1. **The score cannot see shredding.** A sentence sliced one word per column
   scores a perfect coverage. Inputs 18 and 37 are exactly that shape.
2. **Boundary rules cannot see detection.** Where segmentation would help
   (25, 27, 37) the rules do not fire in default mode.
3. **New: nothing measures a parse against the SIZE of its input.** All four
   truncation failures would be caught by a single check — parse produced far
   fewer cells than the input has lines — and that check needs no new parsing
   logic at all, only a comparison the engine already has the numbers for.

The third is the cheapest large win available and does not require resolving
either of the first two.

## Reproducing

```bash
bash tests/benchmark/run.sh /tmp/bench-out
```

Prints a per-input summary line (strategy, confidence, input lines, output
lines, `--multi` dataset count) and leaves `.def`, `.meta` and `.multi` files
for every input. Nothing is asserted; read the diff.
