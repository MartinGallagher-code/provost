# Tools near provost, and what provost should do next (2026-11-12)

- **Ticket:** PV-036, "search the internet to see what else this product should be doing".
- **provost as compared:** main @ 90e44bf, version 2.19.0. Every claim about provost below was checked in the code or by running it, and says how.
- **Other tools:** read from their own documentation, repositories, package indexes or papers on 2026-11-12. Every link's HTTP status is in the [link check](#link-check) at the end.
- **The owner's answers.** The owner's note on PV-036 was "Do your best", followed by "then, work the ticket". That was taken as the ticket's suggested answers to its five questions:
  1. a report plus at most five new Backlog tickets;
  2. favour both users: the general user (sysadmins, SREs, network engineers) and the HPC test-and-evaluation user;
  3. no changes to provost's shape: those are listed here, not filed;
  4. gaps that belong to quarterdeck or Meridian Commander are listed here, not filed;
  5. the report is kept here, as a docs page with a patch bump.

## The short answer

**The top recommendation is [PV-037](#pv-037-use-the-command-name-and-stop-one-tools-parser-reading-anothers).**
- **What is wrong:** when provost files a command's output, a parser written for one tool often wins on another tool's output. Nothing in CI can see it.
  - In full mode, the mode every capture uses, 94 of the 3,733 corpus inputs are claimed by a bespoke strategy written for a different tool. 60 of those are one strategy, `pkg-config`. It files `netstat -anp`, `ip -br addr`, `poetry show` and `gluster volume status` as two columns, `name` and `description`.
  - The corpus gate tests only `--generic` mode, so it never sees this.
  - jc, ntc-templates and Genie choose a parser from the command's name. provost knows the name (`provost run netstat -anp`) and does not pass it to the engine.
- **The fix:** pass the command name to the engine, narrow `pkg-config`'s detector, and check full mode in CI.

**The four others filed, in rank order:**

| Rank | Ticket | Gap | Who needs it | Size |
|---|---|---|---|---|
| 1 | **PV-037** (high) | Use the command name; stop one tool's parser reading another's; check full mode in CI | everyone | M |
| 2 | **PV-038** (high) | Keep what an interrupted `provost run` had captured. Today Ctrl-C or a scheduler's SIGTERM keeps nothing | both: `ping`, `tail -f`, `iostat 1`; jobs ended at walltime | S–M |
| 3 | **PV-039** | Hand-written templates applied without `--llm`, documented, with `provost template test` and a regex time limit; TextFSM as an option | network engineers, sites with in-house tools, sites with no LLM | M |
| 4 | **PV-040** | Record each column's type once, at capture; store it and show it | everyone who reads the data | M |
| 5 | **PV-041** (low) | `provost show --format csv\|json\|ndjson\|md`, `--capture latest`, and a "Getting data out" section | general user, scripts | S |

**What else the survey found:**
- **Already in the toolchain.** quarterdeck already reads any provost dataset as `ds:NAME`. It filters (`--where`), writes CSV, JSON and NDJSON, exports OpenMetrics and Splunk HEC, follows a column across runs, and browses a store in a terminal or a browser. That answers most of what a query layer, a metrics exporter or a web UI would add to provost. provost's own docs do not say so; PV-041 fixes that.
- **Already ticketed: 22 ideas.** Thresholds, baselines, signing, verify, units, redaction, the pandas API, HPC parsers, the manifest, `--env`, lifecycle, the store format and others are all done or ticketed (table [below](#already-ticketed)).
- **Runners-up and the rest.** Nine runners-up are listed for the owner to pick from. Six ideas would change provost's shape; they are listed, each saying which decision in docs/0001 it would reverse. Four belong to quarterdeck or Meridian Commander.

## How this was done

1. **provost first.** A feature map was built from the code at 90e44bf, by running each command on a scratch store and reading the dispatcher, the help text and the engines. The ticket was written against 728140f (2.4.0); fifteen tickets landed after it (PV-019 to PV-033, PV-035), so several of its leads were already closed (`show --tsv`, `--env`, `prune`, signing).
2. **Five research passes**, one per group named in the ticket, ran in parallel. Each read only the tools' own docs, repositories, package indexes or papers. Each recorded every cited URL's HTTP status, and listed separately the pages it could not read. The five category files are attached to PV-036 (`PV-036-survey-output-parsers.md`, `-format-inference.md`, `-provenance.md`, `-tabular-cli.md`, `-benchmark-tracking.md`). Each has every tool's capability table, the exact URL each row came from, its status and the date read.
3. **Parse quality** was measured on provost's own corpus. The corpus harness's report view (`bash tests/corpus/run.sh`) runs the generic and the full engine side by side on 3,733 inputs. 30 common commands that jc has dedicated parsers for were also filed with provost.
4. **Twenty claims** that the new tickets rest on were re-fetched independently, and the key phrase was searched for in each page ([spot check](#spot-check)). All twenty were found.
5. **Every candidate gap was checked against tickets:** every provost (PV) and provost_model (PM) ticket, open and closed; every quarterdeck (QD) ticket; QD-006's two decision tables; QD-025's survey decisions; and Meridian Commander's (MC) tickets.

**Access limits.**
- github.com web pages and api.github.com returned 403 through this session's proxy. Repository files were read from raw.githubusercontent.com. Issue titles and dates were read from the issues.ecosyste.ms mirror, and some issue pages were read through a fetch tool that renders them; the category files say which.
- **Installing the comparison tools was refused** in this session's permission mode (`pip install jc textfsm ntc-templates ttp duckdb` into a scratch virtualenv, refused twice). So the side-by-side comparisons put provost's real output next to the neighbour's output as its own documentation or test fixtures show it, and say so. None of jc, TextFSM, TTP, Miller or DuckDB was run here.
- **Pages that could not be read** are listed in each category file. The ones that matter here:
  - community.cisco.com (403);
  - chat.osquery.io (429);
  - osquery.io/schema (404);
  - `googlecloudplatform.github.io/ramble/` (404; ramble.readthedocs.io was used);
  - `software.llnl.gov/benchpark/7-analyze-experiment.html` (503, then 404);
  - JUBE's `/jube2/` page (403; its `/docu/` pages were used);
  - Microsoft PROSE's old docs path (404).
  - None of these pages is used for a claim.

## provost as compared

Read from the code at **main @ 90e44bf (2.19.0)**. Every row can be repeated from a checkout of 90e44bf with a scratch store (`export PROVOST_HOME=$(mktemp -d)/store PROVOST_ASYNC=0`).

| Area | What provost has | How to see it |
|---|---|---|
| Capture | `run CMD`, a pipe, `provost FILE`, `batch FILE...` (one commit, parsed in parallel), `listen CMD` (a shell function that files every run of CMD), `control DIR` (a store per directory, with its files) | `provost help`; the dispatcher `main()` at `provost:7860` routes 30 verbs: `grep -cE '^\s+[a-z\|-]+\)\s+(shift; )?cmd_' provost` |
| Parsing | 274 strategy scripts in 16 groups (89 delimited and 29 structured are the generic ones), 109 hint rows, `--plugin-dir`, `--multi`, auto-multi, `--model` (the layout model and the tiny LM), `--llm` templates (regex "format 1" or sandboxed Python "format 2"; repaired, reviewed; Anthropic or OpenAI-compatible endpoints; an offline mode) | `find extract/strategies -name '*.sh' \| wc -l` (274); `grep -vcE '^\s*(#\|$)' extract/hints.tsv` (109); `provost help advanced` (LLM TEMPLATES) |
| Templates shipped | two: `ip-addr.json`, `mcstatus.json` | `ls extract/llm/templates` |
| A quality gate | a generic parse under 80% line coverage or 70% type consistency is held in `unsorted`, with the reason | `provost help advanced` (QUALITY GATE) |
| Store | git; plain TSV per dataset; `meta.tsv` per capture with the input's and output's sha256; a versioned store format with a spec and `store check` | `docs/store-format.md`; `provost store check` |
| Provenance and trust | the run manifest (`#%`, `--manifest`, `check-manifest`, `annotate`), `--context-columns`, `--env`, an `Operator:` trailer on every commit, ssh or gpg signing, SHA-256 stores, `verify` | `provost help advanced` (RUN MANIFEST, ENVIRONMENT CAPTURE, SIGNING) |
| Data handling | `--units base` (exact base-unit columns), secrets scrubbed before storing, `export --redact` (a pseudonymised copy), oversize inputs kept by hash outside git | `provost help advanced` (UNITS, SECRETS AND REDACTION, OVERSIZE INPUTS) |
| Lifecycle | `rm`, `rm --capture`, `prune --policy`, `archive --to` (signed, verifiable), a disposal log | `provost help advanced` (Upkeep) |
| Browsing | `ls`, `show NAME [--capture ID] [--at ID] [--tsv]`, `search` (git grep over rows, outputs or files), `diff [NAME] [A [B]]`, `log`, `source`, `restore`/`prev`/`next`, `files`, `triage` | `provost show --help`; `provost search --help`; `provost diff --help` |
| Analysis | `stats NAME [ARGS]`: the analyze engine, with `--format plain\|json\|markdown\|csv\|tsv\|html`, `--threshold`, `--compare`, `--timeseries`, `--mode benchmark` | `provost stats df --format json`; `analyze/provost-analyze --help` |
| From Python | `provost_data.load(name)` (rows as dicts of strings) and `load_df(name)` (pandas; a column whose every value is a number becomes numeric) | `src/provost_data/_dataset.py:136`, `:159` |
| Moving a store | `export` (the whole store as one git bundle), `import` | `provost export --help` |

### What provost does not have (each checked)

| Not there | How it was checked |
|---|---|
| An output format for a dataset other than an aligned table or TSV (no JSON, NDJSON, CSV, Parquet or SQLite) | `provost show df --json` and `--format csv`: "unknown option for 'show'". `grep -rniE 'openmetrics\|prometheus\|parquet\|sqlite\|ndjson' provost docs/usage.md README.md \| wc -l` is 0 |
| Exporting one dataset as a file | `provost export --help`: "Bundle the whole store" only |
| Filtering, sorting or aggregating a dataset by column | `provost search --help`: a regular expression over the whole row. `provost query` and `provost sql`: "unknown command" |
| A recorded column type | `grep -ciE '\btype' docs/store-format.md` is 0. The engine types every cell to measure consistency, `stats` guesses types again ("Column types (guessed)"), and `load_df` guesses a third time (numbers only). None is stored |
| A template a user writes, applied without `--llm` | A hand-written format-1 template is read only under `--llm`. With no key set, `provost --name x ip-addr.txt` files strategy `group-children`, and `provost --llm --name x ip-addr.txt` files `llm-template`. `extract/llm/GUIDE.md` is the prompt Claude is given, not user documentation; `grep -niE 'by hand\|your own' README.md docs/usage.md extract/README.md` finds nothing |
| The command's name as evidence when detecting a format | The engine calls (`provost:2529`, `:2569`, `:2579`) pass no command name, and `extract/provost-extract --help` has no option for one |
| Keeping an interrupted run | `provost:408-409` trap INT and TERM to `exit 130` and `exit 143`. Tried below: nothing is filed |
| Periodic capture, sync, a server | `provost watch`, `push`, `pull`, `sync`, `serve`, `web`: "unknown command". All cut on purpose in docs/0001 |
| `--capture latest` | `provost show free --capture latest`: "invalid capture id 'latest'" |

### Readers outside provost that already fill some of these

**quarterdeck** (main @ 7393578) reads any provost dataset, not only its own runs:
- `ds:NAME` is "a whole provost dataset: every run that ever filed into it" (quarterdeck `README.md:278`).
- Its read commands take `--where`, `--sort`, `--limit`, `--cols` and `--format text|csv|tsv|json|ndjson|md` (`README.md:1460`).
- `qd export` writes `--format hec` and `--format openmetrics` (`README.md:1873`).
- `qd trend`, `qd compare` and `qd changes` follow a column across runs.
- `qd view` and `qd web` browse a store.
- `REF@STORE` reads another machine's store without copying it.

**Meridian Commander** opens TSV and CSV in a table browser that filters and sorts (MC-007, MC-008).

provost's README and usage page say none of this: `grep -niE 'quarterdeck|\bqd\b' README.md docs/usage.md` finds two passing mentions.

## Parse quality: where the comparison matters most

provost's weak point is output it has never seen: 13% PASS and 31% FAIL on round 5 (`HANDOFF.md`, "The honest picture"). jc, TextFSM and Genie avoid that problem by hand-writing a parser per command and choosing it by the command's name. What follows is what that difference costs today, on provost's own inputs.

### What users get is not what CI checks

The corpus gate (`tests/corpus/run.sh --golden`) runs the engine with `--generic`. The path every capture takes is the full engine, which adds 156 tool-specific strategies (274 scripts, less the 89 delimited and 29 structured ones). The harness's report view shows both, but nothing fails when they differ.

`TMPDIR=$(mktemp -d) LC_ALL=C bash tests/corpus/run.sh` on 90e44bf (about 15 minutes on 4 CPUs) gives:
- 3,602 of 3,732 inputs tidy under `--generic`;
- 291 inputs where full mode uses a bespoke strategy instead;
- **94 of those 291 where the bespoke strategy was written for a different tool.** Counted as: the strategy's name and the tool's name share no leading word.

| Strategy that wins | Inputs it claims | Right? |
|---|---:|---|
| `pkg-config` | 60 | **No.** Among them: `netstat -anp`, `netstat -tulpn`, `ip -br addr`, `poetry show`, `gluster volume status`, `emacs --version`, `tox list`, `rabbitmqctl list_exchanges`, `consul catalog services`, `lpstat -p`. Each is filed as `name` and `description`, with the rest of the line in one cell |
| `sysstat` | 21 | Yes: `sar`, `mpstat` and `pidstat` are sysstat's tools |
| `docker-ps` | 4 | Yes: `podman ps` and `nerdctl ps` print the same table |
| `iptables-nat` | 3 | Yes: `ip6tables` |
| `csvlook` | 3 | Mostly: Markdown tables. 2 of the 3 fail the manifest under `--generic` as well |
| `R-version`, `systemctl-status` | 3 | Yes |

How to see one:

```bash
export PROVOST_HOME=$(mktemp -d)/s PROVOST_ASYNC=0
provost run cat tests/corpus/inputs/netstat-anp.txt
#  ok c0001: → dataset 'cat' rows #1..6 (strategy pkg-config, conf 79, coverage 100%) — 3 field(s).
provost show cat | head -3
# #  capture  n  name    description
# 1  c0001    1  Active  Internet connections (servers and established)
# 2  c0001    2  Proto   Recv-Q Send-Q Local Address           Foreign Address ...
```

The generic engine reads the same file as the 7-column table that `tests/corpus/expected/netstat-anp.tsv` holds. **PV-037.**

### Commands jc has a parser for

Each of these corpus inputs was filed with `provost --name NAME FILE`, full mode, no `--llm`. jc has a dedicated, typed parser for every one (jc README parser table).

| Input | provost's strategy | Fields | What came out |
|---|---|---:|---|
| `netstat-anp` | pkg-config (79) | 3 | wrong: name/description |
| `ifconfig` | text-lines (50) | 1 | one column, one row per line; jc gives one object per interface with typed fields |
| `uptime` | line-records (51) | 12 | positional columns `A`…`L`: `up`, `3`, `days,`, `load`, `average:`; jc gives `load_1m`, `uptime_days` and the rest as numbers |
| `arp -a` | aligned-columns (65) | 7 | `A`…`G`, with the literal `at` and `on` as columns |
| `last` | aligned-columns (65) | 10 | the date spread over three columns; "still logged in" spread over three |
| `vmstat` | held in `unsorted` | – | low coverage (75%) |
| `dmidecode` | colons (57) | 6 | partial |
| `ps aux`, `lsof`, `df -h`, `crontab`, `mount`, `free`, `ss -tulpn`, `stat`, `dig`, `lscpu`, `id`, `env`, `du -h`, `lsblk`, `iptables -nvL`, `w`, `route -n`, `ip addr`, `systemctl list-units`, `traceroute`, `ping` | various | – | a usable table. The last seven keep less than all their lines: 87%, 80%, 83%, 83%, 63%, 42% and 42% coverage |

So of 28 everyday commands filed (three of the 31 tried are not in the corpus), 2 come out wrong (`netstat -anp`, `ifconfig`), 1 is held (`vmstat`), 4 are partial (`uptime`, `arp -a`, `last`, `dmidecode`), and 21 give a usable table. A per-command parser fixes the wrong ones, so PV-037 (the command name) and PV-039 (templates) reach them. The partial ones are PV-006's question (the generalisation approach), which the owner has still to pick from docs/0004.

### Network devices

provost's corpus has almost no vendor network output: FRR's `vtysh` tables, and no Cisco IOS, NX-OS, Junos or EOS. ntc-templates has 977 templates for 57 platforms, and stopped taking template requests because demand outran it. Two of its own test fixtures, filed with provost:

| ntc fixture | ntc's expected parse (its `.yml`) | provost |
|---|---|---|
| `cisco_ios_show_version.raw` | 1 record, 18 fields: `hostname`, `version`, `uptime`, `serial`, `hardware`, `config_register`, … | `text-lines`: 32 rows of one column |
| `cisco_ios_show_interfaces.raw` | 9 records (one per interface), 42 fields each: `interface`, `link_status`, `mtu`, `bandwidth`, `input_errors`, … | `csv`: the first interface's status line (`GigabitEthernet0/0 is reset, line protocol is down (notconnect)`) taken as the header, then 249 rows of comma-split prose, at 96% coverage, so the gate passed it |

**PV-039** makes a template (or a TextFSM file) usable without `--llm`.

## The tools

Over 50 tools, in 44 rows, across the five groups the ticket named. The category files attached to PV-036 have each one's capability table.

| Group | Tool | Licence | Latest release (date) | How it runs | Docs read |
|---|---|---|---|---|---|
| 1 Output to data | jc | MIT | 1.26.2 (2026-10-29) | Python CLI filter and library | <https://kellyjonbrazil.github.io/jc/> |
| 1 | TextFSM | Apache-2.0 | 2.1.1 (2026-11-10) | Python library | <https://raw.githubusercontent.com/wiki/google/textfsm/TextFSM.md> |
| 1 | ntc-templates | Apache-2.0 | 9.3.0 (2026-09-14) | 977 TextFSM templates, Python wrapper | <https://ntc-templates.readthedocs.io/en/latest/> |
| 1 | TTP | MIT | 0.10.1 (2026-03-21) | Python library and CLI | <https://raw.githubusercontent.com/dmulyalin/ttp/master/README.md> |
| 1 | Cisco Genie / pyATS parsers | Apache-2.0 | 26.10 (2026-11-03) | Python library | <https://pubhub.devnetcloud.com/media/pyats-development-guide/docs/writeparser/writeparser.html> |
| 1 | nushell | MIT | 0.117.0 (2026-11-09) | shell with structured pipelines | <https://www.nushell.sh/commands/docs/detect_columns.html> |
| 1 | osquery | Apache-2.0 or GPL-2.0 | 5.24.1 (2026-10-29) | daemon and SQL shell | <https://osquery.readthedocs.io/en/stable/introduction/sql/> |
| 1 | PowerShell ConvertFrom-String | proprietary; Windows PowerShell 5.1 only (removed in 7) | – | cmdlet | <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-string?view=powershell-5.1> |
| 1 | Slurp'it TextFSM Template Builder | MIT | no release | LLM writes TextFSM | <https://gitlab.com/slurpit.io/template_builder/-/raw/main/README.md> |
| 1 | Netmiko (`use_textfsm`, `use_ttp`, `use_genie`) | MIT | 4.8.0 (2026-09-21) | Python SSH library | <https://raw.githubusercontent.com/ktbyers/netmiko/develop/EXAMPLES.md> |
| 2 Format inference | Drain3 | MIT | 0.9.11 (2022-07-17) | Python library, online template mining | <https://raw.githubusercontent.com/logpai/Drain3/master/README.md> |
| 2 | LogPAI logparser and Loghub-2.0 | Apache-2.0 (parsers vary); data for research use | logparser3 1.0.4 (2023-09-14) | 17 parsers and a benchmark | <https://raw.githubusercontent.com/logpai/logparser/main/README.md> |
| 2 | LLM log parsers: LILAC, LogBatcher, AdaParser, LUNAR, LogParser-LLM | research code (LogBatcher MIT; LILAC and LUNAR have no licence file) | papers 2024–2025 | Python | <https://arxiv.org/html/2310.01796v3> |
| 2 | Grok (Logstash, Elasticsearch) | Apache-2.0 | filter 4.4.4 (2026-02-11) | pattern library in a pipeline | <https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-grok> |
| 2 | Vector (VRL) | MPL-2.0 | 0.61.0 (2026-10-29) | Rust daemon | <https://vector.dev/docs/reference/vrl/functions/> |
| 2 | Fluent Bit parsers | Apache-2.0 | 5.2.0 | C daemon | <https://docs.fluentbit.io/manual/data-pipeline/parsers> |
| 2 | Microsoft PROSE | non-commercial, closed; discontinued | 10.16.5 (2025-10-06) | .NET SDK | <https://raw.githubusercontent.com/microsoft/prose/main/README.md> |
| 3 Provenance and versions | DVC | Apache-2.0 | 3.67.1 (2026-03-31) | Python CLI over git | <https://dvc.org/doc/command-reference/metrics/show> |
| 3 | DataLad | MIT | 1.8.0 (2026-11-03) | Python CLI over git and git-annex | <https://docs.datalad.org/en/stable/generated/man/datalad-run.html> |
| 3 | git-annex | AGPL-3.0 | 10.20261026 | Haskell CLI | <https://git-annex.branchable.com/todo/compute_special_remote/> |
| 3 | Dolt | Apache-2.0 | 2.7.3 (2026-11-11) | SQL database with git semantics | <https://docs.dolthub.com/cli-reference/cli> |
| 3 | lakeFS | BUSL-1.1 since 1.87.0 | 1.88.0 (2026-10-01) | server over object storage | <https://docs.lakefs.io/reference/cli/oss/> |
| 3 | sqlite-utils | Apache-2.0 | 4.2.1 (2026-08-13) | Python CLI | <https://sqlite-utils.datasette.io/en/stable/cli.html> |
| 3 | Datasette | Apache-2.0 | 0.65.5; 1.0a42 (2026-11-08) | web server over SQLite | <https://docs.datasette.io/en/latest/changelog.html> |
| 3 | W3C PROV | W3C Recommendation | 2013 | vocabulary | <https://www.w3.org/TR/prov-dm/> |
| 3 | RO-Crate (Workflow Run, Process Run Crate) | spec | 1.3 | JSON-LD packaging | <https://www.researchobject.org/workflow-run-crate/> |
| 3 | ReproZip | BSD-3-Clause | 1.3.2 (2026-01-18) | syscall tracer and packer | <https://docs.reprozip.org/en/1.x/packing.html> |
| 3 | Sumatra, noWorkflow (brief) | BSD-2 / MIT | – | run recorders | category file |
| 4 Tabular CLI | Miller | BSD-2-Clause | 6.22.0 (2026-09-25) | Go CLI | <https://miller.readthedocs.io/en/latest/> |
| 4 | csvkit | MIT | 2.2.0 (2025-12-15) | Python CLIs | <https://csvkit.readthedocs.io/en/latest/> |
| 4 | xsv | Unlicense/MIT | 0.13.0 (2018); unmaintained | Rust CLI | <https://raw.githubusercontent.com/BurntSushi/xsv/master/README.md> |
| 4 | qsv | MIT | 28.0.0 (2026-11-01) | Rust CLI | <https://raw.githubusercontent.com/dathere/qsv/master/README.md> |
| 4 | VisiData | GPL-3.0 | 3.5 (2026-10-28) | terminal UI | <https://www.visidata.org/formats/> |
| 4 | DuckDB CLI | MIT | 2.0.0 LTS (2026-10-21) | embedded SQL | <https://duckdb.org/docs/2.0/data/csv/auto_detection.html> |
| 4 | q | GPL-3.0 | 3.1.6 (2021-11-26) | SQL over text | <https://harelba.github.io/q/> |
| 4 | trdsql, clickhouse-local, sqlite-utils `memory` (brief) | MIT / Apache-2.0 | 1.2.3 / 26.10 / 4.2.1 | SQL over files | category file |
| 5 Results tracking | ReFrame | BSD-3-Clause | 4.11.0 (2026-11-11) | Python test framework | <https://reframe-hpc.readthedocs.io/en/stable/manpage.html> |
| 5 | Ramble | Apache-2.0 or MIT | 0.7.1 (2026-10-29) | Python experiment driver | <https://ramble.readthedocs.io/en/latest/_sources/dev_guides/application_dev_guide.rst.txt> |
| 5 | Benchpark | Apache-2.0 with LLVM exception | snapshots only | benchmark suite on Ramble | <https://software.llnl.gov/benchpark/performance-dashboard.html> |
| 5 | XALT | LGPL-2.1+ | 3.2.4 (2026-06-17) | link-time and runtime job tracker | <https://xalt.readthedocs.io/en/latest/115_xalt_internal_design.html> |
| 5 | MLflow | Apache-2.0 | 3.18.0 (2026-11-02) | tracking server and API | <https://mlflow.org/docs/latest/ml/tracking/tracking-api/> |
| 5 | Sacred | MIT | 0.8.7 (2024-11-26) | Python experiment recorder | <https://sacred.readthedocs.io/en/stable/collected_information.html> |
| 5 | node_exporter textfile collector, OpenMetrics | Apache-2.0 | 1.12.1; OM 1.0 (2.0 draft) | metrics exposition | <https://prometheus.io/docs/specs/om/open_metrics_spec_2_0/> |
| 5 | Pavilion2, JUBE, asv (brief) | not confirmed / GPL-3.0 / BSD-3 | 2.6.1 / 2.7.1 / 0.6.6 | HPC test harnesses, benchmark history | <https://pavilion2.readthedocs.io/en/latest/results/parse.html> |

## Feature by feature

For each tool: what it does that provost does not, and what provost does that it does not. "provost lacks" means checked in provost's code at 90e44bf. "Covered by qd" means quarterdeck does it over a provost store.

| Tool | Does, provost does not | provost does, it does not |
|---|---|---|
| jc | Picks the parser from the command (`jc netstat -anp`; PV-037). A typed schema per parser, with numbers as numbers (PV-040). JSON on stdout for `jq` (PV-041). 198 hand-written parsers, `ifconfig` and `uptime` among them. Streaming JSON Lines parsers | Detects the format with no parser named; keeps every run in git with its raw input; diff, search and time travel across runs; redaction, signing, units; `--llm` for a tool jc has no parser for |
| TextFSM / ntc-templates | A template language people write and share; 977 network templates indexed by platform and command; a `.raw` and `.yml` test per template; `-> Error` so that every line is accounted for (PV-039; strict mode is runner-up R4) | Detection without naming a template; works on any tool's output, not only network devices; storage, history and provenance |
| TTP | Templates that look like the output, with `{{ var }}`; lookup tables; validation with Cerberus or YANG; output to Excel or Jinja2 | Detection; storage; provost's gate holds a doubtful parse instead of returning it |
| Genie / pyATS | 6,483 commands' parsers, each validated against a schema; `genie learn` and `genie diff` across snapshots, ignoring counters and timestamps by default (R1) | Not tied to Cisco; a store; signing |
| nushell | Structured pipelines over any table: `where`, `sort-by`, `group-by`, `detect columns --guess`, `@structured` per command | Keeps every run; provenance; a detection engine of 274 strategies |
| osquery | SQL over OS state; scheduled queries with differential (added and removed) results | Any command's output, not a fixed set of 294 tables; nothing installed as a daemon |
| ConvertFrom-String | Learns a parser from marked examples and caches what it learned (PV-039 takes the "write it once, reuse it" half) | Runs anywhere; open source; detection |
| Slurp'it, Netmiko | An LLM writes TextFSM; one switch to parse a device's output with TextFSM, TTP or Genie | provost's `--llm` writes, repairs and reviews its own templates, and refuses to send a capture in offline mode |
| Drain3, logparser | Online template mining over log streams; GA/PA/FGA/FTA accuracy metrics on Loghub | Tables, not log templates; per-capture storage |
| LLM log parsers | Template caching with merge at ≥0.8 similarity; per-dataset cost figures | Already has caching (stored templates), verification (the gate), repair (PV-008), review (PV-009), offline mode (PV-019) and a usage log (`PROVOST_LLM_LOG`) |
| Grok, Vector, Fluent Bit | Named pattern libraries with inline types; `vector test` unit tests; a regex time or step limit (PV-039); multiline assembly (R7); failed parses routed with a reason | Detection; storage. A failed parse is held in `unsorted` with its reason (`provost triage`), as Vector's `reroute_dropped` does |
| DVC | `metrics diff` with a change column (R1); experiments; remotes | Parses raw output into tables; signing; redaction |
| DataLad | `run`/`rerun` with declared inputs and outputs (R3); `--on-cmd-failure` keeps a failed run's output (PV-038) | Parsing; one command to capture; `verify` with input hashes |
| git-annex | Large files by reference with special remotes; `fsck --incremental` | Already has oversize inputs by hash (PV-021) and `verify` (PV-026) |
| Dolt | SQL with `AS OF`; row-level history and `blame`; `diff --where` (R1) | Parsing; capture; plain files any tool can read |
| lakeFS | Pre-commit hooks that can reject a commit; per-branch retention | Already has retention by policy (PV-029); runs with no server |
| sqlite-utils, Datasette | SQL over CSV and JSON with no import step; a JSON API; facets; a web UI | Parsing raw command output; history per capture |
| W3C PROV, RO-Crate | A standard provenance export, readable by other tools (R2) | Already records the same facts: command, input and output hashes, operator, time, environment, manifest |
| ReproZip, Sumatra, noWorkflow | Trace a run's files; pack and re-run elsewhere (R3) | Parsing; a store |
| Miller, csvkit, xsv, qsv | Filter, sort, join and stats by column; CSV, JSON and Markdown out (PV-041); `describe`, `csvstat` and `qsv schema` show types (PV-040); `--fw` for aligned columns with spaces in values | Detects 274 formats, not only delimited ones; keeps history |
| VisiData | An interactive table UI | Covered by `qd view` and Meridian Commander |
| DuckDB, q, trdsql, clickhouse-local | SQL over files and stdin; `sniff_csv` returns a pinned reader; Parquet out | Shape change; DuckDB already reads the store's TSV (PV-041's docs) |
| ReFrame | Per-metric references with thresholds; `--performance-compare` over history (p95, MAD); a results database (DuckDB in 4.11) | provost files ReFrame perflogs (PV-030) and has a ReFrame recipe (PV-023); comparison is quarterdeck's (QD-009, QD-030) |
| Ramble, Benchpark, Pavilion2, JUBE | Figure-of-merit regexes declared per application, with derived values and statistics per pattern (PV-039's templates are the provost form) | Detection without declaring anything |
| XALT, Sacred | A start record, an INTERRUPTED status, a heartbeat (PV-038) | Parses the output; a run's record is a signed git commit |
| MLflow | A tracking server, UI and search API; units and direction per metric (asked in MLflow #25377) | Runs with no server; units are PV-032; direction is quarterdeck's (listed below) |
| node_exporter, OpenMetrics | Metrics exposition | Covered by `qd export --format openmetrics` |

## Every gap, and what was decided

### Filed (five new Backlog tickets, none worked)

Each kept gap names who needs it, the evidence (which tools have it, kept apart from any demand seen), its size, and whether it fits docs/0001.

#### PV-037: use the command name, and stop one tool's parser reading another's

- **Who:** everyone; it is silent, so nobody knows to ask.
- **Evidence (tools):** jc's magic syntax picks the parser from the command; ntc-templates' `index` and Genie's `device.parse("show …")` are keyed by command.
- **Evidence (provost):** 60 corpus inputs claimed by `pkg-config` in full mode; the gate tests `--generic` only (above).
- **Demand:** jc's tracker shows a steady stream of per-command parser requests (22 of its 116 most recent issues carry the `new-parser` label; issues.ecosyste.ms). No outside demand was found for this exact fix, because users cannot see the fault.
- **Size:** M. **Fits docs/0001:** yes; it is the detect step done better.

#### PV-038: keep what an interrupted run had captured

- **Who:** both users. Commands stopped by Ctrl-C by design (`ping`, `tail -f`, `iostat 1`, `tcpdump`); every Slurm job ended at walltime (SIGTERM, then SIGKILL after `KillWait`, 30 s by default; <https://slurm.schedmd.com/slurm.conf.html>).
- **Evidence (tools):** XALT's start record; Sacred's INTERRUPTED and TIMED_OUT statuses and heartbeat; DataLad's `--on-cmd-failure` (1.6.3); quarterdeck already chose this for itself (QD-027).
- **Evidence (provost):** tried with a harness that signals `provost run --show`'s whole process group. SIGINT: exit 130, nothing filed; SIGTERM: exit 143, nothing filed. The pipe form also filed nothing. The command's own summary-on-SIGINT was lost too.
- **Demand:** DataLad #7902, which led to `--on-cmd-failure`; Sacred's statuses exist because runs die.
- **Size:** S–M. **Fits:** yes.

#### PV-039: hand-written templates without `--llm`, a test command, and a regex time limit

- **Who:** network engineers (no Cisco, Junos or EOS in the corpus); sites with their own tools; sites where no LLM may be used.
- **Evidence (tools):**
  - TextFSM, ntc-templates (with `.raw` and `.yml` tests), TTP and ConvertFrom-String;
  - nushell's `@structured`, and `vector test`;
  - Grok's `timeout_millis` and Fluent Bit's 10,000,000-step regex cap.
- **Evidence (provost):** format 1 already exists, but it runs only under `--llm`, is documented only as Claude's prompt, ships two templates, and has no time limit.
- **Demand:**
  - ntc-templates' FAQ: "no longer considering additional template requests";
  - nushell #16092, which asked for per-command parsing schemas;
  - Drain3 #82 and logparser #128, #70 and #39, which asked to freeze or reuse learned templates.
- **Size:** M (L with TextFSM). **Fits:** yes. A template is a parser. `provost template test` is a new verb, but not one docs/0001 cut; PV-039 asks the owner.
- **Licence:** TextFSM and ntc-templates are Apache-2.0, usable as an optional dependency and as data under GPL-3.0-or-later.

#### PV-040: record each column's type

- **Who:** everyone who reads the data: `provost_data`, `stats`, quarterdeck, Meridian Commander.
- **Evidence (tools):**
  - the tabular tools almost all show a column's type: Miller `describe`, `csvstat`, `qsv schema`, DuckDB `DESCRIBE`, sqlite-utils, clickhouse-local;
  - jc publishes a typed schema per parser; Genie validates each parse against one.
- **Evidence (provost):** docs/0001 promises "a clean, typed dataset". The engine types every cell (`extract/lib/_discovery.sh:1393`) and keeps only a percentage, then `stats` and `load_df` guess again, differently.
- **Demand:** jc #530, which asked for declarative type conversion (closed, not planned); sqlite-utils' `--type` override.
- **Size:** M. **Fits:** yes. The type is an addition to the store format, under PV-022's rules.

#### PV-041: `show --format`, `--capture latest`, and "Getting data out"

- **Who:** the general user scripting with `jq`, and CI jobs.
- **Evidence (tools):**
  - jc's JSON default;
  - every tabular tool in group 4 except q and xsv writes JSON or JSON Lines;
  - `qd show ds:NAME --format json` already exists in the toolchain;
  - provost's own `stats --format json` exists, so `show` is the odd one out.
- **Demand:** jc #622 (a TSV parser, so people could get TSV into JSON). Popularity is not counted.
- **Size:** S. **Fits:** yes. It also writes down the routes to SQL, metrics and a browser that the toolchain already has, so none of those has to come into provost.

### Runners-up: kept, not filed (the cap is five), best first

| # | Gap | Who does it | Where it would go |
|---|---|---|---|
| R1 | A keyed `diff`: rows matched on a key column, with changed cells shown and volatile columns (counters, timestamps) ignored. provost's `diff` lists the rows only A filed and only B filed, so a changed counter shows a whole row twice | Genie `diff` (default excludes), Dolt `diff --where --skinny`, DVC `metrics diff`; `qd diff --key --tolerance` does it for qd's runs | provost |
| R2 | Export a capture's provenance as W3C PROV or an RO-Crate Process Run Crate | PROV, RO-Crate, runcrate | provost (`export`), or quarterdeck's `qd report` (QD-021) |
| R3 | `provost rerun ID`: run a capture's recorded command again, then diff | DataLad `rerun`, Sumatra `repeat` | provost; a new verb (docs/0001 cut `process`/`reprocess`, which re-parsed rather than re-ran) |
| R4 | A strict mode in which every input line must be read or be decoration, for tool-specific parsers too (the gate exempts them today) | TextFSM `^. -> Error`, ntc's FAQ | provost (gate); with PV-006 |
| R5 | A cron and systemd-timer recipe for periodic capture, as docs, with `watch` staying cut | osquery scheduled queries | provost docs |
| R6 | Group lines by a shape fingerprint before `--llm` writes a template, and merge near-duplicate templates | Elastic Streams, LILAC, AdaParser | provost `--llm`; with PV-007 |
| R7 | Multi-line records in a template (a value carried down into the rows under it) | TextFSM `Filldown`, Fluent Bit multiline | PV-039's follow-up |
| R8 | A heartbeat during a long capture | Sacred | provost, after PV-038 |
| R9 | Record a fetched input's source URL and checksum | DVC `import-url`, git-annex `addurl` | provost manifest keys (PV-020's profile) |

### Changes to provost's shape: listed, not filed

Each would reverse docs/0001's "one workflow" (pipe in, detect, tidy, analyse), or add a long-running process.

| Gap | Who does it | What it reverses, and why not now |
|---|---|---|
| A SQL or query layer | DuckDB, q, trdsql, sqlite-utils `memory`, Dolt, osquery | Adds a second workflow. `qd show ds:NAME --where` filters already, and DuckDB reads the store's TSV directly (PV-041 documents both) |
| A web UI or JSON API | Datasette, MLflow | A server; `qd web` exists, localhost-only with a token beyond (QD-017) |
| An MCP server or agent skill | `mlr mcp`, qsv's MCP build | A server; new in Miller 6.20. Worth watching, not yet asked for |
| Periodic capture (`watch`) | osquery scheduled queries | Reverses the `watch` cut. A cron recipe (R5) gives the same without a daemon |
| Store sync between machines | DVC remotes, DataLad siblings, Dolt `push`/`pull`, lakeFS | Reverses the `push`/`pull` cut. `export`/`import` exist, and qd's `REF@STORE` reads a remote store in place (QD-002) |
| A filter mode that parses and prints but files nothing | jc | Reverses "every capture is a commit". PV-041's `show --capture latest --format json` gives the same output, with the capture kept |

### Belongs to another project: listed, not filed

| Gap | Who does it | Project |
|---|---|---|
| A metric's direction (higher or lower is better) and a suggested reference from history | MLflow #25377, ReFrame references | quarterdeck (`qd check`, `qd peers`; QD-028, QD-009) |
| Compare a run with its own last N days as a percentile (`compare:p95:30d`) | ReFrame | quarterdeck (QD-009, QD-030) |
| Read PV-040's column types once they exist | – | quarterdeck's store reader (QD-031) |
| Show PV-040's column types in the table browser | VisiData, Datasette | Meridian Commander (after MC-007, MC-008) |

### Already ticketed

Each came up in the survey, from at least one tool above, and is already a provost or quarterdeck ticket, done or open. None of it was filed again.

| Seen in | What it is | Where it already is |
|---|---|---|
| ReFrame, Ramble and Pavilion2 thresholds; Benchpark's success criteria | pass/fail against limits | QD-010 and QD-028 (`qd check`, waivers, tolerance); `provost stats --threshold` |
| MLflow and DVC run comparison; ReFrame `--performance-compare` | compare a metric across runs; find a slide | QD-009 (baselines, peers), QD-030 (change points); `qd compare`, `qd trend` and `qd changes` over `ds:NAME` |
| Prometheus textfile collector, OpenMetrics, Splunk | metrics and events out | QD-013 (`qd export --format hec`); `qd export --format openmetrics` over `ds:NAME` |
| Datasette, VisiData | browse a store's tables | `qd web`, `qd view`; MC-007 and MC-008 (Meridian's table browser) |
| q, Miller, nushell `where`, DuckDB `WHERE` | filter, sort and pick columns | `qd show ds:NAME --where ... --sort ... --cols ...` |
| DataLad siblings, DVC remotes, Dolt | another machine's store | QD-002 (`REF@STORE`); `provost export`/`import` |
| Sacred host info, XALT, ReFrame `--system` | where a run happened | PV-028 (`--env`) |
| DataLad run records, MLflow params, Sacred config | what a run was for, and on what | PV-020 (run manifest, `check-manifest`, `annotate`) |
| git-annex, DVC, lakeFS (large objects by reference) | inputs too big for git | PV-021 (oversize inputs kept by hash) |
| git-annex `fsck`, DVC checksums | integrity | PV-026 (`verify`) |
| Signed commits, SHA-256 objects | trust | PV-027 |
| lakeFS retention and GC, git-annex `drop` | retention | PV-029 (`prune`, `archive`) |
| Dolt and lakeFS format guarantees | a stable on-disk format | PV-022 (the store-format spec, `store check`) |
| jc and sqlite-utils as libraries | rows into Python | PV-031 (`provost_data.load`, `load_df`) |
| jc's size helpers; OpenMetrics unit suffixes; MLflow #25377 and Sacred #880 (units) | units | PV-032 (`--units base`) |
| Vector and Fluent Bit redaction; NetConan in Slurp'it | secrets out of the store | PV-033 (scrub at capture; `export --redact`) |
| ReFrame perflogs, JUnit XML, OSU, IOR | HPC benchmark outputs | PV-030 |
| ReFrame and pytest hooks | running from a test framework | PV-023 (recipes, `provost-wrap`) |
| The LLM log parsers' caching, repair and judging | the `--llm` loop | PV-008 (repair), PV-009 (judge), PV-019 (endpoints, offline), PV-007 (rating; blocked) |
| Drain3, Loghub, LILAC accuracy on unseen logs | generalisation on unseen output | PV-006 (`docs/0004`; the owner's pick between its options is still open) |
| An evidence package for a reviewer | a result handed over | QD-021 (`qd report`) |
| A store-level lock against concurrent writers | concurrent writes | PV-024 |

### Already in provost (dropped: no gap)

| Seen in | What | Where provost has it |
|---|---|---|
| AdaParser, LibreLog, LogBatcher | check an LLM-written template against its own input before caching | the gate, and "kept only when it passes" (`provost help advanced`, LLM TEMPLATES) |
| Drain3 #82, logparser #128 | freeze learned templates; match only | offline mode (PV-019), `llm-offline` |
| Vector `reroute_dropped`, Grok `_grokparsefailure` | failed parses kept, with the reason | `unsorted` and `provost triage` |
| LLM parser papers | calls and tokens per capture | `PROVOST_LLM_LOG` |
| jc `-r` | the raw strings as well as the processed values | the raw input is kept (`provost source`); `--units base` adds columns and keeps the originals |
| jc magic exit codes | the wrapped command's exit status | `provost run` exits with CMD's status |
| jc plug-in directory | user parsers that override the built-ins | `--plugin-dir` |
| jc `_jc_meta` | which parser, when, which command | `meta.tsv` per capture |
| jc's expansion guard for YAML and XML | a bomb input blows up memory | provost's `yaml.sh` and `xml.sh` are its own Bash and awk and call no library that expands aliases or entities (`grep -nE 'python3\|xmllint' extract/strategies/structured/{yaml,xml}.sh` finds nothing). Not tested with a bomb input |
| Genie `diff`, osquery differential results | what changed between two snapshots | `provost diff` (keyed diff is R1) |
| DVC experiments, ReFrame results DB | many runs kept and queryable | the git store; `log`, `show --at`, `search --at` |

## Side by side, for the top three

The neighbours could not be installed here (above). Each comparison puts provost's real output, run on 90e44bf, next to the neighbour's output as its own documentation or test fixtures show it.

### PV-037: `netstat -anp`

| provost, `provost run cat tests/corpus/inputs/netstat-anp.txt` | jc, from its own docs (<https://raw.githubusercontent.com/kellyjonbrazil/jc/master/docs/parsers/netstat.md>; its own example input, not this file) |
|---|---|
| strategy `pkg-config`, 3 fields: `name` = `tcp`, `description` = `0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      812/sshd` | `{"proto": "tcp", "recv_q": 0, "send_q": 0, "local_address": "0.0.0.0", "local_port": "ssh", "foreign_address": "0.0.0.0", "state": "LISTEN", "program_name": "sshd", "pid": 1186, ...}` |

provost's generic engine gets this input right (the corpus golden). It is the full engine's choice that is wrong.

### PV-038: Ctrl-C on a `ping`-like command

| provost | Sacred, from its docs (<https://sacred.readthedocs.io/en/stable/collected_information.html>) |
|---|---|
| `provost run --show ./fakeping.sh`, its process group sent SIGINT after three lines: exit 130; `provost log`: "no captures yet". The three lines and the summary the command printed on SIGINT are gone. SIGTERM: exit 143, the same | A run's record carries `status` (QUEUED, RUNNING, COMPLETED, FAILED, INTERRUPTED, TIMED_OUT), its captured output so far, and a heartbeat. An interrupted run is a record, not an absence |

### PV-039: Cisco `show version`

| provost, `provost --name show-version cisco_ios_show_version.raw` | ntc-templates' expected parse of the same file (<https://raw.githubusercontent.com/networktocode/ntc-templates/master/tests/cisco_ios/show_version/cisco_ios_show_version.yml>) |
|---|---|
| strategy `text-lines`, 32 rows, one column `A`: `Cisco IOS Software, Catalyst 4500 L3 Switch Software (cat4500e-ENTSERVICESK9-M), Version 12.2(54)SG1, ...`, `ROM: 12.2(44r)SG9`, ... | one record: `hostname: router1`, `version: 12.2(54)SG1`, `rommon: 12.2(44r)SG9`, `uptime: 2 years, 31 weeks, 6 days, 9 hours, 55 minutes`, `serial: [CAT1451S15C]`, `hardware: [WS-C4948E]`, `config_register: 0x2102`, ... (18 fields) |

The fixture's input: <https://raw.githubusercontent.com/networktocode/ntc-templates/master/tests/cisco_ios/show_version/cisco_ios_show_version.raw>. The template: <https://raw.githubusercontent.com/networktocode/ntc-templates/master/ntc_templates/templates/cisco_ios_show_version.textfsm>.

**To run the neighbours yourself** (they would not install here):

```bash
python3 -m venv /tmp/pv036 && /tmp/pv036/bin/pip install jc textfsm ntc-templates ttp duckdb
```

```bash
/tmp/pv036/bin/jc --netstat -p < tests/corpus/inputs/netstat-anp.txt
```

```bash
/tmp/pv036/bin/python -c "from ntc_templates.parse import parse_output; import sys, json; print(json.dumps(parse_output(platform='cisco_ios', command='show version', data=open(sys.argv[1]).read()), indent=1))" cisco_ios_show_version.raw
```

## Spot check

Twenty claims that the new tickets rest on were re-fetched on 2026-11-12, separately from the research passes. Each page was searched for the key phrase.

| # | Claim | Page | Status | Phrase found |
|---|---|---|---|---|
| 1 | jc's magic syntax | <https://raw.githubusercontent.com/kellyjonbrazil/jc/master/README.md> | 200 | "Magic" |
| 2 | ntc-templates takes no more requests | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/docs/user/faq.md> | 200 | "no longer considering additional template requests" |
| 3 | TextFSM `Filldown` | <https://raw.githubusercontent.com/wiki/google/textfsm/TextFSM.md> | 200 | "Filldown" |
| 4 | DataLad `--on-cmd-failure` | <https://raw.githubusercontent.com/datalad/datalad/maint/CHANGELOG.md> | 200 | "on-cmd-failure" |
| 5 | Sacred's TIMED_OUT status | <https://sacred.readthedocs.io/en/stable/collected_information.html> | 200 | "TIMED_OUT" |
| 6 | XALT's start record | <https://xalt.readthedocs.io/en/latest/115_xalt_internal_design.html> | 200 | "start record" |
| 7 | DuckDB `DESCRIBE` | <https://duckdb.org/docs/2.0/guides/meta/describe.html> | 200 | "DESCRIBE" |
| 8 | Miller's `summary` verb | <https://miller.readthedocs.io/en/latest/reference-verbs/> | 200 | "summary" |
| 9 | qsv `schema` | <https://raw.githubusercontent.com/dathere/qsv/master/README.md> | 200 | "schema" |
| 10 | Grok `timeout_millis` | <https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-grok> | 200 | "timeout_millis" |
| 11 | Fluent Bit's regex step cap | <https://docs.fluentbit.io/manual/data-pipeline/parsers/regular-expression> | 200 | "10,000,000" |
| 12 | `vector test` | <https://vector.dev/docs/reference/configuration/unit-tests/> | 200 | "vector test" |
| 13 | jc's typed `df` schema | <https://kellyjonbrazil.github.io/jc/docs/parsers/df> | 200 | "use_percent" |
| 14 | Slurm's SIGTERM, then SIGKILL | <https://slurm.schedmd.com/slurm.conf.html> | 200 | "between the SIGTERM and SIGKILL" |
| 15 | jc's `new-parser` label | <https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/kellyjonbrazil%2Fjc/issues?per_page=100&page=1> | 200 | "new-parser" |
| 16 | ntc's index names `show version` | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/ntc_templates/templates/index> | 200 | "cisco_ios_show_version.textfsm" |
| 17 | TTP templates look like the output | <https://raw.githubusercontent.com/dmulyalin/ttp/master/README.md> | 200 | "interface {{ interface }}". The Overview page read first (<https://ttp.readthedocs.io/en/latest/Overview.html>) does not show the braces in its HTML |
| 18 | `csvstat` reports types | <https://csvkit.readthedocs.io/en/latest/scripts/csvstat.html> | 200 | "type" |
| 19 | DataLad `rerun --since` | <https://docs.datalad.org/en/stable/generated/man/datalad-rerun.html> | 200 | "since" |
| 20 | ConvertFrom-String `-UpdateTemplate` | <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-string?view=powershell-5.1> | 200 | "UpdateTemplate" |

## Link check

Every URL in this page was fetched once on 2026-11-12 by a short script: `curl -sS -o /dev/null -w '%{http_code}' -L --max-time 25`, for each URL `grep -oE 'https?://...'` finds in this file. The category files attached to PV-036 carry their own status columns, about 600 URLs in all.

All 60 returned 200.

| Status | URL |
|---|---|
| 200 | <https://arxiv.org/html/2310.01796v3> |
| 200 | <https://csvkit.readthedocs.io/en/latest/> |
| 200 | <https://csvkit.readthedocs.io/en/latest/scripts/csvstat.html> |
| 200 | <https://docs.datalad.org/en/stable/generated/man/datalad-rerun.html> |
| 200 | <https://docs.datalad.org/en/stable/generated/man/datalad-run.html> |
| 200 | <https://docs.datasette.io/en/latest/changelog.html> |
| 200 | <https://docs.dolthub.com/cli-reference/cli> |
| 200 | <https://docs.fluentbit.io/manual/data-pipeline/parsers> |
| 200 | <https://docs.fluentbit.io/manual/data-pipeline/parsers/regular-expression> |
| 200 | <https://docs.lakefs.io/reference/cli/oss/> |
| 200 | <https://docs.reprozip.org/en/1.x/packing.html> |
| 200 | <https://duckdb.org/docs/2.0/data/csv/auto_detection.html> |
| 200 | <https://duckdb.org/docs/2.0/guides/meta/describe.html> |
| 200 | <https://dvc.org/doc/command-reference/metrics/show> |
| 200 | <https://git-annex.branchable.com/todo/compute_special_remote/> |
| 200 | <https://gitlab.com/slurpit.io/template_builder/-/raw/main/README.md> |
| 200 | <https://harelba.github.io/q/> |
| 200 | <https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/kellyjonbrazil%2Fjc/issues?per_page=100&page=1> |
| 200 | <https://kellyjonbrazil.github.io/jc/> |
| 200 | <https://kellyjonbrazil.github.io/jc/docs/parsers/df> |
| 200 | <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-string?view=powershell-5.1> |
| 200 | <https://miller.readthedocs.io/en/latest/> |
| 200 | <https://miller.readthedocs.io/en/latest/reference-verbs/> |
| 200 | <https://mlflow.org/docs/latest/ml/tracking/tracking-api/> |
| 200 | <https://ntc-templates.readthedocs.io/en/latest/> |
| 200 | <https://osquery.readthedocs.io/en/stable/introduction/sql/> |
| 200 | <https://pavilion2.readthedocs.io/en/latest/results/parse.html> |
| 200 | <https://prometheus.io/docs/specs/om/open_metrics_spec_2_0/> |
| 200 | <https://pubhub.devnetcloud.com/media/pyats-development-guide/docs/writeparser/writeparser.html> |
| 200 | <https://ramble.readthedocs.io/en/latest/_sources/dev_guides/application_dev_guide.rst.txt> |
| 200 | <https://raw.githubusercontent.com/BurntSushi/xsv/master/README.md> |
| 200 | <https://raw.githubusercontent.com/datalad/datalad/maint/CHANGELOG.md> |
| 200 | <https://raw.githubusercontent.com/dathere/qsv/master/README.md> |
| 200 | <https://raw.githubusercontent.com/dmulyalin/ttp/master/README.md> |
| 200 | <https://raw.githubusercontent.com/kellyjonbrazil/jc/master/README.md> |
| 200 | <https://raw.githubusercontent.com/kellyjonbrazil/jc/master/docs/parsers/netstat.md> |
| 200 | <https://raw.githubusercontent.com/ktbyers/netmiko/develop/EXAMPLES.md> |
| 200 | <https://raw.githubusercontent.com/logpai/Drain3/master/README.md> |
| 200 | <https://raw.githubusercontent.com/logpai/logparser/main/README.md> |
| 200 | <https://raw.githubusercontent.com/microsoft/prose/main/README.md> |
| 200 | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/docs/user/faq.md> |
| 200 | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/ntc_templates/templates/cisco_ios_show_version.textfsm> |
| 200 | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/ntc_templates/templates/index> |
| 200 | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/tests/cisco_ios/show_version/cisco_ios_show_version.raw> |
| 200 | <https://raw.githubusercontent.com/networktocode/ntc-templates/master/tests/cisco_ios/show_version/cisco_ios_show_version.yml> |
| 200 | <https://raw.githubusercontent.com/wiki/google/textfsm/TextFSM.md> |
| 200 | <https://reframe-hpc.readthedocs.io/en/stable/manpage.html> |
| 200 | <https://sacred.readthedocs.io/en/stable/collected_information.html> |
| 200 | <https://slurm.schedmd.com/slurm.conf.html> |
| 200 | <https://software.llnl.gov/benchpark/performance-dashboard.html> |
| 200 | <https://sqlite-utils.datasette.io/en/stable/cli.html> |
| 200 | <https://ttp.readthedocs.io/en/latest/Overview.html> |
| 200 | <https://vector.dev/docs/reference/configuration/unit-tests/> |
| 200 | <https://vector.dev/docs/reference/vrl/functions/> |
| 200 | <https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-grok> |
| 200 | <https://www.nushell.sh/commands/docs/detect_columns.html> |
| 200 | <https://www.researchobject.org/workflow-run-crate/> |
| 200 | <https://www.visidata.org/formats/> |
| 200 | <https://www.w3.org/TR/prov-dm/> |
| 200 | <https://xalt.readthedocs.io/en/latest/115_xalt_internal_design.html> |
