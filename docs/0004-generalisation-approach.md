# Design note 0004 — How provost should get better on output it has never seen

- **Status:** Proposed, 2026-11-10. **Waiting for the owner to pick an option**
  (PV-006). When the pick is made it is recorded here, in `HANDOFF.md` and in
  `CHANGELOG.md`, and its follow-up work is filed as tickets.
- **Ticket:** PV-006 (HANDOFF "Next steps" 1 and 0h).
- **Evidence:** round 4
  ([benchmark](benchmark-2026-10-20-generalisation-round4.md)), round 5
  ([benchmark](benchmark-2026-11-04-generalisation-round5.md)) and `--llm`
  on round 4 ([parts 1–7](benchmark-2026-10-27-llm-templates-round4.md)).
  Every figure below comes from those rounds' rating sheets and can be
  reproduced with `python3 tests/benchmark/what_if.py`. Nothing was run or
  rated again: each option takes, per input, the rating another reader already
  got on that input.

## The question

Two fix rounds of pattern-level fixes each moved the FAIL rate on unseen
output by only 1 to 3 points, while the rates on the sets the fixes were
written against improved a lot. Round 5 (2.3.0, fresh output) says the same
thing: 14 PASS / 60 PARTIAL / 33 FAIL of 107. Another round of fixes in that
style would probably fit what can be seen again. This note weighs the four
options HANDOFF listed, and one stronger form of the fourth, before any more
work is done.

## What rounds 4 and 5 show

1. **The PASS rate on unseen output does not move.** It was 16%, 21%, 11% and
   13% in rounds 2 to 5, and FAIL stayed between 31% and 41%.
2. **The parse-quality signals can see only one kind of failure.** Below 95%
   line coverage a parse is almost never right: none of 25 in round 4 and 1
   of 23 in round 5. Round 4 suggested this and round 5's fresh inputs
   confirmed it. But 22 FAILs in round 4 and 21 in round 5 had 95% coverage
   or more. Of the parses that scored 95 or more on both coverage and
   consistency, 8 (round 4) and 7 (round 5) were still FAIL. Those are
   prompts, titles or legends promoted to the header, and wrong splits. No
   rule built on these signals can catch them.
3. **The engine's readers all make the same mistakes.** If the better of
   the default parse and `--multi` were chosen for every input, rounds 4 and 5
   would score 13 / 64 / 30 and 15 / 64 / 28. The better of the engine and the
   layout model would score 19 / 64 / 24 on round 5. Nothing that chooses
   between these readers can do better than that.
4. **Only one reader changes the result: a template an LLM writes for the
   tool.** At first contact it scored 87 / 18 / 2 on round 4 (after the
   clean-up) and 96 / 9 / 2 on round 5. On round 4's second captures (stored
   templates, repaired when they missed) it scored 83 / 22 / 2. It needs an
   API key, and each new tool's capture goes to the API once, for about 4 to
   5 cents. After that the template is stored and runs offline, and gives the
   same result every time.

## The options, measured

The baseline is the default engine: 12 / 51 / 44 on round 4 and 14 / 60 / 33
on round 5. Captures the gate holds (18 in round 4, 7 in round 5) are rated
on the engine's output, as in the benchmark write-ups.

### A. Segment with `--multi` by default when the signals are weak

This already ships in its gate-triggered form: auto-multi has been on by
default since 2.2.0, and it files the parts only when every part passes the
gate.

| | round 4 | round 5 |
|---|---|---|
| `--multi` wherever the gate holds (upper bound) | 12 / 59 / 36 | 14 / 63 / 30 |
| `--multi` wherever coverage < 95, consistency < 95 or unjudged | 12 / 63 / 32 | 13 / 64 / 30 |
| `--multi` on every input (better / worse than default) | 15 / 2 | 6 / 7 |

It turns some FAILs into PARTIALs (3 to 12 points) and never adds a PASS. Run
on every input, it did more harm than good on round 5. As a capture fallback
on round 4 it made 2 rescues, filed 1 wrong table and missed 6 (PV-013).
**Verdict:** keep it as it is. It helps a little at the margin, but it is
not an approach.

### B. Let the parse-quality signals decide more, not only veto

Choosing between the readers the engine already has can reach at most 13 to
15 PASS (default or `--multi`) or 19 PASS (engine or layout model, round 5),
against 12 and 14 today (finding 3). The FAILs that cost the most are the
ones the signals cannot see (finding 2). **Verdict:** a low ceiling, at most
1 to 5 more PASS a round. Not measured: re-ranking every candidate strategy by
coverage and consistency inside the engine. That would need every
candidate's output rated, so it would be round 6 work if this option were
picked.

### C. Narrow the claim: hold weak parses for triage

What a wider hold rule (generic winners only, as today) would have held and
filed:

