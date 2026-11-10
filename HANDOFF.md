# Handoff — provost

The history that used to live here (2026-07 → 2026-09-16, ~100 KB) is in git:
`git show 9f9d7c0:HANDOFF.md`. `CHANGELOG.md` has the dated detail.

## Present state (2026-10-23; commands and store format updated 2026-10-28; `batch` and four readers 2026-10-29)

**provost 2.5.1 is everything through 2026-11-10** (`VERSION`, man header,
the `## 2.5.1` section at the top of CHANGELOG): 2.4.0 (BN-002), the HPC
benchmark outputs (PV-030, 2.5.0, below) and the two `--llm` gate rules
(PV-010, 2.5.1, below). 2.4.0 added `provost
verify` and input hashes (PV-026), the run manifest (PV-020) and the
2026-11-04 to 2026-11-09 fixes to 2.3.0. **From 2.4.0 on every change moves
the version** (`CLAUDE.md`, "Every change moves the version";
`tests/check_version.sh` and CI's `version` job enforce it), so the version at
the top of CHANGELOG is always the version `main` is at. Neither 2.4.0 nor
2.5.0 is published yet: run the "Release to PyPI" workflow on `main` (or a
GitHub release tagged `v2.5.0`, not both). 2.3.0 (2026-11-04, on PyPI) added `rm --capture`,
`provost[lm]` (the tiny LM on numpy, weights in `provost-model`) and the
faster `batch` to 2.2.0. 2.2.0 (2026-10-30, on PyPI)
added the quality gate and auto-multi, the engine fixes, removal of the
legacy names, store format 3, browsing and search, `batch`, the opt-in
`--llm` and `--model`, and the 2026-10-29 readers. 2.1.0 (2026-10-16) was
the first release with the rename, store format 2, line coverage and the
2026-10-14 parser work.

**In 2.4.0: the run manifest (PV-020, 2026-11-09).** Profiles
of reserved `#%` keys in `extract/manifests/` (`default`, `proposal`),
`provost check-manifest`, `provost annotate`, and `--manifest FILE`,
`--manifest-profile P` and `--strict-manifest` at capture time. Off unless
asked for. Open: the owner's choice of key names (generic `default` or the
proposal's flat names as the default profile) and whether a missing key
should fail by default; quarterdeck filling `sched.job`, `run.id` and
`operator` itself is its own follow-up.

**2.5.1: the two gate rules that cost `--llm` a FAIL each (PV-010,
2026-11-10; not published).** The fragments rule (auto-multi parts, model
sections, template blocks) sizes a part by its lines or its table's rows,
whichever is more (`_am_frag_add`, `_AM_FRAG_MIN`, was `_AM_FRAG_LINES`): a
one-line block of six records (round 4's 132, a ServerQuery client list) is
no fragment. And a `yaml` parse is no longer beyond a template already
stored for the tool (plain `Label: text` output is valid YAML: round 4's
020, golangci-lint's linter list, was one 110-column record); Claude is
never asked to write one over a yaml parse, so a real YAML document costs
nothing. Both files now; see CHANGELOG for the round-4 before/after.

**2.5.0: the HPC benchmark outputs (PV-030, 2026-11-10; not published).**
OSU, IOR, mdtest, HPL, HPCG, STREAM's full printout, lnet_selftest `lst stat`,
`ibstat`, `perfquery`, ReFrame perflogs (4.x and 3.x), JUnit XML, `sacct -p`
and the fio 3.x run-status range all tidy, with units in the column names.
Generic first: `xml` record mode (JUnit), `pipe-table` (Slurm `--parsable`,
headerless `key=value` columns), `labeled-inline-kv` (fio's range), a hint
row for `ibstat`; then six bespoke strategies in `extract/strategies/hpc/`
(`hpl`, `hpcg`, `ior`, `mdtest`, `stream`, `lst-stat`), each where no generic
parser keeps the rows (PV-006 may want to weigh them). 27 corpus inputs; the
"HPC benchmark set" table in `tests/corpus/README.md` says which are real
captures and which were written from the tools' source (OSU, IOR, mdtest,
HPCG, HPL 2.3, ibstat, perfquery, lst, STREAM). Open:
- **Real site captures** should replace the source-derived inputs (same
  name, `run.sh --golden`, review the diff); the owner was asked for
  sanitised outputs in PV-030.
- `sinfo -N -l` merges `AVAIL_FE` and `REASON` (one space apart over cells
  with spaces); not in the corpus.
- `ibstat` goes to `kv-report`, which drops the `Port N:` level: fine for one
  port per CA (mlx5), not for a two-port mlx4 CA.
- `equals` drops keys over 50 characters (why HPCG needed a strategy);
  `fixed-width` runs past a table's end into the next block (why IOR and
  mdtest did). Either fix would let those go generic, but both parsers sit
  under many goldens.
- nvidia-smi not re-checked against a current driver (no GPU).
- Units are kept in names, not normalised: PV-032.
- `ml/gen/tools/sci_ior.py` and `sci_osu_latency.py` were removed (their families
  are in the corpus now); the layout model's next retrain drops them.

provost is one Bash entry point (`provost`) over:
- the extract engine (`extract/provost-extract`, 274 strategies, ~118 generic)
- the tidy melt (`transform/melt.sh`)
- the analyze engine (`analyze/provost-analyze`)

It has a git-backed store and ships as a thin Python launcher
(`src/provost_data/`).

### The honest picture: generalisation

| measure | PASS | PARTIAL | FAIL | usable |
|---|---:|---:|---:|---:|
| round 2, first rating (unseen, 2026-10-02) | 16% | 47% | 38% | 62% |
| round 3 on 2.1.0 (unseen) | 21% | 42% | 37% | 63% |
| round 3 after the 2026-10-16 round (unseen by its fixers) | 21% | 45% | 35% | 65% |
| round 2 after both rounds (seen: a regression set) | 32% | 58% | 10% | 90% |
| round 4 on the 2026-10-20 engine (unseen) | 11% | 48% | 41% | 59% |
| **round 5 on 2.3.0 (unseen, 2026-11-04)** | **13%** | **56%** | **31%** | **69%** |
| round 5, `--llm` first contact (unseen, rated blind) | 90% | 8% | 2% | 98% |

**On output provost has never seen, about one input in eight is fully right and
about one in three is wrong, and the fix rounds have barely moved that.**
Round 5 (PV-005) confirms it on 107 fresh inputs; its FAIL share is ten
points under round 4's, at the edge of the ±9-point margin, and the PASS
share has not moved. `--llm` is the one reader that changes the answer:
it rated higher than the engine on 85 of the 107 and lower on 1.
They have moved the seen sets a lot. The gap between round 2 (90% usable)
and round 3 (65%) measures how much the fixes fit what their authors could
see. The corpus figure (3677 / 3705 tidy) is a shape check on tuned inputs,
not a quality measure.

Rounds 1 to 5 are all seen now (round 5 was rated for four readers on
2026-11-04: `tests/benchmark/round5/`,
`docs/benchmark-2026-11-04-generalisation-round5.md`). The next honest number
needs a **round 6**: build it, freeze it and rate it before the change it is
to measure, as round 5 was.

### This round (2026-10-16, PR #76)

- **Round 3 benchmark:** 107 inputs, rated on 2.1.0 and then once after the
  round.
- **Column-type consistency:** a 5th `--emit-meta` field and a guarded
  consistency hold. It fixed about a dozen corpus misparses but replaced only
  1 of 11 held round-3 claims. Like coverage, it only warns one way: a
  uniformly shifted header scores 100.
- **Whitespace tables:**
  - a UTF-8-aware gutter grid
  - headerless first rows
  - footers handled in every table parser
  - print-report and pprof banners
- **Format parsers decline what they don't understand:** toml, equals, yaml,
  csv, semicolon-values, colon-fields and colons.
- **New `section-tables`** (titled sub-tables in one table with a section
  column), and indentation kept as depth/parent.
- **Pre-rename `ENVOY_*` / `MFE_*` fallbacks removed**; this ships in 2.2.0.
- **Corpus:** 3583 golden passes, 0 failed. COVERAGE.md shows 3677 / 3705.

`tests/corpus/*/envoy-*` are real Envoy-proxy captures, not leftovers.

Behaviour worth knowing:

- `provost run CMD` names the dataset after the command. Piped input is named
  after the winning parser. `--name` overrides both.
- Background capture only at an interactive terminal; scripts run
  synchronously. Failures: `provost log --failed`.
- `rm NAME` deletes datasets; `rm --capture ID[,ID...]` deletes captures and
  the rows they filed in every dataset they fed (2026-11-02, for
  quarterdeck's `qd rm RUN`). Both are one commit.
- Captures and `rm` are refused while `provost restore <id>` (or `prev` /
  `next`) has a capture out; `show --at`, `source ID`, `search --at`,
  `files` and `diff` read any capture from git without moving the store.
- Every dataset row is `#` (unique in the store), `capture` (`c0007`), `n`
  (record within that capture), then the data (store format 3).
- In a controlled directory each capture also commits the directory's files
  (`files-<id>` tags, chained); `provost files`, `provost diff`.
- `provost batch FILE...` files many inputs as one commit, a capture each
  (parse halves in parallel, store halves under one lock). With
  `--context-columns` a `#%` prologue's `key=value` words become row columns.
- A store whose `.git/config` others can write is refused if it sets keys that
  make git run programs.
- Engines run with `PROVOST_NO_RC=1`.
- Detection steps, in order:
  1. best confidence wins, with exact ceiling pruning;
  2. the coverage hold (`kv-report` rescue);
  3. the consistency hold.

  `--rank priority` gives the old first-match order. `--emit-meta` prints
  strategy, confidence, coverage and consistency.
- Large inputs: above 32 KB, detectors screen a sample (head, tail and middle
  windows) and the winner is re-confirmed on the full text.

Suites (all CI-enforced):
- `tests/smoke.sh` (604)
- `transform/tests/test_melt.sh` (70)
- `extract/tests/run_tests.sh` (70 files)
- `analyze/tests/run_tests.sh` (mawk and gawk)
- `tests/corpus/run.sh --golden`
- `python -m pytest`
- `tests/check_version.sh` (the version job, BN-002)

`tests/corpus/run.sh --coverage` takes about 11 minutes.

## Next steps

1d. **2026-11-10: every change moves the version** (shared_tools BN-002).
    2.3.0 → 2.4.0, numbering the twelve dated entries since 2.3.0 and this
    change; CHANGELOG's next section is `## X.Y.Z — YYYY-MM-DD — summary
    (PV-NNN)`. `tests/check_version.sh` (shared_tools' template; places:
    `VERSION`, the `man/provost.1` header) and CI's `version` job fail a pull
    request that does not bump past its base. Publishing 2.4.0 is the
    owner's call.

1c. **2026-11-09: `provost verify` and input hashes** (PV-026). Every
    capture records `input_sha256` (as received, before CRs are stripped),
    `input_bytes` and `output_sha256` (of `output.txt`) in `meta.tsv`, and
    the commit carries `Input-SHA256:`/`Output-SHA256:` trailers.
    `provost verify` runs `git fsck --full`, flags uncommitted edits, checks
    tags, re-hashes each capture's output against `meta.tsv` and the
    trailer, and fails on capture ids that are not in the history (an `rm`
    purge is counted, not failed); pre-2.4 captures are "unhashed". It cannot
    detect a rewritten history on its own: docs/usage.md "Verifying a store"
    says so, and PV-027 (signing) is the stronger anchor. Not done: a report
    file a test report can cite (the ticket's open question).

1b. **2026-11-09: PyPI links fixed, versioning policy written** (PV-034). The
    repo is public; Documentation points at docs/usage.md on GitHub until
    the mkdocs site is imported on Read the Docs (then point it back and
    `tools/check-project-urls.py` will confirm it). CI checks every
    `[project.urls]` link. README states the versioning and support policy.

1a. **2026-11-09: `batch`'s lock hold measured** (PV-024,
    `docs/lock-2026-11-09-batch-hold.md`). About 50 ms per input; 200-input
    chunks hold it ~10 s against the 30 s timeout. No change made; the doc
    lists the cheap wins in order. `tests/perf/batch-lock-time.sh N` repeats
    the measurement. quarterdeck's `filing.py:228` comment is right and can
    cite the doc (a quarterdeck follow-up).

0z. **2026-11-09: CI smoke green again** (PV-035). The runner now starts the
    suite with SIGINT ignored, which hid it from the two `rm --capture`
    interrupt checks; `own_pg` in `tests/smoke.sh` resets SIGINT to its
    default for the job it starts. Reproduce the old failure with
    `python3 -c 'import signal,os; signal.signal(signal.SIGINT, signal.SIG_IGN); os.execvp("bash", ["bash","tests/smoke.sh"])'`.

0x. **2026-11-04: smoke and the extract suite run in parallel** (PV-018).
    One job per CPU, `PROVOST_TEST_JOBS=N` to change it, `=1` for the old
    serial run; output is printed whole, per file or part, in order. Smoke's
    checks sit in parts (`if _part NAME; then ... fi`); a new check goes in
    one (`core` if it uses `$WS`), and the suite refuses a check outside one.
    On 2 CPUs the two went from 7 min 13 s to 3 min 32 s, and every suite
    from 11 min to 7 min 21 s. CHANGELOG has the measurements.

0w. **2026-11-04: `rm NAME` no longer promises `restore`** (PV-016). Its
    message, the man page and `help advanced` now say git's history (the
    commit before the deletion) holds what was deleted, the same wording as
    `rm --capture`; a purged capture's `files-<id>` tag now goes with its
    `capture-<id>` tag. Making `restore` reach a purged state (tagging the
    pre-deletion commit, or `restore` taking a commit) was not done.

0v. **2026-11-04: round 5 is built, frozen and rated** (PV-005,
    `docs/benchmark-2026-11-04-generalisation-round5.md`). 107 unseen inputs
    (65 captured, 42 reproduced), frozen in b0fd175 before any run, each
    rated blind for four readers:
    - default engine 14 / 60 / 33 (69% usable);
    - `--multi` 14 / 59 / 34;
    - layout model alone (shipped LM, model-first) 10 / 23 / 74;
    - `--llm` first contact 96 / 9 / 2 (105 API calls, about $4.30).
    It answers the measurements 0a, 0d, 0e, 0h and 0k were waiting on:
    - the engine generalises no better than before;
    - `--multi` helps where the gate holds (3 of 7 FAIL to PARTIAL);
    - the LM still does not beat the engine (better on 13, worse on 51);
    - `--llm` is right first time on nine captures in ten.
    Round 5 is now spent for all four; the next change to be measured needs
    a round 6, frozen first. The open `--llm` question is second captures
    (round 4's part 3), not first contact.

0u. **2026-11-04: a data column named `#` is filed as `#_2`** (PV-011). The
    melt renames it so it never shares a name with the store's row id, and
    `meta.tsv` records `renamed_columns`; a dataset filed before has its
    second `#` renamed on the next append, values kept. Closes the "Small"
    item under 0j and 0k (round 4's case 124). CHANGELOG has the detail.

0t. **2026-11-04: 2.3.0 is ready to publish** (PV-003). It carries
    `rm --capture`, which quarterdeck's `qd rm RUN` needs, and the `lm`
    extra. Publishing is the owner's: run "Release to PyPI" on `main` once
    the release PR has merged, then check `pip install 'provost[lm]'` in a
    fresh venv.

0s. **2026-11-03: work is ticketed** (PV-001). Every change goes through a
    ticket in `MartinGallagher-code/shared_tools` (`tickets/provost/`, PV-…;
    provost_model's are PM-…), moved Backlog → In Progress → Review →
    Done (Adversarial Test only when the owner asks, 2026-11-04, ST-005); see "Every task is a ticket" in `CLAUDE.md`.
    `ticket.py status provost` there lists what is open and next, and
    replaces this list as the place to look for the work still to do.
    Pull an existing `shared_tools` clone first (2026-11-04, ST-004): a stale
    one has a stale `CLAUDE.md` and a stale `ticket.py`.

0r. **2026-11-02: the tiny LM ships without torch**
    (`pip install provost[lm]`). The 18-layer model is exported to 8-bit numpy
    arrays (`ml/export_lm.py`) and run by `extract/model/lm_numpy.py` with a
    pure-Python tokenizer (`bpe.py`).
    - **The weights** live in their own repository and package,
      `MartinGallagher-code/provost_model`: `provost-model` 0.1.0, 85 MB,
      Apache-2.0. It is published on PyPI: 0.1.0 went up on 2026-11-02 by
      that repository's `release.yml` (Trusted Publishing, no token). In a
      fresh venv, `pip install provost[lm]` from this branch's wheel pulls it
      from PyPI, and `--model` labels with it.
    - **Faithfulness:** on round 4 the 8-bit model rates exactly like torch
      (5 / 30 / 72; 84 of 107 outputs byte-identical, the other 23 rated
      blind to the same ratings). On fold 0 the export scores 0.863 like
      torch.
    - **Cost:** 282 MB peak memory, a 0.5 s load, no torch import. About 1.7
      times torch's time per capture on 4 CPU cores (round 4: 14.5 min for
      107 captures).
    - **Discovery:** with `PROVOST_LAYOUT_LM` unset, an installed
      `provost-model` is used; `0` keeps the trees. `PROVOST_PYTHON` is set
      by the pip launcher so the package is found.
    - **Next:**
      1. release provost (2.3.0), so `pip install provost[lm]` works from
         PyPI: the `lm` extra exists only from that release on;
      2. a new model means: train (`ml/train_lm.py`), export
         (`ml/export_lm.py --model DIR --out
         ../provost_model/src/provost_model/model --check 200`), bump
         `provost_model/__init__.py`'s `__version__` and its CHANGELOG,
         merge, then publish a GitHub release (or run "Release to PyPI"),
         and `release.yml` uploads it;
      3. `--embed 4` saves 13 MB but moves 19 more round-4 outputs; a
         vocabulary cut is the bigger saving if size ever matters.

0q. **2026-10-29/30: a tiny pretrained LM as the layout labeller, on a CPU**
    (PR #90; `ml/train_lm.py`, `extract/model/lm_runtime.py`,
    `docs/lm-2026-10-29-tiny-labeller.md`). The user asked for an
    ultra-small model trained on provost's own inputs and results, which
    trains and runs on a CPU.
    - **What it is:** SmolLM2-135M with LoRA, plus two heads giving the trees'
      two answers. The capture is echoed so a causal model sees the rows
      below a header.
    - **Per line, fold 0** (627 held-out captures): **0.863 split agreement
      and 39/48 gold**, against trees 0.829 / engine 0.814 (both 32/48) and
      the documented trees + GridNet 0.835. It is the first learner past the
      ~83% plateau. Two passes, about 2 h on 4 cores. Continuing it on
      generated layouts scored lower (0.854, 37/48), so the corpus labels
      stay the training set.
    - **All five folds** (1–4 trained on the user's iMac, M4 GPU, 15.5–19
      min a fold): the LM wins every fold, 0.842–0.893. Over all 14,468
      lines: LM 0.862, trees 0.819, engine 0.814; gold 240 / 212 / 189 of
      287. Two epochs is about right (fold 3 kept epoch 1).
      The model on every fold (`lm-all`) was trained there too; the user has
      it, and weights are not in git.
    - **Whole captures, round 4, model-first, blind-rated:** LM 7 / 30 / 70,
      trees 2 / 32 / 73, default engine 12 / 51 / 44. Neither model replaces
      the engine: it cannot file nested, log or mixed output. On the 18
      captures the gate holds (all `--model` touches) the LM rates 0 / 5 / 13
      against the engine's 0 / 1 / 17.
    - **Capture time, opt-in:** `PROVOST_LAYOUT_LM=DIR` with `--model` labels
      with the LM instead of the trees, without the arbiter; with no model or
      no torch the trees label as before.
    - **Weights are not in git** (`ml/models/`, gitignored): a 22 MB adapter
      plus the base model from Hugging Face.
    - **Workflow lesson:** run nothing else while it trains. Four torch
      threads on four cores stall behind any other process, even a
      low-priority one. A worker restart kills a run: resume it with
      `--init DIR/last --start-step N`, N being the step recorded in
      `DIR/last/config.json` (checkpoints every `--ckpt-every` steps).
    - **Environment:**
      - `pip install torch transformers peft lightgbm scikit-learn`; the
        PyPI torch runs on CPU, and download.pytorch.org is blocked here.
      - `python3 ml/llm/to_corpus.py ml/eval/llm-labels-2026-10-23.jsonl.gz`
        and `ml/corpus_labels.py` rebuild `ml/data/`.
    - **Next:**
      1. **Retrain `lm-all` with `--no-val`** (on the Mac, about 25 min).
         The current `lm-all` was trained before `is_val` was fixed
         (2026-10-30) and never saw the 403 old validation captures.
         `--no-val` trains on all 3,674.
      2. ~~**`fold_eval.py` on macOS** crashes with LightGBM and torch in one
         process (two `libomp` copies).~~ Fixed 2026-11-04 (PV-014): the
         torch learner now trains in a spawned child process whenever the
         trees train too, so the two never share a process. Verified on
         Linux (identical scores, and the process maps show each library
         in its own process); **still to confirm on the Mac** with
         `ml/fold_eval.py --fold 0` at full threads and no
         `OMP_NUM_THREADS`.
      3. **18 layers is the size** (measured 2026-10-30/31 on the iMac).
         - It matches all 30 on all five folds: 0.862 against 0.862, gold
           246 against 242 of 287.
         - It is 95.6M parameters against 140.1M.
         - 12 layers dipped below the engine on fold 4; 6 and 3 are worse.
         The final model at 18 layers, `lm-all-l18`, was trained on the
         iMac on 2026-10-31: 14 min, a 14.5 MB adapter, validation loss
         0.540. The weights are with the user, not in git. It was trained
         without `--no-val`, so on 3,271 captures, not 3,674.
         Next:
         - **Round 4 with `lm-all-l18`** (2026-10-31): 5 / 30 / 72, the same
           as the 30-layer `lm-all` (5 / 31 / 71); gate-held 0 / 2 / 16, also
           the same. So 18 layers is the model to use. Its blank result on
           round 3's `cmake-cache-advanced-help` is a one-off.
         - Optionally retrain it with `--no-val`, for the other 403
           captures (14 min on the iMac).
         - Shipping it without torch is done: see 0r.
      4. **Whole captures are limited by what the model files, not how it
         reads lines.** Round 4 with `lm-all` (2026-10-30) rated 5 / 31 / 71
         against fold 0's 7 / 30 / 70, and 0 / 2 / 16 on the gate-held 18
         against 0 / 5 / 13. One regression: `sge-qhost` took a data row as
         the header. The lever is the output shape (nesting, multi-line
         records, logs) or an arbiter, not more training.
      5. an arbiter fitted to the LM's probabilities, so `--model` keeps the
         engine's split where it trusts it more;
      6. decide how to ship: torch is hundreds of MB, so an ONNX/int8 export
         for `extract/model/` is the likelier route.
      7. Train on a GPU when one is to hand: `--device auto` picks cuda or
         mps, and an M4 iMac ran a fold in about 20 minutes, against 2 hours
         here.

0p. **2026-10-30: `batch` parses each name's first input side by side**
    (after #91). #91's pre-pass parsed the first input of every name one
    after another, before the parallel parse of the rest began: a batch of
    many names (qd's `probe facts inventory` files 7 probes' answers and
    its own `qd.hosts`/`qd.runs`, 9 names) waited on 9 full detections in
    turn with the other CPUs idle. They now run `-j` at a time, as the rest
    do. That qd request on six hosts: 26 s -> 16 s. Same captures, same
    order, same hints.

0o. **2026-10-30: `batch` reuses a name's detection** (after 2.2.0). The
    first input of each name is detected; the rest try its strategy first
    and keep the result only if it is the same table (strategy, header,
    coverage no lower). 200 one-format inputs: 70 s -> 22 s through qd.
    Equivalence checked on 400 corpus inputs (376 identical, 24 refused by
    the rule and detected from scratch). Not done: reusing the detection
    of a hint row (its label is not a strategy name, so `-s` refuses it --
    those inputs are detected from scratch, correct but not faster).

0n. **2026-10-29: four readers qd was working around.** qd converted
    some outputs to TSV before filing them, and escaped quotes in its own
    tables, because provost read them badly. Fixed here instead:
    - **TSV quotes are data.** `tsv` deleted every `"` from every value
      after its split had already consumed the structural ones: `said
      "hi"` filed as `said hi`, a JSON column lost its quotes (the corpus
      golden `quo-tsv-json-column` had frozen exactly that). `""` inside a
      quoted field is now one quote, as in CSV.
    - **Nested JSON without jq.** `json`'s no-jq fallback read `"key":
      value` pairs a line at a time and stopped at the first nested value.
      `_json_walk` (`extract/lib/_helpers.sh`, mawk-safe awk) prints what
      the jq filters print — leaves under jq's paths for `json`, top-level
      keys with nested values as compact JSON for `jsonl` — and was
      checked byte for byte against jq on every JSON input in the corpus
      and samples (98 and 15). One difference, documented: jq 1.7 spells
      `1e3` as `1E+3`.
    - **JSON Lines after `#` comments.** `jsonl` skips comment lines in
      detection and extraction; a header line or two used to push the
      records out of its three-line window and the file read as aligned
      columns.
    - **`dc-results`** (`strategies/misc/`): the floor-plan viewer's
      results format (`!test` metadata over `test target value k=v`
      samples) written by mx export, iperf export-overlay, reckon
      --overlay, dcprobe and dcimport. A row per sample, its test's
      metadata on each. Claimed only by its `!test` lines: a `--no-meta`
      file is shaped like ordinary output, and stays with the generic
      parsers.

0m. **2026-10-29: `provost batch` and `--context-columns`**, for
    quarterdeck (`qd`), which drives the toolchain on a fleet and now
    files what comes back through provost: one capture per host, with
    `#% host=NAME ...` context.
    - **`batch`:** N inputs, a capture each (id, `source`, tag), ONE
      commit. `_ingest` is now `_ingest_parse` (no store writes, LLM
      templates aside) + `_ingest_store` (under the lock); `batch` runs the
      parse halves in parallel (`-j`) and the store halves in input order
      in one lock. 40 inputs: 13 s against 55 s as single captures, on 4
      CPUs; the lock is held about 50 ms an input, so a batch of several
      hundred inputs keeps other writers waiting past
      `PROVOST_LOCK_TIMEOUT` (30 s). Not built: committing in chunks for
      very large batches.
    - **`--context-columns`:** `key=value` prologue words as columns after
      `#` and `capture`; clash → `_NAME`; `unsorted` untouched; default off.
    - The results format and NDJSON after comments, listed here as worth
      doing next, are done: see 0n.

0l. **2026-10-28: provost as a test runner — every run viewable** (PR #88).
    Asked for in one session: a short help, search on git, a way to see
    every run, a capture id per row, a listen on commands, and an import
    that said every bundle was invalid.
    - **Import fixed:** `git bundle verify` refuses to run outside a git
      repository, so importing from an ordinary directory always failed. It
      now verifies in a scratch repository.
    - **`capture` column (store format 3):** every row is `#`, `capture`,
      `n`, then the data. Older stores are migrated on the next write from
      `provenance.tsv`; a data column already named `capture` keeps its name
      and the added one is `_capture`. Store format 4 (2026-11-04, PV-015): a
      reconcile names column 2 alike on both sides first, so a data column
      `capture` never lands in it; format-3 datasets it got wrong are
      repaired from `provenance.tsv` on the next write.
    - **Run files:** a capture in a controlled directory commits the
      directory's files too, tagged `files-<id>`, chained run to run, built
      with a scratch index (the store's tree never holds a copy).
      `.gitignore` honoured; `PROVOST_FILES_MAX_SIZE` (1 MiB) caps a file.
    - **Browse, all from git:** `show --capture ID` / `--at ID`,
      `source ID`, `prev` / `next` (move the restored store), `files`,
      `diff` (rows only A or only B filed, plus the files that changed),
      `search` (`git grep`: rows, `--output`, `--files`, `--at`).
    - **`listen CMD`:** a shell function per command in
      `~/.config/provost/listen.sh` running it through `run --show` (new:
      output shown and filed). Envoy's `watch`, dropped in the rename,
      comes back at shell level.
    - **Help:** `provost help` is 47 lines; `provost help advanced` is the
      full reference, ordered by how a capture is filed. Smoke checks every
      setting there, every command, and a 79-column width.
    - **Not built / worth doing next:** `diff` compares rows as multisets
      (row order and `n` ignored), which suits test results; a keyed diff
      (match rows on a column, report changed values) would suit tables
      like `df`. `listen` pipes the command, so it loses its terminal
      (no colour; Python buffers): running it under `script` would keep a
      pty. The run-files snapshot happens when the capture is filed, which
      at a terminal is in the background just after the command ends.

0k. **2026-10-27 (later): `--llm` measured through the real API, template
    repair on a miss, and a clean-up after extraction** (PR #87, stacked on
    #86; parts 4–7 of `docs/benchmark-2026-10-27-llm-templates-round4.md`).
    - **Where it stands (round 4, rated blind):**

      | | PASS | PARTIAL | FAIL | usable |
      |---|---:|---:|---:|---:|
      | default engine | 12 | 51 | 44 | 59% |
      | first contact, `learn` + clean-up | **87** | 18 | 2 | 98% |
      | the whole pipeline, second capture + clean-up | **83** | 22 | 2 | 98% |

      API cost: about five cents a tool on first contact; on a later
      capture, a call only when the template meets a kind of line it has
      not met (about one capture in three on round 4's second captures).
    - **First contact (`learn`):** before the clean-up, 66 / 30 / 11 for
      $5.20 (108 calls).
    - **Repair** (`template.py misses` / `repair`, wired into
      `_llm_template`): a stored template that meets a kind of line it has
      not met goes back to Claude once, with the captures it was written
      from (its `"examples"`), and the extension is kept only if it still
      reads them. Part 3 rerun: 73 / 28 / 6 against 65 / 32 / 10.
    - **Clean-up** (part 7): values keep to their cells (a newline inside a
      parser's value had made junk columns: all four first-contact
      FAILs); the lines a template sets aside that carry a word or a number
      go to `NAME.notes` instead of being dropped; the catch-all guard no
      longer counts skipped lines as lost. Measured +21 / +17 PASS, nothing
      rated lower. Not built: dropping empty columns (they are the tool's
      schema) or rule/header rows (none in 602 template tables).
    - **What is left, in order of how much it would lift:**
      1. **The judge, aimed at structure.** The ~20 PARTIALs left are a
         parent the template does not keep (an op tree, iseq headers,
         trunk members, taxonomy depth, caller/callee links), a record
         split across tables, a two-layout header half applied; plus, on
         later captures, a new kind of line a pattern matches and misreads
         (LXD rows as units). One call after `learn` and after `repair`,
         PASS or a list of fixes, fed back once.
      2. **Two gate rules still cost a FAIL each:** the `yaml` exemption
         (020 never reaches a template) and `_AM_FRAG_LINES` counting lines,
         not records (132 is held on every run). *(Done 2026-11-10, PV-010:
         both file from their stored templates. Still open: on FIRST contact
         Claude is not asked to write a template over a yaml parse, so 020
         needs its template stored, by `learn` or by hand.)*
      3. Then the library (plan step 5) and round 5, built and frozen before
         anything runs. Round 4 is spent for `--llm`.
    - Small: the melt should rename a template column colliding with the
      row id. *(Done 2026-11-04, PV-011: see 0u.)*

0j. **2026-10-27: `--llm` goes first, templates can be parsers (format 2),
    and round 4 is measured with templates** (`docs/plan-2026-10-27-near-100.md`
    is the plan; CHANGELOG has the detail).
    - **Why:** four rounds at 11–21% PASS on unseen output; the gate files
      27 of round 4's 44 FAILs at ≥95% coverage, so nothing behind it ever
      ran. A template written for one tool only has to fit that tool's next
      capture: no cross-tool generalisation needed.
    - **Done:** LLM-first hook in `_ingest` (before auto-multi/model on a
      held capture; before a generic parse the gate passed is trusted);
      `extract/llm/sandbox.py` runs a format-2 parser in a box;
      `PROVOST_LLM_TEMPLATE_DIRS`; `tests/benchmark/llm_round.sh`;
      `tests/benchmark/round4/llm-templates/` (107 format-1 templates by
      Claude helpers, with `.note`s on what format 1 could not express).
    - **Round 4 with templates** (`docs/benchmark-2026-10-27-llm-templates-round4.md`):
      format 1 alone **35 / 66 / 6**; with format-2 parsers for the 65
      inputs format 1 could not express, **86 / 18 / 3 (80% PASS, 97%
      usable) against the engine's 12 / 51 / 44**. No shape family under
      70% PASS. Of the 21 left, 4 are the catch-all guard declining a
      parser that skipped decoration, 1 the fragments rule on a one-line
      input, 1 the `yaml` exemption, 10 unrewritten format-1 templates
      PARTIAL on strict rule 3, 5 near-misses.
    - **Second capture** (part 3; `round4/variants/`, frozen; rated blind):
      the same stored templates on a never-seen second capture of each
      tool score **65 / 32 / 10 (61% PASS, 91% usable)**. Nearly every drop
      is a line kind the first capture never showed: the template is
      declined (5, falls back to the engine) or misses it (17); once a
      `skip` rule swallowed a diff while coverage read 100%.
    - **Not yet measured:** the first-contact rate through `learn` (two API
      attempts, no iteration).
    - **Next:**
      1. **Template repair on a miss:** a stored template's unread lines on
         a new capture go back to Claude to extend it (one call), kept only
         if it still reads the captures it was written from; record which
         captures each template has seen. Then rerun part 3.
      2. Skip lines audited (count + sample, judged), not counted as
         covered for free.
      3. The judge (step 3), then with the key the `learn` run, the library
         (step 5) and round 5.
      - **The key:** add it as `PROVOST_LLM_API_KEY` (a Claude Code
        environment keeps `ANTHROPIC_API_KEY` for its own sign-in).
      - Small: `_AM_FRAG_LINES` should count records; the melt should
        rename a template column colliding with the row id (done
        2026-11-04, PV-011).

0i. **2026-10-26: `--llm`. Claude writes a parsing template for a tool once,
    and provost reuses it offline** (`extract/llm/`, LLM TEMPLATES in
    `provost help`).
    - **Tested** end to end against a fake API (`tests/fake_anthropic.py`).
    - **Not yet run against the real API:** the session's key was deleted.
    - **Next:**
      1. With a real key, run `--llm` over the 38 captures held in rounds
         2–4 and rate the templates.
      2. Grow `extract/llm/templates/` from the templates that prove good.
      3. Consider letting `--llm` re-check generic parses the gate passed.

0h. **2026-10-26: `--model` ships the LLM-trained trees, with a refitted
    arbiter.**
    - **Measured:** fresh test 136/150 (previous model + arbiter 133,
      engine 126); gold 242/300 (210, 193).
    - **Still opt-in**, and the corpus goldens are unchanged.
    - **Next:**
      - an end-to-end round 5 to measure `--model` on unseen captures;
      - consider making the model the default fallback for held captures.

0g. **2026-10-25: 297 format generators** (`ml/gen/`), **plus the
    LLM-trained trees measured on the full test** (`docs/gridnet-2026-10-23.md`).
    - **Generated data:** small gains for GridNet (+0.8 points), none for the
      trees.
    - **Trees on LLM labels + `synth.py`:** fresh test 131/150 (shipped
      130); gold 219/300 (194), hard lines 97 against 77.
    - **Decision needed:** ship these trees as the opt-in `--model`? It
      would need the arbiter refitted and the layout-model golden
      regenerated.
    - **Otherwise the layout model has plateaued** at about 83% of the
      teacher's splits on unseen families.

0f. **2026-10-23: GridNet, the self-learning model, was built and measured,
    and is not shipped** (`ml/train_grid.py`, `extract/model/gridnet.py`,
    `docs/gridnet-2026-10-23.md`).
    - **Result:** on 3,163 held-out lines it matches the LLM labels 79–81% of
      the time, against 82.9% for the trees. Averaging the two gives 83.5%.
      Too little data (about 3,000 small captures) for it to learn layout
      from scratch.
    - **Next:** have Claude write a few hundred format generators (correct
      labels by construction, about $10–30), then retrain both models and run
      the full 5-fold test plus the fresh test once. Needs a new
      `ANTHROPIC_API_KEY` in the environment.

0e. **2026-10-23: LLM teacher. Claude labelled the whole corpus (3,674 of
    3,705 kept; $24.48)** (`ml/llm/`, `ml/eval/llm-labels-2026-10-23.jsonl.gz`,
    `docs/llm-teacher-2026-10-23-pilot.md`).
    - **Teacher:** 147/150 on the fresh test lines (engine 126/150) and
      286/297 on gold, against a 97% human ceiling.
    - **Student:** the same tree model trained on these labels scores 132/150
      on the fresh test (shipped model 130/150) and 215/300 on gold (194).
      **The student is now the limit, not the labels.** The shipped model is
      unchanged.
    - **Next:**
      1. A character-grid model that learns its own features from the whole
         capture, trained on the LLM labels (numpy/onnxruntime at capture
         time, as an optional extra).
      2. Then a round 5 to measure it.
      3. Review a sample of the 8,931 lines where the LLM and the engine
         differ (`ml/llm/score.py --sheet`); the pilot's 102 lines are in
         `ml/eval/llm-pilot-review-2026-10-23.md`.
      4. ~~**Rotate the API key the user pasted into chat on 2026-10-23.**~~
         Done: the owner confirmed it revoked on 2026-11-04 (PV-004). A
         replacement goes in the environment as `PROVOST_LLM_API_KEY`, never
         in chat or git.

0d. **2026-10-23: the model now works inside auto-multi (per part, and
    with its own sections) and arbitrates with the engine per line.**
    - **Result:** 0 extra rescues on rounds 2 and 3 (22 held captures). The
      gate rejects every model section there, for dropped prose lines or
      headerless tables.
    - **Where the value is instead: captures the engine files WRONG at
      high coverage.** One constructed example: a summary over a table,
      with no blank line between them, filed as whole-line text cells; the
      model's sections are exactly right.
    - **Next:**
      - the model as a second opinion on FILED generic parses (hold or
        replace when it disagrees strongly);
      - a round 5 to measure that honestly.

0c. **2026-10-22: the layout model is in provost, opt-in (`--model`,
    `PROVOST_MODEL=1`, default off).**
    - **Where:** the runtime is `extract/model/` (stdlib; the trees are
      `layout-model.json.gz`, rebuilt by `ml/export_model.py`), behind the
      explicit-only strategy `layout-model`.
    - **When it runs:** only for a capture the gate still holds after
      auto-multi. Its table is filed only if it passes the same gate.
    - **Round 4, measured once:** 15 held captures became 14 held and 1 filed
      (PARTIAL); no wrong table was filed. Almost everything still held is a
      mixed multi-section report, which the model declines by design.
    - **Next:** apply the model per segment inside auto-multi (the parts
      the engine can't read), and use `ml/arbiter.py` where both produce a
      table.
    - **Round 4 is now spent** for this change too; the next honest
      measurement needs a round 5.
    - **Ceiling and arbiter:** the labeller-agreement ceiling is about 97%.
      The arbiter scores 88.7% on the fresh test (model 86.7%, engine 84%).
      `ml/decode.py` became `extract/model/decode.py`.

0b. **2026-10-22: a small learned layout model, steps 1-2 (`ml/`, dev-only,
    nothing ships).** Write-up: `docs/model-2026-10-22-layout-steps1-2.md`.
    - **Training set:** 2,831 corpus files (18,231 lines) labelled from the
      goldens with line roles and field starts, plus a 4,000-document
      synthetic generator. Stdlib tests run in CI (`quick-checks`).
    - **Best model:** LightGBM trees trained on the corpus. On held-out tool
      families they split 77% of lines exactly right, against 54% for
      splitting on spaces (about 85% after a hand audit of label errors).
      Roles: 87% (95% counting row≈kv). Size: 3.3 MB gzipped.
    - **LayoutNet** (a 53k-parameter CNN+GRU, 100 KB) reaches 69%: smaller,
      not better. Synthetic data barely transfers to real tools.
    - **The labels are now the limit:** about a third of the disagreements are
      provost's own golden mistakes.
    - **Measured against 300 hand-labelled lines** (`ml/eval/gold-*.jsonl`,
      scored out of fold by `ml/crossval.py`):
      - the improved tree model is right on 62% of all lines and 77% of
        random lines;
      - the engine scores 64% and 80%;
      - one or the other is right on 85% of random lines.
      - The model uses the new features plus `--clean 0.05 --fix-labels`;
        `train_baseline.py --final` builds it.
    - **Fresh test (150 random lines, scored once; `ml/eval/test-*.jsonl`):**
      model 86.0%, engine 84.0%, so the two are level. One or the other is
      right on 91%.
      - The large dev-set gains were mostly a selection effect: the "hard"
        lines were picked where the first model was wrong.
      - On the 1,755 maintainer-approved lines the model matches 85%.
      - Don't expect it to replace the engine. Step 3 should use it only
        where the gate holds the engine's parse.
    - **Step 3 (next):**
      - a pure-Python tree evaluator, so there is no new dependency;
      - wire it behind `PROVOST_MODEL` (off by default), only for captures the
        gate would hold, and accept its parse only if it passes the gate;
      - measure once on round 4. `tests/benchmark/` was never read by `ml/`.
    - Reproduce: `ml/README.md`.

0a. **2026-10-20, PR #79 (unreleased; would be 2.3.0):**
    - **Round 4:** 107 unseen inputs on the 2.2.0 engine.
      - Default mode: 11% PASS, 48% PARTIAL, 41% FAIL (59% usable).
      - `--multi`: 71% usable.
    - **Automatic `--multi` fallback** (`PROVOST_AUTO_MULTI=1`): before the
      gate holds a weak parse, segment it and file the parts if every part
      passes the gate.
    - **Measured once on round 4:** 2 rescues, 1 wrong table filed, 6 missed
      rescues. That is a small net gain.
    - **Next:** loosen the guards to recover more of the 8 possible rescues,
      tighten the per-part check that let 048 through, then measure on a
      round 5.

0. **Done 2026-10-20 (PR #77), not yet released.**
   - Six engine defects from round 3 are fixed: no-output fallback, tsv
     truncation, duplicate names losing values, fixed-width cutting digits,
     the invented gnu-version field, and the dot-leader near-miss.
   - The **quality gate** is in: likely-wrong generic parses (coverage < 80 or
     consistency < 70) go to triage. On the rated sets it holds 18 of 48 FAILs
     and 0 of 57 PASSes. Tune it with `PROVOST_MIN_COVERAGE` /
     `PROVOST_MIN_CONSISTENCY`, or turn it off with 0.
   - Release as 2.2.0 together with the 2026-10-16 work.

1. **Rethink the approach before another fix round.** Two rounds of
   pattern-level fixes, each developed against new examples, moved unseen
   FAIL by only 1–3 points while seen sets improved a lot. More heuristics in
   the same style will probably fit what we can see again. Options worth
   weighing:
   - Use `--multi` segmentation by default when coverage or consistency is
     weak. `--multi` was better on 19 round-3 inputs.
   - Make the parse-quality signals decide more often, not just veto.
   - Narrow the claim: report low confidence and route to triage instead of
     committing a wrong table. Today every input clears the commit
     threshold, but a third are wrong.
2. ~~Engine bugs found by round 3~~ — fixed 2026-10-20 (see 0). Originally:
   - `java -XX:+PrintFlagsFinal`-style input gives no output at all.
   - `tsv` truncates rows to the first row's width while coverage reads 100.
   - duplicate column names lose values in the melt.
   - `gnu-version` emits a field that is not in the input.
   - a bespoke parser claims near-miss input at under 31% coverage and is not
     held.
3. **Round 4**, built before the next fix round, to measure it.
4. **Release 2.2.0** when PR #76 lands, following the 2.1.0 steps (CHANGELOG
   2026-10-16 release entry). Publishing needs a person: this session type
   cannot create GitHub releases.
