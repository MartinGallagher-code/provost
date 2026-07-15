# Review-workbook fix plan (ingested from gleancorpusreview_4.docx)

Reviewed: 195 pages (alphabetical, `7z` → `az-webapp-list`).
Marks: 140 OK · 31 Not quite · 23 Horrible · 1 note-only.
Actionable pages: 58 (the 4 OK-with-notes are "no parsing here" confirmations).

The reviewed slice is ~5% of the corpus; every cluster below is a generic
defect, so each fix round runs the full-corpus golden gate and is expected to
improve many unreviewed pages too.

## R1 — aligned-columns column fidelity (11 fixtures) — HIGHEST severity

Multi-word headers and values split on single spaces; in the worst case a
whole data column is dropped.

| fixture | note |
|---|---|
| akamai-property-list | "Property Name" split into two header cells; **property-name data column silently dropped**; "Web Delivery" etc. split |
| alertmanager-silences | "Ends At" split; date/time value split |
| aa-unconfined | columns C and D should be one column |
| acpi-battery-thermal | A and B one column; strip trailing colon |
| arp-an-incomplete | multi-word values split |
| apt-cache-stats | parenthetical "(1,764 k)" split |
| adb-shell-getprop | space split one value into two columns |
| adb-devices | "List of devices attached" (a sentence) captured as header |
| aria2c-progress | strip meaningless `[` `]` delimiters |
| arping | Horrible — didn't parse the summary shape at all |
| asv-continuous | Horrible |

Fix: when the header row contains 2+-space runs, slice **positionally** from
header windows (never re-split values on single spaces); sentence-shaped
header veto; punctuation chrome strip.

## R2 — headerless detection: first data row eaten as header (7)

| fixture | note |
|---|---|
| aws-ec2-output-text | "two rows, not headers and a row" (row 1 became sanitized header `10_0_1_5`) |
| aws-s3api-text-tabs | same |
| amixer-scontrols | csv fired on `'Master',0` — row 1 became header |
| at-queue / atq | Horrible; also split `Thu Jul 10 … a deploy` into date / queue / job |
| anacron-tab | command vs argument as separate columns |
| aws-ecs-list-clusters | Horrible — uniform `arn:…:cluster/name` rows deserve colon-split fields |

Fix: value-shaped row-1 (digits/dots/ARNs/quoted) ⇒ headerless for csv/tsv;
uniform-colon-count rows ⇒ colon-delimited candidate; date-block aware
splitting for at/atq.

## R3 — chrome rows leaking into data (10)

| fixture | note |
|---|---|
| amass-intel | `$ cmd` prompt line defeated table detection entirely |
| aureport | banner + `====` rules + `# hdr` line → mush (the `#` line IS the header) |
| aureport-login | same family |
| ansible-galaxy-list | `# /path` comment emitted as data row 1 |
| apk-info-installed | prose row 1 kept |
| apptainer-inspect | rows 1 and 5 are chrome |
| atlantis-status | row 4 is not information |
| ansible-playbook-recap | `PLAY RECAP ****` row kept |
| aide-check | prose line 1 kept (also R5) |
| apachebench | row 7 junk (also R5) |

Fix: pre-strip leading `$ command` prompt lines; strip/skip `#` comment rows
(or promote `# a b c` to header when token count matches data); `====` rule
lines; `N.` row-number prefixes; sentence-row veto inside tables.

## R4 — hierarchy/tree output shape unusable (9, nearly all Horrible)

alternatives_display, ansible-version, apachectl-S, apk-policy, aplay-list,
apt-cache-policy (dotted-path column names like
`curl.***_7.81.0-1ubuntu1.14_500.500_http`), apk-info-a (multiline kv),
asdf-list (parent + indented children → 3 cols: tool/version/current),
ansible-inventory-graph (depth-0 items are group values, children are rows).

Fix: replace indented-hierarchy's dotted-path wide explosion with tidy leaf
rows + ancestor columns (the kv-under-group shape). tree-view: emit
`group | member` rows.

## R5 — kv snapshots should pivot to ONE wide row (6 + convention)

aide-check, apachebench, airflow-variables-list, ansible-v, R-sessioninfo
(also missing "R version" + base packages), age-keygen (`# key: value`
comments → one row: created / public_key / secret_key).

Reviewer's rule: a single-entity kv report is one record → one row, keys as
columns. Corpus-wide convention change for the `key-value`/`colons` parsers —
large golden churn, so it ships as its own round with a full flip audit.
(Caveat honored: two-column outputs whose rows are *records* — e.g.
ansible-galaxy-list collections — stay one-row-per-record; only field-name
shaped left columns pivot.)

## R6 — decoration & delimiter handling (6)

