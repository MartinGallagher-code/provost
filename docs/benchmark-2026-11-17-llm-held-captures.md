# `--llm` through the real API on the 38 held captures of rounds 2-4

**2026-11-17 (PV-007).** HANDOFF 0i's first two steps: run `--llm` with a real
key over the 38 captures held in rounds 2 to 4, rate the templates, and grow
`extract/llm/templates/` from the ones that prove good. The engine is `main` @
bc1679ef, provost 2.24.0. The pipeline is the default one: `learn`, the skip
audit when a template sets lines aside, the judge (on), and one revision when
the judge asks for fixes. The model is provost's default, `claude-opus-5-5`.

As in every round, **the ratings are a self-assessment by agents: a screen, not
a verdict.** These captures have all been seen before, so this is not a
generalisation number.

Everything is in the repo:

- per capture (filed by, datasets, calls, tokens, cost, rating, reason, shipped):
  `tests/benchmark/llm-held/summary.tsv`
- the templates `--llm` wrote for all 35 captures sent, and the API log
  (one line per reply, with its usage): at the commit named in
  `tests/benchmark/README.md` ("LLM run records"), out of the tree as PV-042 set
- the inputs: `tests/benchmark/round{2,3,4}/inputs/`
- the criteria: `tests/benchmark/round4/CRITERIA.md`, unchanged

## Which 38

"The 38 held captures" was a count, not a list (`docs/plan-2026-10-27-near-100.md`).
The list was made again: the engine of 2026-10-25 (`2d4fac58`, the commit after
CHANGELOG's count) holds exactly **7 / 16 / 15** of rounds 2 / 3 / 4, the
count CHANGELOG gives. Today's engine holds 36: it now files round 4's
003-bison-report-states, 029-jhsdb-jmap-heap and 137-windows-robocopy-log, and
newly holds round 4's 048-pytest-ra-report (not in the 38, not sent).

The three today's engine files were **not sent** (their rows say so). The other
35 were, one at a time: round 4's 113-ibmi-wrksyssts first, to measure the cost
before the rest (it took all four calls, so it set the upper estimate), then
the other 34. Each ran once.

## Headline

| of the 35 sent | PASS | PARTIAL | FAIL |
|---|---:|---:|---:|
| `--llm`, first contact, judge on | **30** | 4 | 1 |

Before this, the default engine filed **none** of these 35; they were held.
34 were filed by a new template; 1 (round 2's 035-od-hex) stayed held, because
the template Claude wrote failed the gate (its blocks are fragments).

The judge passed 27 of the filed templates as written and asked for fixes on
the other 7. All 7 were revised and filed. That took 8 revise calls, because
022-gprof-brief's first revision was retried. 035-od-hex's template was
reviewed (no revision) and then declined by the gate.

**The four PARTIALs:**

| capture | what is wrong |
|---|---|
| round 3 030-node-test-spec | each failure keeps only its first stack frame |
| round 3 059-sort-debug | `--debug`'s key-span underlines (what sort compared) are dropped |
| round 2 109-ibmcloud-resource-groups | account ID and user merged into one value; `OK` only as a column header |
| round 3 110-macos-log-show | the `skipped` line loses its second half |

## Cost

**100 calls: 35 `learn`, 22 skip audits, 35 judge reviews and 8 revise calls.**
397,537 input and 130,434 output tokens, no cache use. At US$4 / US$20 per
million (Claude Opus 5.5's price), that is **US$1.59 + US$2.61 = US$4.20**:
US$0.12 a capture on average. The cheapest was US$0.03 (two calls, no audit);
the dearest was US$0.32 (round 4's 022-gprof-brief: five calls, two fixes).
The first capture alone cost US$0.28 and suggested about US$10.50 for the 38.
The real average was well under half that, because most captures needed no
audit and no revision.

## What ships

**28 templates go into `extract/llm/templates/`**, as Claude wrote them
(examples, decoration record and the judge's verdict included). A shipped
template applies without `--llm` to any capture its `detect` recognises and
reads well, so each one was also run against all 3,733 inputs in
`tests/corpus/`:

- **update-alternatives-query** (PASS) is **not shipped.** Its detect,
  `^(Name|Link|Alternative|Priority|Slaves):`, recognises any `Name:` report.
  Through the CLI it took 44 corpus captures from their own parsers: `pip show`,
  `kubectl describe`, `dpkg -s`, `apt-cache show`, `virsh dominfo` and more.
- **cmake-cache-advanced-help** (PASS) is **not shipped.** It took
  `cmake-list-cache` (`cmake -L`), which has its own golden. It may well read it
  correctly, but that is a change to a corpus tool nobody has reviewed.
- The other 28 come near no corpus capture: the best any of them scores on one
  is 0.167 (apt-cache-showpkg on `apt-cache show`), far below what provost
  files.

`ml/tests/test_llm_template.py` (`ShippedLibrary`) holds all of this:
- each of the 28 is shipped;
- each shipped template is the one `find` picks for the capture it was written
  from, at full coverage;
- each benchmark input is read by its template;
- no PV-007 template scores 0.5 or more on any corpus input.

That last test fails on 49 corpus inputs with update-alternatives-query put
back. `tests/smoke.sh` checks one end to end through the CLI with no `--llm`:
round 4's Junos `show interfaces terse`.

## Not done here

- **No second capture.** These templates were rated on the one capture each was
  written from. Round 4's part 3 found that a stored template meets new kinds
  of line on a tool's next capture about one time in three (repair handles
  that under `--llm`). Without `--llm` a shipped template that does not fit is
  passed over, and the engine reads the capture as before.
- **The two templates not shipped** could ship with a narrower `detect`. That
  is a hand edit to what was rated, so it is left as a follow-up.
- **The PARTIALs** would need the judge to catch them, or a repair. Three are
  the judge's known blind spot: something a pattern reads, but reads short.
