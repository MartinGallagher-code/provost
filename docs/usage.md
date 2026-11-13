# Usage

Everything `provost` does, from `provost help advanced` (`provost help` is the short version). The man page
(`man/provost.1` in the repository, installed with the wheel) carries the same
content in roff form.

## Capturing

```console
$ provost run [--] <cmd> [args...]     # run a command, file its output as dataset <cmd>
$ cmd | provost                        # inject stdin (dataset named after the parser)
$ provost FILE                         # inject a file instead of stdin
$ provost batch FILE... [--from LIST]  # inject many files: a capture each, one commit
$ provost listen <cmd>                 # file <cmd>'s output every time it runs (unlisten to stop)
```

`provost run df -h` files into a dataset called `df` — wrappers such as `sudo`,
`env`, `nice` and `timeout` are looked through, so `sudo df -h` is `df` too.
Injected input has no command, so it is named after the parser that recognised
it (`csv`, `json-array`, `aligned-columns`, …); `--name` sets the name for either.

### Interrupted runs

Stopping a command is often how a run ends: `ping`, `tail -f`, `iostat 1` and
`tcpdump` run until Ctrl-C, and a batch job runs until its walltime, when Slurm
sends it SIGTERM (and SIGKILL `KillWait` seconds, 30 by default, later). provost
keeps what such a run printed:

- **The first SIGINT, SIGTERM or SIGHUP** while `provost run` runs its command,
  or while piped input is read, does not stop the reading. The command (a
  Ctrl-C at the terminal reaches it too, as it always did) has
  `PROVOST_INTERRUPT_GRACE` seconds (default 2) to finish, time for `ping` to
  print its summary; one still running then is sent SIGTERM, and SIGKILL a
  second later.
- **What it printed is filed** as any capture is, into the same dataset, so
  `show`, `diff` and `qd` see it. Its `meta.tsv` says `interrupted<TAB>SIGINT` (or
  `SIGTERM`, `SIGHUP`) beside the command's `rc` (143 or 137 when provost had
  to stop it),
  and `provost log` shows `[interrupted: SIGINT]` after the command.
- **provost exits 130** (143 for SIGTERM, 129 for SIGHUP), so a script still
  sees the interruption.
- **A second signal** (Ctrl-C twice), or one that arrives while provost is
  filing a capture whose command ran to its end, stops provost at once and
  files nothing. The store is left as it was: no commit, no tag, no lock, and
  `provost verify` passes. That is the way out when filing itself hangs.
- **Nothing printed** before the signal: nothing is captured.
- **In the background** (`--async`, the default at a terminal), the capture is
  queued once the reading stops, and a signal after that does not reach it.
  `batch` reads files rather than a live command, and is unchanged.

An interrupted capture you did not want goes with `provost rm --capture ID`.

```console
$ provost run --show ping -c 100 example.org
64 bytes from 93.184.215.14: icmp_seq=1 ttl=56 time=11.2 ms
64 bytes from 93.184.215.14: icmp_seq=2 ttl=56 time=11.0 ms
^C
--- example.org ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 11.0/11.1/11.2/0.1 ms
interrupted (SIGINT): capturing what the command printed (it exited 0), marked interrupted.
queued (async, pid 41822) — capturing in the background; see 'provost log' shortly.
$ echo $?
130
```

### The command's name is used in detection

The format is still detected from the output itself, but when provost knows
which command printed it, the name decides between the parsers that
recognised the output (`provost-extract --command NAME`):