| fixture | note |
|---|---|
| apk-list | `{origin} (license) [installed]` → own columns; prometheus-query misroute produced `label.*` explosion |
| apache2ctl-modules | `(static)`/`(shared)` → own column |
| alias-list | split on first `=` (quote-aware): alias / command |
| atop | `\|` is the delimiter, not part of values |
| artillery-report | dot-leader values `..... 120488` need leader strip; block merge |
| acpi-battery-thermal | trailing-colon strip (with R1) |

## R7 — charts/TUI best-effort or acknowledged-hard (5)

asciichart-boxed / asciichart-series-frame ("the numbers are meaningful, not
the lines") → emit title + y-axis series; asciigraph-plot; amdgpu-top (TUI
dashboard); asciidoctor-version (reviewer unsure themselves — leave ⏳).

## Sequencing

R1 → R2 → R3 are engine/table-core fixes with the broadest corpus-wide
payoff and fix the observed data loss. R4 and R5 are output-shape redesigns
(bigger golden churn, own rounds). R6 mop-up. R7 last, best-effort.
Each round: implement → full golden gate → audit every flip → freeze →
CI suites → docs → commit/push.

---

# Round 2 review ingest (2026-07-15, reviewed 7z-benchmark → cabal-list)

322 pages marked: 264 OK · 21 Not quite · 37 Horrible. Raw marks:
`docs/review-marks-2026-07-15-round2.tsv`.

## Validation of R1–R3

**32 fixtures the reviewer flagged in round 1 are now OK** — aa-unconfined,
acpi-battery-thermal, adb-shell-getprop, age-keygen, airflow-variables-list,
akamai-property-list, alertmanager-silences, alternatives_display,
amass-intel, amixer-scontrols, anacron-tab, ansible-galaxy-list,
ansible-playbook-recap, apache2ctl-modules, apk-info-installed,
apptainer-inspect, apt-cache-stats, aptitude-search, aria2c-progress,
arp-an-incomplete, arping, asdf-list, asv-continuous, at-queue, atac-env,
atlantis-status, atq, aureport, aureport-login, aws-ec2-output-text,
aws-ecs-list-clusters, aws-s3api-text-tabs.

**Zero regressions I caused.** 7 fixtures went OK→flagged (7z-benchmark,
airflow-dags-list, amtool-cluster-show, apt-cache-show-vim, atuin-stats,
autocannon-run, avro-tools-getschema) but NONE appears in any R1–R3 flip
list — their output is byte-identical to round 1. The reviewer's standards
sharpened (pipes-are-delimiters, lists-should-be-rows); these are new
requirements, folded into the buckets below.

## Refined buckets (remaining ~58 actionable)

**R4 — hierarchy / tree redesign** (leaf rows + ancestor cols):
ansible-version, apachectl-S, apk-policy, aplay-list, apt-cache-policy,
ansible-inventory-graph ("misses the boat"), bombardier-run, brew-uses-tree,
broot-summary, atuin-stats (indented top + a *table at the bottom* both
need capturing).

**R5 — kv / list → correct row shape** (the biggest round; sharpened):
- 2-column kv → ONE row: aide-check ("Summary should not be a row… single
  row, only two columns"), R-sessioninfo (also *missing the R version*).
- list-valued field → one row per element, outer fields repeated:
  amtool-cluster-show (Peers append to Name), avro-tools-getschema (2 rows
  under the `fields` envelope, outer type/name repeated).
- sparse wide → collapse: apk-list ("so many columns with one value — make
  a single column after the value column holding all remaining values").
- multiline kv (key on the line ABOVE its value) + don't split URLs:
  apk-info-a.
- embedded bottom table: apachebench ("bottom readout is a table — expand
  into columns with the given headers"), atuin-stats.

**R6 — delimiters / decoration** (pipes now a firm rule):
atop / airflow-dags-list / 7z-benchmark ("pipes are delimiters, remove
them"), artillery-report (dot-leaders are delimiters), alias-list ("horrid"
— `=` split), ansible-v (square brackets + space → just A/B), autocannon-run
(first line is data, not header), bundle-outdated (missed rows),
apt-get-download-progress, bat-color-numbers.

**R7 — charts / TUI values-not-graphics**:
asciichart-boxed, asciichart-series-frame, asciigraph-plot ("extract the
values, not the graphics"), amdgpu-top; asciidoctor-version (reviewer unsure).

**New b*/c* to trace (no note — inspect):** bareos-status-storage,
bash-version-full, bat-config, bcc-funccount, biosdecode, bird-show-route,
birdc-show-memory, blkid-sparse-fields, bloop-projects, bluetoothctl-devices,
bonnie-plus, borg-create-progress, borg-prune-list, bowtie2-align-summary,
bpftool-prog-show, bpftrace-histogram, bridge-fdb, bridge-link,
btrfs-filesystem-show, bun-install-summary, bwa-index-log, bwa-mem-log,
cabal-freeze. Plus adb-devices (device:/model:/device: → columns).