| hold rule | round 4 held (P / Pa / F) | round 4 filed wrong | round 5 held | round 5 filed wrong |
|---|---|---:|---|---:|
| now: coverage < 80 or consistency < 70 | 18 (0 / 1 / 17) | 27 of 89 (30%) | 7 (0 / 1 / 6) | 27 of 100 (27%) |
| coverage < 95 or consistency unjudged | 27 (1 / 3 / 23) | 21 of 80 (26%) | 28 (2 / 9 / 17) | 16 of 79 (20%) |
| coverage < 95, consistency < 95 or unjudged | 49 (1 / 13 / 35) | 9 of 58 (16%) | 45 (3 / 17 / 25) | 8 of 62 (13%) |

**The trade:**
- With the widest rule, a table that is filed is wrong half as often (13–16%
  against 27–30%).
- But 42–46% of unseen captures go to triage instead, and 14 to 20 of those
  would have been usable. A held capture keeps its raw text but makes no
  dataset.
- Compared with today's gate, the widest rule keeps 19 more wrong tables out
  on round 5 and holds 19 more usable ones. On round 4 it is 18 against 13.
  The middle rule: 11 against 10 (round 5), and 6 against 3 (round 4).
- Auto-multi would then run on more captures. It still files only the parts
  that pass the gate.

**The risks:**
- The thresholds were read off rounds 4 and 5. The coverage line at 95 held
  on fresh data; the consistency cut has not been tested on fresh data.
  Round 6 has to measure both.
- With the widest rule, close to half of new tools' captures would say "held
  for triage".
- Not measured: how many of the corpus's seen tools a wider rule would hold.

**Variant:** file the weak parses with a visible "unverified" mark instead of
holding them. No data is held back, and the user knows which tables to
check.

### D. `--model` or `--llm` as the default fallback for held captures

| | round 4 | round 5 |
|---|---|---|
| layout model where the gate holds | 0 / 2 / 16 ([LM note](lm-2026-10-29-tiny-labeller.md)) | 0 / 1 / 6 |
| `--llm` where the gate holds | 14 / 3 / 1 | 6 / 1 / 0 |
| `--llm` as the fallback for held captures (whole round) | 26 / 53 / 28 | 20 / 60 / 27 |
| `--llm` where coverage < 95, consistency < 95 or unjudged | 49 / 48 / 10 | 53 / 46 / 8 |
| **D′: `--llm` first, on every input** (what `PROVOST_LLM=1` does today) | **87 / 18 / 2** | **96 / 9 / 2** |

- **`--model`:** no gain on either round. **Verdict: no.** PV-012's arbiter
  has a ceiling of 5 more PASS on round 5.
- **`--llm` as a fallback for held captures:** fixes almost everything it
  reaches, but the gate holds only 7 to 18 captures a round, so it adds 6 to
  14 PASS.
- **D′, `--llm` first:** this is what `PROVOST_LLM=1` already does. It adds
  75 to 82 PASS, because it also replaces the high-coverage misreads the gate
  cannot see.
- **What D′ costs:**
  - It needs a key and a network.
  - Each new tool's capture leaves the machine once (up to 400 lines and 64
    KB; larger ones are not sent). PV-019 adds local
    endpoints and a mode that never sends a capture off the box, and PV-033
    adds redaction.
  - About 4 to 5 cents per new tool.
  - Second captures have been measured only on round 4. Round 6 should
    measure them again.
- **"Default" cannot mean on for everyone:** some sites have no key and no
  network, including the HPC sites PV-030 was for. It can mean: on whenever a
  key or endpoint is configured.

## Recommendation: C and D′ together

This is one pick with two halves, because neither half is enough alone. C
alone never adds a PASS. D′ alone does nothing for a site that cannot send
output to a model.

1. **D′ is how provost gets things right on tools it has never seen.**
   `--llm` runs first whenever a key or a local endpoint is configured (PV-019
   first, so a misconfiguration can never send a capture off the box). Its
   templates are stored and reused offline, as today.
2. **C is what provost says when it has no template.** Hold for triage when
   coverage is under 95 or consistency is unjudged (the middle row: 27 to 28
   held, the filed-wrong rate down to 20–26%). Make the held message say what
   would file the capture (`--multi`, or a template). Try the consistency < 95
   cut, and the "unverified" variant, against round 6 before adopting either.
3. **Whatever is picked:**
   - Stop running pattern-level fix rounds to make provost generalise. Fix
     reported defects as defects.
   - Build and freeze round 6 before the chosen change lands, and quote round
     6 as that change's number.
   - Leave `--model` opt-in.

## Follow-up tickets, filed once the owner picks

| pick | tickets to file (titles) |
|---|---|
| A | none new; PV-013 is that work |
| B | "Re-rank candidate strategies by coverage and consistency, measured on round 6" |
| C | "Hold parses under 95% coverage or with unjudged consistency for triage"; "Say in the held message what would file a held capture" |
| D′ | "Turn --llm on whenever a key or local endpoint is configured" (after PV-019, with PV-033); "Ship a template library for the corpus's tools" (plan 2026-10-27 step 5) |
| any | "Build and freeze generalisation round 6 before the next change is measured" |

PV-007 (`--llm` over the held captures) is mostly answered: held captures
rated 14 / 3 / 1 (round 4) and 6 / 1 / 0 (round 5). Whether to close it is
part of the pick.
