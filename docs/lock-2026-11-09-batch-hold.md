# How long `provost batch` holds the store lock (PV-024, 2026-11-09)

An outside assessment (attached to QD-006) said `provost batch` holds the
store lock "about 50 ms per input". It said a thousand hosts in one batch
would keep a second writer waiting past the 30 s lock timeout, and called this
"a ceiling for CLIN 3-scale runs". The 50 ms figure came from a comment in
quarterdeck, not from a measurement. This is the measurement.

## Method

`tests/perf/batch-lock-time.sh N [PROVOST]` files N synthetic one-host outputs
with one `provost batch --context-columns` into a fresh store. Each input is a
`#% host=` prologue and a 3-column CSV row, the shape quarterdeck files. A
background loop polls for the store's `.lock` directory every 5 ms. The hold
is the time from the first poll that saw the lock to the last. Resolution is
about 5–10 ms, which is nothing against holds of seconds.

- provost `main` @ bde1c68 (2.3.0), unmodified
- 4 CPUs, Linux 6.18, bash 5.2.21, git 2.43.0, a local disk
- parse jobs: the default (one per CPU)

Where the time goes was measured on a 100-input batch run with `bash -x` and an
`$EPOCHREALTIME` `PS4` (set through `BASH_ENV`, because bash ignores `PS4`
from the environment when run as root). Each traced line's time was added up
by function and line number, between `_lock` and `_unlock`.

## Results

| inputs | whole batch | lock held | per input |
|---:|---:|---:|---:|
| 200 | 17.6 s | 9.7 s | 48.3 ms |
| 1,000 | 86.6 s | 51.2 s | 51.2 ms |
| 5,000 | 521.3 s | 322.2 s | 64.4 ms |

The assessment's 50 ms is right. The cost per input grows slowly with the
store (48 → 51 → 64 ms). Each capture adds files that the final
`git add -A` and commit walk, and appends to datasets that grow.

**Where the ~50 ms goes.** Nothing dominates. Inside the lock each capture
runs more than a dozen short processes: command substitutions (`$(_cap_dir)`,
`$(_rowid_file)`, `$(_meta_safe ...)`), a `git rev-parse` per candidate id in
`_next_capture_id` (to never reuse a tagged id), `cp` and `mkdir` of the
capture directory, the dataset append, and the provenance and meta writes. At
1–4 ms per fork that adds up to the figure above. The final `git add -A`,
`git commit` and one `git tag` per capture took 0.53 s for 100 captures,
about 10% of the hold. About 4 ms of that per capture is the tags, one
`git` process each.

## What it means

- **quarterdeck's chunk of 200 holds the lock about 10 s**, a third of
  `PROVOST_LOCK_TIMEOUT` (30 s). A second writer that arrives during a chunk
  gets the lock as soon as that chunk commits. Any number of hosts files, one
  commit per 200.
- **An unchunked batch of 1,000 holds it about 51 s**, so a second writer
  arriving at its start times out after 30 s. That is a reason to keep
  chunking (or to raise `PROVOST_LOCK_TIMEOUT` for the waiting writer). It is
  not a ceiling on how many hosts can be filed.
- **A batch of 5,000 holds it over five minutes.** No other writer can file
  in that time, so a wrapper filing that many must chunk.
- **Fairness:** the lock is a `mkdir` spin, not a queue. A writer that arrives
  while chunks run back to back competes for the lock at each gap between
  chunks, with no priority. In the concurrent-writers smoke check (two
  6-input batches at once) both finish, each with its own commit, with no
  gaps or duplicates in ids or rows.

## Recommendation

**No change now.** At 50 ms per input and 200 per chunk, filing 1,000 hosts
holds the lock for about 50 s in total, in five pieces of about 10 s, and
nobody waits past the timeout. If a store ever needs much more throughput,
the cheap wins, in order:

1. Tag all of a batch's captures with one `git update-ref --stdin` instead of
   one `git tag` per capture: about 4 ms per input, roughly 8%.
2. Pick the batch's ids once (one scan of tags, then count up) instead of one
   `git rev-parse` per id in `_next_capture_id`: a few ms per input.
3. Replace the `$(_cap_dir)`-style substitutions inside `_ingest_store` with
   variables set once per batch: the rest of the forks.

Together these might halve the hold. Per-dataset locking, the assessment's
other idea, would change the store's guarantee that capture ids and commits
are in one order. Nothing measured here calls for it.

quarterdeck's comment at `quarterdeck/filing.py:228` ("about 50 ms per
input") turns out to be right. It can cite this file. (A follow-up on
quarterdeck, by PV-024.)