- `provost run CMD …` and `provost listen` (which is a `run`) pass the command
  they ran — looked through `sudo`, `env`, `nice` and the rest, as the dataset
  name is. A **tool-specific** parser written for that command ranks 15 points
  higher. A parser is written for the command when its name is the command or
  starts with `COMMAND-` (`docker-ps` for `docker`, `git-log-graph` for `git`),
  or its `## Commands:` header lists it (`sysstat`: `sar mpstat pidstat`;
  `*` there marks one that reads a format many tools print, such as
  `csvlook`'s Markdown tables, which no name ranks lower); a
  `hints.tsv` row whose tool is the command is preferred the same way. A
  tool-specific parser written for **another** command ranks 20 points lower,
  so it wins only by a clear margin. Generic parsers rank as they would
  anyway: they read a format, whatever printed it.
- `--name NAME` and a batch file's `NAME` are passed as a **hint**
  (`--command-hint`): a name may be a command's or only a label (`cpu-load`),
  so a parser written for it ranks higher but nothing ranks lower. With `run`,
  the hint is used only when the command is a relay
  (`provost run --name netstat cat saved.txt`).
- A command that only relays another's output or prints given text — `cat`,
  `echo`, `printf`, `ssh`, a shell, `grep`, `sort`, … — names no format and is ignored. Piped input with no
  `--name` is detected by its content alone, as before.

`meta.tsv` records `command_name` (with a note when it was a hint or a relay),
`command_changed` — whether the name changed which parser ranked first
(`yes: aligned-columns ranked first; without the name, pkg-config would have`)
— and `command_fit` when the winner is a parser written for another command
that won by the margin. `provost-extract explain --command NAME FILE` shows the
ranking with the name.

Capture flags (for `run` and inject):

| flag | effect |
|---|---|
| `--name NAME` | file into dataset `NAME` (letters, digits, `.`, `_`, `-`) |
| `--sync` / `--wait` | capture in the foreground and print the resulting dataset and `#N` range |
| `--async` | capture in a detached background process |
| `-q` / `--silent` | no output on success |
| `--min-confidence N` | commit threshold, 0–100 (default 50) |
| `--plugin-dir DIR` | add an extra strategy directory to detection |
| `--multi` | file **every** dataset the input holds instead of one winner |
| `--no-auto-multi` | hold a parse the quality gate rejects without first trying to segment it (`--auto-multi`, the default, tries) |
| `--context-columns` | make each `key=value` word of a `#%` prologue a column on every row (see [Metadata prologue](#metadata-prologue)) |
| `--units base` | after each column whose unit can be read, add a `NAME[UNIT]` column of the same values in base units (see [Units](#units)); `--units off`, the default, adds none |
| `--no-redact` | store the input as it comes; by default known secrets are scrubbed first (see [Secrets and redaction](#secrets-and-redaction)) |
| `--refuse-oversize` | refuse an input over `PROVOST_MAX_INPUT`, as provost did before 2.15.0; by default it is kept whole outside git and its head parsed (see [Oversize inputs](#oversize-inputs)) |

At an interactive terminal the capture runs in the background and the prompt
returns at once; in a script or pipeline (stderr not a terminal) it runs in the
foreground, so `cmd | provost; provost show …` sees the result. A background
capture that fails is recorded in the store: the next provost command warns
about it, and `provost log --failed` lists it with the kept input and log.

## Browsing the store

```console
$ provost ls                     # list datasets
$ provost show NAME              # present a dataset ('#', 'capture', 'n' lead each row)
$ provost show NAME --capture ID # only the rows capture ID filed
$ provost show NAME --at ID      # the dataset as it stood just after capture ID
$ provost show NAME --tsv        # tab-separated, as stored: what a program reads
$ provost show NAME --format F   # table, tsv, csv, json, ndjson or md (Getting data out, below)
$ provost search PATTERN [NAME]  # git grep over the rows (--output, --files, --at ID)
$ provost log [--failed]         # list captures (the git history) / failed background ones
$ provost source <#N | ID>       # the original input behind row #N, or a capture
$ provost diff [NAME] [A [B]]    # rows and run files that changed between two captures
$ provost stats NAME [args]      # statistics on a dataset (--all for everything)
$ provost triage                 # low-confidence / unmatched bucket
$ provost restore <id|latest>    # bring a capture's commit back up
$ provost prev / provost next    # step the store back / forward one capture
$ provost rm [-f] [--no-purge] NAME...   # captures are purged only when no dataset still uses them
$ provost rm [-f] --capture ID[,ID...]   # captures, and the rows they filed in every dataset
$ provost prune --policy FILE [--yes]    # dispose of what a retention policy no longer keeps (dry run without --yes)
$ provost archive --to DIR --before DATE # a verifiable archive of older captures (--purge --yes: then dispose of them)
```

Every row carries `#` (its number in the store, `provost source N`),
`capture` (the capture it came from, `provost source c0007`) and, for
records, `n` (its place within that capture). An ID is `c0007`, `7` or
`capture-c0007`, or `latest` (the newest capture) or `latest~N` (the Nth
before it), so a script never has to read `provost log` for the id of the
capture it just made. `latest` counts the captures the store has: after
`provost rm --capture`, `latest~1` is the one before that is still there.
`provost restore latest` is the one place it means something else: it returns
the store to the present, which can be a commit past the newest capture (an
`rm` or an `annotate`); `restore latest~0` brings up the newest capture itself.
A word that is a capture ID is read as one where a command takes either an ID
or a name, as `7` already was: `provost diff latest` is the newest capture, and
`provost files -- latest` the path called `latest`.

## Getting data out

A dataset is a table, and it leaves provost in one of four ways. None of them
adds a query language, a metrics exporter or a viewer to provost (one tool
that captures, [docs/0001](0001-rename-and-simplification.md)): each is a
format other tools read, or a tool that reads the store as it is.

**`provost show --format`** writes a dataset as `table` (the default, for
people), `tsv` (as stored; `--tsv` is the same), `csv`, `json`, `ndjson` or
`md`. The names and shapes are those of quarterdeck's `qd show --format`, so a
script moves between the two unchanged (`text` and `markdown` are taken too,
for qd's and `provost stats`'s names):

- `csv` is RFC 4180: a cell holding a comma, a double quote or a line break is
  quoted, with its quotes doubled. Lines end in LF.
- `json` is an array of objects, one a row; `ndjson` is one object a line.
  The keys are the columns, in order. A blank cell is `null`, never `""` or
  0, as `provost_data` reads it. Every other value is a string, as stored
  (`"82%"`, `"50G"`, `"3"`): typed numbers come with column types (PV-040),
  and a reader that takes strings will keep working then.
- `md` is a Markdown table. A `|` in a cell is written `\|`, and a column whose
  every filled cell is a number, bare or with a unit (`12`, `3.5 ms`, `37%`),
  is right-aligned, as qd aligns it.
- `--capture` and `--at` work with every format. With no rows, `csv`, `tsv`
  and `md` print the header alone, `json` prints `[]` and `ndjson` nothing.
- Text that is not ASCII is written as the UTF-8 it is, in every format.
- Beside `qd show ds:NAME`, the columns differ (qd leaves out `#` and calls
  the capture column `capture` whatever provost named it), qd's JSON has its
  keys sorted, numbers as numbers and non-ASCII text as `\u` escapes, qd's
  NDJSON leaves out a blank cell's key where provost writes `null`, and qd's
  TSV quotes a cell that holds a `"`, where provost's is the store's own.

```bash
provost show df --capture latest --format csv > df.csv      # the last capture's rows, for a spreadsheet
provost show df --format json | jq -r '.[] | select(.Size == "50G") | .Mounted_on'
provost show df --format ndjson | jq -c '{capture, Mounted_on, Avail}'
provost show df --format md                                 # a table to paste into a ticket
provost diff df latest~1 latest                             # what the last capture changed
python3 -c 'import provost_data; print(provost_data.load("df", capture="latest")[0]["Mounted_on"])'
```

**`provost_data`**, the Python package (the README's "From Python and
Jupyter"), gives the same rows as a list of dicts (`load`) or a pandas
DataFrame (`load_df`); `capture="latest"` works there too.

**The store's own files.** `datasets/NAME.tsv` is the dataset, in a format
[docs/store-format.md](store-format.md) specifies and keeps compatible:
tab-separated, a header line, no quoting, and no tab or newline in a cell. The
store is `~/.provost` unless `PROVOST_HOME`, `PROVOST_WORKSPACE` or a
controlled directory says otherwise (`provost doctor` names it). DuckDB and
Miller read it in place:

```bash
duckdb -c "SELECT Mounted_on, Avail FROM read_csv('~/.provost/datasets/df.tsv', delim='\t', quote='', escape='') ORDER BY Mounted_on"
mlr --itsv --opprint sort -f Mounted_on ~/.provost/datasets/df.tsv
provost show df --format csv | mlr --icsv --ojson filter '$Size == "50G"'
```

DuckDB needs `quote=''` and `escape=''` because the store does not quote and a
cell may hold a `"`. Miller's TSV reader turns a `\t` or `\n` in a cell into a
tab or a newline, where provost keeps them as the two characters (the
`unsorted` dataset's decoded inputs have them); piping `--format csv` into
`mlr --icsv` reads every cell as stored.

**quarterdeck** (`qd`, a fleet tool that reads provost's store) filters,
exports and views any dataset as `ds:NAME`:

```bash
qd show ds:df --where 'Use%>80' --cols Mounted_on,Avail --format csv
qd export ds:df --format openmetrics --labels capture,Mounted_on   # Prometheus gauges; --format hec: Splunk HEC events
qd view ds:df                                               # interactive: full screen in a terminal
qd web                                                      # interactive: every dataset, in a browser
```

## Instances and portability

```console
$ provost control [<dir>]        # make <dir> its own capture instance; each run keeps its files
$ provost files [ID] [PATH]      # those files as a capture kept them (--to DIR writes them out)
$ provost uncontrol [<dir>]      # release a controlled directory
$ provost instances              # list controlled directories
$ provost export [<file>]        # bundle the store into a portable file
$ provost export --redact POLICY [<file>]  # ...a copy with host names and addresses pseudonymised
$ provost import <file> [<dest>] # reconstitute a bundle elsewhere
$ provost doctor                 # check engine + store
$ provost verify                 # check the store's integrity (exit 1 on findings)
```

Captures go to a **global git store** — `$PROVOST_HOME`, or `~/.provost` if
unset — so you can capture from any directory. `provost control <dir>` makes
`<dir>` its own instance (`<dir>/.provost`): captures run inside it (or a
subdirectory) route there, and each commit snapshots the directory's contents
as context. Resolution order: `PROVOST_WORKSPACE` override, else the nearest
controlled directory walking up from the current directory, else the global
store.

While `provost restore <id>` has an old capture checked out, new captures and
`rm` are refused until `provost restore latest`.

A shared store (a group-writable `PROVOST_HOME`) is supported: a lock serialises
writers across users, and provost refuses a store whose `.git/config` others can
write if it sets anything beyond git's own keys — filter drivers, pagers and
includes can make git run programs as whoever captures next.

## Verifying a store

Every capture records three things about its input in `meta.tsv`:

| Key | What it is |
|---|---|
| `input_sha256` | sha256 of the input exactly as provost received it, before CRs were stripped and secrets scrubbed |
| `input_bytes` | its size in bytes |
| `output_sha256` | sha256 of `output.txt`, the input as stored (CRs stripped, secrets scrubbed) |
| `redacted` | what the secret scrub replaced: `kind=n,...`, `none`, or `off` (see [Secrets and redaction](#secrets-and-redaction)) |

The capture's commit carries the same hashes as trailers
(`Input-SHA256: c0007 …`, `Output-SHA256: c0007 …`; a `batch` commit has one
pair per capture). The hash comes from `sha256sum`, `shasum -a 256` or
`openssl`, whichever is installed; with none, the capture is filed unhashed.
`input_sha256` is for comparing with a hash taken elsewhere (a test harness
that hashed its own log); `output_sha256` is what `verify` re-checks.

`provost verify [--capture ID]` checks:

1. `git fsck --full` on the store.
2. No tracked file was changed outside provost and left uncommitted.
3. Every `capture-*` tag names a commit on the store's history (and every
   `files-*` tag a commit).
4. Each capture's `output.txt` on the main branch is the one its tag filed,
   and it re-hashes to the `output_sha256` in its `meta.tsv` and in its
   commit's trailer.
5. Capture ids run from `c0001` to the highest with no gap the history cannot
   explain. An id `rm` removed was committed once, so it is counted, not
   failed; an id that never appears in the history is a failure.

It exits 0 with no findings and 1 with a list of them. Captures filed before
hashes were recorded (provost 2.3.0 and earlier) are counted as unhashed, not
failed. `--capture` narrows steps 3–4 to those captures.

**What it proves, and what it does not.** `verify` shows that the store is
consistent with itself: nothing was edited, lost or dropped without the
history being rewritten to match. It does not show that the history was
never rewritten. Anyone who can write the store can rebuild every commit,
hash and tag, and `verify` would pass. To make that detectable, record the
head commit `verify` prints (`main at …`), with the capture count, somewhere
the store's writers cannot change: a test report, a ticket. A later `verify`
that prints a head which does not contain that commit means the history was
rewritten. Signed commits are the stronger anchor (PV-027).

## Checking a store against the format

The store's layout is a versioned format, specified in
[The store format](store-format.md) and recorded in the store's
`.store_format` (a store without one is format 1). **Every provost reads every
older format.** A command that writes (a capture, `rm`, `annotate`,
`restore`, `control`) first migrates an older store to the current format, in
a commit of its own; a command that only reads (`ls`, `show`, `source`, `log`,
`search`, `files`, `diff`, `stats`, `triage`, `verify`, `doctor`, `export`,
`store check`, `archive` without `--purge`, `prune` without `--yes`) never
changes a store on disk, and works on a store it cannot
write: an evidence copy, read-only media, a store whose history was signed.

```
$ provost store check              # the active store
$ provost store check /evidence/run-17/.provost
 ok store format 3 (read as it is; the next write migrates it to 4)
   3 dataset(s), 11 row(s), 6 capture(s)
 ok store check: the store is a valid format-3 store
```

`store check` validates the layout against the format the store records: the
format number, the `.gitignore` and the counters, `provenance.tsv` and every
dataset (headers, field counts, each row in provenance under its own dataset,
from format 3 the capture in column 2), each capture's files and `meta.tsv`
(its keys, its tag, a truncated capture's kept input), `files-*` tags and the
template ledgers. It exits 0 with no findings and 1 with them, and takes no
lock and commits nothing. `verify` is the other half: it checks the history
(fsck, hashes, tags), where `store check` checks the files' shape. A program
that writes to or reads a store (quarterdeck) can run both in its own CI.

## Retention: prune and archive

provost keeps everything until told otherwise, and has **no retention of its
own**: nothing goes unless a policy you wrote says so (PV-029, 2.19.0).

```
$ cat retention.policy
# a year for the disk inventories, but always the newest ten;
# the apollo project's captures for 90 days
dataset=disks          keep-days=365 keep-last=10
tag=project=apollo     keep-days=90
$ provost prune --policy retention.policy            # a dry run: what would go, what is kept
$ provost prune --policy retention.policy --yes      # dispose of them
```

A rule selects captures by dataset (`dataset=NAME`; `dataset=*` is a rule for
each dataset) or by a `#%` prologue or annotation key (`tag=KEY=VALUE`), and
keeps those younger than `keep-days` days or among the newest `keep-last`. A
capture goes only when every rule that selects it lets it go, and a capture
that also filed a dataset no rule names is kept. `--as-of DATE` judges ages
as of a date rather than now.

`--yes` disposes of them as `rm --capture` does: the captures and the rows
they filed, in one commit, all or nothing; git's history still holds them.
Each one is recorded, in that same commit, in the store's **disposal log**,
`disposals.tsv`: the capture, when, who (the operator), how, and the rule
that let it go, with the policy file's sha256. Nothing removes a record from
it, and capture ids are never used again. See
[The disposal log](store-format.md#the-disposal-log).

To keep evidence out of the working store but still verifiable, archive it
first:

```
$ provost archive --to /records/2025 --before 2026-01-01            # write and verify an archive
$ provost archive --to /records/2025 --before 2026-01-01 --purge --yes   # ...then dispose of those captures
$ provost archive verify /records/2025 --allowed-signers signers --require-signed
$ provost archive import /records/2025 ~/audit-2025                # open it read-only
```

An archive is a git bundle of the store's whole history, a manifest
(`ARCHIVE.tsv`, `captures.tsv`: the store format, each capture's commit and
hashes), the archived captures' kept inputs, and `SHA256SUMS`, signed with
`PROVOST_SIGNING_KEY` when `PROVOST_SIGN` is set ([Archives](store-format.md#archives)).
It is verified before `archive` finishes, so `--purge` never disposes of
anything an archive that does not verify was meant to hold.

## Oversize inputs

`PROVOST_MAX_INPUT` (10 MiB by default) is how much of an input is parsed. A
larger input is not refused (since 2.15.0, PV-021): the whole of it, scrubbed
of secrets as a stored input is, is kept **outside the store's git history**,
in the artifact directory, as a read-only file named by its sha256. Its first
`PROVOST_MAX_INPUT` bytes, cut back to the last whole line, are parsed and
stored as the capture's `output.txt`, and `meta.tsv` says so:

| key | what it holds |
|---|---|
| `truncated` | `1` |
| `parsed_bytes` | how much of the input was parsed |
| `raw_artifact` | where the whole input is kept |
| `raw_sha256`, `raw_bytes` | the kept file's sha256 (its name) and size |
| `raw_redacted` | what the secret scrub replaced in it |

`input_sha256` and `input_bytes` are the whole input's, as received.
`provost source` re-hashes the kept copy and adds `raw_check: ok`, `MISSING`
or `ALTERED` (exit 1 when it is not ok); `provost verify` counts a missing or
altered copy as a finding. A copy moved with the artifact directory is found
there by its hash.

The artifact directory is `PROVOST_ARTIFACT_DIR`, or `<store>.artifacts`
beside the store: `~/.provost.artifacts`, or `DIR/.provost.artifacts` for a
controlled directory (left out of its files and manifest). It is never the
store or inside it, so no clone, `export` or handover of the store carries
it. `provost rm`, `prune` and `archive --purge` leave it alone: one kept
file serves every capture of the same bytes. `provost archive` copies the
kept inputs of the captures it archives into the archive. Inputs within the cap are read and filed exactly as before;
`--refuse-oversize` (`PROVOST_OVERSIZE=refuse`) refuses an input over the cap
with "input too large", as every provost before 2.15.0 did.

## Secrets and redaction

Two different needs (PV-033): secrets never belong in a store, and host
names and addresses are data that a dataset is keyed on, until it has to
leave.

### Secrets are scrubbed at capture

Before an input is stored, every known secret pattern in it is replaced by
`[REDACTED:kind]`:

| kind | what |
|---|---|
| `private-key` | a PEM or PGP private key block, BEGIN line to END line (to the end of the input when there is no END) |
| `authorization` | the value of an `Authorization:` or `Proxy-Authorization:` header |
| `bearer` | a token of 16 characters or more after `Bearer` |
| `url-password` | the password in `scheme://user:password@host` |
| `aws-access-key`, `github-token`, `slack-token`, `vault-token`, `jwt` | tokens in their own formats (`AKIA…`, `ghp_…`, `xoxb-…`, `hvs.…`, `eyJ….eyJ….…`) |
| `password`, `secret`, `token`, `api-key` | the value after a key whose name ends that way: `DB_PASSWORD=…`, `"token": "…"`, `password: …`, `--api-key …` |

The command line `run` records (`mysql --password=…`) and `--manifest` lines
are scrubbed as well. A value that says it is hidden or empty (`yes`, `none`,
`***`, `<hidden>`, `$VAR`) is left alone, and so is a plain word after a
token, secret or key name (`unexpected token: expected`) or after a `--flag`
(help text). A table that merely has a column called `password` is not
touched: only the forms above are.

`meta.tsv` records what was done as `redacted`: `password=1,private-key=1`,
`none`, or `off`. `--no-redact` (`PROVOST_REDACT=0`) stores the input as it
comes, and records `off`. An input with nothing to scrub is stored byte for
byte as it came.

**The hashes of a scrubbed capture.** `input_sha256` stays the hash of the
input as it was *received*, secrets and all, so it still matches a hash a test
harness took of its own log. `output_sha256` is of `output.txt` as stored,
scrubbed, and is what `verify` re-checks. The two differ exactly when
something was scrubbed (or a CR stripped), and `redacted` says which. One
consequence: someone holding the store and a guess at a weak password can
check the guess against `input_sha256`. Keep a store inside the boundary it
was made in, and take data out with `export --redact`.

How it was checked: the scrub changes 11 of the corpus's 3,733 inputs, each a
real secret (`tests/corpus/scrubbed.tsv`, checked by the smoke suite); filed
through the generic parsers, those 11 change 13 golden rows, and in each row
only the secret's own cell.

### Host names and addresses are pseudonymised on export

```console
$ provost export --redact policy.conf fleet.bundle
```

writes a copy of the store, history and all, in which every name the policy
picks out is replaced by a pseudonym made with a keyed hash: `host-` and 12
hex digits of `sha256(key, kind, name)`, likewise `ip4-…` and `ip6-…`. The
same pseudonym stands for the name in every dataset, output, `meta.tsv`,
commit message and dataset file name, and the same key gives the same
pseudonyms, so datasets exported at different times still join. Secrets are
scrubbed again on the way out (captures filed with `--no-redact`, or before
provost 2.13.0).

A policy is `KEY = VALUE` lines; `#` lines are comments:

```ini
# take a fleet's results to a vendor
key    = ~/.config/provost/redact.key   # the default; made at random if missing
domain = cluster.example.com            # every name in it, and the domain itself
host   = node[0-9]+                     # names the awk regex matches, whole, lower-cased
column = host                           # every value of the datasets' "host" column
hosts  = inventory.txt                  # a file of names or addresses, one a line
ipv4   = yes                            # the default (never 0.0.0.0, 127.x, netmasks)
ipv6   = yes                            # the default (never :: or ::1)
```

`domain`, `host`, `column` and `hosts` can be repeated; a relative path is
relative to the policy file. A name is replaced wherever it stands as a word,
or as a part of one between `.` `_` `:` `-`: `node7` in `node7-ib0`,
`node7.cluster.example.com` and `node7:22`. A host name has a letter in it,
and a capture id (`c0007`) is never one; four dotted numbers inside a longer
dotted run (an SNMP OID) are not an address. IPv6 addresses are compared in
full form, so `2001:db8::5` and `2001:0db8:0:0:0:0:0:5` get one pseudonym.

The key stays behind: it may not live in the store, and nothing derived from
it but the pseudonyms and its id leaves. In the copy:

- each `meta.tsv` loses `input_sha256` and `input_bytes` (with them, a
  guessed name could be checked against the hash) and gains
  `pseudonymised  key <id>`;
- `output_sha256` and the commits' `Output-SHA256` trailers are those of the
  exported `output.txt`, and the `Input-SHA256` trailers go, so
  `provost verify` passes on the import;
- a controlled directory's own files (the `files-*` tags) are left out.

## Environment variables

| variable | meaning | default |
|---|---|---|
| `PROVOST_HOME` | global store dir | `~/.provost` |
| `PROVOST_WORKSPACE` | explicit store override (wins over `PROVOST_HOME`) | — |
| `PROVOST_MIN_CONFIDENCE` | commit threshold 0–100 | `50` |
| `PROVOST_PLUGIN_DIR` | extra strategy dir for detection | — |
| `PROVOST_ASYNC` | `1` always background, `0` always foreground, unset = background only at a terminal | unset |
| `PROVOST_MULTI` | file every dataset an input holds (same as `--multi`) | `0` |
| `PROVOST_CONTEXT_COLUMNS` | `1` = each `key=value` word of a `#%` prologue becomes a column on the capture's rows (same as `--context-columns`) | `0` |
| `PROVOST_UNITS` | `base` = add a `NAME[UNIT]` column in base units after each column with a readable unit (same as `--units base`) | `off` |
| `PROVOST_MANIFEST_PROFILE` | run-manifest profile, NAME or `.tsv` file; when set every capture is checked (same as `--manifest-profile`) | unset |
| `PROVOST_MANIFEST_STRICT` | `1` = refuse a capture lacking a required manifest key (same as `--strict-manifest`) | `0` |
| `PROVOST_ENV` | `1` = record where each capture was taken (same as `--env`); `modules` = and the kernel modules (`--env=modules`) | `0` |
| `PROVOST_ENV_VARS` | the variables `--env` records: names or glob patterns, space- or comma-separated; set but empty = none | `OMP_* MPI_* OMPI_MCA_* I_MPI_* MPICH_* UCX_* CUDA_* NCCL_*` |
| `PROVOST_AUTO_MULTI` | `1` = segment a parse the quality gate would hold, when the parts are clearly better; `0` = hold it (same as `--no-auto-multi`) | `1` |
| `PROVOST_TEMPLATES` | `1` = apply a parsing template that fits (see [Parsing templates](#parsing-templates)); `0` = don't (same as `--no-templates`) | `1` |
| `PROVOST_TEMPLATE_DIRS` | colon-separated directories of your own templates (`PROVOST_LLM_TEMPLATE_DIRS`, the older name, is read too) | — |
| `PROVOST_TEMPLATE_TIMEOUT` | seconds one template may take on one capture; past it, it is declined | `10` |
| `PROVOST_MAX_INPUT` | max input bytes parsed, for inject and `run`; a larger input is kept by hash (see [Oversize inputs](#oversize-inputs)) | `10485760` |
| `PROVOST_OVERSIZE` | `keep`: an input over the cap is kept whole outside git and its head parsed; `refuse`: it is refused (same as `--refuse-oversize`) | `keep` |
| `PROVOST_ARTIFACT_DIR` | where inputs over the cap are kept; never the store or inside it | `<store>.artifacts` |
| `PROVOST_LOCK_TIMEOUT` | seconds to wait for the store lock | `30` |
| `PROVOST_INTERRUPT_GRACE` | seconds an interrupted command has to finish before what it printed is filed (see [Interrupted runs](#interrupted-runs)); `0` = none | `2` |
| `PROVOST_LOCK_MAX_AGE` | seconds after which a lock is presumed stale | `3600` |
| `PROVOST_RECONCILE_OVERLAP` | % column overlap needed to merge a changed schema into a dataset instead of splitting `NAME.v2` | `60` |
| `PROVOST_QUIET` | `1` suppresses progress/ok messages (same as `--silent`) | `0` |
| `PROVOST_REDACT` | `0` = store inputs as they come, secrets and all (same as `--no-redact`) | `1` |

Numeric settings must be whole numbers; anything else is rejected at startup.

## Parsing templates

For output provost reads badly, write a **template**: a JSON file of regular
expressions, one per kind of line, for one tool. Put it in a directory named in
`PROVOST_TEMPLATE_DIRS` (or in a store's `llm-templates/`), and every capture it
fits is read by it, offline, with or without `--llm`:

```bash
provost template test volumes.json volumes.txt     # its tables, coverage, unread lines
export PROVOST_TEMPLATE_DIRS=~/provost-templates   # where volumes.json lives
provost run volumes                                # read by the template
```

`provost template test T CAPTURE EXPECTED.tsv` diffs the tables against the
expected ones and exits 1 on a difference; `--no-templates` turns templates off
for a capture; TextFSM templates work with `pip install 'provost[textfsm]'`.
The format, with worked examples, and how the quality gate treats a template:
[Parsing templates](templates.md).

## Multiple datasets per input (`--multi`)

Some reports hold more than one kind of data — a key/value block, a table, and
a banner or comment run that is best left alone. The default one-winner capture
keeps whichever the engine ranks first and drops the rest; `--multi` splits the
input, parses each part on its own terms (a kv block and a table can even use
different delimiters), and files each as its own dataset under **one** capture.

Datasets are named by their winning strategy (prefixed `NAME.` when `--name`
or `run` supplies one), so two parts that parse the same
way but differ in shape land in `NAME` and `NAME.v2`. Row indices (`#N`) run
consecutively across them and `provost source N` still returns the whole
original input. `provost log` shows the comma-joined list; the capture's
`meta.tsv` records `datasets` (how many) and `dataset_rows` (each one's range).

**Auto-multi.** Without `--multi`, provost still segments a capture when the
quality gate would otherwise hold its single parse for low coverage or low
consistency — but only when the split is clearly better: two or more parts,
each passing the gate on its own (a part read by a tool-specific parser
must keep the gate's coverage of its own lines too), together keeping at
least the gate's coverage and 10 points more than the single parse, no part a
table under positional `A`/`B`/`C` columns that shows a lost header or
shredded rows (a column of box chrome, mostly empty cells, or a header-like
line right above it; a headerless table is filed), and no shattering into
fragments.
Otherwise the capture is held as before, with the reason. The ok line says it
segmented and why; `meta.tsv` records `auto_multi`, the held single parse's
`single_*` measures, and each part's `dataset_coverage` /
`dataset_consistency`. With a `NAME`, the part whose columns match the single
parse's keeps dataset `NAME`, so repeated captures of one command keep their
rows together whether or not a capture segments. `PROVOST_AUTO_MULTI=0` (or
`--no-auto-multi`) turns it off.

See [the multi-dataset design note](0003-multi-dataset.md) for the rationale
and the scoring machinery behind the split.

## Units

**Where a unit lives.** By default provost leaves a unit where the tool
printed it, and converts nothing:

- in the column's name: `Bandwidth_(MB/s)` (OSU), `Best_Rate_MB/s` (STREAM);
- in each cell: `482MiB/s (505MB/s)` (fio), `42.18_GiB` (vnstat);
- in a column of its own beside the number: `transfer` and `transfer_unit`
  (the iperf3 parser).

So `9.4 GB/s` in one tool's output and `9400` under `MB/s` in another's are
different strings, and a tool that compared them as numbers would be wrong.

**`--units base`** (or `PROVOST_UNITS=base`, for `run`, piped input and
`batch`) adds, right after each column whose unit can be read exactly, a
column named `NAME[UNIT]` holding the same values as plain numbers in a base
unit. The original column is kept as it was. That suffix is the convention: a
column whose name ends in `[UNIT]` holds plain numbers in `UNIT`, and the
column it was read from is the one before it.

| base unit | for |
|---|---|
| `B` | bytes |
| `B/s` | bytes a second |
| `bit` | bits |
| `bit/s` | bits a second |
| `s` | seconds |

```console
$ provost --sync --units base --name osu osu_bw.txt
$ provost show osu
#  capture  n  Size  Bandwidth_(MB/s)  Bandwidth_(MB/s)[B/s]
1  c0001    1  1     3.26              3260000
2  c0001    2  2     6.55              6550000
```

Bits are never turned into bytes, nor bytes into bits: a `[B/s]` column and a
`[bit/s]` column are different units, and stay so.

**How a unit is read: by the letter.**

- `B`, `Byte`, `Bytes` are bytes; `bit`, `bits` are bits. A short `b` is
  bits only in a rate (`Mb/s`, `Gbps`): as a size it means bytes about as
  often (tc prints a 15 KiB burst as `15Kb`; sysfs has `read_ahead_kb`), so
  `Kb`, `Mb` or `kb` alone are not read. A bare `B` glued to its number
  (`8.0B`) is not read either, as it is as often a count (8 billion
  parameters); `3600 B` is.
- `k`, `K`, `M`, `G`, `T`, `P`, `E` are powers of 1000; `Ki`, `Mi`, `Gi`,
  `Ti`, `Pi`, `Ei` are powers of 1024. A tool that prints `kB` for 1024 bytes
  (`/proc/meminfo`) is converted as printed: the original column still says
  what the tool said.
- A rate is a size unit followed by `/s` or `/sec`, or `ps` after a short
  form (`MBps`, `Mbps`).
- Times: `ns`/`nsec`, `us`/`usec`/`µs`, `ms`/`msec`, `s`/`sec`/`seconds`.
- A bare multiplier that names no quantity is **not** read: `7.8Gi`
  (`free -h`), `1.2G`, `128K` (`df -h`, whose `G` is 1024^3 although the
  letter says 1000^3). Nothing is guessed.
- The one exception, from the tools' own source: iperf2 and iperf3 print
  powers of 1024 as `KBytes`, `MBytes`, `GBytes` and `TBytes`, so in a dataset
  the iperf3 parser filed, or one named `iperf` or `iperf3` (as
  `provost run iperf3 …` names it), those are read as KiB, MiB, GiB and TiB.
  Their bit rates (`Mbits/sec`) are powers of 1000, as labelled.

**Which columns.** The unit comes from, in this order:

1. the column's name: a trailing `(UNIT)` or `[UNIT]` (`Latency (us)`,
   `bw(MiB/s)`; a one-letter unit only after a space or `_`, so `Error(s)` is
   a plural, not seconds), the whole name when it is a size or a rate
   (`MB/s`; never a bare time: vmstat's `us` is user CPU), or its last `_`- or
   space-separated word when that carries a prefix or a rate
   (`Best_Rate_MB/s`, `rtt_ms`; not `kb_read_s` or `requests_per_ms`). Each
   cell must then be a plain number.
2. a column named `NAME_unit` beside it: each row is read in its own unit.
3. each cell: a number, optionally a space or `_`, and a unit (`1.19 MBytes`),
   optionally followed by the same quantity in another unit in parentheses
   (fio's `482MiB/s (505MB/s)`: the first is used).

A column is converted only when every cell that holds a digit can be read and
all its units are one quantity (sizes, byte rates, bit rates or times); a cell
with no digit (empty, `-`, `N/A`) gives an empty converted cell.

**Exact.** Every factor is a power of 10 or of 1024, so the conversion is done
on the decimal digits, never in floating point (which loses precision past
2^53), and printed in full: `28.2GiB` is `30279519436.8`, `1 EiB` is
`1152921504606846976`, `0.041 ms` is `0.000041`.

**The record.** A capture filed with `--units base` says `units  base` in its
`meta.tsv`, and, when it added any column, `units_columns  units.tsv`: a TSV
of `dataset`, `column`, `unit_column`, `base`, `from` (`name`, `cells`, or
`column NAME_unit`) and `read`, each unit read with its exact factor:

```text
dataset  column            unit_column            base  from  read
osu      Bandwidth_(MB/s)  Bandwidth_(MB/s)[B/s]  B/s   name  MB/s=10^6
```

Run over every corpus input as provost files it (3,733), `--units base`
converted 466 columns in 276 of them; each was checked for a false reading,
and the three found (vmstat's `us`, sysfs `read_ahead_kb`, llama-bench's
`8.0B` parameters) are the rules above that refuse them.

A dataset fed by captures with and without `--units base` keeps one table
(the earlier rows' `[UNIT]` cells are empty), unless the added columns take
its shape below `PROVOST_RECONCILE_OVERLAP`, when the new capture goes to a
variant (`NAME.v2`) as any changed shape does. A capture held in `unsorted`
is kept as it came.

## Metadata prologue

A leading run of `#%` lines on injected input is treated as capture context,
not data: it is peeled off before format detection (so it cannot corrupt a
parse), stored with the capture (`context.txt`), and shown verbatim by
`provost source`. Wrappers can prepend context unconditionally.

**Context columns.** With `--context-columns` (or `PROVOST_CONTEXT_COLUMNS=1`)
every `key=value` word in the prologue is also put on each row the capture
files, after `#` and `capture`:

```console
$ printf '#%% host=web03 rack=r2\nName,Load\nweb,0.5\n' | provost --sync --context-columns --name load
$ provost show load
#  capture  host   rack  n  Name  Load
1  c0001    web03  r2    1  web   0.5
```

Keys are letters, digits, `_`, `.` and `-`, starting with a letter or `_`;
the last value of a repeated key wins, and words that are not `key=value` stay
context only. A data column of the same name keeps it, and the context column
becomes `_host` — the rule `capture` already follows, so a by-name union never
merges the two. The names are chosen once per capture, against the data
columns of every dataset it files (and `capture` itself), and recorded in its
`meta.tsv` as `context_columns` (`host=_host,rack=rack`), so a reader can tell
a context column from a data column of the same name. A capture held in
`unsorted` is kept as it came, one raw column.

A value holding spaces is double-quoted: `#% build.toolchain="gcc 13.2"`
(`\"` and `\\` inside the quotes). An unterminated quote is an ordinary word.

## Run manifest

A run manifest is a prologue with agreed key names, so a result can be traced
to the requirement it tests, the build it measured and the run that produced
it. A **profile** names the keys: `extract/manifests/default.tsv` ships with
provost, and `proposal.tsv` has the same keys under a proposal's flat names.

| key | when | required | what |
|---|---|---|---|
| `req` | run | yes | requirement this run gives evidence for (RVTM id) |
| `test` | run | yes | the test or benchmark that was run |
| `test.version` | run | yes | its version |
| `build.commit` | run | yes | source commit of the software under test |
| `build.sha256` | run | no | sha256 of the binary that ran |
| `build.toolchain` | run | no | compiler and toolchain |
| `sched.job` | run | no | scheduler job id |
| `run.id` | run | no | the launcher's id for the run |
| `sut` | run | yes | system under test |
| `operator` | run | no | who started the run |
| `deviation` | run | no | a recorded departure from the procedure |
| `reviewer` | post | yes | who reviewed the result |
| `disposition` | post | yes | the review's verdict |

Nothing is checked unless asked:

```
$ cat manifest.txt
req=REQ-12
test=stream
test.version=5.10
build.commit=abc123
build.toolchain=gcc 13.2
sut=node7
$ provost run --manifest manifest.txt ./stream     # prepends it as '#%' lines, and checks it
$ provost check-manifest                            # every capture: what each lacks
capture  status      missing
c0001    complete    -
c0002    incomplete  req,sut
$ provost annotate c0001 reviewer=jo disposition=pass   # post-run keys, later
$ provost check-manifest --post --strict c0001          # exit 1 if any is incomplete
```

- `--manifest FILE` (run, piped input, FILE, batch): `KEY=VALUE` lines, the
  value the rest of the line; prepended as the prologue and checked.
- `--manifest-profile P` checks the input's own prologue as it is filed.
- A missing required key is a warning; `--strict-manifest`
  (`PROVOST_MANIFEST_STRICT=1`) files nothing and exits 1.
- `post` keys are never demanded at capture time. `provost annotate` keeps
  them beside the capture (`captures/ID/annotations.txt`, its own commit).
- The profile: `--profile`/`--manifest-profile`, else
  `PROVOST_MANIFEST_PROFILE`, else the store's own `manifest-profile.tsv`,
  else `default`. A NAME is looked up in `~/.config/provost/manifests`, then
  in provost's `extract/manifests`.

## Environment capture (`--env`)

`--env` (or `PROVOST_ENV=1`) adds where a capture was taken to its prologue.
Nothing is recorded without it.

```
$ module load gcc/13.2.0 openmpi/4.1.6
$ OMP_NUM_THREADS=8 provost run --env ./stream
$ provost source c0007
...
----- original source (capture c0007) -----
#% env.host=node7
#% env.kernel="Linux 5.14.0-427.el9.x86_64"
#% env.arch=x86_64
#% env.os="Rocky Linux 9.4 (Blue Onyx)"
#% env.modules=gcc/13.2.0:openmpi/4.1.6
#% env.user=jo
#% sched.job=4242
#% env.slurm.nodes=node[07-08]
#% env.var.OMP_NUM_THREADS=8
...
```

| key | what | from |
|---|---|---|
| `env.host` | the host provost ran on | `$HOSTNAME`, else `uname -n` |
| `env.kernel` | kernel name and release | `uname -sr` |
| `env.arch` | machine architecture | `uname -m` |
| `env.os` | OS release | `/etc/os-release` (`PRETTY_NAME`), or `sw_vers` on macOS |
| `env.modules` | loaded environment modules (Lmod, Environment Modules) | `$LOADEDMODULES` |
| `env.user` | the user provost ran as | `id -un` |
| `sched.job` | the Slurm job id (the manifest's key: `job_id` under `proposal`; `env.slurm.job` under a profile that claims no key for it) | `$SLURM_JOB_ID` |
| `env.slurm.nodes`, `.cluster`, `.partition` | the job's node list, cluster and partition | `$SLURM_JOB_NODELIST`, `$SLURM_CLUSTER_NAME`, `$SLURM_JOB_PARTITION` |
| `env.kernel.modules` | loaded kernel modules, sorted (only with `--env=modules`) | `lsmod`, else `/proc/modules` |
| `env.var.NAME` | an allow-listed environment variable | `PROVOST_ENV_VARS` |
| `env.withheld` | allow-listed variables not recorded because they look like secrets | `extract/secrets.tsv` |

- **Variables only from an allow-list**, never all of them: an environment
  carries tokens and passwords. `PROVOST_ENV_VARS` holds names or glob
  patterns, separated by spaces or commas; the default is
  `OMP_* MPI_* OMPI_MCA_* I_MPI_* MPICH_* UCX_* CUDA_* NCCL_*`, and set but
  empty it records none.
- **A variable that looks like a secret is never recorded**, even when
  allow-listed by name. `extract/secrets.tsv` lists the patterns: a name
  holding `TOKEN`, `SECRET`, `PASSWORD`, `KEY`, ...; a value holding a private
  key, an `Authorization:` header or bearer token, an AWS, GitHub, GitLab,
  Slack, Anthropic/OpenAI-style or Google API key, a JWT, credentials in a
  URL, or `password=`. provost warns, files the capture without it, and names
  it in `env.withheld`.
- **A manifest profile can claim a reading** for one of its own keys, in an
  optional fifth column, `env`. `default.tsv` and `proposal.tsv` claim the
  Slurm job id for `sched.job` and `job_id`; a store's own profile can claim
  others (`sut` from `host`, say).
- **The input's own prologue and `--manifest FILE` win:** a key either of
  them sets is left out of `--env`'s lines.
- **The readings describe the host provost runs on**, read once per command.
  `provost batch --env` puts the same readings on every input: right for
  outputs made on this host, wrong for files gathered from other hosts. A
  launcher that already gathers facts per host (quarterdeck's `qd probe
  facts`) should not pass `--env`.
- With `--context-columns`, every reading becomes a column, like any other
  prologue key. As with `--manifest`, `input_sha256` is of the input as
  received and `output_sha256` of what is stored, the readings included.

## Batch capture

```console
$ provost batch [options] FILE... [--from LIST]
```

Each file is a capture of its own, exactly as `provost FILE` would make it —
its own id, its own `provost source`, its own `capture-<id>` tag — but the
inputs are parsed in parallel and filed under one hold of the store lock as
**one** commit. The parse is the slow half of a capture and needs no lock, so
fifty captures in a row each pay for their own parse and commit, while fifty
in a batch share the CPUs and one commit (40 small inputs: 13 s against 55 s
on 4 CPUs). The lock is held about 50 ms an input; other writers wait for it
up to `PROVOST_LOCK_TIMEOUT`.

- Capture ids follow the order the files were named, whichever parsed first.
  Each capture's `meta.tsv` records its `input` path and its `batch` (the id
  range).
- `--name NAME` applies to the files after it, until the next `--name`.
- `--from LIST` reads more files from `LIST` (`-` for stdin), one a line:
  `PATH`, or `NAME<TAB>PATH` for a file of its own name. Blank lines and lines
  starting `#` are skipped.
- `-j N` / `--jobs N` parses at most `N` files at a time (default: the CPUs,
  at most 16). `--llm` parses one at a time, so a template Claude writes for a
  tool is written once, not once per file.
- Every file is checked before anything is filed. An empty file is skipped
  with a note; one that is too large or fails to parse is reported and the
  rest are still filed. The exit status is 1 if any file was not captured.

For a wrapper that captures a fleet, write one file per host, open each with
`#% host=NAME` (and anything else worth a column), and pass
`--context-columns`: every row then says which host it came from, and
`provost source` still shows each host's answer on its own.
