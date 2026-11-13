# The provost store format

This is the specification of the store provost files captures into: its
directory layout, every file in it, the git refs it keeps, and how each
earlier format differed. It describes **store format 4**, the format provost
2.4.0 and every later release writes. A program that reads a store without
provost (quarterdeck does) can rely on what is written here, and on nothing
that is not.

- The format number is in the store's `.store_format` file. A store with no
  such file is format 1.
- `provost store check [DIR]` checks a store against this document, judging
  it by the format it records. It only reads.
- `tests/store-fixtures/` holds a store of every format, each written by the
  last release that wrote that format, and CI opens every one of them with
  the current provost (`tests/smoke.sh`, part `store-spec`).

## Contents

1. [The compatibility promise](#the-compatibility-promise)
2. [Where a store is](#where-a-store-is)
3. [Layout](#layout)
4. [Files at the top of the store](#files-at-the-top-of-the-store)
5. [Datasets](#datasets)
6. [provenance.tsv](#provenancetsv)
7. [Captures](#captures)
8. [meta.tsv](#metatsv)
9. [Git: the branch, the commits and the tags](#git-the-branch-the-commits-and-the-tags)
10. [Inputs kept beside the store](#inputs-kept-beside-the-store)
11. [The disposal log](#the-disposal-log)
12. [Other files](#other-files)
13. [Runtime files](#runtime-files)
14. [Format history](#format-history)
15. [Reading a store from another program](#reading-a-store-from-another-program)
16. [Changing the format](#changing-the-format)
17. [Archives](#archives)

## The compatibility promise

**Every provost reads every older store format.** A store a provost release
wrote is read, as it is, by every later release.

- **A new format bumps the number and ships a migration.** Format N+1 is
  never introduced without a migration from format N, run automatically.
- **Only a write migrates.** The first command that writes to a store (a
  capture through `run`, `inject` or `batch`; `rm`; `prune --yes`;
  `archive --purge --yes`; `annotate`; `restore`, `prev`, `next`; `control`)
  first brings an older store up to the current
  format, in a commit of its own (`provost: store maintenance (... store
  format 4)`), and then does its work. The migration is in the store's git
  history like any other change, so the store as it was is still there.
- **A command that only reads never changes a store on disk.** `ls`, `show`,
  `source`, `log`, `search`, `files`, `diff`, `stats`, `triage`, `verify`,
  `doctor`, `instances`, `check-manifest`, `export`, `store check`,
  `archive` without `--purge` and `prune` without `--yes` leave every byte
  of the store as it was, its `.git` directory included, and work
  on a store they cannot write (an evidence copy, read-only media, a store
  whose history has been signed). They read an older store in its own
  format. CI holds this: each fixture store is read by each of these and
  must come out byte for byte unchanged. One runtime file is the exception,
  and it is not part of the store's content: `log --failed` records in
  `.async-failures.seen` how many background failures it has shown, when it
  can ([Runtime files](#runtime-files)).
- **Release lines.** There is no long-term-support branch: fixes ship in the
  next release. The promise above is what makes that enough, since any later
  release opens an older store; evidence filed at one stage of a programme is
  read by whatever provost is current at the next.
- **Not promised: an older provost on a newer store.** A provost does not
  refuse a store whose format is newer than the one it writes. Reading one
  mostly works (a later format has so far only added to what an earlier one
  held), but writing to one can file data in the older shape. Use a provost
  at least as new as the store's format to write to it; `store check` says
  when a store is newer than the provost running it.
- **Not part of the format:** the exact tidy table a parser files for a given
  tool's output (parsers improve between releases; a capture already filed
  never changes), the wording of commit messages beyond what is listed here,
  and any file this document does not describe.

The promise covers the store as provost's own commands left it. A store
edited by hand is checked by `provost store check` and `provost verify`;
neither repairs anything.

## Where a store is

A store is a directory that is a git repository. Which one a command uses:

| Kind | Directory |
|---|---|
| explicit | `$PROVOST_WORKSPACE` |
| controlled directory | `DIR/.provost`, for the nearest directory above the current one that `provost control` made an instance |
| global | `$PROVOST_HOME`, else `~/.provost` |

A store is created by its first write, or by `provost init`. Nothing in the
store depends on where it is; a store can be moved, copied or cloned
(`provost export` and `provost import` move one as a git bundle).

**The git object format** (2.18.0 on) is SHA-1, git's default, unless the
store was made with `provost init --object-format sha256` or
`PROVOST_OBJECT_FORMAT=sha256`; then it is SHA-256 (git 2.29 or later), and
its `.git/config` sets `extensions.objectformat = sha256`. Nothing else
about the store differs: the layout, the files and the refs are the same,
and object ids are 64 hex digits instead of 40. provost never converts a
store from one format to the other. A reader must read a store with a git
that knows its object format, and cannot fetch a SHA-256 store into a SHA-1
repository (`git clone` makes a copy in the source's format; `git init`
followed by `git fetch` does not). `provost doctor` and `provost store
check` show the format.

## Layout

```
STORE/
├── .git/                       the store's history (see Git)
├── .gitignore                  runtime files, never committed (format 2 on)
├── .store_format               the format number (format 2 on)
├── .provostrc                  "provost workspace (store model VERSION)"
├── .next_row_id                the next row number
├── .next_capture_id            the next capture number (format 2 on)
├── provenance.tsv              every row: its number, dataset and capture
├── disposals.tsv               captures disposed of by prune or archive --purge (2.19.0 on)
├── datasets/
│   ├── NAME.tsv                one dataset
│   ├── NAME.v2.tsv ...         another shape filed under the same name
│   └── unsorted.tsv            inputs held back, whole
├── captures/
│   └── c0007/
│       ├── output.txt          the input as stored
│       ├── meta.tsv            what the capture was
│       ├── context.txt         its '#%' prologue (when it had one)
│       ├── units.tsv           columns --units base added (when it did)
│       └── annotations.txt     keys added after it ('provost annotate')
├── llm-templates/              parsing templates for this store (Claude's or a person's)
│   ├── TOOL.json, sig-HASH.json, TOOL.textfsm
│   └── STEM.seen.tsv           each template's ledger
├── context/manifest.tsv        a controlled directory's files (controlled only)
└── CONTROLLED                  the controlled directory's path (controlled only)
STORE.artifacts/                inputs over the size cap, kept whole (outside git)
```

Everything under `STORE/` except `.git/` and the runtime files is committed.
All text is UTF-8 as received (provost does not re-encode), with LF line
ends. TSV files are tab-separated, one record a line, with a header line and
no quoting of any kind: a cell holds no tab and no newline.

## Files at the top of the store

| File | Content | Since |
|---|---|---|
| `.store_format` | One line: the format number, digits only. | format 2 |
| `.gitignore` | Exactly the block below; its first line is the marker provost recognises. | format 2 |
| `.provostrc` | One line, `provost workspace (store model VERSION)`, VERSION being the provost that created the store. Informational. | format 1 |
| `.next_row_id` | One line: the next row number to assign, an integer of at least 1, greater than every row number the store has used. | format 1 |
| `.next_capture_id` | One line: the next capture number, an integer of at least 1, greater than every capture number the store has used, including captures `rm` has since removed. | format 2 |

Row numbers and capture numbers are never reused: not after `rm`, `prune`
or `archive --purge`, not after `restore`. Both counters are committed with
each capture.

The `.gitignore`, as written by format 2 and later:

```
# provost store .gitignore v1 — runtime files, never committed
/.lock
/.lock.*
/.async-failures.log
/.async-failures.seen
/instances.tsv
/instances.tsv.*
/datasets/.recon.*
/datasets/.stage.*
/datasets/.rm.*
/datasets/.rmprov.*
/captures/*/.meta.tmp
/context/*.tmp
```

## Datasets

`datasets/NAME.tsv` is one dataset: a header line and one line per row. NAME
is letters, digits, `.`, `_` and `-`, starting with a letter or digit.

Columns, in order:

| Column | Name | Holds |
|---|---|---|
| 1 | `#` | The row's number: unique across the whole store, never reused. `provost source N` finds its capture. |
| 2 | `capture`, or `_capture`, `__capture`, ... | The id of the capture the row came from (`c0007`). The column is named `capture` unless the data has a column of that name, in which case it takes a leading `_` until the name is unique (the data column keeps its own name). Find it **by place, not by name**. |
| 3 ... | context columns | Only with `--context-columns`: one column per `key=value` in the capture's `#%` prologue, named by the key (a leading `_` on a clash, as above). `meta.tsv`'s `context_columns` says which columns these are. |
| then | the data | What the parse filed. A parse that melts records leads with `n`, the record's place in that capture (or `key`, a keyed group's member), then the record's fields. A data column named `#` is filed as `#_2` (the first `#_K` free), and `meta.tsv` records the rename. |

Rules that hold for every dataset:

- Every row has exactly as many fields as the header. An empty field is
  empty, never a placeholder.
- When a capture's table has the same header as the dataset, its rows are
  appended. When the headers differ but share at least
  `PROVOST_RECONCILE_OVERLAP` per cent of their columns, the dataset is
  rewritten with the union of the two headers and both sides' rows
  blank-filled. When they share less, the capture is filed in a variant,
  `NAME.v2.tsv`, `NAME.v3.tsv`, ... (the first variant whose header is the
  same, or a new one). A variant is a dataset like any other.
- A row's number appears in `provenance.tsv` exactly once, against this
  dataset and the capture in column 2.

**`unsorted.tsv`** holds the inputs that were held back (no parser was
confident enough, or the quality gate stopped it): one row per held capture,
columns `#`, `capture` (format 3 on), `raw`, where `raw` is the whole stored
input (`output.txt`) base64-encoded on one line.

## provenance.tsv

One line per row in the store. Header `#`, `dataset`, `capture`:

```
#	dataset	capture
1	disks	c0001
```

`dataset` is the dataset's file name without `.tsv` (a variant's name
includes `.v2`); `capture` is the capture id. `rm` removes the lines of the
rows it deletes. Every dataset row is in it, and every line in it is a row
of an existing dataset.

## Captures

Each capture is a directory `captures/cNNNN/`: `c` and at least four digits
(`c0007`, `c12345`). The number is the capture's, from `.next_capture_id`.

| File | Present | Holds |
|---|---|---|
| `output.txt` | always | The input as provost stored it: as received, carriage returns removed, secrets scrubbed (`redacted` in meta.tsv says what was replaced; `PROVOST_REDACT=0` turns the scrub off), prologue included. For a truncated capture, only the part that was parsed. `provost verify` re-hashes this file. |
| `meta.tsv` | always | What the capture was ([meta.tsv](#metatsv)). |
| `context.txt` | when the input opened with `#%` lines | That leading run of `#%` lines (including what `--manifest` and `--env` added), as in `output.txt`. |
| `units.tsv` | when `--units base` added columns | `dataset`, `column`, `unit_column`, `base`, `from`, `read`: one line per column it added. |
| `annotations.txt` | after `provost annotate` | `#% key=value` lines, one key each; setting a key again replaces its line. |

A capture `rm`, `prune` or `archive --purge` removes loses its directory
(and its tags); its number is not used again, and git's history still holds
it. `rm` of a dataset that a capture also filed into another
dataset keeps the capture and rewrites the `dataset` line of its meta.tsv.

## meta.tsv

`KEY<TAB>VALUE` lines. Keys are lower case. A value holds no raw tab or
newline: one that had them is written with `\t` and `\n`. A reader must
ignore keys it does not know, and must not depend on their order.

Always present:

| Key | Value |
|---|---|
| `id` | The capture id, the same as its directory. |
| `ts` | When it was filed, UTC, `YYYY-MM-DDTHH:MM:SSZ`. |
| `source` | `run`, `inject` or `batch`. |
| `dataset` | The dataset(s) it filed into, comma-separated. |
| `row_ids` | `FIRST-LAST`, the row numbers it was given (consecutive across its datasets), or `none`. |

Written by every capture since format 1, possibly empty: `command` (a
`run`'s command line, quoted as a shell would need it), `rc` (a `run`'s exit
status; empty for `inject`), `strategy` (the parser, per dataset,
comma-separated), `confidence` (per dataset).

Present when they apply:

| Key | Value |
|---|---|
| `coverage`, `consistency` | The quality gate's measures, per cent. |
| `datasets`, `dataset_rows`, `dataset_coverage`, `dataset_consistency` | With more than one dataset: how many, and per dataset `NAME:#A..B` (or `NAME:none`), its coverage and its consistency. |
| `auto_multi`, `auto_multi_model_parts` | The input was segmented into parts (`segmented (KIND): REASON`), or segmenting was tried and declined (`declined: ...`). |
| `layout_model` | `filed: ...` or `declined: ...`: whether the layout model filed it. |
| `llm_template`, `llm_skip_audit` | `filed by ...` or `declined: ...`; what the template skipped. |
| `template` | The template that filed it (2.20.0 on): `llm-templates/NAME.json`, `shipped:NAME.json`, or its path in a template directory (`PROVOST_TEMPLATE_DIRS`). |
| `single_strategy`, `single_confidence`, `single_coverage`, `single_consistency` | The single parse that another route replaced, kept for the record. |
| `plugin_dir` | The `--plugin-dir` in force. |
| `context` | `context.txt`, when the capture has one. |
| `context_columns` | `key=column,...`: the dataset columns its prologue became. |
| `units`, `units_columns` | `base`; `units.tsv`. |
| `renamed_columns` | `DATASET:old=new,...`: data columns the melt renamed (`#` to `#_2`). |
| `detection` | How the parser was chosen when it was not detected afresh (`reused (...)` in a batch). |
| `redacted` | What the secret scrub replaced: `kind=n,...`, `none`, or `off`. |
| `input_sha256`, `input_bytes` | The input as received, before any change: its sha256 (64 lower-case hex digits) and size. |
| `output_sha256` | The sha256 of `output.txt` as stored. `provost verify` re-checks it. |
| `input` | In a `batch`: the file this capture was read from. |
| `interrupted` | `SIGINT`, `SIGTERM` or `SIGHUP` (2.23.0 on): a signal cut the capture short, and `output.txt` holds what came before it (and what the command printed in the grace after it). `rc` is the command's status, or empty when it had not ended. Absent on a capture that ran to its end. |
| `batch` | In a `batch`: `FIRST..LAST`, the batch's capture ids. |

An input over the size cap (format 4, from 2.15.0; [Inputs kept beside the
store](#inputs-kept-beside-the-store)) adds all six of these:

| Key | Value |
|---|---|
| `truncated` | `1`. Absent on a capture that was not truncated. |
| `parsed_bytes` | How many bytes of the input were parsed and stored in `output.txt` (`PROVOST_MAX_INPUT`, cut back to the last whole line). |
| `raw_artifact` | The path the whole input was kept at, when it was filed. |
| `raw_sha256` | The sha256 of the kept copy: its file name. |
| `raw_bytes` | The kept copy's size. |
| `raw_redacted` | What the scrub replaced in the kept copy (as `redacted`). |

On a truncated capture `input_sha256` and `input_bytes` describe the whole
input as received, and `output_sha256` the part in `output.txt`.

Keys have been added over the releases (the input hashes in 2.4.0, the
`truncated` set in 2.15.0, `interrupted` in 2.23.0, and others), and none
changed the format number: a key is added within a format, and a reader that
ignores keys it does not know reads every capture, old or new.

## Git: the branch, the commits and the tags

- **The branch** is `main`, or `master` in a store an older git created.
  Captures are committed on it, one commit each (a `batch` is one commit for
  all its captures). HEAD is on the branch, except after `restore`, `prev`
  or `next`, which check out an earlier capture with HEAD detached; a store
  in that state refuses writes until `provost restore latest`.
- **Commits** are made with the identity `provost <provost@localhost>`.
  They are unsigned unless whoever ran provost set `PROVOST_SIGN` (2.18.0
  on): then every commit provost made in that run carries an SSH or OpenPGP
  signature (the `gpgsig` header). A store can hold signed and unsigned
  commits side by side; signing is a setting of the person writing, not of
  the store. Their subjects:

  | Subject | Made by |
  |---|---|
  | `provost: init workspace` | creating the store |
  | `provost: store maintenance (...)` | a migration |
  | `capture cNNNN: SOURCE STRATEGY → DATASET (#A..B) [COMMAND]` | a capture |
  | `batch: N capture(s) cA..cB (R rows)` | a batch |
  | `annotate cNNNN: KEY, ...` | `annotate` |
  | `rm: ...` | `rm` |
  | `prune: disposed of N capture(s) [...], pruned R row(s)[, emptied ...] under policy NAME (sha256 HEX12)` | `prune --yes` (2.19.0 on) |
  | `archive: disposed of N capture(s) [...], pruned R row(s)[, emptied ...] to archive DIRNAME` | `archive --purge --yes` (2.19.0 on) |
  | `provost: control DIR (...)`, `provost: uncontrol DIR` | `control`, `uncontrol` |

  A capture's or batch's commit message ends with trailers, one pair per
  capture that recorded hashes: `Input-SHA256: cNNNN HEX` and
  `Output-SHA256: cNNNN HEX`. From 2.18.0 every commit provost makes ends
  with an `Operator: WHO` trailer (in the same trailer block as the hashes):
  who made it, as `user@host`, or `PROVOST_OPERATOR` when that was set. It
  is one line of printable text, at most 512 characters. A commit made
  before 2.18.0 has none. Read it with `git log
  --format='%(trailers:key=Operator,valueonly)'`.
- **`capture-cNNNN`** is a tag on the commit that filed capture cNNNN, one
  per capture on the branch: a lightweight tag, or, for a capture made with
  `PROVOST_SIGN` set (2.18.0 on), an annotated tag signed with the same key,
  whose message is `capture cNNNN` and an `Operator:` trailer. **Peel it**
  (`capture-cNNNN^{commit}`) rather than assume it names the commit itself.
  `rm`, `prune` and `archive --purge` delete the tags of the captures they
  remove.
- **`files-cNNNN`** (controlled directories, 2.2.0 on) is a lightweight tag
  on a commit holding the controlled directory's own files as capture cNNNN
  saw them. These commits are **not on the branch**: they form a chain of
  their own, each with the previous run's as its parent; a run whose files
  did not change is tagged on the previous run's commit.

`provost verify` checks the history: `git fsck`, each tag against the branch,
each `output.txt` against its recorded hash, gaps in the capture ids, and each
signed capture's commit and tag signatures (`--allowed-signers FILE` or
`PROVOST_ALLOWED_SIGNERS` for SSH; `--require-signed` fails an unsigned
capture). `provost export --redact` writes a rewritten history: its copy
carries no signatures and no `Operator:` trailers.

## Inputs kept beside the store

Format 4 stores, from provost 2.15.0 (PV-021). An input larger than
`PROVOST_MAX_INPUT` is not refused (unless `PROVOST_OVERSIZE=refuse`): its
first `PROVOST_MAX_INPUT` bytes, cut back to a whole line, are parsed and
stored as usual, and the whole input is kept **outside the store's git
history**, in the **artifact directory**:

- `$PROVOST_ARTIFACT_DIR` when set; otherwise `STORE.artifacts`, a sibling of
  the store (`~/.provost.artifacts`; `DIR/.provost.artifacts` for a
  controlled directory). Never the store or inside it.
- Each kept input is one file named by its sha256 (64 lower-case hex
  digits), scrubbed like a stored input, read-only. The same bytes kept
  twice are one file.
- It is not committed, is not in an `export` bundle, and is not in a
  controlled directory's `files-*` commits.
- A capture finds its kept input at `raw_artifact`, or, when that path no
  longer exists (the store and its artifact directory were moved together),
  by `raw_sha256` in the artifact directory as it is now. `provost source`,
  `provost verify` and `provost store check` report a kept input that is
  missing or no longer hashes to `raw_sha256`.

## The disposal log

`disposals.tsv`, at the top of the store, from provost 2.19.0 (PV-029). It is
written only by `prune --yes` and `archive --purge --yes`, which append one
line per capture they dispose of, **in the same commit as the disposal**.
Nothing in provost removes or changes a line of it, and nothing prunes it. A
store that never disposed of anything has no such file. Header and columns:

| Column | Holds |
|---|---|
| `capture` | The capture id disposed of (`c0007`). Never in `captures/` again: ids are not reused. |
| `disposed` | When, UTC, `YYYY-MM-DDTHH:MM:SSZ`. |
| `operator` | Who: `PROVOST_OPERATOR`, else `user@host` (as the commit's `Operator:` trailer). |
| `how` | `prune` or `archive`. |
| `rule` | Why: for `prune`, `policy NAME (sha256 HEX12) line N: RULE`, the policy file's name, the first 12 hex digits of its sha256, and the rule that let the capture go; for `archive`, `archive DIR (SHA256SUMS sha256 HEX12)`. |
| `ts` | The capture's own `ts` from its `meta.tsv`. |
| `dataset` | Its `dataset` (comma-separated). |
| `output_sha256` | Its `output_sha256`, or empty when it recorded none. |
| `raw_sha256` | For a truncated capture, the sha256 of its kept input, which is **left in place** in the artifact directory (it is outside git, and the same bytes may serve another capture); else empty. |

A disposal removes a capture from the working store, as `rm --capture` does:
git's history (the commit before the disposal) still holds it, and
`provost source ID` still finds it there. Destroying it from the history as
well would mean rewriting it; provost does not do that.

`store check` checks the header and each line's form, that no capture is
recorded twice, that no capture recorded is still in `captures/`, that every
one is below `.next_capture_id`, and that the file is committed. An older
provost ignores the file, and a store with one is still format 4.

## Other files

- **`llm-templates/`**: parsing templates for this store, written
  by `--llm` (`TOOL.json`, or `sig-HASH.json` for a tool known by its output's
  signature) or put there by a person (`TOOL.json`, or a TextFSM template
  `TOOL.textfsm`; [docs/templates.md](templates.md)), and each template's
  ledger, `STEM.seen.tsv` (written when a template from any directory files
  one of its captures; from 2.20.0 with or without `--llm`), with the header
  `capture`, `how`, `template`, `read`, `unread`, `skipped`, `unjudged`,
  `input_sha256`: one line per capture the template filed. The template
  files' own format belongs to `extract/llm/` and is not part of this one.
- **`context/manifest.tsv`** (controlled directories): `path`, `size`,
  `mtime`, `sha1`, one line per file of the controlled directory at the
  latest capture, sorted by path (`sha1` is `(skipped)` for a file over 1 MiB,
  or with no `sha1sum`).
- **`CONTROLLED`** (controlled directories): one line, the directory's path.
- **`manifest-profile.tsv`**: a store's own run-manifest profile, if one is
  put there (`check-manifest`). provost reads it; it never writes it.
- **`llm-offline`**: if a file of this name is at the top of the store (its
  content is not read), `--llm` is in offline mode for that store whatever
  the environment says: no template is written or extended, nothing is sent.
  Put there by hand and committed with the next capture; provost reads it
  and never writes it. Since provost 2.17.0; an older provost ignores it.

## Runtime files

These are in a store's directory but are not its content: never committed
(from format 2 the `.gitignore` excludes them), not checked, not exported.

| File | What |
|---|---|
| `.lock/` | The writer's lock, held while a store is written; `owner` names the holder (`host<TAB>pid<TAB>uid<TAB>epoch`). |
| `.async-failures.log`, `.async-failures.seen` | Background captures that failed, and how many of them `log --failed` has shown. |
| `instances.tsv` | The global store's list of controlled directories (`provost instances`). |
| `datasets/.recon.*`, `.stage.*`, `.rm.*`, `.rmprov.*`, `captures/*/.meta.tmp`, `context/*.tmp` | Work files during a write. |

A format-1 store committed some of these (`.lock/pid` in particular); its
migration untracks them, and until then `verify` and `store check` leave
them out.

## Format history

Each format, the releases that wrote it, and what changed. The fixtures
`tests/store-fixtures/format1.tar.gz` to `format3.tar.gz` were written by the
release named last for that format (2.0.1, 2.1.0 and 2.3.0); `format4.tar.gz`
by provost 2.16.0. `tests/store-fixtures/make.sh` makes them, and says how.

### Format 1

**Written by:** provost 2.0.0 and 2.0.1. No
`.store_format` file: a store without one is format 1.

- No `.gitignore`: the runtime files (`.lock/`, `instances.tsv`, the failure
  log) could be committed, and were.
- No `.next_capture_id`: the next capture number was worked out from the
  `captures/` directories, the `capture-c*` tags and the commit subjects.
- A dataset whose parse the extract engine counted records for carries a
  **`total_entries`** column: that count, repeated on every row. It is not a
  variable.
- No capture column: a dataset's columns are `#` and then the data. A row's
  capture is found only through `provenance.tsv`.
- A dataset was named after its parser when `run` was given no name (2.0.1
  filed `disks` output as `aligned-columns`).

### Format 2

**Written by:** provost 2.1.0. **Migration from 1:** writes the
`.gitignore` and untracks the runtime files; seeds `.next_capture_id` (one
past the highest capture number in the directories, tags and commit
subjects); drops `total_entries` from every dataset where it holds only
integers (a column of that name holding anything else is data, and stays);
writes `.store_format`.

- `.gitignore`, `.next_capture_id` and `.store_format` as above.
- Still no capture column.

### Format 3

**Written by:** provost 2.2.0 and 2.3.0. **Migration from 2:** inserts the capture
column after `#` in every dataset whose header starts with `#`, filled from
`provenance.tsv`, named `capture` unless the data has a column of that name
(then `_capture`). A dataset that already has it is left as it is.

- Every dataset row carries its capture id in column 2.
- **Known fault (PV-015):** a reconcile could match a data column named
  `capture` to provost's capture column by name, so in such a dataset some
  rows hold a data value in column 2 and their capture id in another
  `*capture` column. In a format-3 store, take a row's capture from
  `provenance.tsv`, not from column 2. `store check` reports these rows and
  does not fail them.

### Format 4

**Written by:** provost 2.4.0 and every later release (current).
**Migration from 3:** puts PV-015's rows right from `provenance.tsv`: in a
dataset where every row whose column 2 disagrees with provenance has its
capture id in one and the same other `*capture` column, the two values change
places in those rows (and the two columns' names, when column 2 has the
shorter). A dataset it cannot put right that way is left as it is.

- Column 2 holds the row's capture id in every row.
- Within format 4, later releases added `meta.tsv` keys (the input hashes in
  2.4.0, the scrub in 2.6.0, ...) and, in 2.15.0, inputs kept by hash beside
  the store with the six `truncated`/`raw_*` keys. None of these changes what
  a format-4 reader already relied on, so none bumped the number.
- 2.19.0 (PV-029) added `disposals.tsv` ([The disposal
  log](#the-disposal-log)) and the `prune:` and `archive:` commit subjects,
  within format 4: an older reader can ignore the file, and nothing a reader
  relied on changed, so nothing is migrated.
- 2.18.0 (PV-027) added, all within format 4: the `Operator:` commit
  trailer; signed commits and signed annotated `capture-*` tags when the
  writer sets `PROVOST_SIGN`; and SHA-256 stores. None needs a migration (an
  existing store is never signed after the fact, nor converted), and the
  layout is unchanged, so the number stays 4. What a reader must do is in
  [Reading a store from another program](#reading-a-store-from-another-program).

### Fixed on write, not by a format

One repair is made on write without a format number: a dataset filed before
2.4.0 can hold a data column named `#` beside column 1 (PV-011). The next
capture appended to it renames that column `#_2` (the first `#_K` free),
in place, so new rows line up with old. A reader of an older store must
expect a second `#` column in such a dataset.

## Reading a store from another program

- Read `.store_format` (none means 1) and refuse a format you do not know.
- Find the capture column by place (column 2 when the header starts with `#`
  and column 2 is named `capture` with any number of leading `_`), never by
  name. Below format 3 there is none: use `provenance.tsv`. In format 3,
  prefer `provenance.tsv` too (PV-015).
- Tell context columns from data by `meta.tsv`'s `context_columns`, not by
  position or name.
- Read `meta.tsv` as key/value pairs, ignore keys you do not know, and turn
  `\t` and `\n` back into a tab and a newline. A comma-separated value
  (`dataset`, `strategy`) has one entry per dataset.
- A `#%` prologue word is `key=value`; a value may be double-quoted to hold
  spaces (`key="gcc 13.2"`), with `\"` and `\\` inside. The last value of a
  repeated key wins.
- `output.txt` of a capture with `truncated` set is only the parsed head of
  its input: the whole input is the kept copy (`raw_sha256`).
- Treat `unsorted.tsv`'s `raw` as base64.
- Peel a `capture-*` tag to its commit (`capture-cNNNN^{commit}`): in a
  signed store it is an annotated tag. Read a commit's message through
  the tag, not the tag's own message, for the hash trailers.
- Use a git that knows the store's object format (`extensions.objectformat`
  in `.git/config`; none means sha1), and copy a store with `git clone`, which
  keeps it, rather than `git init` and `git fetch`, which cannot fetch a
  SHA-256 store into a SHA-1 repository.
- A capture id missing from `captures/` was removed by `rm`, `prune` or
  `archive --purge`; `disposals.tsv`, when there is one, says which were
  disposed of, when, by whom and why.
- Run `provost store check DIR` in your own CI against stores you write to
  or read from: it fails on anything this document says cannot happen.

## Changing the format

A change to what a reader of the store can rely on bumps `_STORE_FORMAT` in
`provost`, and the same pull request:

1. adds the migration from the previous format to `_migrate_store`, as a
   `if (( $(_store_format) < N )); then ... fi` step, idempotent (a store
   whose `.store_format` went missing must not be migrated twice into
   damage);
2. adds a `### Format N` section above, with the releases and what the
   migration does, and moves "current" to it;
3. adds `tests/store-fixtures/formatN.tar.gz`, made with
   `tests/store-fixtures/make.sh` and the new provost, and — before the bump
   — makes sure the fixture of the previous format was written by its last
   release;
4. teaches `provost store check` the new format's rules.

`tests/smoke.sh` fails a `_STORE_FORMAT` without a migration step, a spec
section and a fixture for every format up to it. Adding a `meta.tsv` key, or
a file that an older reader can ignore, does not need a new format; add it
to the tables above with the release that first writes it.

## Archives

Not a store, but written from one and read by other programs, so specified
here: what `provost archive` writes (2.19.0 on, PV-029). An archive is a new
directory:

| File | Holds |
|---|---|
| `store.bundle` | `git bundle create --all` of the store as it was: its whole history, every branch and tag. A git bundle names its own prerequisites (none) and is checked with `git bundle verify`. Clone it with a git that knows the store's object format. |
| `ARCHIVE.tsv` | `KEY<TAB>VALUE` lines: `archive_format` (`1`), `provost_version`, `store_format` (the store's `.store_format`, 1 when it had none), `object_format` (`sha1` or `sha256`), `created` (UTC), `operator`, `store` (its path then), `branch`, `head` (the commit the bundle's branch was at), `selection` (in words), `captures` (how many), `signed` (`no`, `ssh` or `gpg`). Ignore keys you do not know. |
| `captures.tsv` | The captures the archive was made for. Header `capture`, `ts`, `dataset`, `commit` (the commit their `capture-*` tag names, peeled), `output_sha256`, `input_sha256`, `raw_sha256` (empty when not recorded). |
| `artifacts/SHA256` | The kept input of each truncated capture in `captures.tsv` ([Inputs kept beside the store](#inputs-kept-beside-the-store)), named by its sha256. Only when there is one. |
| `SHA256SUMS` | `HEX  PATH` (two spaces, `sha256sum`'s form), one line per file above, sorted by path. Every file in the archive but `SHA256SUMS` and its signature is listed. |
| `SHA256SUMS.sig` | When the writer set `PROVOST_SIGN=ssh`: an SSH signature of `SHA256SUMS` (`ssh-keygen -Y sign`, namespace `provost-archive`). An allowed-signers line restricted to `namespaces="git"` does not admit it. |
| `SHA256SUMS.asc` | When the writer set `PROVOST_SIGN=gpg`: an ASCII-armoured detached OpenPGP signature of `SHA256SUMS`. |

The bundle holds the whole history, not only the selected captures: git
cannot take a capture out of a history without rewriting it, and the whole
history is what `verify` needs to judge the selected ones. `captures.tsv`
says which captures the archive is *for*. `provost archive verify DIR`
checks every file against `SHA256SUMS` (and that none is unlisted), the
signature, the bundle, each capture in `captures.tsv` against its tag in a
clone of the bundle, and runs `provost verify --capture` on that clone (kept
inputs from `artifacts/`). `provost archive import DIR DEST` does all of that
and leaves the clone at `DEST`, its kept inputs at `DEST.artifacts`, with
every write bit removed.
