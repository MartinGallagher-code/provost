# glean — Changelog

## 2026-07-18 — round-3 specifics: apk-list license, apache2ctl module type

Two contained columnar-spec fixes from the round-3 review notes:

- `delimited/columnar-specs.sh` apache2ctl-modules: was one `@line` column
  (`core_module (static)`); now two — `module` and `type@unwrap` (static /
  shared as its own column). (reviewer: "(static)/(shared) own column")
- `delimited/columnar-specs.sh` apk-list (NEW spec): `pkg arch {origin}
  (license) [status]` now maps to package / arch / origin / license / status
  with the origin/license/status brackets unwrapped. The `absorb` sink on the
  license column keeps a space-bearing licence whole in ONE column
  (`(MPL-2.0 AND MIT)` → `MPL-2.0_AND_MIT`, underscore-joined by the absorb
  mechanism) instead of splitting it across two columns as aligned-columns
  did. (reviewer: "keep `(MPL-2.0 AND MIT)` whole")

Goldens re-frozen (both already `table` in the manifest; mincols tightened).
Gate 3444/0, extract 62/62. Zero regressions.

aptitude-search (reviewer wanted 4 columns) stays on its `text-lines` hint:
its fixed-width state prefix (`i  `/`i A`) plus ` - ` description separator
is genuinely tool-specific and doesn't fit the generic columnar engines
without a fragile bespoke — left as acknowledged.

## 2026-07-18 — reviewer round 6 (R6, cont.): alias / dot-leader / blank-cell rows

Continued R6 delimiter/decoration cleanup — three more of the reviewer's
firmest asks landed, each a format-level generic parser or a contained fix:

- `delimited/alias-list.sh` (NEW, priority 14): shell `alias NAME='CMD'`
  listings now emit a clean `name`/`command` table — the `alias ` keyword
  and the surrounding quotes are stripped, the command kept whole. Detection
  is exact (EVERY non-empty line is `alias <name>=<value>`), zero blast
  radius. Was aligned-columns shredding `ls -alF` across columns and keeping
  a redundant `alias` column A. (reviewer: "horrid — `=` split")
- `delimited/dot-leader-kv.sh` (NEW, priority 15): `label: ....... value`
  reports (artillery and similar) where a run of dot leaders separates key
  from value now emit one `key`/`value` row per metric, leaders stripped.
  Nested section metrics (`min`/`max`/`mean` under `http.response_time:`)
  are captured; the valueless section header is dropped. Detection requires
  ≥3 dot-leader lines. (reviewer: "dot-leaders are delimiters")
- `delimited/embedded-table.sh`: the detection window now admits a row with
  FEWER tokens than the header when its tokens positionally align to
  distinct header columns — a genuine blank interior cell. bundle-outdated
  (sidekiq's empty `Requested`, rubocop's `development, test`) now yields
  all 5 rows instead of 3. The first data row must still be full-width so a
  multi-word-label header (spec-cpu's doubled `Ref. Run Time Rate`, which
  makes every row "short") stays with aligned-columns — verified no flip.

Files: `extract/strategies/delimited/{alias-list,dot-leader-kv,embedded-table}.sh`,
new samples under `extract/strategies/delimited/samples/{alias-list,dot-leader-kv}/`,
goldens `tests/corpus/expected/{alias-list,artillery-report,bundle-outdated}.tsv`,
manifest `tests/corpus/expected.tsv` (alias-list/artillery-report text→table).
Gate 3444/0, extract 62/62, smoke 49/0, melt 10/0. Zero regressions.

- `delimited/pipe-cells.sh` (NEW, priority 31): atop-style monitor rows —
  a short row LABEL followed by `|`-separated `key value` cells — now tidy
  to a long `group`/`key`/`value` table with the pipes removed (atop:
  6 groups → 28 rows). Detection is tight (uppercase-led label OUTSIDE the
  pipes, trailing pipe, ≥2 two-token cells per row), so it poaches no real
  pipe/box table — full-corpus gate flipped atop and nothing else. A lone
  device-name cell (DSK's `sda`) is skipped; empty cells (SWP's gap) too.
  Was aligned-columns keeping the `|` glyphs as their own columns.
  (reviewer: "pipes are delimiters, remove them")

Still open in R6 (each niche, best-effort): ansible-v (bracket+space → A/B),
7z-benchmark (dual-table with a `|` gutter), autocannon-run (box-drawing
frame).

## 2026-07-15 — reviewer round 6 (R6, partial): pipe-table equals rule

Sixth review-workbook round (round-2 marks). The reviewer's firmest R6 ask
— "pipes are delimiters, remove them from the output." First landed fix:

- `delimited/psql-table.sh`: the box-separator now recognises an EQUALS
  rule (`====+====+====`) alongside the dash rule, so airflow dags list
  (`dag_id | filepath | owner | paused` over a `===+===` rule) parses as a
  clean 4-column pipe table (pipes gone) instead of vertical-line keeping
  the `|` glyphs as their own columns. 1 flip, 0 collateral.

Still open in R6 (each a distinct format, deferred): atop (`PRC | sys 1.42s
| …` pipe-delimited kv rows), alias-list (`alias NAME='VALUE'` — `=` split,
drop the `alias` keyword), artillery-report (dot-leader `……` delimiters),
ansible-v (bracket + space → A/B), autocannon-run (first line is data),
bundle-outdated (missed rows). Gate 3443/0.

## 2026-07-15 — reviewer round 5 (R5, partial): kv misroutes + multiline values

Fifth review-workbook round (round-2 marks). R5's headline — single-entity
kv → one wide row — is a large convention change; this pass ships the
contained, unambiguous fixes and DEFERS the sweeping pivot (it needs the
kv-under-group grouping treatment, not a blunt row-drop: sensters `Core 0:`
/ docker `Client:` are group labels that disambiguate repeated keys).

- `structured/prometheus-query.sh`: detection tightened to the real
  `name{key="value"} 123.45` form — braces must hold a `="` assignment and
  the line end in a bare number. A package list whose `{origin}` braces have
  no `=` (apk list → aligned-columns per-package rows) and a profiling
  table (parca-query → clean 5-col aligned table) no longer false-match.
- `structured/key-value.sh`: a bare label (`webpage:`) folds the
  below-the-line value VERBATIM — its own colons are data, not a new key
  (`https://busybox.net/`, `so:libc…`, openssl's multiline Serial Number
  `0a:1b:…`). Fixes apk info -a (URLs no longer split into `https:` keys)
  and collapses bogus hex-fragment keys across the openssl / x509 / crl /
  cryptsetup / numactl family into their parent labels.

Closes reviewer fixtures apk-list, apk-info-a; upgrades the openssl/x509
family + parca-query. Gate 3443 passed, 0 failed, 263 ⏳, 0 deletions
(14 goldens re-frozen; parca-query manifest 5→4 rows; vmagent-targets
demoted to ⏳ — labeled-inline-kv splits its endpoint URLs, needs a
containment pass). Suites: smoke 49/0, melt 10/0, extract all green.

DEFERRED to a dedicated kv-pivot round: aide-check (single row + drop
Summary), R-sessioninfo (missing R version), apachebench / atuin-stats
(embedded bottom table), amtool-cluster-show / avro (list-value → rows),
ansible-version (header line as field).

## 2026-07-15 — reviewer round 4 (R4): tree-view ancestor + value columns

Fourth review-workbook round (round-2 marks; plan
docs/0002-review-fix-plan.md). tree-view emitted a flat depth/name dump —
the reviewer wanted the hierarchy legible ("the things one level up are the
context"). Redesigned `structured/tree-view.sh`:

- **parent column** — a depth-keyed ancestor stack gives every node its
  immediate parent, turning the dump into a navigable parent -> child edge
  list (brew-uses-tree, broot-summary, ansible-inventory-graph group ->
  member, npm/pstree/systemd-cgls/gradle/terraform all readable).
- **value column** — a trailing metric after a 2+-space gap
  (broot's `main.rs   1.2 kB`, exa's file sizes, pstree's `2*[{proc}]`
  counts) splits off the name instead of welding to it.
- **depth generalized** to variable-width vertical cells (`│  `, `│   `,
  ASCII `|  `) so 2-space-indented trees (broot) get correct depths.
- **numbered-hop decline** — `mtr` / `traceroute` draw `1.|-- host …`
  whose `|--` is a hop connector, not tree indentation; tree-view now
  declines when most node lines carry an `N.|--` prefix, so those columnar
  reports fall to aligned-columns instead of a false tree (mtr / mtr-report
  correctly stay ⏳ rather than become garbage goldens).

Audit: 47 flips, all tree fixtures gaining parent/value — zero node-count
changes (depth rewrite lossless), the 6 name changes all legitimate
value-splits. Gate 3443 passed, 0 failed, 263 ⏳, 0 deletions. Extract
self-test golden (tree-view) updated. Suites: smoke 49/0, melt 10/0,
extract 173/0.

Deferred to R5 (they are kv, not trees, and want the header line as a
field): ansible-version / ansible-v, apk-policy, apt-cache-policy,
aplay-list, apachectl-S.

## 2026-07-15 — reviewer round 3 (R3): chrome rows — prompts, comments, banners, titles

Third review-workbook round (plan: docs/0002-review-fix-plan.md). The
cluster: non-data lines a capture drags in — shell-prompt echoes, comment
banners, rule lines, section banners, prose titles — leaking into the
dataset (amass-intel's `$ amass intel …` prompt defeated table detection
entirely; aureport's `# date time acct …` comment IS the header).

- Engine (`extract/envoy-extract`): leading-chrome strip — `$ command`
  prompt echoes, `WARNING:`/`ERROR:`/`NOTICE:` stderr noise, `NAME ****`
  banner rules, and prose-title first lines (`List of devices attached`),
  each leading-only over >=2 remaining lines; interspersed `== word ==`
  section banners dropped anywhere (apptainer's `== labels ==` /
  `== runscript ==`) — exactly-two-equals so `=== SET ===` /
  `====== JOB MAP ======` GROUP-LABEL banners the embedded-table /
  kv-under-group parsers consume stay intact.
- `delimited/aligned-columns.sh` (`_ac_body`): audit-report chrome, gated
  on a `====` rule — drops the rules and the title above the first rule,
  promotes a lone `# col col …` comment to the real header, strips
  sequential `N.` row-number prefixes (aureport).
- `delimited/vertical-line.sh`: defers the `# header` + `====` audit shape
  to aligned-columns.
- `delimited/line-records.sh`: strips a leading `# /path` location banner
  (ansible-galaxy's collection root) — narrowed to paths so `# title`
  section lines a parser uses as a header survive; go-mod-why's bespoke
  `# module` markers untouched (strategy-local).
- `structured/inline-kv.sh`: `host : k=v` two-token name form
  (ansible-playbook-recap → one row per host).
- NEW `delimited/ping-report.sh` (priority 35): ping/ping6/arping reply
  streams — one row per reply (bytes / from / optional ip / a column per
  `k=v` with the trailing bare unit folded in), banner and
  `--- … statistics ---` footer dropped.

Closes reviewer fixtures amass-intel, aureport, aureport-login,
ansible-galaxy-list, apk-info-installed, apptainer-inspect (banners),
ansible-playbook-recap, arping, adb-devices (title row); ~26 collateral
`$`-prompt improvements across security tooling (checksec, subfinder,
yara, hashcat, gitleaks, gobuster, trufflehog, openssl/cosign/step/rekor).
Gate: 3443 passed, 0 failed, 263 ⏳, 0 deletions (35 goldens re-frozen +
4 new). 11 manifests recalibrated from pre-strip dims. Suites: smoke 49/0,
melt 10/0, extract all green.

Files: extract/envoy-extract, extract/strategies/delimited/{aligned-columns,
vertical-line,line-records,ping-report}.sh,
extract/strategies/structured/inline-kv.sh, extract/samples/ping-report/,
tests/corpus/expected/*, tests/corpus/expected.tsv.

## 2026-07-15 — reviewer round 2 (R2): headerless detection — row 1 is data, not a header

Second review-workbook round (plan: docs/0002-review-fix-plan.md). The
cluster: delimited parsers eating the first DATA row as a header
(`i-0abc123 / t3.micro / 10.0.1.5` became sanitized column names).

- `structured/csv.sh`: TAB-dominant input declines to tsv (aws `--output
  text` carries commas *inside* values — "my-logs, prod"); DUAL-ROW SHAPE
  test — a header must show label-over-value contrast somewhere, so when
  every column has the same shape in rows 1-2 and at least one is
  value-shaped, row 1 is data (amixer's `'Master',0`, tshark's quoted
  fields, ycsb's `[OVERALL]` rows, logcli timestamps — all previously
  header-eaten).
- `structured/tsv.sh`: cell-split pre-pass — a ctime-style stamp opening
  every row's cell with a uniform token tail becomes stamp + per-token
  columns (`at`/`atq`: job | datetime | queue | user); a constant
  >=2-token prefix with an ARGUMENT-shaped remainder (path/flag/number)
  splits into prefix + rest (anacrontab's `nice run-parts` |
  `/etc/cron.daily`; bcftools' "number of samples:" label stays whole).
- `delimited/line-records.sh`: space-free lines with a uniform colon count
  >=2 split on colons (ECS/SNS ARNs → arn|aws|service|region|account|name,
  bpftrace probes → type|provider|name); URLs and non-alpha-led lines
  keep theirs.

Closes reviewer fixtures aws-ec2-output-text, aws-s3api-text-tabs,
amixer-scontrols, at-queue, atq, anacron-tab, aws-ecs-list-clusters, plus
6 collateral upgrades (aws-sns-list-topics, bpftrace-l, logcli-query,
pytest-collect-color, tshark-fields-quoted, ycsb-run — three of which had
their first data row baked into golden headers) and one NEW gap closed:
exo-perf-stat-x-csv. Gate: 3439 passed, 0 failed, 267 ⏳, 0 deletions
(13 goldens re-frozen + 1 new). Suites: smoke 49/0, melt 10/0, extract
62/62, analyze all green. COVERAGE.md headline regen batched with R3.

Files: extract/strategies/structured/csv.sh,
extract/strategies/structured/tsv.sh,
extract/strategies/delimited/line-records.sh, tests/corpus/expected/*.

## 2026-07-15 — reviewer round 1 (R1): column fidelity across the table core

First fix round driven by the human review workbook
(docs/0002-review-fix-plan.md, marks in docs/review-marks-2026-07-15.tsv;
195 pages reviewed, 58 actionable, clustered into rounds R1–R7). R1 takes
the worst cluster: aligned-columns splitting multi-word headers/values on
single spaces — in akamai-property-list it silently DROPPED a whole data
column (duplicate `Property` keys collided in the melt).

`extract/strategies/delimited/aligned-columns.sh`:
- EQUAL-token-count positional gate: a table whose header token count equals
  its data rows' can still hide multi-word labels AND multi-word values
  ("Property Name … Group" over "www.example.com … Web Delivery"); it now
  reaches the positional grid when the header's 2-space segmentation
  collapses below its token count AND the data segments the same way the
  header does (data segmenting more finely — pam-tally2, ip6tables — means
  the single-spaced header under-segments and tokenization is right).
- SUB-COLUMN refinement in `_ac_assign` (buffered): a 2-space window holding
  k>=2 header tokens splits into k sub-columns only when every header token
  edge-aligns (start OR end, ±1) with the data in >=60% of rows — so
  swapon's "SIZE USED PRIO", wipefs, vgs, smartctl, systemctl ACTIVE/SUB,
  lsblk, xz-list, bconsole Type/Level all split, while "Ends At",
  "Property Name" (one value below) stay one column. Eight vetoes earned
  from the 89-flip audit: max-window-tokens >= k (a lone "webapp" under
  "Job ID" must never split — melt collision drops data), alnum-only edge
  witnesses (docker-stats' "/" false witness), per-ordinal denominators
  (lsblk's sparse MOUNTPOINT), bridge tokens spanning a sub-label start
  (ss-e "Peer Address:Port"), duplicate sub-labels across windows
  (kube-capacity "CPU REQUESTS / CPU LIMITS"), bare separators BETWEEN
  window values (ctop's "12M / 4M" — but a trailing bare "/" mountpoint is
  a value, not a separator), plus the data-segmentation gate above.
- Char-accurate bash grid (`_ac_grid_mb`) for lightly-non-ASCII blocks —
  the awk grid measures bytes, so `412±2ns` (asv-continuous) drifted a
  window right; narrow 2-byte chars only (emoji/CJK/box-drawing/soft-hyphen/
  combining marks keep the awk path), with a ragged-alignment label-overlap
  fallback (asv's unnamed sign + benchmark-name columns become letters).
- PROSE-header veto: `Titleword lower lower …` with a stopword over
  mismatched-width data is a title ("List of devices attached" — adb),
  not labels; "Host cpu mem disk net" (no stopword) stays a header.
- Multi-word colon-label decline: blocks where EVERY line is a distinct
  `Two words: value` go to `colons` (apt-cache-stats, acpi, bazel-version,
  kubectl version, rabbitmqctl, rsync-stats, deno-info, lsusb-style
  same-digit-template labels exempted — those are table rows).
- HEADERLESS trailing phrase-merge: the last column pair holding the same
  two lowercase words on every row is one phrase ("not confined" —
  aa-unconfined); trailing-only so ls -l's owner/group stay columns.
- SCAFFOLD split for ragged headerless sentence-records: constant function
  words (at/on/from/via/dev/to/of/by/for) once per row in the same order
  become field anchors — arp -an's `<incomplete>` rows align, MAC+"[ether]"
  stays one cell.

`extract/strategies/delimited/colons.sh`: bracketed kv unwrap
(`[ro.product.model]: [Pixel 8]` → key ro.product.model, value "Pixel 8" —
adb-shell-getprop).

`extract/strategies/structured/inline-kv.sh`: strict colon-pair flavor
(`CN:8 DL:12MiB ETA:1m14s`, one colon, alpha label, same label set on every
line) with positional letters for the unlabeled leading run, plus gauge-line
outer-bracket unwrap — aria2c-progress becomes A/B/CN/DL/ETA columns.

Corpus: 47 goldens re-frozen, every flip audited (many fixed silently
SHIFTED goldens: nerdctl PLATFORM, flarectl Name, exo-kubectl NODE,
talosctl, vercel, doctl, kube-capacity values). Six manifests re-calibrated
from shredded-column counts to the honest merged columns (akamai 9→8c,
doctl 11→9c, pscale-db 9→8c, vercel-domains 8→7c, vercel-projects 8→5c,
adb-devices 2→3r until R3 strips its title row). Gate: 3438 passed,
0 failed, 0 deleted goldens. Suites: smoke 49/0, melt 10/0, extract 62/62,
analyze 8/8.

Files: extract/strategies/delimited/aligned-columns.sh,
extract/strategies/delimited/colons.sh,
extract/strategies/structured/inline-kv.sh, tests/corpus/expected.tsv,
tests/corpus/expected/*.tsv (47), docs/0002-review-fix-plan.md,
docs/review-marks-2026-07-15.tsv, COVERAGE.md, tests/corpus/review-output/.

## 2026-07-14 — kv-under-group parser: the kv carry-down shape

New generic parser `strategies/structured/kv-under-group.sh` (priority 10 —
it must outrank `key-value` at 11, which flattens these into one record with
colliding keys) for the long-documented kv-CARRY-DOWN frontier that
grouped-rows explicitly cannot take (its leaves must be a table) and
pivot-stats cannot either (no header/values pivot): a GROUP label over an
INDENTED run of `key: value` / `KEY value` leaves, the same keys repeating
group after group (ethtool per-queue stats, nvme per-namespace stats,
blkid-style per-device attribute runs). One wide row per leaf group —
`name` = the label, one column per key, the nearest OUTER level (nvme's
`Controller nvme0 …`, ethtool's NIC title) carried as a `group` column.

Sitting at priority 10 demanded the strictest containment of any round; the
detection signature plus seven vetoes, each earned from a real gate victim:
- THE signature: >=2 groups with >=2 leaves each AND >=2 leaf keys repeated
  across DIFFERENT groups — a single-record kv snapshot never has that;
- `- ` list items or `&anchor`/`*alias` tokens → YAML's (kubectl config
  view, helm values, YAML anchors);
- `{`/`}` block syntax → config files (named.conf);
- >20% of leaves with a value whose 1st/2nd token ends ':' → the real keys
  are MULTI-WORD (`API version: 1.43`) and this model would truncate them
  (docker version, dotnet --info, resolvectl);
- a key repeated WITHIN one group (ifconfig's two RX lines) → not kv keys;
- bare (colon-less) leaf keys must be ALL-CAPS or lowercase_snake — a
  Titlecase word is the first word of a multi-word key (geekbench);
- >=70% of bare leaves sharing a uniform >=3-token count → the leaves are
  TABLE rows under a group header (lsof per-process) — grouped-rows' shape;
- group labels must bear an alphanumeric (netlify's `────` card separators).

Closes nst-ethtool-queue-stats, nst-nvme-per-namespace-stats,
nst-blkid-per-device-nested (manifests re-calibrated to the corpus's
one-row-per-record wide convention: 8r3c → 4r4c, 6r4c → 3r5c, 6r3c → 3r4c —
they had been authored for a long form) and upgrades five covered fixtures
whose old goldens embedded real losses: conan-info (dotted-key single row →
row per package), lshw-memory (duplicate-key collision dropped columns),
nst-btrfs-device-per-disk (A/B token pairs → real stat columns; manifest
6r3c → 2r5c wide), nst-firewall-zones-blocks (the `internal` zone had been
LOST entirely), nst-rsync-per-dir-stats (rows gain their directory name).
Golden audit: 17 first-cut flips → 7 → final 5, all improvements. Gates:
golden 3430/0 pre-freeze; extract 62/62 (new sample + baseline); smoke 49/0;
melt 10/0.

## 2026-07-14 — embedded-table parser: the report shape (nst-* round)

New generic parser `strategies/delimited/embedded-table.sh` (priority 37,
ahead of block-records) for the REPORT shape: prose/kv preamble, ONE dominant
whitespace-aligned table, optional footnotes — smartctl -a, benchmark
write-ups, backup job reports, trivy scans. Finds the largest table window
(labelly header + >=3 digit-bearing consistent rows) and extracts only it via
positional slicing with midpoint column boundaries and an overflow snap (a
boundary landing inside a token slides right, so `zstd-19` under a 4-char
`Tool` label and `Reallocated_Sector_Ct` past its header span stay whole);
inner alignment padding collapses to one space.

Containment took five gate rounds (31 → 11 → 17 → 5 flips) and is where the
value lives:
- chrome must include a PROSE line — >=3 tokens, >=2 alphanumeric-bearing,
  digit-free, no kv colon, no box-drawing glyphs. An all-kv report
  (mdadm --detail, nvidia-smi -q, kubectl describe) is fully representable by
  the kv-capable parsers — taking only its table would LOSE the fields;
- a chrome line token-identical to the window header (faillock's per-user
  sections, ps/top page reprints) or a token-SUBSET of it (yugabyte's
  narrower sibling section header) means a multi-section table — decline,
  aligned-columns/grouped-rows collect those in full;
- the window must open a section (preceded by blank/start/narrower line —
  banner chrome like `=== SECTION ===` excepted) and close one (followed by
  blank/EOF/narrower line) — a truncated window inside a bigger table
  (prlimit's digit-free `unlimited` rows, `worker stopped - -`) declines;
- header tokens must start alphanumeric-or-bracket (a diff hunk's `+use`
  line is not a header) and data rows never end in '.' (prose sentences).

Closes 5 of the 6 report-shaped nst-* gaps (nst-benchmark-report-footnotes,
nst-report-preamble-table-footnotes, nst-kv-table-kv-backup-report,
nst-pg-report-mixed, nst-smartctl-info-attrs-selftest;
nst-mdadm-detail-devices stays ⏳ — all-kv chrome, needs kv+table dual
emission) plus NINE bonus gaps the same shape covers: cargo-audit,
dotnet-list-package, kubectl-get-all, nmap_sv, rocm-smi, sfdisk-l, and three
cmb spinner/clear-screen tables. Upgrades trivy ×4 (real vulnerability
columns instead of the command line shredded into token rows) and
nodetool-netstats (the Pool table instead of `Mode:/NORMAL` as a header) —
whose manifests were re-calibrated (they had been tuned to the old mush:
trivy-fs 7r7c → 4r5c, config/repo/sbom 6r → 3r4c, nodetool 9r4c → 3r6c).
Gates: golden 0 failed post-freeze; extract 62/62 (new sample + baseline);
smoke 49/0; melt 10/0.

## 2026-07-14 — encoding round: VT-in-cell, control bytes, fullwidth digits, ZWSP, lowercase headers

Engine-normalization refinements plus one aligned-columns promotion rule,
closing 6 of the 8 enc-* gaps (and the noted fullwidth-colon follow-up):

- **VT is context-sensitive.** The line-terminator normalization mapped VT
  unconditionally to `\n`, so a stray vertical tab INSIDE a cell
  (`disk\vfailure`) split its row in two. When the input already has real
  `\n` lines, VT now becomes a SPACE; only in a `\n`-less capture (VT as the
  sole separator — the adversarial breaker the block was built for) does it
  stay a line break. FF is untouched (page breaks).
- **BEL/BS stripped** (gated; after the ANSI strip, since BEL terminates OSC
  sequences) — decoration/erase intent, never data.
- **ZWSP (U+200B) deleted** — invisible, corrupts field names and comparisons.
  ZWNJ/ZWJ stay: Farsi half-spaces and emoji family joins are real content.
- **Fullwidth digits U+FF10–FF19 and colon U+FF1A → ASCII** — CJK tables get
  numeric-contrast header detection and clean `key: value` splits
  (`uni-kv-fullwidth`, the follow-up noted since the Unicode-spaces round).
- **Lowercase headers with data-side styling contrast** (aligned-columns):
  the all-text promotion demanded a Titlecase/camelCase header token, so
  `username fullname active` / `household members flag` / `key value` stayed
  headerless. A lowercase wordy header now promotes when EVERY data row
  carries a token the header lacks — Titlecase (`Alice Anders`) or fully
  non-ASCII (emoji, Farsi) — while a lowercase name grid (sqlite .tables)
  has neither and stays data.

Closes enc-control-mix, enc-vtab-in-cell, enc-fullwidth-digits,
enc-zwsp-header, enc-zwj-emoji, enc-zwnj-farsi. Deliberately left ⏳:
enc-formfeed-report (page banners differing only in page number — needs
banner-modulo-digits logic) and enc-two-space-in-value (a 2-space run inside
a value is indistinguishable from a column gap). Golden audit: 11 flips, all
content-level normalization improvements (invisible bytes removed, fullwidth
digits ASCII-normalized) — enc-backspace-overstrike and enc-bell-in-cell now
byte-clean, uni-fullwidth ×3 / uni-zero-width-hidden / uni-jp-en / uni-yaml-cjk
values normalized. Gates: golden 0 failed post-freeze; extract 62/62; smoke
49/0; melt 10/0.

## 2026-07-14 — spanning group headers, sysstat headers, wrapped device rows

Four `aligned-columns` capabilities closing the tbl-* spanning/structural
cluster (5 targets) plus two long-standing hard-tail gaps for free:

- **HDR2 widened to digit-bearing field rows.** The two-line-header path
  (group row + field row) demanded a digit-free field row, so `p50`/`p99`/
  `BW(MB/s)` labels demoted benchmark tables to single-line-header mush. The
  discriminator is now VALUE-shaped tokens (bare number/time/IP/date): row 2
  must have none while row 3 has one. Contained by two shape gates — every
  row-1 token must bear an alphanumeric (a `==== test session starts ====`
  banner fails), and row 2 may hold no lone-punctuation token (an
  ` X : Y ` kv line fails) — both added after the first cut claimed
  pytest-summary/ib-write-bw/opam-list/pandas-show-versions prose.
- **Group-prefixing for duplicate header names.** A field row repeating names
  under group labels (`Req Lim Use  Req Lim Use` under `CPU  Memory`) used to
  COLLIDE in the wide record — the melt silently dropped the earlier group's
  columns (tbl-spanning-three-groups' golden had lost its whole Ingress
  group; vmstat -d its reads block; proc-net-dev its Receive block).
  Duplicated names now get the positionally-nearest group label as a prefix
  (`CPU_Req`, `Read_IOPS`, `reads_merged` — group tokens dash-trimmed), with
  duplicates marked on the ORIGINAL names first so the second group doesn't
  hide behind the first's rename. Skipped when the group row is banner chrome
  (punctuation-edged tokens — goose-report).
- **sysstat interval headers.** A row-1 whose ONLY value-shaped token is a
  leading bare clock time, over >=half %-prefixed/ALL-CAPS labels
  (`07:00:01  CPU  %user …`), is now promoted to a header — and the
  header-repeat chrome drop accepts digit-bearing headers when their exact
  repeats are RARE (<=1/4 of data rows), so sar's per-interval reprint is
  dropped while a block dominated by one repeated log line (entr) keeps its
  data. Closes tbl-sar-interval-repeat AND the long-documented sar-cpu gap.
- **First-cell wrap merge.** A lone-token data row followed by an INDENTED row
  one column short is a too-long column-1 value printed on its own line
  (df's `/dev/mapper/vg-root`) — the pair merges into one row (headed tables
  with >=4 columns only). Closes tbl-df-wrapped-device.

Bonus closures from the same mechanics: `sar-cpu` (AM/PM interval header) and
`quota-report` (Block/File-limits group header; minor prefix-assignment warts
from centered labels, all values in distinct columns). Golden audit: 8 flips
in the first cut → 5 regressions contained with the two shape gates + the
banner-prefix skip → final 3 flips, all improvements re-frozen (each recovers
a silently-lost column group). Gates: golden 3405/0 (then re-frozen), extract
62/62, smoke 49/0, melt 10/0.

## 2026-07-14 — quoted-delimiter round: the quo-* cluster (8 gaps) + bare pipe tables

Closes the full `quo-*` quoted/escaped-delimiter gap cluster with five
format-level capabilities (no per-tool code), each blast-radius-audited to
zero regressions:

- **`psql-table` escape-aware split** — `\|` inside a cell is a literal bar
  (regex alternations, `s1 || s2` concat); a naive split shredded such rows off
  the modal width so they were silently dropped. Closes
  `quo-pipe-table-bar-in-cell`.
- **`pipe-table` bare dialect** — `a | b | c` rows with NO outer pipes and NO
  rule row, split escape- and quote-aware (`\|` literal, `"a|b"` protected).
  Strictly gated: every non-blank line must split to the same >=2 top-level
  cell count, >=3 lines, no `---+---`, no border pipes, and no cell may contain
  an internal 2+-space run (TUI gauge lines like glances' `|####|` bars never
  match). Headerless when a row-1 cell is digit-leading (`ipmitool sdr`).
  Closes `quo-pipe-escaped-bar`/`quo-pipe-quoted-bar`, and upgrades 7 covered
  fixtures from literal-`|`-token mush to real columns (freeipmi, ipmitool-sdr,
  lutris-list, mimirtool-rules-list, pgbouncer-show-pools,
  thanos-tools-bucket-inspect, wireshark-tshark-io) plus closes the standing
  `git-log-pretty-pipe` gap for free.
- **`inline-kv` quote-aware tokenization** — `k="a b"` / logfmt
  `msg="request done, 200 OK"` spans are one token (quotes structural only at
  token start or right after `=`, the proven csv containment rule; outer quote
  pair stripped from the value). A leading `label:` token becomes a `name`
  column instead of counting against the kv-majority gate — so blkid keeps its
  device column. Closes `quo-kveq-quoted-spaces`/`quo-logfmt-quoted`; upgrades
  blkid ×3 and thanos-compact-status (complete msg values, real columns).
- **`tsv` quote-aware tabs** — `"a<TAB>b"` is one cell (protected tab becomes a
  space; tab RUNS still collapse like the `IFS read` this replaced, so ldd /
  proc-cpuinfo alignment padding doesn't shift columns). Plus a numbered-series
  header rescue (`col1 col2 col3` — same alpha prefix, suffixes ascending by 1
  — is a header even though it bears digits). Closes `quo-tsv-quoted-tab`.
- **new `delimited/two-col-gap.sh` (priority 54)** — the long-documented
  "2-col table, free-text last column" class: single-token key, a 2+-space gap,
  then a value that freely contains single spaces (`systemctl show`-style
  execstart tables, container entrypoint lists, getent hosts/services). Heavily
  contained after the first cut fired on ~600 inputs: value may not contain a
  2+-space run; free-text evidence must come from a data row (not a `VOLUME
  NAME` header); a (near-)uniform >=2-token value word count (>=2/3 modal
  share) is an aligned GRID and declines (git-worktree-list, rpm -V, dust); a
  multi-token row-1 value whose word count equals the modal data count is a
  single-space-aligned table header (lsblk) and declines; headerless when a
  row-1 cell is digit-leading. Closes `quo-entrypoint-json-array` /
  `quo-systemd-execstart`; getent_hosts-style inputs keep their aligned-columns
  goldens.

One manifest correction: `mimirtool-rules-list` mincols 5 → 4 (the 5 was
calibrated against the old junk output whose literal `|` counted as a column).

Audit trail: three full-gate rounds during containment (670 → 45 → 31 → 17 → 16
flips), every flip diffed and classified; final state is 16 improvement
re-freezes + 9 new goldens (8 quo-* + git-log-pretty-pipe), 0 regressions, 0
deletions. Gates: golden 0 failed; extract 62/62 (incl. the new two-col-gap
sample + baseline); smoke 49/0; melt 10/0.

## 2026-07-13 — wide fixed-width follow-up: columnar-spec overflow-decline + tsv header rescue

Closes the wide-fixed-width column-dropping gaps flagged as follow-ups by the
manifest-discipline pass, via two generic capability fixes (no per-tool code).

**`columnar-specs` overflow-decline (`_cs_row_overflow`).** A ws-delim spec with
a FIXED column layout (no `absorb` sink, no terminal `@rest`) silently dropped
any tokens past its column count — and worse, on a table WIDER than the spec it
mapped the first N tokens onto the wrong names (`turbostat`'s 10-column
space-aligned spec claiming `turbostat -q`'s 20-column tab output: SMI→PkgTmp,
POLL→PkgWatt, …, 10 columns lost). Such a spec now declines when the
overwhelming majority (≥80%) of its accepted data rows carry more tokens than it
has columns, so a generic full-width parser wins instead. No fixed-layout spec
can legitimately rely on the drop (a real multi-token trailing column already
needs `@rest`/absorb), so this only removes misapplications — it also
de-false-positives `hadolint-output`, which the `dpkg-get-selections` spec was
grabbing purely because its lines end in "…apt get install" (now honest
text-lines rather than a bogus `package`/`status` split).

**`tsv` header-vs-headerless disambiguation.** tsv treated row 1 as headerless
(synthesised `A,B,C…`) whenever any field merely CONTAINED a digit — which
demoted genuine headers whose labels embed digits (`Core CPU … C1 C6`,
`Avg_MHz`), losing every column name. It now keeps the long-standing
digit-bearing trigger but overrides back to "header" when a column is a
non-numeric label in row 1 yet a numeric value in row 2 (a real label-over-data
column), gated to ≥3 columns so 2-column key/value & pair lists (`wg show`
pubkey→time, colon-value KV dumps) — whose value column legitimately mixes text
and numbers row to row — are never mis-promoted.

Together: `turbostat-wide` (all 20 columns, ⏳→✅) and `enc-tsv-numeric` (⏳→✅),
plus real column names for the already-✅ `exo-nvidia-smi-topo-matrix` and
`featurecounts-summary`. Full blast-radius audit: an over-broad first cut (tsv
"all-numeric" then "digit-leading" rules) hit 50 then 5 goldens; the final
dual-row + ≥3-col form lands at exactly 5 flips, all classified — 4
improvements/neutral re-goldens + 1 honest de-false-positive, 0 regressions.
Gates: golden 3394 passed / 0 failed / 309 not-yet-covered (then re-frozen);
extract 62/62; smoke 49/0; melt 10/0. Coverage 3548 / 3706 (+2 vs the
discipline pass).

## 2026-07-13 — manifest-discipline follow-up: yaml/iostat fixes + stale-golden cleanup

Completes the manifest-discipline pass begun by the strict-`_ok` commit
(`enforce text-kind mincols in the tidy harness`), which deliberately deferred
"a coverage re-run + triage of newly-strict text entries" to this follow-up.

**Two root-cause parser fixes surfaced by the strict-mincols re-run.**

- `structured/yaml.sh` was false-positive-claiming `/proc/interrupts`-style
  numeric tables: its yamlish-ratio line check counted a purely-numeric label
  before a colon (`0:`, `16:` — IRQ row ids) as a YAML key, inflating the ratio
  past the 80% gate on output that is not YAML at all. The check now requires a
  key to start with a LETTER (matching the strategy's own top gate), so numeric
  row-label tables no longer register as yamlish. Blast radius (full-corpus
  winner scan, parallelised): 143 → 140 yaml winners, exactly 3 declined, zero
  unintended — `proc-interrupts-smp` (→ aligned-columns; real per-CPU columns
  now, residual one-column offset from the header-less leading IRQ-id column),
  `docker-pull-layers` and `ogrinfo-layers` (both → labeled-records, clean
  name/value lists). All three were yaml-garbage before; all three now clear
  their manifest and are ✅.

- `filesystem/iostat-x.sh`'s detect required BOTH `rrqm/s` and `aqu-sz` in the
  Device header, so the reduced-column `iostat -c -x` variant (`iostat-cx`,
  header carries `aqu-sz` but not `rrqm/s`) fell through to `block-records`,
  which dropped the entire Device table and kept only a garbled `avg-cpu:` line
  (2 cols vs the manifest's 9). Detect now keys on `aqu-sz` alone — distinctive
  enough to never match a plain `iostat -d` table — so `iostat-cx` is tidied by
  the bespoke `iostat-x` (all 9 columns, ✅ᵇ).

**Stale-golden cleanup + manifest correction.** Re-running `--update-golden`
under the now-strict `_ok` deleted 33 generic-mode goldens whose output no
longer clears its manifest's `emin` (the loose goldens the discipline pass
exists to retire). Each was triaged, generic AND full mode, to separate genuine
gaps from apt-get-style manifest miscalibration: all 33 are genuine shortfalls,
not bad manifests. The bespoke-covered subset (sar-u-all/-r-memory/-p-disk/
-n-edev, mpstat-p-all, pidstat-t, iostat-cx/-xz) honestly moves ✅→✅ᵇ (they
need a bespoke; generic can't); the rest (amdgpu-top, nvidia-smi-*, storcli-
show, turbostat-wide, ssh-config-*, brew-info-*, zpool-iostat-*, …) become
honest ⏳. One manifest WAS miscalibrated and is corrected: `apt-get-download-
progress` `mincols 4 → 2` (the 4 was calibrated against the pre-bugfix garbled
csv output; the honest single-column text-lines result is 2-wide and correct).

Gates: golden 3397 passed / 0 failed / 309 not-yet-covered; extract 62/62;
smoke 49/0; melt 10/0. Coverage **3546 / 3706** (✅ 3314 / ✅ʰ 83 / ✅ᵇ 149) —
down from the pre-discipline 3571 because the strict check stops ~28 lossy
parses from counting as tidy (the honest reclassification this pass is for),
net of +3 from the yaml fix. Remaining wide-fixed-width gaps (turbostat-wide
dropping 8 of 20 cols, storcli-show, nvidia-smi-full, the sar/iostat generic
paths) are documented follow-ups, not addressed here.

## 2026-07-13 — aligned-columns kv-header guard + csv thousands-comma false-positive

Two root-cause fixes from a manual quality review of `tests/corpus/review-output/`
(first 100 files triaged; full writeup in session notes).

**`aligned-columns` first-kv-pair-as-header bug.** A single-record colon-kv
description block (`apt-cache show` / `dpkg -s` style — `Package: vim` then one
`Label: value` line per field) was being wrongly claimed by `aligned-columns`:
row 1's two tokens ("Package:", "vim") became literal COLUMN NAMES and every
later field got stuffed under them as if it were a second data row. `_ac_shape`
now declines when a block is dominantly one DISTINCT `Label:` per line (majority
of rows, no duplicate labels) AND row 1 itself is such a label line — the second
condition is what keeps real tables whose first *column* happens to carry
colon-suffixed labels (`/proc/interrupts`'s `HI:`/`TIMER:`/`NET_TX:` rows under a
`CPU0 CPU1 CPU2 CPU3` header) on `aligned-columns`, since there row 1 is the real
header, not a field. Declining hands the block to `colons` (priority 60), which
already renders one clean wide record. Fixes apt-cache-show-vim/curl,
dpkg-s-nginx, dpkg-status-openssl, ipset-list(-hash), helm-status.

**`csv` comma-in-brackets false positive.** `apt-get`'s download-progress lines
(`[1,234 kB]`, `2,341 kB/s`) have a consistent per-line comma count purely from
repeated thousands-grouping punctuation, which was enough to satisfy csv's
comma-count-consistency detector and produce garbage. Two bracket-stripping
attempts (blanket greedy `[*]`, then a depth-tracking bracket stripper) were
tried and dropped — both erased the bracket-internal comma-count *variation*
that correctly makes `vegeta-report` decline csv (`[total, rate]` vs `[mean,
p95, p99]`), so stripping bracket contents wholesale is the wrong lever. Landed
on `_csv_strip_thousands`: exclude a comma from the count only when it has a
digit immediately before it and EXACTLY three digits after (not a fourth) —
precise enough to match true grouping commas anywhere (bracketed or not) while
leaving a real field-separator comma alone even when it sits between two
digit-ish tokens (`eu-west-1,881204` keeps its comma: 3 digits then a
disqualifying 4th). Fixes apt-get-download-progress and vegeta-report (both now
correctly decline to `text-lines`), and incidentally un-broke 8 pre-existing
false-positive csv winners plus closed a standing ⏳ gap
(`perf-stat-scientific`, headerless numeric CSV with `1,234,567,890`-style
grouping). `ledger-balance` also stops false-detecting as csv; the next-best
generic winner (`vertical-line`) is imperfect for this shape (dollar amounts +
account names, no true header/separator table) but matches the same accepted
lossy pattern already on file for its sibling `hledger-balance` — both are the
loose `text` manifest kind flagged for the pending manifest-tightening pass.

Blast-radius audit: full `tests/corpus/run.sh --golden` gate re-run after each
fix, every flip diffed against its golden. Two false-positive regressions
caught and fixed during development (`_ac_shape`'s first cut mis-claimed
`/proc/interrupts`-shaped tables; the bracket-stripping attempts before
`_csv_strip_thousands` broke `gpu-nvidia-query` and `vegeta-report`). Final
state: golden gate 3430 passed / 0 failed / 276 not-yet-covered (pre-existing,
no golden ever frozen — unrelated to this change); extract suite 62/62; smoke
49/0; melt 10/0. 9 goldens re-frozen (7 kv-header targets + apt-get-download-
progress + ledger-balance), 1 new golden written (perf-stat-scientific).
Coverage 3571 / 3706 (✅ 3346 / ✅ʰ 84 / ✅ᵇ 141) — the committed `COVERAGE.md`
had drifted stale since before the grouped-rows/pivot-stats rounds (last
showing 3478/3706); this commit both catches that up and folds in this
round's fixes. Net vs. the stale baseline: +93 tidy, -1 (`lsusb-v`, confirmed
via an `e4acc0b` worktree diff to be an unrelated pre-existing gap the stale
doc hadn't surfaced, not a regression from this change).

## 2026-07-13 — pivot-stats parser: the ip -s link pivot shape

New generic parser `strategies/structured/pivot-stats.sh` (priority 39) for
the shape grouped-rows explicitly could not take: a LABEL line naming counters
with the values on the NEXT line — a pivot, not a carry-down:

    2: eth0: <BROADCAST,...> mtu 1500 qdisc mq state UP ...
        RX: bytes  packets  errors  dropped  overrun  mcast
        9928374011 8837422  0       12       0        4421

One wide row per record: `name` from the `N: name:` header (or first token),
generic `word value` pairs from the header line (mtu 1500, qdisc mq, state UP,
mode DEFAULT, qlen 1000 — a token scan, no ip-specific list), and each pivot
folded into prefixed counters (rx_bytes, rx_packets, …, tx_bytes, …).
Detection needs >=2 header+values pivot pairs under >=1 unindented record
header; a value row must match the header's token count with every token
numeric — so ordinary labeled text never pairs up.

Routed by one hint row (`ip-stats  regex  RX: +bytes  pivot-stats`): the
signature IS the family, and the hint also carries `ip -s addr` past the
key-value parser (priority 11, unreachable otherwise). Closes the 4-fixture
family (ip-s-link, ip-s-link-eth, ip-s-addr-stats, nst-ip-s-link-nested — the
nested manifest aligned 6->3 to the family's one-row-per-interface wide
convention) and improves `exo-ip-s-s-link`, whose old indented-hierarchy
golden was welded header blobs. Residual noted: `ip -s -s` doubled stats
(`RX errors:` two-token label) drop the error-detail counters. The
kv-under-group siblings (nvme/ethtool per-namespace stats) stay ⏳ — they lose
to key-value at priority 11 and are a different shape (kv carry-down, not
pivot). Gates: golden 0 failed, extract green, smoke/melt green. Coverage
3567 -> 3571 tidy of 3706 (135 ⏳); ✅ 3347 / ✅ʰ 82 / ✅ᵇ 142.

## 2026-07-13 — grouped-rows parser: the nested-records frontier

New generic parser `strategies/structured/grouped-rows.sh` (priority 41 —
after block-records and tree-view, before indented-hierarchy) for the
biggest remaining ⏳ cluster: an outer GROUP line over INDENTED tabular rows,
up to two levels deep, with each group's keys carried down onto its leaf rows.

Group forms recognised: `Label: value` (spaced; the no-space `group:web`
variant only when alone on its line — `worker:w_02  STARTING` is a data row),
a run of KEY=value tokens (`COMMAND=nginx PID=1201`), a trailing-colon opener
(`Node node-01:`), a bare block token (`Images`), and multiple inline pairs
(`Filesystem UUID: 3f7a  Label: data`). A digit-free FIRST leaf under a group
names the leaf columns (`FD TYPE DEVICE NAME`); only the first — a later
digit-free leaf (`w_02  STARTING`) is data.

Containment (first cut fired on 42 corpus inputs; shipped form: 27 detects,
4 engine flips beyond the targets):
- leaves must BE a table — modal token count (±1) over >=70% of rows, and
  leaves >= groups: ifconfig-style attribute blocks and kv hierarchies vary
  too much / are group-heavy and never match;
- YAML list markers (`- `) walk detection away from YAML documents entirely;
- priority 41 leaves block-records (fdbcli, python-sysconfig, resolvectl) and
  tree-view (ostree) their wins;
- four kv-flavoured outputs the parser would token-soup (volta-list,
  vulkaninfo-summary, numpy-show-config, lsusb -v family) are pinned to their
  original parsers by hint rows — content byte-identical to their goldens.

Closes 11 nested ⏳ (region→az→instances, lsof per-process FD tables, sales/
quota/du/ledger grouped subtotals, supervisorctl groups, btrfs per-device
io_errs, cluster node disks, namespace pods, disk-smart partitions).
PROMOTES two bespoke-tier inputs to generic — `iotop` and `proc-devices` now
tidy without their per-tool strategies. Improves `pulumi-preview` and
`yugabyte-cluster-status` (the carried group column finally distinguishes
Masters from TServers). Manifest fixes: nst-lsof 8->7 (generator miscount),
nst-ledger 8->9 (actual leaf count), nst-du 7->9 (subtotals-are-data
convention). ip -s link stays ⏳ (its RX:/TX: label lines are column headers
for the FOLLOWING value row — a pivot, not a carry-down; different shape).

Also corrected the README headline to the tally-derived figure (the previous
round's arithmetic overcounted by 2): now 3567 tidy, 139 ⏳ of 3706
(✅ 3348 / ✅ʰ 77 / ✅ᵇ 142).

## 2026-07-13 — corpus output review snapshot

Added `tests/corpus/review-output/` — one tidy TSV per input in
`tests/corpus/inputs/` (3707 files) generated via `--generic` mode + the tidy
melt, plus `_summary.tsv` (tool, strategy, confidence, cols, rows) and a
README. This is a review snapshot for spot-checking current output quality,
not a change to the CI-enforced golden set (`tests/corpus/expected/`).

## 2026-07-12 — wrapped cells + the tab-collapse bug

Two changes in `aligned-columns`' positional-grid path:

- **Wrapped-cell rejoin.** A grid row whose only content sits in the LAST cell
  (first cell empty) is the previous row's last column wrapped onto a new line
  — kubectl events' MESSAGE, systemctl list-units' DESCRIPTION, a crontab's
  two-line COMMAND, issue-tracker DESCRIPTION columns. Appended space-joined.
  A sparse-matrix row keeps its row label, so first-cell-empty + only-last-cell
  never fires there. (A leading-overflow rule — value alone on its own line,
  next row's first cell empty — ships too, for the df long-device shape, but
  that fixture doesn't reach the positional path; see below.)
- **The tab-collapse bug (long-standing, uncovered by the wrap join not
  firing):** `IFS=$'\t' read -ra` treats TAB as IFS *whitespace*, so empty grid
  cells COLLAPSED and every value to their right shifted one column left —
  docker/podman ps rows with empty PORTS carried their NAME in the PORTS
  column; lastlog's "**Never logged in**" sat in the Port column. A tab-safe
  splitter (`_ac_cells`) now keeps cells in place. 22 covered goldens
  re-frozen, every one an empty-cell column-labeling fix (audited: docker-ps
  x3, podman-ps x3, lastlog x2, sparse network/volume/branch listings, consul's
  positionally-faithful relabel).

Closes 4 ⏳: tbl-kubectl-events-wrapped, tbl-systemctl-wrapped-desc,
tbl-two-line-wrapped-command, tbl-wrapped-desc-col. `tbl-df-wrapped-device`
stays open honestly — its table never reaches the positional path
(single-space numeric gaps fail `_ac_aligned`; the fixed-width byte-offset
family). Golden gate 0 failed after re-freeze; extract 62/62, smoke 49/0,
melt 10/0. Coverage 3554 -> 3558 tidy of 3706 (150 ⏳).

## 2026-07-12 — semicolon-values: quote-awareness + low-density band

The csv treatment for `strategies/delimited/semicolon-values.sh`. One shared
splitter (`_strat_ssv_split`: quotes structural at field start, `""` escape,
top-level `;` counting) drives detection and extraction:

- **Quote-aware counting/splitting:** a `;` inside "…" is data
  (`Schraube;"1.234,56";"12; nachbestellen"` — the embedded `; ` stays in its
  cell). Previously the raw count differed per line, detection failed, and the
  input fell to a blob parser.
- **Low-density band:** 2-3 top-level separators accepted only when EVERY line
  has the IDENTICAL count and there are >=2 lines — prose with stray semicolons
  ("o - Other; r - Repeater; …") varies line to line and never qualifies. The
  dense fio band (>=4, ±1, single-line OK) is untouched: fio terse goldens
  byte-identical.

Closes 5 ⏳: quo-ssv-euro-numbers, enc-nbsp-thousands-fr (the one the
unicode-space round couldn't take), cmb-ansi-csv-semicolon,
num-decimal-comma-scsv, num-semicolon-eu-decimals. Improves 4 covered fixtures
(csv-semicolon-comma-values, european-decimal-csv, quo-csv-semicolon-delim,
quo-semicolon-embedded) — all had been one-blob or welded token-soup via
text-lines/line-records/aligned-columns; now real headers and columns. Full
blast scan: 12 detections total = fio x2 unchanged + 5 closes + 4 improvements
+ 1 non-flip (yaml still wins cmb-truecolor-colonsep-kv at the engine level).

Telling find from the suite: the strategy's own sample golden was EMPTY — the
old >=4 rule rejected the sample's documented `name;value;unit` case, and the
golden had frozen that miss. Regenerated (7 fields). Golden gate 3408/0,
extract 168 sample-golden verifications 0 failed, smoke 49/0, melt 10/0.
Coverage 3547 -> 3554 tidy of 3706 (154 ⏳).

## 2026-07-12 — Unicode spaces + CJK headers

Two fixes for the Unicode-space/width cluster:

- **Engine: Unicode-space normalization** (`extract/envoy-extract`, after the
  line-terminator block, same gated once-per-input pattern). Maps NBSP (U+00A0),
  narrow NBSP (U+202F), U+2000–U+200A (quad/en/em/thin/hair), medium math space
  (U+205F) and the ideographic space (U+3000) to ASCII space, so column
  splitting — which keys on runs of 0x20 — sees the alignment the terminal
  showed. The locale subtlety that blocked this before resolves itself: a
  single normalized NBSP inside a grouped number ("1 234,56") survives the
  2+-space column rule, so NBSP-as-grouping and NBSP-as-padding coexist.
  Gotcha: in a $'…' sed script a byte range must be raw bytes ([\200-\212]) —
  double-escaping puts a literal backslash in the bracket ("Invalid range end").
- **aligned-columns: non-ASCII header labels.** The labelly check required
  every header token to carry [A-Za-z0-9], so an all-CJK header row
  (名前 年齢 都市) was never promoted and the header landed in the data as
  row 1. A label token may now be any token carrying an ASCII alphanumeric OR
  a multibyte character; CJK/hangul tables get real column names.

Closes 7 ⏳: enc-nbsp-padding, enc-em-space-padding, enc-thin-space-sep,
enc-ideographic-space, uni-ideographic-space-sep, uni-hangul-servers,
enc-formfeed-pages (num-nbsp-grouping and uni-jp-en-mixed-table also now parse
correctly — they carried goldens already). enc-nbsp-thousands-fr stays ⏳
honestly (it is semicolon-delimited — the semicolon-values density cluster,
not a space problem).

Golden audit of the 17 flips: the labelly first cut (any multibyte token =
label) promoted glyph-decorated LOG lines to headers (⚡️ volta, ✖ commitlint,
› stern, · navi, 🐷 trufflehog, │ docker-scout — each losing row 1 as data);
tightened to fire only when EVERY non-separator token in the row is fully
non-ASCII (a pure CJK label row) — all 6 restored byte-identical. The 11
NBSP-family goldens re-frozen as improvements (NBSP/em/thin/figure bytes ->
clean cells; "1 234,56" one cell). One accepted trade: uni-kv-fullwidth now
splits its fullwidth-colon pairs properly (was 4 unsplit blobs) but the
pre-existing all-caps rule takes pair 1 as a header — still passes its kv
manifest; the full fix is fullwidth-colon (：) support in the colons parser
(noted as follow-up). Golden gate 0 failed after re-freeze; extract 62/62,
smoke 49/0, melt 10/0.

## 2026-07-12 — table chrome: header repeats + units rows

`aligned-columns` and the `columnar-specs` engine now drop rows that are table
furniture, not data. Both rules are containment-first (each first cut caused
real regressions the golden audit caught; the shipped form restores all of them):

- **Mid-table header repeats** (watch/top/vmstat/ps re-print the header every
  page/interval): any later line token-identical to the header is dropped —
  but only when the header is digit-free AND has ≥3 tokens, so a legitimately
  repeated 2-token log line (`entr`'s "restarting: app.py") and repeated data
  lines carrying digits ("[app] listening on :8080") survive. Same rule in
  columnar-specs (exact repeat of the consumed header line), closing
  `tbl-watch-diskio-repeat` via the iostat-d spec.
- **Units row under the header** (`(C)  (RPM)  (V)`, `MHz  dBm  dB`): dropped
  only in that one position and only when digit-free, deeper-indented (blank
  first cell), fewer tokens than the header, and EVERY token unit-shaped
  (parenthesized or case-mixed, ≤6 chars). An all-lowercase data row with an
  empty first cell (consul's `web  db  allow`) or long values (nerdctl's
  conflist paths, needrestart's service names) is never eaten.
- **Totals-footer manifests aligned with corpus convention:** the ✅ sar family,
  `rsync-stats`, `coverage-report` all keep their `Average:`/`TOTAL` row as a
  data row, so the four adversarial footer fixtures now expect it too
  (dropping totals corpus-wide would have flipped ~11 established goldens and
  their manifests — wrong trade).

Closes 10 ⏳: vmstat/ps/top header repeats, watch-diskio, sensors/SI units rows,
and the four footer fixtures. Improves 4 already-covered goldens (faillock,
exo-iostat-x-repeated, nst-vmstat-sections, curl-progress-meter — each carried
a repeated-header/chrome row as data). `tbl-sar-interval-repeat` stays ⏳
honestly: its header starts with a timestamp, so the table reads as headerless
and there is nothing safe to key a repeat off. Golden gate 0 failed, extract
62/62, smoke 49/0, melt 10/0. Coverage 3530 -> 3540 tidy of 3706 (166 ⏳).

## 2026-07-12 — quoted-fields parser: the access-log family

New generic parser `strategies/delimited/quoted-fields.sh` (priority 12) for
space-delimited positional records where `"…"`, `'…'` and `[…]` group a
multi-word value into ONE field — apache combined / nginx access logs, quoted
app logs, quoted crontabs, `lspci -mm`. No header; columns are synthesised.

Containment (the first cut fired on 45 corpus inputs; tightened to 9):
- grouping/signature only at TOKEN start — logfmt (`msg="…"`) and quoted CSV
  (quotes after commas) never form spans and stay with their parsers;
- the signature is a QUOTE span on every line (brackets group `[ts +0000]`
  but don't qualify — else every bracket-tag log and aligned table with a
  `[SWAP]` cell would match), ≥5 fields, field-count spread ≤2;
- DNS RRs decline via the (IN, <rr-type>) token pair — dig TXT stays with
  dns-records; JSON declines via _is_json.

Closes 5 ⏳ (`quo-apache-combined-log`, `quo-access-log-referer-query`,
`quo-app-log-quoted-fields`, `quo-cron-quoted-cmd`, `quo-nginx-log-ua-commas`).
Exactly 3 audited flips, all improvements: `lspci-mm` (one-blob text-lines →
7 real columns), `nginx-access-log-quoted` (garbled csv 1-row → clean 9-column
table), `quo-haproxy-log-quoted` (quoted request no longer split across 3
columns). Ships sample + golden. Golden gate 0 failed, extract suite green,
smoke/melt green. Coverage 3525 -> 3530 tidy of 3706 (176 ⏳); generic 3313.

Also: `local x="$1" y=${#x}` breaks under the engine's `set -u` (bash expands
all words of a `local` before any assignment lands) — split declarations.

## 2026-07-12 — csv: RFC-4180 quote-awareness end-to-end

Gap-cluster round on the quoted-CSV family (`strategies/structured/csv.sh`).
The extractor's row parser was already quote-aware, but everything around it
wasn't; four fixes, one shared splitter (`_strat_csv_split` — quotes structural
only at field start, `""` escape, `_CSV_OPEN` flag for continuation lines):

- **Detection counted commas inside quotes**, so genuinely quoted CSV
  (`1001,"Cash, operating","1,234,567.89"`) failed the comma-consistency check
  and fell through to a worse parser. Detect now counts only top-level commas.
- **Header split was a naive `IFS=','`** — a quoted header column
  (`"Last, First",Dept`) misaligned every data row. Now uses the same splitter.
- **The multi-line joiner keyed on raw quote parity**, so a literal inch-mark
  row (`Pipe,3/4",100`) was welded into the next line. Now keys on whether the
  RFC-4180 parse ends inside an open quoted field.
- **A blanket quote-strip erased literal quotes from values** (`6"" widget`
  became `6 widget`). Structural quotes are consumed by the splitter; anything
  left is data and stays.

Closes `quo-csv-currency-thousands` / `quo-csv-tags-column` /
`quo-csv-inch-marks` (3 ⏳). Full golden audit of the 12 changed goldens: 7
outright improvements (`psql-csv-quoted-commas`, `sqlite-csv-mode-quotes`,
`quo-csv-name-city-commas` went from garbled token-soup to correct columns;
escaped `""` quotes now preserved; `tshark-fields-quoted` no longer splits its
quoted request field), 5 faithful-neutral (logcli/ss/nginx keep the quotes the
raw log really contains), **0 regressions** — all 12 still meet their manifest.
Golden gate 0 failed, extract 62/62. Coverage 3522 -> 3525 tidy (181 ⏳).

Also triaged and documented as NOT cleanly fixable this round: `getent-group`
(csv steals it via member-list commas; a colon-vs-comma decline rule would flip
5 existing csv winners), `quo-ssv-euro-numbers` (semicolon-values requires
;-dense lines by design), and the quoted-access-log family
(`quo-apache-combined-log`, `quo-nginx-log-ua-commas`, …) which needs a
space-delimited quoted/bracketed-field log parser — a candidate next parser.

## 2026-07-11 — Generic parser: ini-sections (multi-section INI/config)

New `extract/strategies/structured/ini-sections.sh` (priority 20) — closes a
cluster of non-conforming `⏳` inputs and improves a batch of already-covered
config dumps.

- **Problem.** Multi-section INI/config output (`[section]` headers + `key =
  value` runs) was flattened by the plain `equals` parser into ONE wide record,
  which collides duplicate keys across sections (three `host` columns) and drops
  the section each value belongs to. The correct, lossless tidy is one row per
  pair carrying its section: **(section, key, value)**.
- **Fix.** `ini-sections` emits that long form. It fires only when section names
  are simple tokens AND distinct, so repeated-section block formats (ffprobe
  `[STREAM]…[/STREAM]`) and spaced section names (`[Unit multi-user.target]`)
  are left to their better-fitting parsers, and `toml` (priority 15) still wins
  real TOML. The line classifier is inlined into both detect and extract because
  the engine unsets `_strat_*` helpers between the detection sweep and
  extraction. Guards against `{`-only for JSON (INI legitimately opens with `[`,
  which a bare `_is_json` check misreads as a JSON array — the bug that first
  hid this parser from every INI input).
- **Closes** `nst-ini-duplicate-keys`, `nst-php-ini-sections`,
  `nst-tox-ini-sections` (3 ⏳ → ✅).
- **Improves 9 already-covered configs** (`gitconfig-aliases`/`-multiline`,
  `systemctl-cat`, `rclone-config-show`, `gcloud-config-list`, `atac-env`,
  `wg-showconf`, `ini-database-profiles`, `ini-equals-in-value`) from a flat
  duplicate-column form to the clean section/key/value table — goldens
  re-frozen, each still meets its manifest (all improvements, 0 regressions).
- Fixed `nst-tox-ini-sections` manifest row count (agent-written 8 → actual 7).
  Coverage **3519 → 3522 tidy** of 3706 (**184 ⏳**) — ✅ 3305 / ✅ʰ 73 / ✅ᵇ 144.

## 2026-07-11 — Adversarial +510 (round 2) + line-terminator normalization

A second adversarial expansion: 510 new inputs generated (8 parallel themed
batches) specifically to BREAK the parser across mechanisms not stressed before —
encoding/whitespace pathologies, Unicode display-width vs mawk byte math, numeric
punctuation, embedded-delimiter quoting, structural table oddities, nested
multi-section records, stacked color+box+emoji, and real-tool exotics
(`openssl x509`, `ss -i`, `smartctl -a`, `perf -x`, …).

- **Engine: line-terminator normalization** (`extract/envoy-extract`). The one
  clean format-level fix the break-hunt surfaced. Record splitting keys on `\n`
  throughout, so a capture using any other terminator collapsed to a single
  physical line. The engine now normalises — once, before the ANSI strip, gated
  on such a byte being present (a true no-op for ordinary input) — Windows CRLF,
  bare-CR (classic Mac), vertical-tab / form-feed page breaks, and the Unicode
  line separators NEL (U+0085), LS (U+2028), PS (U+2029). Fixed the cr-only /
  NEL / U+2028 / vertical-tab / CRLF-block-records breakers. Golden gate 0
  regressions (2987 existing goldens byte-identical), extract 62/62, smoke 49/0.
- **Corpus +510** (`tests/corpus/inputs/`, `expected.tsv`, `expected/`). Of the
  510 adversarial inputs, **393 tidied with no new per-tool code (77%)** — a
  deliberately low rate, since they were built to fail. 117 landed ⏳, honestly
  documenting the frontier. New tallies: **3706 tools; 3519 tidy; 187 ⏳** (✅ 3302
  generic / ✅ʰ 73 hint / ✅ᵇ 144 bespoke). Golden freeze added 388 new goldens,
  deleted/modified 0 existing (no regression).
- **Break clusters left ⏳ (documented, not closed):** nested per-record
  sub-tables (`ip -s link` RX/TX, grouped subtotals — the known hard frontier);
  quote-aware CSV/pipe splitting (embedded commas/newlines/bars); INI/TOML
  `[section]` files (candidate for a future `ini-sections` generic strategy);
  Unicode-space column separators (NBSP / ideographic-space — conflicts with
  NBSP-as-thousands-grouping, so not blindly normalisable); display-width vs byte
  column math for CJK/emoji.

## 2026-07-11 — Gap-triage: vercel-list hint + README tier-count fix

A focused pass over the 71 ⏳ gaps looking for clean, non-regressing wins.

- **README tier counts corrected.** The per-tier breakdown had drifted stale
  across the expansion rounds — it read "✅ 1934 / ✅ʰ 58 / ✅ᵇ 134" against a
  live COVERAGE.md of **2915 / 71 / 139**. Updated to match (headline 3125/71 was
  already correct; only the sub-sentence was wrong). File: `tests/corpus/README.md`.
- **`vercel-list` routed via a hint.** A banner + fixed-width deployment table
  (`Age  Deployment  Status  Environment  Duration  Username`) that
  `indented-hierarchy` was collapsing to a single record. Added a structural hint
  row (`vercel-list  regex  Age +Deployment +Status  aligned-columns`) — the
  signature is unique in the corpus and matches the column layout (stable across
  runs), so it also covers unseen vercel output. Now a clean 4-row × 6-col table,
  `● Ready`/`● Error` preserved. New ✅ʰ. Files: `extract/hints.tsv`,
  `tests/corpus/expected/vercel-list.tsv`, `tests/corpus/COVERAGE.md`.
- **Triaged the rest as genuinely hard (documented, not closed):** banner-table
  siblings `pueue-status` / `apachectl-S` (stolen by `indented-hierarchy` at
  detection, banners not stripped), `lsblk-tree` (can't hint without demoting
  already-generic lsblk siblings that share the `MAJ:MIN` / tree-glyph
  signatures), `df-locale-de` (UTF-8/mawk byte-vs-char column positions —
  umlaut headers), and the wide-stat cluster `sar-cpu` / `numastat-p` /
  `quota-report` (embedded time columns, banners, grouped 2-row and
  `|`-separated headers). Net: **3125 -> 3126 tidy, 71 -> 70 ⏳.**

## 2026-07-11 — Gap-closing: ANSI strip + box-table interior/type-row

Two generic capabilities that close a batch of the remaining ⏳ and improve
dozens of already-covered tools.

- **Engine-level ANSI strip.** Colored tool output (`ls --color`, `gh`, `git`,
  `kubectl`, `systemctl status` dots, `terraform plan`, npm/cargo/pip/pytest, …)
  embeds VT escape sequences that pollute or split data cells. The engine now
  strips ECMA-48 CSI / OSC / two-byte escapes once, right after reading the
  input — gated on an ESC byte being present, so it is a true no-op (no
  subprocess) for the vast majority of inputs. Closed `gh-run-list-color` /
  `terraform-plan-color` and **cleaned 45 already-covered color fixtures** whose
  goldens had carried raw `\e[..m` codes inside cells (`[32mRunning[0m` ->
  `Running`). Two colour fixtures that only "passed" because the escapes happened
  to split them (`cargo-clippy-color`, `delta-diff-color`) are now honestly ⏳ —
  they are prose/diff formats, not tables.
- **box-table: interior rows + type rows.** Split now strips the outer `│` only
  when a row is bracketed at BOTH ends, so an interior-only row with an empty
  edge cell (psql `linestyle unicode` with a blank first column) keeps that cell
  — closing `supabase-projects-list`, `psql-linestyle-unicode`,
  `psql-pset-unicode`, `tabulate-presto-unicode`. And a duckdb/clickhouse "type
  row" (every cell a bare SQL type keyword, printed under the header before the
  separator rule) is skipped — closing `duckdb-box-output`, `duckdb-describe-box`
  and fixing `duckdb-show-tables` (its golden had wrongly included the `varchar`
  type row as data).

Full golden audit: 45 improved (de-ANSI'd) + duckdb fix, 4 newly ✅, 2 honest ⏳
demotions, 0 real regressions. Golden gate 0 failed; extract 62/62.

Follow-up manifest audit (three fixtures that were *already* tidying but
mis-scored, no code change): `kubectl-get-svc-none` (`table 6 6`->`5 6`) and
`lsblk-empty-mountpoint` (`table 8 7`->`7 7`) were correct 6-/7-column tables
whose `<none>` / empty-`MOUNTPOINT` cells are preserved — the manifest simply
over-counted the data rows by one. `systemctl-status-nginx` was reclassified
`table`->`kv - 5`: it is a single-unit status snapshot, the same key/value shape
as the eight describe/status fixtures reclassified above, not a table. Goldens
frozen for all three (aligned-columns / aligned-columns / block-records). Net:
**3122 -> 3125 tidy, 74 -> 71 ⏳.** Files: `tests/corpus/expected.tsv`,
`tests/corpus/expected/{kubectl-get-svc-none,lsblk-empty-mountpoint,systemctl-status-nginx}.tsv`,
`tests/corpus/COVERAGE.md`, `tests/corpus/README.md`.

## 2026-07-11 — Multi-line records: single-resource describes are kv, not table

The second frontier weakness from the adversarial round. Unlike trees, the
multi-line "breaks" had no single generic fix — they split two ways:

- **Single-resource describes** (`kubectl describe`, `systemctl status`) are
  fundamentally a `Key: value` snapshot of ONE object. The parser already
  produces a clean 1-row kv (Name/Namespace/Selector/Replicas/…); they only
  counted as "breaks" because the fixtures were labelled `table` (expecting the
  embedded Conditions/Events sub-table). Reclassified 8 fixtures `table -> kv`
  — the honest shape — so they land ✅ with no parser change.
- **Genuinely nested multi-record** (`ip -s link`: interface header + RX:/TX:
  sub-tables across 6 lines each) has no faithful flat form and stays ⏳; a
  bespoke parser for it would be speculative and low-generality.

Regen: **+8 kv goldens, 0 modified, 0 deleted.** Golden gate 0 failed.

## 2026-07-11 — Tree flattening: tree-view wins glyph hierarchies (priority + variants)

Closes most of the deep-tree cluster the adversarial round exposed. The engine
dispatches in priority order, first-match-wins, so a genuine glyph tree was
being grabbed by block-records (p40) or indented-hierarchy (p50) — which seized
a preamble or the first `label:` line and collapsed the whole tree to a single
record — before tree-view (p50) ever ran.

- **tree-view priority 50 -> 38**, so it is tried before those generic parsers.
  Its detect gate (>=60% of non-blank lines carry a ├/└/┬ branch marker; no
  ALL-CAPS columnar header) is specific enough that only real trees flip.
- **Depth counts more conventions**: 2-column indent cells (`│ `/`  `, pstree /
  systemd-cgls / pnpm) as well as the classic 4-column, and branch markers of
  any dash count (`├─`, `├──`, `├─┬`, ASCII `+--`/`` `-- ``) — a small cosmetic
  left-margin is dropped so it isn't mistaken for a level.
- **Names lose connector debris**: a leading ASCII marker (`+---`, `` `-- ``,
  stray dashes from the box-glyph pass) is stripped, while internal hyphens
  (dbus-daemon) survive.

Full golden audit: **0 deleted, 13 modified, +21 new goldens for now-covered
trees**. The 13 modified are all improvements or benign depth-normalisation:
systemd-cgls-machine (collapsed kv -> proper node table), gradle deps and
ansible-inventory-graph (names no longer prefixed with `+---`/`--`), and
pstree/busctl/broot depth values now counted consistently. Newly tidy: pnpm,
ip-netns, conda-tree, systemd-cgls, npm-ls, yarn, and more. (A few — pipdeptree,
cargo-tree-dedup, pstree-ap — remain shape-valid but carry cosmetic glyph debris
where a non-tree-view parser still wins; left as-is.) Golden gate 2973 passed, 0
failed; extract 62/62, smoke 49/0, melt 10/0. Coverage 3090 -> 3111 tidy of
3196. Files: `extract/strategies/structured/tree-view.sh`, `tests/corpus/*`.

## 2026-07-11 — Adversarial stress test (+500 hard inputs) + box-table upgrade

A red-team round: 500 inputs generated specifically to BREAK the parser, across
10 hard mechanisms (Unicode box-drawing borders, embedded ANSI color codes,
multi-line/wrapped cells, two-row/grouped headers, ragged/sparse tables,
delimiter-in-value, deep indented trees, numeric-format edge cases,
blank-line-separated paragraph records, and TUI/progress-bar chrome). Each
carries a ground-truth tidy shape.

**Break diagnosis** (`--generic`, single strategy): the parser is robust to
embedded ANSI color, grouped 2-row headers, paragraph-stanza records, and
TUI/progress bars (~0 breaks each). The genuine soft spots are **deep trees**
(glyph-prefixed hierarchies), **multi-line/wrapped records** (`kubectl describe`,
`git log` bodies), and a subset of **box-drawing** dialects. In FULL mode
(hints + all strategies) 431 of the 500 tidy; 69 are documented ⏳ gaps.

**Fix — `box-table` v2** (`extract/strategies/delimited/box-table.sh`): the
previous version handled only light/rounded borders. Rebuilt as a strict
superset that also covers heavy (`┃━┏┓`), double (`║╔╦╗`), tabulate
(`╒╤╕╞╪╡`) and dotted (`┆`) glyphs, interior-only rows (psql `linestyle
unicode`, no outer border), and a framed ASCII dash rule (`│ --- │`, csvlook).
It normalises every vertical divider to `|` and recognises a rule as "strips to
only box glyphs + spaces". This closed 8 box-drawing breakers (mysql/csvlook/
heavy/double/tabulate) AND upgraded two already-covered corpus tables from
tokenised junk to real tables (`railway-variables` 10-row `║`-noise → clean
NAME/VALUE; `polars-describe` mangled `┆` column → proper 5-column table).

All 500 added to the corpus (431 ✅ goldens, 69 ⏳). Full golden audit: 0
existing goldens deleted, 2 improved (railway/polars, re-goldened after manifest
correction), 427 new. Golden gate 2952 passed, 0 failed. Extract 62/62.
Coverage 2696→3196 tools, 2659→3090 tidy (106 ⏳). Files:
`extract/strategies/delimited/box-table.sh`, `tests/corpus/inputs/*` (+500),
`tests/corpus/expected/*`, `tests/corpus/expected.tsv`, `tests/corpus/COVERAGE.md`.

## 2026-07-11 — +539 unique corpus inputs (batch 3), ~98% generalized with no new code

Third large expansion of unique never-before-seen tools, generated across 10
domains (cloud/SaaS CLIs, k8s/containers, databases, observability, networking,
security, build/language toolchains, data/ML/scientific, system/hardware,
storage/backup). **529 of 539 (98%) tidied with no new per-tool code** — the
generic parsers generalized to the unseen tools. The 10 genuine gaps left as ⏳
are the usual hard shapes: JSON after a leading `-- comment` (surreal-sql-select),
Unicode box tables `│` (supabase-projects-list), log-preamble-then-table
(cargo-audit, cargo-nextest-run), inline `k=v` after a preamble
(datadog-ci-junit-upload), `name = "v" # desc` list mistaken for kv (cargo-search),
right-aligned banner tables (powertop-devices, gluster-volume-profile,
vercel-list), offset dumps (openssl-asn1parse). Golden gate re-run clean (0
existing goldens modified/deleted; 529 new goldens). A random data-sanity
spot-check across domains confirmed the new goldens are real tidy tables, not
shape-passing garbage. Files: `tests/corpus/inputs/*` (+539),
`tests/corpus/expected/*` (+529), `tests/corpus/expected.tsv`,
`tests/corpus/COVERAGE.md`.

## 2026-07-11 — Holdout generalization pass for the recently-touched tools

Added 12 held-out (second, different-content) samples for the tools touched
this session, to prove the parsers generalize to UNSEEN captures rather than
memorising the corpus fixtures: `ceph-osd-df` (different OSDs, mixed hdd/ssd —
the direct test that segment-split generalizes), the 8 segment-split
beneficiaries (`zstd-list`, latencytop, google/catch2-benchmark, az-ad-user-list,
bandwhich, gh-run-list, spark-history-apps), and the 3 multi-mode adds
(pvesm-status, rbd-du, zk-mntr). All 12 land on the **generic** tier
(aligned-columns / tsv) with no goldens — judged on tidy shape only, the way an
unseen capture is. Holdout now **80/80 tidy** (generic 55, hint 23, bespoke 2).
Files: `tests/corpus/holdout/inputs/*` (12), `tests/corpus/holdout/expected.tsv`.

## 2026-07-11 — Segment-split for right-aligned space-in-value fixed-width tables (aligned-columns)

Closes the hardest gap cluster: fixed-width tables whose values carry inner
spaces ("1.0 TiB", "180 GiB") under a multi-word header ("RAW USE"), where the
numbers are right-justified so positional (column-start) assignment can't align
them — the value's start falls under the wrong header column. Flagship: `ceph
osd df`.

- **New `_ac_split`** in `aligned-columns` — splits a line on >=2-space gaps
  (the same boundary a fixed-width table uses), keeping a single-spaced
  multi-word cell intact. It is `_ac_seg` as a splitter.
- **Tight, HDR-only trigger.** Fires only when: the block is a headed table
  (`_ac_shape` == HDR — a header row fixes the true column count), every
  non-blank line has the SAME >=2 two-space-segment count, and the MODAL data
  row has MORE whitespace tokens than the header has labels. That last test is
  the discriminator that keeps single-space-delimited tables (`ps -ef`'s narrow
  "C STIME TTY" — three columns, not one multi-word cell; modal data tokens ==
  header tokens) on tokenization, and excludes headerless log records
  (`who`/`last`, whose "date time (host)" the established tidy splits into
  columns — no header to say otherwise).

**Full golden audit** (the discipline that caught a first-cut `ps-ef` deletion
and a 38-file over-fire, both fixed by the modal-token gate): 8 modified —
**all improvements** (multi-word headers joined AND space-in-value cells
preserved AND previously-jammed trailing columns recovered: `az ad user list`
DISPLAY-NAME, `bandwhich` "ip:port => ip:port", catch2 / google-benchmark
"248 ns", `gh run list` TITLE, latencytop Cause, spark App ID, zstd "44.2 MiB").
1 new golden: `ceph-osd-df` (the target, ⏳ -> ✅). **0 deleted, 0 regressions**;
golden gate 1996 passed, 0 failed. Coverage **2156 -> 2157 tools; 2129 -> 2130
tidy**. Files: `extract/strategies/delimited/aligned-columns.sh`,
`tests/corpus/inputs/ceph-osd-df.txt`, `tests/corpus/expected/*` (9),
`tests/corpus/expected.tsv`, `tests/corpus/COVERAGE.md`.

## 2026-07-11 — Multi-mode coverage audit (all ~1000 tools) + net-new mode samples

An audit of whether every tool's *range* of output modes is sampled — the same
check that exposed fio's under-coverage earlier. Findings and actions:

- **The corpus is already deeply multi-mode.** High-fanout tools already carry
  many modes each (kubectl 54, aws 46, git 43, docker 28, ip 20, ss 13, tc 9,
  sensors 5, zfs 4, …). Programmatically probing the ~738 single-sample tool
  families for plausible additional modes produced **~70% collisions** — the
  candidate mode was already represented — confirming the breadth is real, not
  an artifact of fio being special.
- **Net-new mode samples added (generic, no new code).** Three real common-tool
  modes that weren't sampled and tidy under the generic parsers: `pvesm-status`
  (Proxmox storage, aligned-columns), `rbd-du` (Ceph RBD usage with `50 GiB`
  space-in-value cells, aligned-columns), `zk-mntr` (ZooKeeper `mntr`, tab kv).
- **Two genuine gaps found and tracked honestly as ⏳** (same hard structural
  classes as the existing 25): `supervisorctl-status` (multi-space-aligned
  status table with `pid …, uptime …` value cells) and `ovs-ofctl-dump-flows`
  (comma `k=v` flow records — the generic kv-pairs parse collapses multiple
  flows to one record).
- **Rejected a garbage-passing sample rather than inflate coverage.**
  `ceph-osd-df` mechanically satisfied a shape check (17 cols × 2 rows) but its
  data was misaligned garbage (multi-word `RAW USE` header + `1.0 TiB` /
  `180 GiB` space-in-value cells shift every column; the tail jams into one
  cell). Since the shape gate can't detect the misalignment, the sample was
  removed entirely instead of committing a golden that enshrines wrong data.

Coverage **2151 → 2156 tools; 2126 → 2129 tidy** (✅ 1937 generic, ✅ʰ 58 hint,
✅ᵇ 134 bespoke); ⏳ 25 → 27. Golden gate re-run: **1995 passed, 0 failed**, no
existing golden touched. Files: `tests/corpus/inputs/{pvesm-status,rbd-du,zk-mntr,ovs-ofctl-dump-flows,supervisorctl-status}.txt`,
`tests/corpus/expected/{pvesm-status,rbd-du,zk-mntr}.tsv`,
`tests/corpus/expected.tsv`, `tests/corpus/COVERAGE.md`.

## 2026-07-10 — Positional multi-word headers + fixed-width banner strip (aligned-columns)

The audited positional-header round. Two capabilities in `aligned-columns`, each
validated by a full-corpus golden audit:

- **Positional column assignment for multi-word headers.** It now also triggers
  when the header carries MORE whitespace tokens than the data rows AND its
  2-space segmentation collapses exactly to the modal data-column count — a
  genuine multi-word-header table (STREAM's `Best Rate MB/s`, kubectl's
  `NOMINATED NODE`). The equality is the safety net: single-spaced labels (df's
  `Used Avail Use%`) under-segment and never match, so numeric tables keep
  tokenization.
- **Fixed-width banner strip.** A leading title banner before a fixed-width table
  is dropped, gated by four discriminators (single-column/decorated-rule banner
  shape, an all-label header — every token has a letter, none digit-leading,
  ≥2 two-space segments — digit-bearing data, and header/data at the same
  indent). Version banners (`Consul v1.18.1`), kv blocks (ipset, xh), logs
  (git log) and decorated rules (mpirun `==== JOB MAP ====`) are all excluded,
  each verified by audit.

**Every changed golden audited individually**: 39 modified — all improvements
(multi-word headers correctly joined AND previously-dropped trailing columns
recovered: proc-net-arp's 6 columns, kubectl AGE / READINESS_GATES /
ALLOWED_DISRUPTIONS, arp `Flags_Mask`+Iface, npm `Depended_by`, ss-tcp
Local/Peer `Address:Port`, unixbench's real header, …). 7 new goldens: the
target benchmarks (stream-benchmark, blender-benchmark) + 5 bonus recoveries
from the old hard tail (frr-show-bgp-summary, gluster-volume-status, watch-diff,
nodetool-compactionstats, pytest-benchmark). **0 goldens deleted.**

Coverage 2120/2151 → **2126 / 2151** (✅ 1934 generic · ✅ʰ 58 · ✅ᵇ 134);
extract 62/62, smoke 49, melt 10, holdout 68/68. Benchmark corpus now **97/99**
(only kdiskmark — headerless first column — and lzbench — single-space multi-word
cells — remain).

## 2026-07-10 — Two generic parsers close 6 fio output forms

Fully covered fio (its 12 output modes are now all handled — 9 tidy, 3 correctly
loose text) with two format-level, non-fio-specific parsers:

- **`delimited/semicolon-values`** — `;`-delimited records (fio
  `--output-format=terse` v3/v5: one `;`-line of ~48 positional fields;
  European-locale CSV). A single line is one headerless record; a strict
  detector (every line ≥4 semicolons, consistent count) leaves the lone
  `;`-legend line in `networkctl-lldp` alone.
- **`delimited/labeled-inline-kv`** — `label: k=v, k=v, …` records (fio
  disk-stats, run-status, io-depths, latency-dist; `ip -s`-style). The label
  becomes a `name` column and each `k=v` a data column, one row per label, an
  optional section title skipped. Records must dominate (≤1 non-record line), so
  it stays off `key: value` snapshots (`mdadm --examine`, `nmcli`) that carry a
  stray `label: k=v` line; splits on the last `=` so fio's `>=64=99.9%` keeps
  its key.

Coverage 2115/2151 → **2120 / 2151** (✅ 1927 generic · ✅ʰ 58 · ✅ᵇ 135);
golden regression 1980 pass / 0 fail / 0 deleted (only 6 fio goldens changed);
extract 62/62, smoke 49, melt 10, holdout 68/68.

**Deliberately left ⏳ — 5 fixed-width benchmark tables** (stream-benchmark,
pytest-benchmark, blender-benchmark, kdiskmark-run, lzbench-run): a title banner
+ multi-word column header over a whitespace grid. A dedicated `banner-fixed-table`
strategy was prototyped (it cleanly tidied stream + blender) but its detector
grabbed 26 existing inputs — the shape is structurally indistinguishable from
headerless word-data lists (`vagrant status`, `clang -targets`), single-space
headers (`netstat -rn`), and `key: value` blocks (`ceph status`) without gates
that also break blender — so it was dropped rather than churn 2151 goldens. The
principled fix is positional multi-word-header handling in `aligned-columns`
(a genuine improvement — it reunites `Depended_by`, `NOMINATED_NODE`,
`Flags_Mask` across ~60 tables) but it changes 69 goldens and needs a full
audit round, deferred as separate work.

## 2026-07-10 — Cover the full range of fio output + headerless numeric CSV

The corpus had only 2 fio fixtures, both truncated slices of the *normal*
report. fio actually emits a whole family of output shapes — added all 12
distinct forms and measured each honestly (2139 → 2151 inputs):

- **Tidy (3):** `fio-json-output` (flattened JSON), `fio-bw-log`, `fio-iops-log`.
- **Loose text (3)** — nested multi-section *reports*, correctly not forced into
  one table: `fio-normal-full`, `fio-multijob`, `fio-status-line`.
- **Documented gaps ⏳ (5):** `fio-terse-v3`/`v5` (`;`-delimited record — no
  semicolon parser), `fio-disk-stats` / `fio-io-depths` / `fio-run-status`
  (inline `label: k=v, k=v` records — the same inline-kv-with-banner shape as
  the rest of the hard tail).

One generic, non-fio-specific capability added: **headerless numeric CSV**.
`structured/csv` always ate row 1 as a header, which broke any data logger that
emits raw rows with no header (fio `--write_bw_log` / `--write_iops_log`,
`sar -o` CSV, collectd). Now if the first row's fields are all numeric there is
no header — synthesise `A,B,C…` and keep every row. redis-benchmark-csv (which
has a real header) is unaffected. Golden regression **0 changed / 0 deleted**
from the csv change.

Coverage 2108/2139 → **2115 / 2151** (✅ 1922 generic · ✅ʰ 58 · ✅ᵇ 135);
golden regression 1980 pass / 0 fail / 0 deleted; extract 62/62, smoke 49,
melt 10, holdout 68/68.
Files: `tests/corpus/inputs/fio-*.txt` (+12), `tests/corpus/expected.tsv`,
`tests/corpus/expected/` (+7 goldens), `extract/strategies/structured/csv.sh`,
`tests/corpus/COVERAGE.md`, `tests/corpus/README.md`, `HANDOFF.md`.

## 2026-07-10 — +99 benchmark tool formats + generic markdown pipe-table parser

Added 99 unique benchmark-tool outputs (0 basename overlap with the existing
2040) spanning every benchmarking domain — CPU/system (sysbench, stress-ng,
coremark, 7z b, openssl speed, geekbench, unixbench, spec-cpu, perf-stat, …),
memory (STREAM, mbw, tinymembench, ramspeed), disk/IO (fio, ioping, bonnie++,
iozone, dbench, kdiskmark), network (netperf, qperf, sockperf, iperf2, tcpkali),
HTTP load (ab, hey, bombardier, oha, autocannon, siege, wrk2, h2load, vegeta,
tsung, goose, artillery), database (pgbench, redis-benchmark, memtier, YCSB,
cassandra-stress, hammerdb, tpcc), GPU/compute (glmark2, clpeak, gpu-burn,
mixbench, hashcat, blender), language microbench (JMH, BenchmarkDotNet,
google-benchmark, pytest-benchmark, cargo/go bench, nanobench, tinybench,
vitest), and compression (zstd -b, lzbench, brotli).

- **94/99 tidy with no per-tool code.**
- **New generic `delimited/pipe-table` parser** for GitHub-flavored markdown
  tables (`| a | b |` rows + a `|---|---|` rule) — closes BenchmarkDotNet and
  generalizes to any markdown table. Distinct dialect from psql-table (no outer
  pipes, `+` joints) so it collides with nothing; ships with sample + strategy
  golden. Golden regression 0 changed / 0 deleted from adding it.
- The 5 misses (stream-benchmark, kdiskmark, pytest-benchmark, lzbench,
  blender-benchmark) are the documented multi-word-header + banner hard tail.
- Coverage 2014/2040 → **2108 / 2139** (✅ 1915 generic · ✅ʰ 58 · ✅ᵇ 135);
  golden regression **1972 pass / 0 fail / 0 deleted** (94 new benchmark
  goldens); extract 62/62, smoke 49, melt 10, holdout 68/68.
  Files: `tests/corpus/inputs/*.txt` (+99), `tests/corpus/expected.tsv` (+99),
  `tests/corpus/expected/` (+94 goldens),
  `extract/strategies/delimited/pipe-table.sh` (+ sample + strategy golden),
  `tests/corpus/COVERAGE.md`, `tests/corpus/README.md`, `HANDOFF.md`.

## 2026-07-10 — Close 41 of the 67 corpus format gaps with generic capabilities

Worked the full ⏳ list (39 from the batch-2 expansion + 28 older). Every fix
is a format-level rule, a new format parser, or a tidy-melt improvement — **no
per-tool parser was added**. Coverage 1973 → **2014 / 2040** (✅ 1822 generic ·
✅ʰ 56 hint · ✅ᵇ 136 bespoke); ⏳ 67 → 26. Golden regression **1878 pass / 0
fail / 0 deleted** (48 changed goldens audited neutral-or-better — real headers
instead of eaten first rows, correct multi-word labels, php-i's real kv fields);
holdout 68/68.

- **melt: lone key/value → long form.** A 1-col × 1-row wide (the shape of a
  version banner or one-line status) now melts to canonical `field`/`value`
  long form. Closes ~15 single-pair inputs (distrobox/nats/nx/task/envoy
  versions, tofu-plan-summary, tasmota-status, …). +2 melt unit checks.
- **New `structured/go-struct` parser** for Go `%+v` struct dumps
  (`{Key:value Key:value …}` — helm/kustomize/kubectl version banners).
- **text-lines**: the markup guard now requires a document to OPEN with `{`/`[`
  and close with a matching bracket — a mid-line `{` (vboxmanage UUIDs, exabgp
  blocks, `[INFO]` tags) is just text; a lone ≤3-token period-free line is a
  status record (gamemode, signify).
- **aligned-columns header heuristics** (the big one): value-token contrast
  replaces raw digit-count for header promotion (labels like `IPv4`/`1K-blocks`
  no longer confuse it, and promotion demands a label-looking row); all-text
  tables promote a styled disjoint header (dependabot-alerts, spark-sql) while
  name grids and prose stay headerless; 2-column value tables are recognized
  (go-mod-graph, redis latency); leading chrome is dropped (wide banner lines —
  `w`, numastat; trailing-colon titles — vagrant; ellipsis progress lines —
  apt); `=`-rules treated like `-`-rules (tokei); `#`-comment headers picked by
  token-count fit (nvidia-smi dmon); positional assignment extended to all-text
  multi-word labels (ibmcloud `Service Name`, spin `Name Description`).
- **Manifest corrections (verified clean output)**: go-test-summary 3→4 rows,
  perf-list 8→9.
- The remaining 26 ⏳ are documented in `HANDOFF.md` — nested/2-line-header/
  ragged formats needing capability that would risk golden churn, plus a few
  genuinely-not-a-dataset one-liners.
  Files: `transform/melt.sh`, `transform/tests/test_melt.sh`,
  `extract/strategies/delimited/{aligned-columns,text-lines}.sh`,
  `extract/strategies/structured/go-struct.sh` (+ sample + strategy golden),
  `tests/corpus/expected.tsv`, `tests/corpus/expected/` (52 new, 48 updated),
  `tests/corpus/COVERAGE.md`, `tests/corpus/README.md`, `HANDOFF.md`.

## 2026-07-10 — +500 more unique corpus inputs (batch 2): 1540 → 2040 tools

Second +500 expansion of the tidy-coverage corpus with tools never seen by the
first ~1540 (0 basename overlap, 432 distinct tool prefixes) across fresh
domains: data engineering, ML serving, security scanners, bioinformatics,
blockchain, distributed storage, APM, CI/CD, cloud services, container/k8s
tooling, terminal monitors, HTTP clients, editors/gaming, and a large block of
`--version` banners. This measures **generalization** (unseen tools) against the
frozen-fixture corpus that measures regression.

- **461 / 500 (92.2%) came out tidy with no new per-tool code** — 454 via a
  generic parser (auto-detected), 7 via a bespoke fallback — mirroring batch 1's
  466/500. No bespoke parser was added and no engine change was made; this batch
  is pure corpus expansion (the batch-1 gap-closing engine work rode in the
  previous entry).
- **Corpus coverage 1512/1540 → 1973 / 2040** (✅ 1771 generic, ✅ʰ 55 hint,
  ✅ᵇ 147 bespoke). 454 new goldens regenerated; golden regression 1826 pass /
  0 fail / **0 deleted** (no existing tool lost its golden).
- **39 batch-2 gaps left as an honest ⏳** — not manifest errors and not worth a
  bespoke: ~19 single-line `--version`/one-liner banners that are genuinely not
  datasets, and ~20 tables that need generic capability the format tier doesn't
  yet have (headerless tables whose first data row is eaten as the header —
  go-mod-graph, git-log-oneline, retroarch-cores, redis-cli-latency-history;
  ragged/tree tables — ceph-osd-tree, scylla-nodetool-status; header-not-promoted
  — dependabot-alerts, spark-sql-show-tables; colon-delimited getent-group).
  Files: `tests/corpus/inputs/*.txt` (+500), `tests/corpus/expected.tsv`
  (+500 manifest rows), `tests/corpus/expected/*.tsv` (+454 goldens),
  `tests/corpus/COVERAGE.md`, `tests/corpus/README.md`, `HANDOFF.md`.

## 2026-07-10 — Close 6 of the 34 corpus gaps (json-array rewrite, box-table parser, 2 hints)

Worked the format gaps the +500 expansion surfaced, closing the ones with a
genuine generic home (no memorization) and leaving the rest as an honest ⏳
capability shopping list. Coverage 1506 → **1512 / 1540**; ⏳ 34 → 28.

- **json-array rewritten as a real JSON scanner.** It previously only handled
  objects spread over multiple lines; compact one-object-per-line arrays
  (`[{"a":1,"b":2},…]` — what rclone, shellcheck, meson-introspect and most
  `--format json` tools emit) produced nothing. The new char-scanner handles
  both shapes and correctly skips nested objects/arrays as values — which also
  fixed docker/podman-inspect goldens (the old code emitted a garbage `Args [`
  cell from a nested array). Closes rclone-lsjson, shellcheck-json,
  meson-introspect-targets.
- **New `delimited/box-table` parser** for Unicode box-drawing tables
  (`│` cells, `─┼╭╮╰╯` borders) — the format modern Rust/Python CLIs render
  (pdm, gum, glow, …). Closes pdm-list and generalizes; it only fires on a
  genuine `─`-rule + `│`-row, so ASCII tables stay with psql-table and tree
  output is untouched. (Also incidentally gave hexyl-output a real
  offset/hex/ascii tidy instead of its old 1-column box-border garbage.)
- **2 hint rows** (verified clean, not shape-only): iw-dev-scan-summary and
  nvidia-smi-topo → aligned-columns.

The remaining 28 ⏳ are genuinely non-tabular (weather ASCII art, one-line
version banners / error messages, prose status, nginx config, Go `BuildInfo{}`
struct printing) or need real new capability (2-column tables whose last
column is free text — spin/vagrant/bluetoothctl/ansible-galaxy/go-test;
sysstat timestamp+%% headers — sar-cpu; nested tab records — kafka-topics).
Forcing them would be memorization, so they stay honest ⏳.

Coverage: 1512/1540 — ✅ 1321 generic, ✅ʰ 51 hint, ✅ᵇ 140 bespoke, ⏳ 28.
Gate: smoke 49/49, melt 8/8, extract 62/62, analyze green, golden 1372/0.

## 2026-07-10 — Corpus +500: 500 new unique tool inputs; 93% tidy on never-seen tools

Expanded the corpus from 1040 to **1540 inputs** — 500 new, genuinely-unique
Linux tool outputs across ~418 tool families, none overlapping the existing
set (generated collision-checked against every existing corpus name; 80
guessed candidates that collided were dropped). Domains span containers/k8s
extras, cloud CLIs (AWS/GCP/Azure/DO/Fly/Hetzner/Linode), message queues
(kafka/nats/pulsar/rabbitmq), search (ES/OpenSearch/Solr/Meili), databases,
observability (prom/loki/otel/jaeger/vector), PKI & scanners (trivy/grype/
syft/cosign/step), backup/sync (restic/borg/kopia/rclone), virtualization
(virsh/lxc/incus/multipass/proxmox), HPC (slurm/pbs/lsf/mpi), package
ecosystems (brew/nix/apk/emerge/conda/uv/gem/opam/…), dev/build/lint/test,
media (ffprobe/mediainfo/pactl/v4l2), hardware/sensors, /proc & /sys, shells/
terminal, data/text tools, DNS & routing daemons, and 38 version banners.

**This doubles as the largest generalization test yet of the generic-first
engine — brand-new tools it has never seen:**
- **466 / 500 (93%) come out tidy**, essentially all via generic parsers +
  hint rows, with ZERO new per-tool code written for them.
- 34 are genuine format gaps, now honest ⏳ (the next-capability shopping
  list): multi-section colon blocks (sensors, cryptsetup), tab/space hybrid
  tables (kafka-topics, nvidia-smi topo, sar), `key{...}`/BuildInfo banners
  (helm-version), tree/graph dumps (nginx -T, frr bgp), and one-line status
  messages that aren't tables at all (batch-jobs, iconv).
- No existing corpus input regressed.

Full-corpus coverage: **1506 / 1540 — ✅ 1317 generic, ✅ʰ 49 hint, ✅ᵇ 140
bespoke, ⏳ 34.** 462 new goldens frozen; golden regression 1366/0.
Manifest note: 21 of the initial "misses" were my hand-authored expected
shapes being wrong (the engine's output was clean named columns) — those
manifest rows were corrected to the verified output; only the 34 genuine
gaps remain ⏳.
Gate: smoke 49/49, extract 62/62, corpus golden 1366/0.

## 2026-07-10 — Exhaustive bespoke-reduction sweep: 5 conversions, colon-pairs parser, and the measured floor

An exhaustive sweep forced every remaining ✅ᵇ input through every generic
strategy via the hint path (detect bypassed — hints run strategy_extract
directly, so this finds matches ordinary detection never would). Each
candidate was verified as the actual dispatch winner (a first, broken sweep
measured the bespoke's own output through hint fall-through — the winner
check is now part of the method) and then eyeballed for content quality
against the bespoke's output, not just manifest shape.

**The measured floor:** of 139 swept inputs, 60 shape-pass under some
generic strategy — but only 4 meet the quality bar. The other 56 are
shape-passing mush (shredded banners, csv/prometheus parsers claiming
non-csv/non-metrics text, key/value blobs), the same failure class the
golden-quality audit reversed. The remaining bespoke tail is now
EVIDENCE-BASED irreducible without new generic capabilities; the sweep
previews identify the missing ones: version-banner → named fields,
nested/stateful multi-line records (lsusb -v, gpg, multipath trees),
number+unit merging, and inline-label splitting.

**Shipped from the sweep:**
- 4 hint conversions (bespokes deleted): consul-kv-get-recurse →
  block-records, cpuid-summary → block-records, systemctl-list-units →
  aligned-columns, tshark-summary → line-records.
- 1 new generic capability closing an identified gap:
  `delimited/colon-pairs` — inline "Label: value  Label: value" status
  lines with multi-word labels (mysqladmin status; the format also appears
  in memcached/redis one-liners). Priority 11 (ahead of yaml, which
  otherwise claims the line as one column); detect requires ≤4 lines with
  ≥4 pairs each, so it cannot reach into documents. mysqladmin-status
  converts with field-for-field identical output to its bespoke, by
  detection alone (no hint row).

Coverage: 1040/1040 — ✅ 859 generic, ✅ʰ 45 hint, ✅ᵇ 136 bespoke.
Strategy files 168 → 164. Holdout 66 → 68 (68/68).
Gate: smoke 49/49, melt 8/8, extract 62/62, analyze green, corpus golden
904/0.

## 2026-07-10 — Three rounds: json-array + diffstat parsers, snmp-output promotion, sqlite-output deleted, holdout 66/66

**Round A — `structured/json-array`.** A top-level JSON array of objects is a
list of records; the `json` strategy flattened it into one 0.field/1.field
row. json-array (structural detect: `[` then `{` plus a `"key":`) emits one
record per element. Replaces `cloud-json-list` (same extract, tool-specific
detect guards). 4 inputs flip ✅ᵇ→✅ (az-account-list, az-acr-list,
az-keyvault-list, gcloud-pubsub-topics-list); the inspect quartet
(docker-inspect, docker-network/volume-inspect, podman-inspect) upgrades to
clean per-element records.

**Round B — `delimited/diffstat` + snmp-output promotion + sqlite-output
deleted.** diffstat parses the block every `git --stat` variant prints
(file/changes/graph per line, files-changed summary as scalars), declining
commit-header inputs (git-log-stat's domain). git-diff-stat +
git-stash-show-stat flip to it from sqlite-output, which had been winning
them accidentally with a broken parse. snmp-output moves to structured/
(its detect is purely the Net-SNMP `MIB::oid = TYPE: value` format);
snmpget + snmpwalk flip ✅ᵇ→✅. sqlite-output then had zero corpus wins and
was deleted — it was also the engine's most notorious hijacker (7z,
jmap-histo, dnf-history all carried guards against it).

**Round C — holdout 48 → 66.** 18 new unseen variants (untested hint rows,
kubectl/toml/jsonl/psql-table/exposition-histogram/kernel-log, new-parser
variants). Two failures root-caused: both `aws-s3-ls` and `dmsetup-table`
hint rows targeted aligned-columns, whose shape detection returns empty on
ragged mixed-width rows (PRE dirs + dated files; crypt vs linear targets) —
retargeted to line-records, which handles ragged rows positionally. The
corpus dmsetup-table golden gained four columns of previously-dropped
parameters in the process.

**Holdout: 66/66 tidy on unseen output — 43 generic, 21 hint, 2 bespoke.**
Coverage: 1040/1040 — ✅ 860 generic, ✅ʰ 39 hint, ✅ᵇ 141 bespoke.
Strategy files: 168 (37 generic + 131 bespoke).
Gate: smoke 49/49, melt 8/8, extract 62/62, analyze green, corpus golden
899/0.

## 2026-07-10 — Promote exposition-format + syslog to the generic tier (−4 bespoke-covered inputs)

Both parse standard FORMATS, not tools, so they belong in the generic
directories (the same reasoning that promoted `bracket-log`):
- `structured/exposition-format` — the Prometheus/OpenMetrics text format.
  Its extract now splits the label set into one `label_<key>` field per
  label (method, code, cpu, …) instead of a single opaque `labels` blob, so
  the melted table gets a real column per label key.
- `delimited/syslog` — BSD syslog lines. Its detect now requires a
  MAJORITY of non-blank lines to open with the syslog timestamp, so a
  status block that merely embeds a journal tail (`systemctl status`) is
  declined instead of hijacked — caught by the corpus gate during the
  promotion.

Effects: 4 inputs gained generic goldens (blackbox-probe, journalctl-k,
journalctl-u, mysqld-exporter), 5 goldens upgraded (arpwatch + journalctl
from positional mush to timestamp/hostname/process/message; the metrics
trio keeps split labels), and the two strategies now serve unseen
prometheus/syslog captures in generic mode — verified by two new holdout
entries (app-metrics, auth-log), both tidy first try.

Coverage: 1040/1040 — ✅ 852 generic, ✅ʰ 39 hint, ✅ᵇ 149 bespoke.
Holdout 46 → 48 (48/48 — 32 generic, 13 hint, 3 bespoke). The empty
`extract/strategies/logging/` category retires (only its HANDOFF remains).
Gate: smoke 49/49, melt 8/8, extract 63/63, analyze green, corpus golden
891/0.

## 2026-07-10 — dns-records generic parser collapses the DNS bespoke family (−6 strategies)

`structured/dns-records` parses the standard BIND presentation format
(`name ttl class type rdata`) that every dig/drill/host query prints — one
record per RR line in any section, MX rdata split into preference/exchange,
TXT quotes stripped. It replaces six bespokes with one format parser:
`dig-answer`, `dig-output`, `dig-mx`, `dig-txt`, `drill`, and `host_a`
(`host -a` output is the same RR format). All 10 corpus inputs they covered
flip ✅ᵇ→✅ with named columns, plus two free golden upgrades (`delv` was
"; fully validated"-header mush; `dig_noall_answer` was positional A–E).
A `host` hint row (` has address ` → text-lines) keeps prose `host` output's
dataset identity now that the host_a bespoke is gone.

Holdout grown 40 → 46 (dig AAAA, drill MX, host prose, psql -x single-record,
multi-LV lvdisplay, faillock per-user) — all pass first try: **46/46 tidy on
unseen output — 30 generic, 13 hint, 3 bespoke.**

Coverage: 1040/1040 — ✅ 848 generic (+10), ✅ʰ 39, ✅ᵇ 153 (−11).
Strategy files 173 → 168 (1 added, 6 deleted).
Gate: smoke 49/49, melt 8/8, extract 63/63, analyze green, corpus golden
887/0, holdout 46/46.

## 2026-07-10 — Generic parsers for the labeled-record cluster; holdout grown to 40 (40/40)

**Two new format parsers** attack the biggest shape in the bespoke tail
("one record over many labeled lines"):
- `structured/psql-expanded` — any `psql \x` output, one record per
  `-[ RECORD N ]` block of `key | value` lines. Replaces the
  `psql-pg-stat-bgwriter` bespoke (single-record, keyed on one table's
  column names) with identical output.
- `delimited/dashed-sections` — `--- Section ---` banners over aligned
  label/value lines, one record per banner (banner kept as a `section`
  column). Replaces the `lvdisplay-m` bespoke (which dropped every section
  after the first) and upgrades `pvdisplay`/`vgdisplay` from garbage-header
  mush to full named columns.

**Holdout grown 24 → 40 unseen variants** (`tests/corpus/holdout/`), and the
four failures it surfaced were fixed at the root:
- `pkg-config` detect: declines headed tables — a first line without the
  ` - ` name/description separator while later lines have it (yum/dnf
  repolist), and Title-Case 3+-token header lines (lastlog's
  "Username Port From Latest").
- `lastb` detect: declines lastlog's "Username …" headed table.
- `aligned-columns`: a blank line after header + data ends the table when a
  footer legend follows (next non-blank line contains " = ", e.g.
  `systemctl --failed`'s LOAD/ACTIVE/SUB explanations); tables that resume
  after a blank (faillock's per-user sections) keep collecting.
- New `getcap` hint row (`/path cap_…` → line-records).

Result: **holdout 40/40 — 25 generic, 12 hint, 3 bespoke.**
Coverage: 1040/1040 — ✅ 838 generic, ✅ʰ 38 hint, ✅ᵇ 164 bespoke.
Strategy files 170 → 170 (2 added, 2 deleted).
Gate: smoke 49/49, melt 8/8, extract 63/63, analyze green, corpus golden
876/0, holdout 40/40.

## 2026-07-10 — QUALITY: golden audit (restore 13 bespokes, promote bracket-log), traceroute6 fix, held-out generalization set

Follow-through on the generic-first refactor's three open items.

**Golden-quality audit** (the refactor's manifest-tidy criterion checks shape,
not content — this pass checked content):
- Audited all 62 goldens the refactor changed, old parser output vs new. Most
  positional `c1..cN` conversions are faithful and several improved (apk-list,
  node-exporter, promtool-query gained proper labels); 18 tools had real
  damage — shredded records, garbage headers (`--- Logical volume`,
  `-[ RECORD 1 ]`), or lost fields.
- `bracket-log` promoted to `strategies/delimited/` (it parses a format —
  `[ts] message` lines — so it belongs in the generic tier): dmesg-hw, lsscsi,
  mvn-dependency-list/-tree, service-status-all now tidy generically with
  named `timestamp`/`message` columns.
- 13 bespokes restored where quality beats the generic parse (the
  free/docker-ps rule): R-version, lvdisplay-m, psql-pg-stat-bgwriter,
  haproxy-vv, mysqladmin-status, lsusb-v, git-branch-vv, snmp-output
  (snmpget+snmpwalk), lspci-tv, numactl-show, fossil-status,
  proc-filesystems, systemd-cgls. 11 hint rows that had been shadowing them
  with worse parses were dropped (35 rows remain).

**traceroute6 — last coverage gap closed:** the columnar-specs traceroute spec
required 9 tokens/row, silently dropping `* * *` timeout hops; minreq is now 4
with `@opt` rtt columns, so timeout hops emit as rows.
**Coverage: 1040/1040 — ✅ 838 generic, ✅ʰ 37 hint, ✅ᵇ 165 bespoke, ⏳ 0.**

**Held-out generalization set** (`tests/corpus/holdout/`): 24 second samples
of covered tools — different hosts/versions/values/flags, no goldens — judged
on tidy shape only, the way unseen captures are. `holdout/run.sh` runs full
mode and attributes each win to a tier. Current: **24/24 tidy on unseen
output — 12 generic, 10 hint, 2 bespoke** (free, ping — both intentional).
This is the direct measure of the "process inputs I haven't seen" goal; the
frozen-fixture corpus only measures regression.

Files: extract/strategies/** (restores + bracket-log move),
extract/hints.tsv, extract/strategies/delimited/columnar-specs.sh,
tests/corpus/holdout/** (new), tests/corpus/expected/** (regen),
tests/corpus/{README,COVERAGE}.md, README.md, HANDOFF.md.
Verified: smoke 49/49, melt 8/8, extract 63/63, analyze green, corpus golden
875/0, holdout 24/24.

## 2026-07-09 — REFACTOR: generic-first extraction — hints table, honest metric, −218 bespoke parsers

The project goal ("as many inputs with as few instructions as possible, no
bespoke parsers, generalize to unseen input") was being defeated by drift: 375
strategy scripts (~36k lines), a `## Technique: yes` header tag applied to
~145 per-tool parsers so they counted as "generic" in the coverage metric, and
a long tail of parsers each memorizing exactly one corpus fixture.

**Engine** (`extract/envoy-extract`, `extract/lib/_discovery.sh`):
- `--generic` is now **directory-based**: only `strategies/delimited/` +
  `strategies/structured/` (28 files) participate. The `## Technique:` tag is
  removed everywhere and no longer read; `--list-strategies` shows `[G]` (by
  location) instead of `[T]` (by tag). The scaffolding tool
  (`extract/tools/new_strategy.sh`) no longer emits the tag.
- New **declarative hints layer**: `extract/hints.tsv` — one TAB row
  (tool, match-type prefix|contains|regex, structural signature, target
  strategy) routes a recognized tool to an existing strategy before
  auto-detection, bypassing the target's detect. Reports the tool name via
  `_STRATEGY_REPORT_NAME` (dataset identity without parser code). New flag
  `--no-hints`; `MFE_HINTS_FILE` overrides the path. Under `--generic`, hints
  may only target generic strategies. 46 rows cover 50 corpus inputs.

**Corpus** (`tests/corpus/run.sh`, `COVERAGE.md`, `README.md`):
- Coverage is now three-tier and honest: ✅ generic auto-detected · ✅ʰ
  hint-routed · ✅ᵇ bespoke script. Result: **1039/1040 — ✅ 836, ✅ʰ 50,
  ✅ᵇ 153, ⏳ 1** (`traceroute6`, whose previous "covered" entry was stale;
  the old headline "989 via a generic parser" was tag-inflated — the honest
  pre-refactor split was ~777 generic / ~274 per-tool).
- Goldens regenerated (886, `--golden` 0 failed): 27 added, 62 updated
  (hint-routed inputs changed parser), **119 deleted deliberately** — their
  old "generic" goldens were pseudo-generic per-tool parser output; those
  inputs are now honestly ✅ᵇ (bespoke-covered, no golden), like every other
  bespoke tool. This is the intended exception to the "deleted golden =
  regression" rule; the coverage table confirms none dropped to ⏳.

**Deletions** (−220 strategies +2 restored = net −218; 375 → 156 strategy
files, strategy code roughly halved):
- Every bespoke strategy whose corpus inputs stay manifest-tidy via a generic
  parser or hint row, plus their samples, goldens, and `test_strategy_*.sh`
  files. Engine-level tests referencing deleted strategies (`ini`,
  `pipe-table`, `network-hops`, `test-results`, `http-headers`,
  `curl-headers`, `warc-headers`, `env-vars`, `journald`, snapshot cases)
  were pruned.
- `free.sh` and `docker-ps.sh` were **restored** after the smoke test showed
  the generic parse is shape-tidy but qualitatively worse (merged columns) —
  bespokes that beat the generic stay.
- The unused config-file format parsers (`ini`, `hcl`, `properties`,
  `crontab`, `dockerfile`, `systemd-unit`, `nginx-conf`) were deleted: no
  corpus input needs them (glean's domain is command output) and `ini` was
  grabby enough to hijack `dbmate-status`/`sbt-dependencytree`.

**Detection-order fixes** (full mode):
- `git-log-stat` p22→13 (before `git-log` p14); requires diffstat lines so it
  can't hijack plain logs; also covers `git show --stat`, so `git-show-stat.sh`
  was deleted.
- `nmap-sn` p26→14 (before `nmap` p15) and its detect now declines outputs
  containing a `PORT … STATE` table.
- `bundle-outdated`/`semanage-boolean` p26→12 (before the grabby `pkg-config`
  p21, which stays: it legitimately, if accidentally, tidies
  `consul-catalog-services` and `systemd-analyze-time` as before).

**Cleanup:**
- Deleted the orphaned analyze `test_browse_*`/`test_dashboard_*`/
  `test_help_overlay.sh`/`test_mdx.sh` (surfaces glean doesn't ship). The raw
  `analyze/tests/run_tests.sh` is green now; CI runs it unfiltered.
- Deleted 7 unreferenced shared libs: `lib/envoy_{common,format,humanize,spinner,status,tasklist}.sh`,
  `lib/exit_codes.sh`.
- Docs updated: `README.md` counts, `tests/corpus/README.md` (three-tier
  model), strategy-dir HANDOFFs, `docs/columnar-specs-engine.md`,
  `extract/lib/_globals.sh` comment.

Verified: smoke 49/49, melt 8/8, extract 63/63 files, analyze suite green,
corpus `--golden` 886/0, coverage 1039/1040.

## 2026-07-09 — Fix 3 mis-shadow bugs (bespoke now wins via priority)
Three tools were mis-parsed because a greedy generic parser out-prioritized the
correct bespoke. Fixed by lowering each bespoke's `## Priority` below the greedy
competitor — safe because each bespoke's `detect()` is specific to its own tool
(so no other tool's winner changes):
- `systemctl-status` (22→19): was won by `syslog` (misparsed the unit block as
  journal rows); now yields `unit/description/loaded/active/since/main_pid/…`.
- `fail2ban-status` (20→10): was won by `key-value` (mangled the `|-` tree); now
  yields the named jail/filter/actions columns.
- `ulimit` (25→20): was won by `pkg-config` (mis-split `name (…, -x) value`); now
  yields `resource/flag/value` (e.g. `core file size | c | 0`).
Bespoke output bytes unchanged (priority-only), so goldens stay valid. Verified
no other tool changed winner via a full-corpus winner-scan diff. Gate: extract +
smoke 49/49 + melt 8/8. This clears 3 of the 4 mis-shadow bugs from docs/0002 /
HANDOFF; `cargo-tree` (competitor is a columnar-specs spec) is deferred.

## 2026-07-09 — Prune 13 redundant bespokes (tidy-first bar)
Under the reframe (docs/0002 — judge output on tidy/meaningful merits, not
byte-fidelity), retired 13 per-tool bespoke strategies that **never win their own
corpus input** because a sibling or generic parser already produces tidy, usable
output. Verified via a full-corpus (1040-input) winner scan: each retired bespoke
wins zero corpus inputs, so deletion is full-mode output-neutral.

Retired → replaced by: `docker-inspect`→`json`, `iostat`→`iostat-d` (spec),
`ip-addr`→`ip-link`, `iperf3`→`iperf3-intervals`, `podman-ps`→`docker-ps`,
`rocm-smi`→`rocm-smi-concise`, `host`→`host_a`, `terraform-plan`→
`terraform-plan-actions`, `perf-stat`→`perf-counters` (also removes the known
duplicate file in benchmark/ + profiling/), `lscpu`→`key-value`,
`proc-meminfo`→`yaml`, `valgrind-summary`→`valgrind`, `perf-report`→
`aligned-columns`. Each deletion removed the strategy + its `test_strategy_*.sh`
+ golden + sample; `test_search.sh`'s AND-semantics example repointed
docker-inspect→docker-stats.

NOT retired — 4 mis-shadow **bugs** where the bespoke is better but a greedy
parser wins with worse output (deleting would lock in the worse output; these are
detection fixes, tracked separately): `cargo-tree` (→`poetry-show-tree` flattens),
`fail2ban-status` (→`key-value` mangles), `systemctl-status` (→`syslog` misparses),
`ulimit` (→`pkg-config` misparses).

Gate: extract suite + smoke 49/49 + melt 8/8 green; corpus golden unaffected
(generic-mode, excludes bespokes). Strategy count: ~374 → ~361 distinct.

## 2026-07-09 — Nameless columns: spreadsheet-style A,B,C… (was c1,c2,c3)
Renamed the placeholder labels glean emits for genuinely-nameless columns from
`c1,c2,c3…` to the spreadsheet convention `A,B,C…,Z,AA,BB,CC…`. `c1` reads as an
apologetic internal placeholder ("we failed to name this"); `A` is the universal
positional-column convention every spreadsheet user already understands as
"unnamed column N, label it yourself." Same information, better affordance.
- New helper `_col_letter <1-based idx>` in `extract/lib/_helpers.sh`
  (1→A … 26→Z, 27→AA, 28→BB, 29→CC …; self-tested through AAA).
- Wired into the generic parsers that mint nameless labels: `aligned-columns`,
  `colon-fields`, `line-records`, `text-lines`, `psql-table` (header fallback),
  and `structured/tsv`; plus the 5 `columnar-specs` `@line` specs (`c1@line`→
  `A@line`) and 14 single-column columnar bespokes (`.c1`/`.c2`→`.A`/`.B`).
- Regenerated 17 extract goldens + 224 corpus goldens; every diff verified as a
  clean header-only positional rename (0 value drift, 0 multi-line changes).
- Gate green: extract **213/213**, corpus golden **991 passed / 0 failed**
  (up from 978 — the regen also captured goldens for 13 previously-uncovered
  tidy tools), smoke **49/49**, melt **8/8**.
- Rationale + the broader "judge output on tidy/meaningful merits, not bespoke
  byte-fidelity" reframe: **docs/0002-tidy-first-and-nameless-columns.md**.

## 2026-07-09 — FIX: repoint/repair migrated tools' dedicated tests; revert crontab
Caught a real regression: removing a bespoke leaves its dedicated
`extract/tests/test_strategy_<tool>.sh` calling `-s <tool>` (now "Strategy not
found"), which fails the CI-enforced extract suite. Only `mount`'s test had been
repointed; later migrations hadn't — so `test_strategy_crontab.sh`,
`_beegfs.sh`, `_tar_listing.sh`, and `_ls_l.sh` were red (and shipped that way in
earlier commits). Fixes:
- Repointed `beegfs`, `tar-listing`, and `ls-l` tests to `-s columnar-specs`.
- **Reverted `crontab`**: its `## Sample` includes `SHELL=`/`MAILTO=` env-var
  lines that the bespoke extracts but the job-only spec drops — the batch-7
  byte-check used the corpus input (which lacks them), not the richer sample.
  crontab bespoke + test + golden restored; **373 → 374 distinct names**.
- Process note: verify each migration against the strategy's `## Sample`
  (what `test_strategy_*.sh` exercises), not only the corpus input, and read the
  extract suite's final `Overall:` line + exit code.
- Verified: extract **213/213 (exit 0)**, golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: report the matched tool name (per-tool datasets)
Fixed a latent issue affecting every columnar-migrated tool: `glean` names a
dataset after the winning *strategy*, so all migrated tools collapsed to a single
`columnar-specs` dataset (and different tools would reconcile/collide into it).
Now `strategy_detect` sets `_STRATEGY_REPORT_NAME` to the matched tool name and
the engine (`extract/lib/_discovery.sh`) uses it for the dispatch winner, the
`matched` list, and the `STRAT-<name>` label — so `mount | glean` → dataset
`mount`, `iostat -d | glean` → `iostat-d`, etc. Cleared before each strategy's
detect so a name never leaks; set in `strategy_detect` (parent shell) because
`strategy_extract` runs in a command-substitution subshell.
- Files: `extract/strategies/delimited/columnar-specs.sh`,
  `extract/lib/_discovery.sh`, `docs/columnar-specs-engine.md`.
- `free` stays bespoke (smoke's canonical reconciliation/provenance example).
- Verified: extract all-pass, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: migrate 5 more (git-remote, w, dpkg -l, tar, beegfs)
Migrated five more bespokes with existing engine features — **378 → 373 distinct
strategy names**. Each byte-identical to its bespoke (verified against the
strategy's `## Sample`):
- `git-remote` (`@unwrap` on `(fetch)`/`(push)`), `w-sessions` (`what@rest`),
  `dpkg-list` (`dpkg -l`; `description@rest`), `tar-listing` (structural `re:`
  detect, `~time` drop, `path@rest`), `beegfs` (`target` prefix, `~node_id`).
- `tar`/`dpkg-c` generic goldens regenerated as **improvements** (old `c1..c6`
  incl. the time token → now named `permissions/owner/size/date/path`).
- **`free` NOT migrated** (reverted): it exposed that the `glean` tool names a
  dataset after the winning *strategy*, so every columnar-migrated tool would
  create a `columnar-specs` dataset instead of one named for the tool — the
  smoke suite guards this via `free`. This is a latent property of the whole
  columnar-specs approach (all migrated tools share the `columnar-specs`
  identity); a follow-up should let a matched spec report its own name so
  datasets stay per-tool. `free` stays bespoke until then.
- Verified: extract all-pass, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: configurable record prefix; migrate crontab
New engine feature **`prefix`** (spec field 10, default `entry`): some bespokes
label records `jobN`/`commitN`/… instead of `entryN`. Migrated `crontab`
(`job` prefix, `command@rest`, `rowre ^[^#]` drops the header comment) —
byte-identical; **379 → 378 distinct strategy names**. crontab generic golden
regenerated (clean `minute/hour/…/command` columns).
- Reverted `git-log`: its `re:^[0-9a-f]{7} ` detect matched any hex-prefixed
  line and hijacked 8 tools (7z, nvme-list, vagrant, vault-*, …) — a bare
  `hash message` list has no distinguishing one-line signature.
- Doc updated (field 10 `prefix`).
- Verified: extract all-pass, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: migrate 8 more (nethogs…traceroute)
Migrated eight more bespokes with existing engine features — **387 → 379
distinct strategy names**:
- `nethogs`, `slabtop`, `objdump-headers`, `iptables-save` (`~sep` + `@rest`),
  `ldconfig-p` (`@unwrap` + `~sep`), `perf-top` (`~sep` + `@rest`), `turbostat`,
  `traceroute` (`~sep` on the `ip`/`ms` tokens). Each byte-identical.
- `iptables-save` generic golden regenerated — generic mode now yields clean
  `chain`/`rule` columns instead of the old whole-line dump (`# Generated by…`,
  `*filter`, `:INPUT ACCEPT` junk rows).
- Reverted `pkg-config`: its `re:^[a-z0-9.+-]+ {2,}[A-Za-z]` detect matched *any*
  aligned 2-col table and hijacked 117 tools (aws/az/argocd lists) — a 2-col
  `name description` list has no distinguishing signature for a one-line detect.
- A migration worklist was built by a subagent; ~31 of its 42 candidates turned
  out to be `Technique: yes` generic parsers (excluded per the getconf lesson).
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: migrate 3 more (memcached/es-cat/bundle-list)
Migrated three more bespokes with existing engine features — **390 → 387
distinct strategy names**:
- `memcached-stats` (`~sep` drops the `STAT` literal), `es-cat-allocation`
  (9-col ES table), `bundle-list` (`~star` + `@unwrap`, `rowre` drops the
  footer). Each byte-identical.
- **Lesson recorded** (doc + harness): a `## Technique: yes` strategy is a
  **generic multi-tool parser**, not a per-tool bespoke — `getconf` also tidies
  `docker-diff`/`nats-stream-ls`, so migrating it 1:1 silently regressed those.
  Reverted getconf and flatpak-remotes (the latter's `Name;Options` detect was
  too greedy). Added `mig.sh technique <name>` and a step-0 check to the recipe.
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: migrate 3 more tables (no new engine code)
Migrated three more bespokes using existing engine features (plain table,
`absorb`, `rowre`) — **393 → 390 distinct strategy names**:
- `route-6` (7-col IPv6 route table), `snap-connections` (4-col), and
  `networkctl-lldp` (`absorb` folds the multi-word `PORT DESCRIPTION`; `rowre`
  `^eth[0-9]` drops the `Capability Flags:` legend footer). Each byte-identical.
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: @line transform; migrate 5 single-column lists
Added the **`@line`** transform — a sole column whose value is the whole trimmed
line (no tokenizing) — for single-column list outputs. Migrated, each verified
byte-identical — **398 → 393 distinct strategy names**:
- `rustc-cfg`, `apache2ctl-modules`, `dub-list`, `lstopo-no-graphics`,
  `lshw-network`.
- Recorded a real engine limit: the `_is_json` pre-check declines any input whose
  first non-blank line starts with `[`/`{`, so bracket-headed outputs (e.g.
  `php -m`'s `[PHP Modules]`) can't be a `columnar-specs` tool — stays bespoke.
- Deferred `@line` variants needing prefix/token/tree-char stripping (go-list,
  cabal-freeze, systemd-cgls, fwupdmgr, mix-deps, pnpm-why).
- Doc `docs/columnar-specs-engine.md` updated (`@line`, JSON-guard limit).
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs: row-guard + @rest transforms; migrate 4 more
Extended the engine with two transforms, each verified byte-identical on the
tools it unlocked — **402 → 398 distinct strategy names**:
- **`rowre`** (spec field 9): a per-row accept regex — process a row only if its
  raw line matches. The engine's first per-row structural guard, for outputs
  whose footer/note lines survive the `minreq` filter. Migrated `gsutil-ls-l`
  (`TOTAL:` footer), `grafana-cli-plugins` (trailing note), `bq-ls` (rule row).
- **`@rest`**: a terminal column that soaks the remaining tokens joined with
  single spaces (verbatim internal spacing, unlike `absorb`'s `_`). Migrated
  `arp-scan` (space-containing `vendor`).
- Detection lessons (both caught by the corpus golden run): a greedy grafana
  `re: @ [0-9]` hijacked CPU-info files → keyed on the `installed plugins`
  header; `composer-show` shares its `vendor/pkg version` shape with docker/go/
  apt/crictl image+package lists (hijacked 13 tools) and was reverted — it needs
  an *all-lines-match* detect mode, now recorded as a future engine feature.
- Doc **docs/columnar-specs-engine.md** updated (field 9, `@rest`, detection
  limitations, migrated-tools list).
- Files: `extract/strategies/delimited/columnar-specs.sh`,
  `docs/columnar-specs-engine.md`, four removed strategy files.
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — columnar-specs batch: migrate 5 more bespokes; add engine doc
Migrated five more bespoke strategies into the `columnar-specs` engine as
one-line specs, each verified **byte-for-byte identical** to the strategy it
replaces before retirement — **407 → 402 distinct strategy names**:
- `iostat-d`, `rabbitmqctl-list-queues`, `goose-status`, `ipmitool-sensor`,
  `dpkg-get-selections` (removed their `extract/strategies/**/*.sh`).
- Tightened the `ipmitool-sensor` detect to its sensor-status field
  (`re:[|] *(ok|na|nc|cr) *[|]`) after a first, too-greedy "≥9 pipes" regex
  hijacked wide bordered SQL tables (`mysql-show-index`,
  `mysql-show-table-status`, `etcdctl-endpoint-status`) — caught by the corpus
  golden run.
- New doc **[docs/columnar-specs-engine.md](docs/columnar-specs-engine.md)**:
  how the engine works, the spec format, transforms, the recipe for adding a
  tool / a transform, and current limitations. To be kept current as engine
  features are added.
- Files: `extract/strategies/delimited/columnar-specs.sh`,
  `docs/columnar-specs-engine.md`, five removed strategy files.
- Verified: extract 213/213, corpus golden 978/0, smoke 49/49.

## 2026-07-09 — richer columnar-specs engine: prove value-add transforms (ss-tulnp)
Extended the `columnar-specs` engine (v1.1) so a spec can express the value-add
work that per-tool bespokes do — not just a flat column map:
- `minreq` — minimum tokens for a row (lets trailing columns be optional)
- `name@opt` — emit a column only when non-empty
- `name@between@L@R` — extract the substring between two markers (sub-field
  parsing), e.g. ss `users:(("sshd",…))` → `sshd`
- per-spec `total` flag — match bespokes that do/don't emit `total_entries`

Migrated `ss-tulnp` (covers ss-tulpn / ss-memory / ss-udp / ss-tp, incl. the
process-name extraction) into a single spec line; retired the bespoke. All four
tools verified **byte-identical** (melted) to the old bespoke. ss generic goldens
regenerated — they now carry the good ss-quality output (named columns + extracted
process) in generic mode too, where they previously fell to a cruder parser.

Performance (measured): a full auto-detect run is ~3.2s, ~89% of which is the
detection loop's per-strategy overhead (source + metadata + detect + cleanup),
~7ms per strategy file. The engine's per-tool cost is comparable/slightly lower
(0.063s vs 0.074s forced), and every file it absorbs removes one loop iteration —
so collapsing toward ~300 files projects to ~20-25% faster auto-detect. The spec
engine is thus both a count reduction and the biggest lever on run latency.

Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.
Count: 410 files / 409 distinct names.

## 2026-07-09 — declarative columnar-specs engine (foundation for spec-driven parsers)
Introduces `extract/strategies/delimited/columnar-specs.sh`: a single data-driven
engine that replaces per-tool columnar strategies with one TAB-separated spec line
each (`name · detect substrings · header marker · delim ws|pipe · absorb column ·
column names`). One engine detect/extract interprets all specs; the tidy output per
tool is verified **byte-identical** to the retired bespoke before migration.
Migrated first batch: `zypper-search`, `buildah-containers`, `lsmem` (3 bespokes →
1 engine). Engine is `## Technique: yes` so it preserves generic-mode coverage.

Scope note (important for anyone extending this): only a **minority** of the ~89
"columnar" bespokes fit a simple spec. Most do value-add work a flat column-map
can't express — sub-field parsing (`ss-tulnp` pulls the process name out of
`users:((…))`), multi-section layouts (`stream`, `imb`, `nfsstat`), pattern-based
token classification (`lsblk-output`), or positional multi-word cells (`docker-ps`).
Those stay bespoke. Realistic clean-spec yield is modest, not a path to a large
reduction on its own.

Verified: extract 213/213, corpus golden 978/0, smoke 49/49, melt 8/8.
Count: 421 → 411 strategy files (420 → 410 distinct names) across this session's work.

## 2026-07-09 — consolidate strategies: merge same-logic families (420 → 412)
A different angle on shrinking the strategy set than "delete redundant": **merge
strategies that share the same extraction, keeping one whose `detect()` is the
union of the originals'.** Found the clusters by hashing each strategy's
`strategy_extract` body and grouping identical ones. All merges are behavior-
preserving (each old tool's output is byte-identical under the merged strategy):
- **dig**: `dig_ns` + `dig_any` + `dig_trace` + `dig_noall_answer` →
  **`dig-answer`** (all emit `name ttl class type value`; only the banner-type
  detect differed). `dig-mx`/`dig-txt` (semantic `preference`/`exchange`, `text`
  columns) and `dig-output` (full report) stay separate. 4 → 1.
- **cloud JSON lists**: `az-account-list` + `az-acr-list` + `az-keyvault-list` +
  `gcloud-pubsub-topics-list` → **`cloud-json-list`** (one JSON-array-by-brace-
  depth extractor; per-command field-name guards OR-ed in detect). 4 → 1.
- **snmp**: `snmpget` + `snmpwalk` → **`snmp-output`** (same OID/type/value parser,
  split only by a `.0`-vs-subtree detect heuristic that changed no output). 2 → 1.
- **kubectl top**: `kubectl-top-nodes` + `kubectl-top-pods` → **`kubectl-top`**
  (one strategy; the header's `%` columns pick nodes-vs-pods mode). 2 → 1.

Net −8 strategies (421 → 413 files; 420 → 412 distinct names). Verified: extract
213/213, corpus golden 978/0, smoke 49/49, melt 8/8.

## 2026-07-09 — redundant-strategy prune: investigated, nothing safe to remove
Rigorous sweep to prune redundant per-tool strategies (the standing "then prune"
goal). Computed the full-mode winner for all 1040 corpus tools, then byte-compared
each shadowing bespoke's output against the generic golden. Finding: the
obviously-redundant columnar bespokes (`df`, `ps-aux`, `ss`, `lsblk`, `vmstat`,
`netstat`, `top`, `systemctl`, `kubectl`, `container-top`, …) were **already**
removed in earlier sessions, and every *remaining* bespoke that shadows a
generic-covered tool produces **better or distinct** output (e.g. `mount` names
`device/mount_point/fstype/options` vs generic raw `c1..c6`; `free` labels the
row; `ls-l` joins the date; `kv-pairs` strips the `, ` delimiter). So **no
strategy is safely removable** — the count stays at 420 distinct strategies (421
files; one stray duplicate `## Name: perf-stat`). Recorded in `HANDOFF.md` so the
stale "prune" step isn't chased again. No code changes.

## 2026-07-09 — parse-wrong tail (clusters 2–3): ip-link parser, colon routing, text-inputs
- **New `ip-link` parser** (`extract/strategies/network/ip-link.sh`, + sample +
  golden) for iproute2 `ip addr` / `ip link`. Parses the multi-line per-interface
  stanza into one tidy row per interface — `index, name, flags, mtu, qdisc, state,
  group, qlen, mac, inet, inet6`. Previously `indented-hierarchy` transposed the
  whole thing into a single mangled wide row. (Bespoke, so it improves real
  full-mode `glean`; the `--generic` corpus goldens are unaffected.)
- **`vertical-line` declines `label: value` blocks that merely carry a `===`/`---`
  banner** → routed to `colons`. Fixes `aureport --summary` and
  `duplicity collection-status` (were shredded into positional columns off the
  banner's title line), and incidentally un-mangles `nodetool-tablestats` (its old
  golden was `vertical-line` garbage; now a clean `colons` kv record). File:
  `extract/strategies/delimited/vertical-line.sh`; goldens regenerated.
- **Routed genuine logs to `tests/corpus/text-inputs/`**: `dmesg` (kernel ring
  buffer) and `ausearch-avc` (audit log) are free-form log streams with no tidy
  target — moved out of the corpus (manifest row + golden dropped), per the
  established just-text policy.

Verified: extract 213/213, smoke 49/49, melt 8/8, corpus golden 980/0 (1040 tools).
Still deferred (need dedicated bespoke parsers — documented in `HANDOFF.md`):
`ifconfig`/`iwconfig` (RX/TX field collisions, inline `key:value`), `git-diff-stat`,
`gradle-q-dependencies`, `gpg-list-secret-keys`, and the record-vs-wide-row /
colon-in-value groups.

## 2026-07-09 — parse-wrong tail (cluster 1): route shadowed tools to correct parsers
Working the documented parse-wrong tail; the clean, verified wins in this batch:
- **`git-config-list` → `equals`.** The `equals` detect key class excluded `.`, so
  dotted config keys (`user.name=Jane Developer`) never matched and fell to the
  last-resort `line-records` (ragged `c1/c2`). Added `.` to the tight-assignment
  key class; git-config-list now tidies to one wide `key=value` record with values
  intact. Reclassified its manifest row `table`→`kv`. File:
  `extract/strategies/delimited/equals.sh`.
- **`jmap-histo` → its bespoke parser (un-shadowed).** `sqlite-output` claimed any
  block with a dash rule, including jmap's single solid `----` banner, and flattened
  it to one column. `sqlite-output` column-mode now requires a *segmented* separator
  (`--- ----- ---`, ≥2 dash groups) the way `.mode column` prints it; a solid rule is
  no longer a column separator, so the `jmap-histo` bespoke wins and emits proper
  `num/instances/bytes/class` rows.
- **`dnf-history-list` fixed in `sqlite-output` pipe mode.** Skip a pure dash/space
  rule under the header (was becoming a bogus data row), and underscore multi-word
  header names (`Command line`→`command_line`, `Date and time`→`date_and_time`) so
  the tidy melt — which splits `entryN.field value` on the first space — keeps each
  value whole. This header-underscore fix benefits every multi-word-header sqlite
  pipe/column table. File: `extract/strategies/misc/sqlite-output.sh`.

Verified: extract 213/213, smoke 49/49, melt 8/8, corpus golden 980/0.
(The corpus goldens are `--generic`-mode; the `sqlite-output`/`jmap-histo` wins
improve real full-mode `glean` but are not reflected in generic goldens — only the
`equals` Technique change touched a generic golden.)

## 2026-07-09 — aligned-columns: gate positional to multi-word tables; regen corpus goldens
- **Fixed a regression in the opt-in positional path.** `_ac_aligned` keyed the
  positional assignment off the header's 2-space column starts, which *under-counts*
  columns when a header uses single spaces between real labels (df `Used Avail
  Use%`, lsblk, ss, elasticsearch cat/nodes, losetup). Those clean single-token
  tables were being crammed into 3 wide columns. Positional now requires a genuine
  multi-word cell — a data row must carry **more** whitespace tokens than the header
  has labels (docker `2 hours ago`, helm's timestamp) — before it fires; otherwise
  whitespace tokenization (correct for single-token tables) is kept. Files:
  `extract/strategies/delimited/aligned-columns.sh`.
- **Regenerated all corpus goldens** (`tests/corpus/expected/*.tsv`) to reflect the
  positional path: docker/helm/podman-top/crictl/kubectl now keep multi-word cells
  whole, while df/lsblk/ss/elasticsearch/losetup are restored to their correct
  multi-column split. `run.sh --golden`: 980 passed, 0 failed.
- **Reclassified `hg-paths` to `kv`** in `tests/corpus/expected.tsv`. It is a
  `key = value` block (same shape as `ansible-config-dump`), which the `equals`
  parser tidies to one wide record; the old `table` expectation was a pre-guard
  artifact. Manifest + golden updated to match.
- Updated `CLAUDE.md` with a git-practices section (set the commit identity per
  session, push after every step because the container can roll back, subagents
  never run git, never commit a broken corpus regen).

## 2026-07-09 — review 500 inputs: positional aligned-columns + shadow/identifier fixes
- Reviewed ~500 corpus inputs (classified ok / just-text / parse-wrong). 11 more
  free-text/banner captures moved to `tests/corpus/text-inputs/` (corpus now 1036).
- **aligned-columns: opt-in positional parsing for cleanly-aligned tables.**
  docker / kubectl / helm / crictl / dnf / az / gcloud tables were shredding
  multi-word headers (`IMAGE ID`) and values (`2 weeks ago`, cron `0 2 * * *`,
  `Rocky Linux 9 - AppStream`, PORTS `80, 443`, wide timestamps) on whitespace.
  Now, when a block's data rows are confirmed aligned to the header's column
  starts (`_ac_aligned`: ≥80% of rows leave whitespace before each header column
  start), tokens are assigned to their header column region (`_ac_assign`),
  keeping multi-word cells whole. Everything else — irregular single-space
  headers (ps/df), right-aligned-overflow numerics (ps-aux-sort), two-line
  headers (vmstat/dstat), headerless — keeps the known-good tokenization. Two
  earlier all-positional rewrites regressed those common tools; the opt-in gate
  is what makes it safe. ~50 tools fixed, no regressions.
- **Retired the `kubectl` and `container-top` bespokes** — both transposed
  multi-record output into one wide row and mis-split; positional aligned-columns
  now tidies `kubectl get pods/nodes/svc/daemonset`, `helm list`, `docker/podman
  top`, `crictl ps` to proper records. Removed the strategies, samples, goldens,
  and the kubectl test.
- **Shadow narrowings:** `hg-branches` declines `changeset:`-style logs (hg
  log/heads/summary); `git-log` oneline requires a hex-letter hash and rejects
  tab-delimited / `* `,`- ` markers (gsutil du, git for-each-ref, git lfs);
  `version-string` declines bare-IP lists (dig +short) and git-hash lines (git
  submodule status); `pip-list` declines `*-outdated` 3-col tables.
- **colon-fields declines uniform identifier lists**: an ARN/URI list (every line
  sharing the same first colon-field, e.g. `arn:aws:…`) is one value per line, not
  colon-delimited record fields. `aws-ecs-list-clusters` / `aws-sns-list-topics`
  now come out as a single-column list; passwd/group still split.
- **docker-ps requires the COMMAND column** so it stops hijacking `docker stats`
  and `buildah containers` (no COMMAND); those tidy via their own / generic parsers.
- Batch-1 review fixes: 7z (aws-s3-ls now needs ≥2 object rows), acpitool (colons
  trims alignment-padding from keys), ansible-config dump (equals handles
  `KEY(ctx) = value`; aligned-columns declines ` = ` blocks).
- Verified: extract suite 213/213, smoke 49/49, melt 8/8.
- Remaining review tail (documented in HANDOFF.md): more greedy shadows
  (sqlite-output on jmap-histo/gpg/gradle, pkg-config stragglers, proc-stat,
  line-records, docker-compose-ps transpose), record-vs-wide-row cases
  (yaml/ini/labeled-records), nested-heading grouping, and a few multi-panel
  dashboards / wide variable-width date columns.

## 2026-07-08 — vet corpus output quality: preserve spaces in values; fix box-table shadowing
- **Data values keep their spaces.** ~200 extract strategies were replacing
  spaces with underscores in emitted VALUES (`${v// /_}`), corrupting multi-word
  data ("Eye Holes" → "Eye_Holes", cert issuer "C=US, O=DigiCert Inc" →
  "C=US,_O=DigiCert_Inc", commit subjects, package summaries, etc.). The engine
  splits `entryN.field value` on the FIRST space, so multi-word values never
  needed underscoring — only FIELD NAMES / column headers do (a space there is
  the field/value boundary). The space-substitution was removed from every VALUE
  path across the strategy set while field-name/header underscoring and the
  tab→underscore TSV-safety substitution were kept. Files: all of
  `extract/strategies/**` that carried `${var// /_}` on a value (config,
  container, database, delimited, hardware, network, security, structured,
  system, benchmark, build, logging, misc, packages, profiling trees).
- **Regenerated 414 strategy goldens** (`extract/tests/golden/`) and updated 53
  assertions across 18 `extract/tests/test_strategy_*.sh` to the space-preserving
  output (values gained spaces; field names unchanged).
- **Box-table shadowing fixed.** `pipe-table`, `sqlite-output`, `strace-summary`
  and `fixed-width` now decline `+---+` box tables in `strategy_detect`, so
  `psql-table`'s box parser (which strips outer borders and the single-cell
  title banner) wins them. Fixes ~55 `aws --output table` / mysql / pg /
  pgbouncer grids that were flattened to one/few columns
  (e.g. `aws-ec2-describe-instances` 2 → 8 columns). No priority changes, so
  bespoke parsers (nvidia-smi, vnstat, zypper, jmap-histo) still win their own
  tools and non-box tools are unaffected. Files:
  `extract/strategies/misc/pipe-table.sh`,
  `extract/strategies/misc/sqlite-output.sh`,
  `extract/strategies/system/strace-summary.sh`,
  `extract/strategies/delimited/fixed-width.sh`.
- Verified: extract suite 214/214, smoke 49/49, melt 8/8.

## 2026-07-07 — flip defaults: async capture + rm --purge are now on by default
- **Async is the default** for inject/`run`: a bare `cmd | glean` now spools and
  captures in a detached background process, returning the prompt at once
  (`queued (async …)`) instead of printing the resulting dataset. Use
  `--sync`/`--wait` (or `GLEAN_ASYNC=0`) for the foreground path that prints the
  dataset + `#N` range — this is what scripts that read the result inline should
  use. (Implementation flip: `cmd_inject`/`cmd_run` default `${GLEAN_ASYNC:-1}`.)
- **`glean rm` purges captures by default**: deleting a dataset now also drops the
  `captures/<id>/` dirs that fed it (and their tags), not just the dataset file +
  provenance rows. `--no-purge`/`--keep-captures` retains the source captures. The
  deletion is still committed, so `glean log`/`restore` reach the pre-deletion
  state regardless.
- Docs/plumbing: help text, `man/glean.1`, and `completions/glean.bash` updated
  for both flips (`--sync`, `--no-purge`/`--keep-captures`). Tests: `tests/smoke.sh`
  pins `GLEAN_ASYNC=0` for its synchronous assertions, adds checks that the bare
  default is async and `--sync` forces foreground, and updates the rm checks to the
  purge-by-default behavior (49 checks, all green). Melt 8/8; extract unaffected.

## 2026-07-07 — opt-in async capture + a concurrency-lock fix it exposed
- **Feature:** `--async` (and `GLEAN_ASYNC=1`) on inject/`run`. The input is
  spooled and the extract→classify→commit runs in a **detached background
  process**, so the shell prompt returns immediately (~0.03s vs ~0.35s). Results
  appear in `glean log` shortly after; use `--sync`/`--wait` to force the
  foreground path (or when `GLEAN_ASYNC=1` is the default). The spool lives
  outside the workspace (never committed) and self-removes on success; on failure
  it is kept, with a `log.txt`, for inspection. Store serialisation is unchanged —
  the background child takes the same lock as any writer.
- **Bug fix (found while testing async):** `_lock` recorded `$$` as the lock
  owner, but a detached ingest runs in a subshell where `$$` is still the
  already-exited parent glean. The stale-lock breaker then saw a "dead" owner and
  could steal a live lock mid-write, producing **duplicate row indices**. `_lock`
  now records `$BASHPID` (the real current process). This also hardens the
  existing parallel-`run` path.
- Files: `glean` (`_ingest_async`; `--async`/`--sync` on `cmd_inject`/`cmd_run`;
  `_lock` → `$BASHPID`; help + ENV docs), `completions/glean.bash`, `man/glean.1`,
  `tests/smoke.sh` (+3 async checks incl. a duplicate-index concurrency guard).

## 2026-07-07 — extract engine ~40% faster per invocation (mktemp hoist)
- **Perf:** piping into `glean` was ~0.6s wall per capture; the extract engine
  was ~0.5s of that (git commit is ~0.01s). The auto-detect loop spawned a fresh
  `mktemp` subprocess for **every** strategy it sourced (dozens per run, ~60 for a
  typical input) just to capture source-time stderr. Hoisted that to a **single**
  private temp file created once per run and reused (same umask-077, symlink-safe
  mktemp — just not per-strategy). Measured ~0.60s → ~0.35s per pipe (~42%), with
  identical classification. If the one temp file can't be created, the loop now
  degrades to discarding source stderr rather than spawning per-strategy temps.
- Verified: extract suite 214/214, smoke 44/44, melt 8/8 — all unchanged.
- Files: `extract/lib/_discovery.sh` (`run_auto_strategies`).

## 2026-07-07 — hermetic smoke test + doctor warns on a shadowing engine
- **Bug:** `bash tests/smoke.sh` could fail with the `free` sample classified as
  `dmsetup-table` (or any other type) on a machine whose `GLEAN_HOME` (e.g.
  `~/.glean`) contained a stale `extract/envoy-extract`. `_find_engine` resolves
  `$GLEAN_HOME/extract/…` *before* the bundled engine, so an old copy there
  silently shadows the repo's engine — and the smoke test, which only set
  `GLEAN_WORKSPACE`, inherited it. (PR CI was green; this only bit local runs.)
- **Fix:** `tests/smoke.sh` is now hermetic — it clears every `GLEAN_*` knob the
  caller's shell may carry (`GLEAN_HOME`, `GLEAN_MIN_CONFIDENCE`,
  `GLEAN_RECONCILE_OVERLAP`, `GLEAN_QUIET`, `GLEAN_MAX_INPUT`) so it always
  exercises the bundled trees.
- **Diagnostic:** `glean doctor` now warns when the resolved extract engine is a
  `GLEAN_HOME` override rather than the bundled one, and points at the bundled
  path — so a shadowing/stale engine diagnoses itself.
- Files: `tests/smoke.sh` (unset block), `glean` (`cmd_doctor` warning).

## 2026-07-07 — `glean rm` deletes datasets (provenance-aware, committed)
- New verb `glean rm [-f|--yes] [--purge] <dataset>...` (aliases `delete`/`drop`).
  Previously there was no way to remove a dataset short of hand-deleting files
  from the store. `rm` now:
  - removes each named dataset file (only the named dataset — variants like
    `NAME.v2` are their own datasets, removed by name);
  - prunes the matching rows from `provenance.tsv` so `glean source #N` no longer
    points at a vanished dataset;
  - with `--purge`, also drops the `captures/<id>/` dirs (and their `capture-<id>`
    tags) that fed the removed dataset(s), identified by each capture's own meta
    `dataset` field;
  - commits the deletion, so the git history — and `glean log` / `glean restore`
    — still reach the pre-deletion state. Row indices (`#N`) are never reused.
  Prompts for confirmation unless `-f`/`--yes`; validates all names up front and
  refuses the whole operation if any is missing.
- Files: `glean` (new `cmd_rm`; dispatch `rm|delete|drop`; help entry),
  `tests/smoke.sh` (8 new checks: refuse-missing, delete, file removal,
  provenance prune, sibling rows kept, capture kept without purge, capture
  purged with `--purge`, deletion committed).

## 2026-07-07 — `show unsorted` / `triage` render decoded raw input
- The `unsorted` dataset stores each held-back capture as a single base64-encoded
  `raw` column (so arbitrary bytes survive the TSV). Previously `glean show
  unsorted` and `glean triage` printed those base64 blobs verbatim — unreadable.
  They now decode each row back to text for display, escaping any embedded
  tabs/newlines (`\t`/`\n`) so one capture stays one table row. `glean source #N`
  is unchanged and remains the way back to the exact original bytes.
- Files: `glean` (new `_decode_unsorted_tsv` helper; `cmd_show` special-cases the
  `unsorted` dataset; `cmd_triage` reuses the decoder), `tests/smoke.sh` (three
  new checks: show/triage decode the raw input and no longer emit the base64 blob).

## 2026-07-07 — 1050/1050 tidy coverage (corpus doubled to 1050 tools)
- Grew the corpus from 500 to **1050 tools** (550 new: extended k8s, AWS/GCP/Azure
  CLIs, SQL + NoSQL databases, package managers, `/proc` & sysfs, process/perf,
  networking, storage/LVM/ZFS, systemd/services, hardware, security, observability,
  VCS, and IaC/cloud-native) and drove them to **1050/1050 tidy**, zero gaps.
  Inputs authored in parallel by ~22 subagents; parsers by ~16 more, then
  integrated and de-conflicted here.
- **Box-table parser** — rewrote `psql-table` into a general pipe-box parser: it
  strips outer `|` borders and picks the header by modal column count, so it now
  tidies `aws --output table` full ascii boxes (title line + `+---+` rules),
  mysql/mariadb `+---+` grids, and pgbouncer/flyway/cockroach/etcdctl boxes — one
  parser covering the whole AWS `--output table` cluster plus DB box tables.
- **~86 new format-family / bespoke parsers** for idiosyncratic formats: `/proc`
  files (buddyinfo/pagetypeinfo/net-tcp/net-snmp/self-mountinfo/…), DNS answer
  sections (dig variants/drill/host/nslookup), sysstat/perf tables (pidstat/
  vmstat/iostat/top/collectl/pcp-pmstat/perf-trace/jmap-histo), cassandra
  `nodetool`, elasticsearch `_cat`, rabbitmq/promtool/telegraf, JVM/hardware
  diagnostics (lsusb -v/lspci -tv/lscpu --extended/smartctl/rocm-smi/ipmitool),
  package/language trees (poetry/pnpm/pipenv/sbt/cabal/dub), JSON-array cloud
  outputs (az/gcloud list --format=json, ansible-inventory) parsed by bracket
  depth at low priority so they beat generic `json`, and many more.
- **Cross-strategy de-confliction** — the main integration work: narrowed
  over-broad detects that were stealing pre-existing tools (`csvlook` full-rule
  separator; `consul-kv-get-recurse` slash-before-colon; `liquibase-status`
  banner-gated, IPv6-safe; `poetry-show-tree` npm/podman-safe; `lspci-tv` hex bus
  address; `dmsetup-table` alphabetic target-type vs `/proc/net/snmp`), and set
  per-tool parsers below the generic parser (`csv`/`tsv`/`yaml`/`key-value`) that
  shadowed them. Resolved name collisions (`rocm-smi`, `terraform-plan`, `iperf3`).
- Tests: extract suite **214/214**, smoke 33/33, melt 8/8, corpus **1050/1050 tidy**.

## 2026-07-07 — 500/500 tidy coverage (fourth + fifth 100 driven to 100%)
- Grew the corpus to **500 tools** (200 new: extended networking, containers/k8s,
  storage/LVM/ZFS, process & `/proc`, package managers, databases, security/auth,
  hardware, systemd/services, and VCS/cloud/IaC) and drove them to **500/500
  tidy**, zero gaps. 200 new inputs authored in parallel by ten subagents; the
  new parsers by eight more, then integrated and de-conflicted here.
- **Generic-parser refinements** (close many gaps with no per-tool rule):
  - `aligned-columns` now drops a pure separator rule (`---- -----`) wherever it
    appears (fixes `aws configure list`), extends the trailing-summary skip to
    "N loaded units listed." (`systemctl --failed`), and defers `label: value` /
    `label : value` / `Key=Value` blocks to `colons`/`equals` — but only when the
    block is *ragged* (a genuine kv snapshot), keeping consistent multi-column
    tables like `/proc/softirqs` ("HI: 0 0 0") and `lsusb` with aligned-columns.
    This routes `rpm -qi` and similar mixed-padding kv blocks to a single wide row.
- **New format-family / bespoke parsers** for genuinely idiosyncratic formats the
  generic parsers can't tidy, e.g. sysstat-style `iostat -x`, `/proc/{slabinfo,
  net/dev}`, `nstat`, `ifstat`, `vnstat`, `tcpdump`/`tshark` summaries; DB output
  `clickhouse` PrettyCompact Unicode box, `cassandra nodetool tpstats`,
  `mysqladmin status`, `keytool -list`; DNS `dig MX`/`dig TXT`; kv snapshots
  `sshd -T`, `xfs_info`, `zypper info`, `hdparm -I`, `dmidecode`/`biosdecode`,
  `cpuid`, `decode-dimms`, `gpg --card-status`, `ansible --version`; trees
  `systemd-cgls`, `systemd-analyze critical-chain`, `lshw -c network`, `lstopo`,
  `fwupdmgr get-devices`; and network `ip tunnel`/`ip xfrm state`/`iwlist scan`/
  `nmap -sn`/`mii-tool`/`numactl --show`/`parted print`, plus `pipx list`,
  `bundle outdated`, `semanage boolean`, `vagrant global-status`, `ansible-inventory`,
  `aureport`, `rc-status`, `ssh-keyscan`, `fossil status`, `mix deps`.
  Tool-specific parsers that overlap `json`/`yaml`/`csv`/`key-value` are set to a
  low `## Priority` so their specific detect wins over the structural fallback.
- **Manifest reconciliations** where glean's canonical long-melt is the honest
  tidy shape: the `key/value` snapshot tools `dmsetup info`, `dumpe2fs -h`,
  `hdparm -I`, `tune2fs -l`, `cryptsetup luksDump` use `kv/-/4` (n·key·value·total,
  like `lscpu`); `vmstat -d`/`proc-net-dev` mincols trimmed to the true width.
- Tests: extract suite **214/214**, smoke 33/33, melt 8/8, corpus golden clean.

## 2026-07-07 — 300/300 tidy coverage (third 100 driven to 100%)
- Grew the corpus to **300 tools** (100 new: extended Kubernetes/cloud/IaC,
  containers, networking, systemd/storage, process/perf & security, package
  managers, language/hardware/DB) and drove them to **300/300 tidy** — now
  **264 via generic parsers, 36 bespoke**, zero gaps. New inputs under
  `tests/corpus/inputs/`, manifest rows in `tests/corpus/expected.tsv`, goldens
  re-frozen; `tests/corpus/COVERAGE.md` regenerated. (100 new inputs authored in
  parallel by seven subagents; the 20 new parsers by four more, then integrated
  and de-conflicted here.)
- **New generic parser** — `colon-fields` (`extract/strategies/delimited/`,
  priority 48): colon-delimited records (`/etc/passwd`/`group`/`getent`), keyed on
  the first whitespace token carrying ≥3 colons so a stray `10:15:42` timestamp
  never trips it. Also now cleanly tidies `lsscsi`'s `[H:C:I:L]` rows.
- **Generic-parser improvements** (fixed several tools without a bespoke rule):
  - `aligned-columns` now declines pure key/value blocks (`label : value` /
    `Key=Value`) so `pacman -Qi` → `colons` and `systemctl show` → `equals` as
    single wide rows; and collapses a leading `#`-comment block to its last line
    as a de-hashed header (fixes `conda list`, `opam list`).
  - `text-lines` accepts a lone single-token line (`getenforce` → "Enforcing")
    while still declining multi-word prose.
  - `sqlite-output` ignores ASCII tree glyphs (`|__`) when counting pipe columns,
    so it no longer claims `lsusb -t` (git-diff-stat still works).
  - `pkg-config` declines all-caps header tables (routing `prlimit`/`aws`/`who`
    to `aligned-columns` for proper multi-column output).
- **New bespoke parsers** (19): storage/trees `zpool-status`, `btrfs-filesystem-show`,
  `multipath-ll`, `lsusb-t`; network `nft-list-ruleset`, `ip-maddr`, `rfkill-list`,
  `bridge-fdb`, `netstat-s`; lists/footers `arping`, `bundle-list`, `php-modules`,
  `go-list`, `getconf`; stats/kv `memcached-stats`, `numastat`, `pmap`,
  `zypper-search`, `vault-status`.
- Tests: extract suite **214/214**, smoke 33/33, melt 8/8, corpus golden 264/264.

## 2026-07-06 — 200/200 tidy coverage (second 100 driven to 100%)
- Drove the full 200-tool corpus to **200/200 tidy** (166 via generic parsers,
  34 bespoke) — up from 169/200. The 31 remaining gaps were closed by new,
  format-family parsers (authored in parallel by five subagents, then integrated
  and de-conflicted here):
  - **Box tables** — `psql-table` (priority 35): `col | col` header, a `---+---`
    separator, then `value | value` rows (psql `\l`/`\dt`/`\du`, `pg_stat_activity`,
    mysql). Also cleaned up the previously-garbled `psql \du` columns.
  - **Version banners** — `version-string` (priority 28): short `vN.N.N` /
    `cmake version N.N.N` output (node/java/cmake/gcc `--version`). Guarded to
    reject tab-separated, many-token headers so it no longer steals `mpstat`/`sar`.
  - **Monitoring tables** — `perf-top`, `turbostat`, `slabtop`, `iotop`, `iftop`,
    `nethogs` (banner + columnar), and `perf-counters` (priority 18) for
    `perf stat`'s counter list → one tidy row per counter.
  - **Binutils / packages** — `objdump-headers`, `readelf-sections`, `ldconfig-p`,
    `pkg-config`, `gem-list`, `composer-show`.
  - **Network / VCS / security** — `arp-scan`, `aws-s3-ls`, `host`, `mtr-report`,
    `git-remote`, `lastb`, `gpg-list-keys`, `chage-l`.
  - **Ragged single-column text** — `text-lines` (priority 97, absolute last
    resort): one row per line for unstructured output like `strings`.
- **Cross-strategy de-confliction** (the integration work): lowered `git-remote`
  to 13 (beat generic `tsv`) and `gpg-list-keys` to 19 (beat `sqlite-output`);
  gave the greedy `colons` fallback a "≥40% of lines are `key:`" gate so a lone
  `usage:` line no longer captures `strings`; renamed the new mtr parser to
  `mtr-report` with its own sample+golden so it stops clobbering the existing
  `network-hops` mtr fixtures; dropped a duplicate `git-log` strategy; fixed the
  corpus `git-log.txt` fixture to use realistic hex shas.
- `cargo-tree` now emits the standard `entry<N>` + `total_entries` contract
  (root crate = entry1), so its dependency tree melts to one tidy row per crate
  (9 rows) instead of the old `root.`/`dep<N>.` shape.
- Extract suite 214/214; smoke 33/33; melt 8/8; corpus golden regression
  166/166. `COVERAGE.md` regenerated (queryable ✅/✅ᵇ list, 0 ⏳).

## 2026-07-06 — 100/100 tidy coverage (the last gaps closed)
- Drove the corpus from 82 to **100/100 tidy** (87 via generic parsers, 13
  bespoke). The final gaps, in order:
  - `systemd-analyze`: `aligned-columns` now counts a number+unit token (`8.421s`)
    as a value, so its first line is data, not a header → falls to `line-records`.
  - `lshw` (and any header/separator table): fixed `vertical-line` to emit one
    record per data row (it was welding every cell into one wide record).
  - `loginctl`: `aligned-columns` drops a trailing `N sessions listed.` summary.
  - `file`: new generic `labeled-records` parser — one row per
    `single-token-label: prose-value` line (distinct from meminfo's numeric values
    and hostnamectl's multi-word labels, which stay single-observation).
  - `groups`: small `user-groups` parser (`user : g1 g2 …` → one row per membership).
- Extract suite 214/214; smoke 33/33; melt 8/8; corpus golden regression 87/87.

## 2026-07-06 — corpus to 100 tools (73 tidy) via parallel authoring
- Grew the tidy corpus from 42 to **100 common Linux tools** — authored in
  parallel by six subagents across networking, storage, system/process, package
  managers, containers/k8s, and hardware/misc (58 new tools with realistic
  captured output + manifest rows).
- Coverage **73/100** — 69 via a generic parser (no new strategies needed), 4 via
  bespoke. The parallel harness scores all 100 in ~44s (coverage) / ~6s (golden).
- 27 documented gaps in a few clusters: leading banner/preamble (`mpstat`, `sar`,
  `pidstat`, `apt-list`, `dpkg-l`, `df-T`, …), single freeform lines (`date`,
  `groups`, `proc-loadavg`, `taskset`), single-column lists (`dig-short`,
  `rpm-qa`, `brew-list`), tree structures (`pstree`, `tree`, `npm-ls`), and a few
  key-value snapshots (`hostnamectl`, `ulimit`, `loginctl`).
- Inputs + manifest + goldens only; no engine changes (extract suite 214/214).

## 2026-07-06 — widen the corpus to 42 tools (39 tidy)
- Added 8 more common tools: `lsmod`, `nmcli`, `ip-link`, `last`, `date`,
  `mpstat`, `apt-list`, `dmidecode`. Coverage now **39/42** — 35 via a generic
  parser (`lsmod`/`nmcli`/`last` → `aligned-columns`, `ip-link` →
  `indented-hierarchy`), 4 via bespoke (`dmidecode`, `lspci`, `uname`, `uptime`).
- 3 new gaps, all a shared pattern: `mpstat` and `apt list` have a leading
  banner/preamble line before the table; `date` is a single freeform line. Next
  work: a generic "skip leading banner/preamble" for the columnar parser (also
  helps `sar`), and a single-line parser for `date`.
- Inputs + manifest + goldens only; no engine changes (suite 214/214 unaffected).

## 2026-07-06 — start pruning redundant per-tool strategies (−5)
- Began removing bespoke strategies the generic parsers now cover, the payoff of
  the generic-parser work. Removed **`ss`, `df`, `ps-aux`, `lsblk`, `vmstat`**
  (strategy + tests + goldens + samples), −5 strategies, coverage unchanged
  (34/34).
- `ss` was **broken** and shadowing a better strategy: it emitted `socket1_…`
  (underscore, not the dotted `entryN.` melt convention) so full-mode `ss` came
  out as one wide non-tidy row. It also outranked the good `ss-tulnp` (priority
  40 < 42). Removing it lets `ss-tulnp` win → full-mode `ss` is now 3 tidy rows.
- `df`/`ps-aux`/`lsblk`/`vmstat` now resolve to the generic `aligned-columns` in
  full mode (verified tidy; the corpus goldens are exactly that output). The only
  change is raw header column names (`%CPU`) instead of the bespoke's normalised
  ones (`cpu_pct`) — an acceptable trade for one fewer strategy each.
- Removed the now-dangling `vmstat` case from `test_snapshot_regression.sh`.
- Extract suite 214/214; smoke 33/33; melt 8/8; corpus golden regression 31/31.
- Method for the ongoing sweep: `tests/corpus/run.sh` compares generic vs
  full-mode melt per tool — prune where generic is tidy-equal-or-better; the
  broken/shadowing bespokes (like `ss`) are the highest-value targets.

## 2026-07-06 — close the 4 corpus gaps: 34/34 tools tidy
- `du -h` — taught `tsv` a **headerless mode**: when the first line is already
  data (a digit-bearing field) it synthesises `c1..cN` instead of eating row 1 as
  a header. `du` (size <tab> path) now tidies to one row per line.
- `id` — new generic **`inline-kv`** parser (space-separated `key=value` tokens on
  a line) → `uid`/`gid`/`groups` columns.
- `uname -a` — new small **`uname`** parser (single-line positional): kernel name,
  nodename, release, machine, operating-system.
- `lspci` — its bespoke strategy filtered output to GPU/NIC/storage and emitted
  only those; rewrote it to emit **all** devices as (slot, class, description,
  driver). Updated its unit test to the new schema.
- Coverage now **34/34** — 31 via a generic parser (8 parsers total, adding
  `inline-kv`), 3 via bespoke (`uptime`, `uname`, `lspci`). Full extract suite
  219/219; smoke 33/33; melt 8/8; corpus golden regression 31/31.
- Files: `extract/strategies/structured/{tsv,inline-kv}.sh`,
  `extract/strategies/system/uname.sh`, `extract/strategies/hardware/lspci.sh`,
  `extract/tests/test_strategy_lspci.sh`, new samples + goldens, `tests/corpus/*`.

## 2026-07-06 — broaden the corpus to 34 tools (30 tidy, 29 via generic parsers)
- Expanded `tests/corpus/` from 22 to **34 common Linux tools**, including varied
  output for the same tool (`free -h`, `df -i`, `ps -ef`): added `ps-ef`, `lsof`,
  `du-h`, `lsusb`, `free-h`, `df-i`, `os-release`, `ethtool`, `id`, `uname-a`,
  `journalctl`, `lspci`.
- **29 of the new+old set tidy via a generic parser** with no new strategy needed
  (the `aligned-columns` header/headerless/two-line modes and `bracket-log` carry
  most of them); `uptime` stays bespoke. Coverage: **30 / 34** — see
  `tests/corpus/COVERAGE.md` (regenerate with `run.sh --coverage`).
- Four documented gaps for later: `du-h` (tab-separated headerless 2-col stolen by
  `tsv`), `id` / `uname-a` (single-line freeform), `lspci` (its bespoke strategy
  emits only 1 of N devices).
- `run.sh` coverage view now also melts full mode so it can mark bespoke-only
  coverage (✅ᵇ); fixed a stray `local` outside a function.
- No engine/strategy changes this batch (inputs + manifest + harness only); smoke
  33/33, golden regression 29/29.
- Files: `tests/corpus/inputs/*` (+12), `tests/corpus/expected.tsv`,
  `tests/corpus/expected/*`, `tests/corpus/run.sh`, `tests/corpus/COVERAGE.md`,
  `tests/corpus/README.md`.

## 2026-07-06 — full tidy coverage of the 22-tool corpus (21 generic + 1 bespoke)
- Closed the last corpus gaps; all 22 common tools now come out tidy — **21 via
  a generic parser, `uptime` via its small bespoke strategy** (a single-line
  prose status no generic parser fits; the accepted exception).
- `aligned-columns`: added a **two-line-header** mode (group row + field row, for
  `vmstat`) and a **`total <n>` preamble skip** (for `ls -l`).
- New generic **`bracket-log`** parser (`extract/strategies/logging/bracket-log.sh`)
  for `[tag] message` log lines — tidies `dmesg` (and the kernel ring buffer /
  many app logs) into (timestamp, message) rows. Ships a sample + golden.
- The 21 generic tools are covered by 7 parsers total: `aligned-columns`,
  `bracket-log`, `yaml`, `key-value`, `equals`, `colons`, `indented-hierarchy`.
- `run.sh --coverage` / `COVERAGE.md` now distinguish ✅ generic vs ✅ᵇ bespoke
  coverage. Full extract suite 219/219; smoke 33/33; melt 8/8; golden regression
  21/21.
- Files: `extract/strategies/delimited/aligned-columns.sh`,
  `extract/strategies/logging/bracket-log.sh`,
  `extract/samples/bracket-log/dmesg.txt`, `extract/tests/golden/bracket-log.txt`,
  `tests/corpus/*`.

## 2026-07-06 — generic tidy coverage 13 → 18/22 (headerless tables + tighter structured parsers)
- **Tightened the over-eager structured parsers** so they stop stealing tabular
  input from the columnar parser: `json` now requires the input to *close* with
  `}`/`]` (rejects `dmesg`'s `[ts] msg`), `yaml` requires a strong majority of
  YAML-shaped lines (rejects `free`/`sensors`), and `csv` ignores commas inside
  parentheses (rejects `mount` options like `(rw,nosuid,nodev)`).
- **Added a guarded headerless mode to `aligned-columns`** (now the generic
  parser for `who`, `mount`, `ip route`): when the first line already looks like
  data (has a digit-bearing token) it synthesises `c1..cN` columns instead of
  eating a data row as the header. Requires ≥3 consistent columns so it can't
  swallow key/value input.
- Net: generic-only tidy coverage **13 → 18 of 22** (`ss`, `lsblk`, `docker-ps`,
  `mount`, `who`, `ip route`, `free`, `sensors` added). Full extract suite stays
  **219/219**; smoke 33/33, melt 8/8.
- **Coverage is now queryable**: `tests/corpus/run.sh --coverage` generates
  `tests/corpus/COVERAGE.md`, a ✅/⏳ table of which tools tidy via a generic
  parser. Remaining gaps: `dmesg`, `ls -l`, `vmstat`, `uptime` (each needs
  targeted handling — see the corpus README).
- Files: `extract/strategies/structured/{json,yaml,csv}.sh`,
  `extract/strategies/delimited/aligned-columns.sh`, `tests/corpus/*`.

## 2026-07-06 — tidy-coverage corpus + generic columnar parser (fewer strategies)
- Start moving toward the design goal of tidying common tool outputs with a
  **minimum of strategies** (the ~12 generic parsers), rather than one bespoke
  strategy per tool.
- **New corpus + batch harness** under `tests/corpus/`: 22 common Linux tool
  outputs (`inputs/`), a correctness manifest (`expected.tsv`: per-tool expected
  tidy shape), frozen golden outputs for covered tools (`expected/`), and one
  script `run.sh` that runs every input through the engine in full and
  `--generic` modes, melts it, and checks tidiness. Modes: report / `--golden`
  (regression) / `--update-golden`.
- **Rewrote `aligned-columns` detection** (the generic whitespace-columnar
  parser) from a brittle header-shape regex to structural column-consistency
  with graded confidence, and raised its precedence (priority 70 → 55) so it
  wins tabular input over the key/value parsers (`colons`/`equals`) that were
  collapsing tables to a single row. Generic-only tidy coverage went **7 → 13
  of 22** (now: ps, df, top, iostat, netstat, ss, lsblk, docker-ps, systemctl +
  the key/value set). Full extract suite stays green (219/219); smoke 33/33,
  melt 8/8.
- Documented the tested tools and the 9 remaining gaps (over-eager
  `json`/`yaml`/`csv`; headerless tables; irregular structure) in
  `tests/corpus/README.md`.
- Files: `extract/strategies/delimited/aligned-columns.sh`, `tests/corpus/*`.

## 2026-07-06 — cut the cord to Envoy: extract/analyze/transform/lib are now first-party
- glean is now a **fully standalone** project with no live tie to Envoy. The
  `extract/`, `analyze/`, `transform/`, and `lib/` trees — originally imported
  from the Envoy suite — are now maintained here directly as first-party code.
  Extract strategies and engine changes are made in place, without regard to
  upstream Envoy; any future re-integration is a deliberate manual merge.
- **Removed the vendoring apparatus:** deleted `tools/sync-extract.sh`,
  `tools/sync-analyze.sh`, `tools/sync-melt.sh` (emptying `tools/`), and the
  `extract/VENDOR.json` / `analyze/VENDOR.json` provenance files. The original
  import points are preserved in git history and in this log (extract from
  `EnvoyExtract` @ `81bcb18`, analyze from `EnvoyAnalyze` @ `533bec8`, transform
  from `EnvoyCapture` @ `8639a6ef`).
- **`glean`:** removed the sibling-Envoy runtime fallbacks — `_find_engine` and
  `_find_analyze` no longer walk up looking for `EnvoyExtract/`/`EnvoyAnalyze/` or
  a `command -v envoy-*` on PATH, and `_source_transform` no longer falls back to
  a sibling `EnvoyCapture/lib/_core.sh`. The engines resolve only from this tree
  (`GLEAN_ROOT/extract`, `/analyze`, `/transform`) with a `GLEAN_HOME` override.
  Reworded the "not found" errors and `doctor` note that pointed at the deleted
  sync scripts to point at the expected in-repo paths.
- **Docs flipped from "vendored, do not hand-edit" to first-party:** rewrote the
  repository-layout / policy sections of `CLAUDE.md`, `README.md`, `HANDOFF.md`,
  and `extract/README.md`; updated the `transform/melt.sh` header (kept the
  original-import provenance line, dropped the "VENDORED / re-import" framing).
  Retitled a couple of stale "vendored" comments in `install.sh` / `tests/smoke.sh`.
- Historical CHANGELOG and `docs/0001` entries that describe the earlier vendored
  model are left intact (dated record).
- Verified green: smoke 33/33, transform 8/8, extract suite, analyze suite.
- Files: `glean`, `transform/melt.sh`, `CLAUDE.md`, `README.md`, `HANDOFF.md`,
  `extract/README.md`, `install.sh`, `tests/smoke.sh`; removed `tools/sync-*.sh`,
  `extract/VENDOR.json`, `analyze/VENDOR.json`.

## 2026-07-06 — drop Phase-5 framing (out of scope for the standalone repo)
- Phase 5 of proposal 0001 was "retire Envoy" — hard-cut the `Envoy*` trees in
  place in the monorepo. The standalone-repo split (2026-07-05) superseded that:
  `glean`'s vendored `extract/`/`analyze/`/`transform/`/`lib/` trees are already
  canonical here, and removing the upstream `Envoy*` trees is now a task in the
  Envoy monorepo, not this repo. Removed the stale "until the Phase-5 hard cut" /
  "retired at the Phase-5 cut" caveats that framed pending in-repo work.
- `HANDOFF.md`: dropped Phase 5 from "Next steps"; retitled the standalone-repo
  section; clarified the vendored trees are canonical here.
- `docs/0001-rename-and-simplification.md`: marked Phase 5 superseded by the split;
  reworded the Phase-2 re-sync caveat.
- `glean`, `tools/sync-{extract,analyze,melt}.sh`, `extract/README.md`: reworded
  engine/transform-locator and sync-script comments to describe the trees as
  canonical and the sync scripts as upstream re-vendoring (not "retired at Phase 5").
- Regenerated the `note` text in `extract/VENDOR.json` and `analyze/VENDOR.json`
  to match the updated sync scripts.
- Historical CHANGELOG entries below that mention Phase 5 are left intact (dated
  record). Verified green: smoke 33/33, transform 8/8.
- Files: `HANDOFF.md`, `docs/0001-rename-and-simplification.md`, `glean`,
  `tools/sync-extract.sh`, `tools/sync-analyze.sh`, `tools/sync-melt.sh`,
  `extract/README.md`, `extract/VENDOR.json`, `analyze/VENDOR.json`.

## 2026-07-05 — extracted to standalone repository (glean split from envoy)
- glean is now its own repository. The self-contained `glean/` tree was extracted
  from `MartinGallagher-code/envoy` via `git subtree split --prefix=glean` (history
  preserved: 15 glean commits replayed to repo root) and merged onto the existing
  repo (LICENSE retained; the stub README replaced by the tree's real README).
- **Restored the `extract/strategies/build/` directory (16 strategies + HANDOFF).**
  These files were silently dropped when the tree was committed to envoy: envoy's
  root `.gitignore` has a `build/` rule (for Python build artifacts) that matched
  `glean/extract/strategies/build/`, so the 16 build-tool strategies (`cargo-tree`,
  `cobertura`, `compiler-diagnostics`, `coverage`, `github-actions`, `go-mod-graph`,
  `gradle-output`, `junit-xml`, `make-stats`, `maven-output`, `npm-list`, `pip-list`,
  `sanitizer`, `test-results`, `test-summary`, `valgrind`) were never tracked even
  though `VENDOR.json` counted them (205). Their tests/goldens/samples *were*
  tracked, so the suite failed 17/219 until the strategies were restored. Recovered
  from `EnvoyExtract/strategies/build/` at the vendor SHA (`81bcb18`) so they match
  the rest of the vendored tree's goldens. Strategy count is now the recorded 205.
- **Added a root `VERSION` file (`1.2.1`).** The vendored extract engine resolves
  the canonical suite version by walking up for a `VERSION` file (`lib/envoy_version.sh`);
  envoy's lived at the repo root, outside `glean/`, so the subtree split left it
  behind and `--version` reported `0.0.0+unknown`. Restored at the extraction-point
  version so `extract/tests/test_interface.sh` passes.
- Added a `.gitignore` for the standalone repo (runtime `.glean/` store, backups,
  Python cache). Deliberately omits a bare `build/` rule — that pattern is exactly
  what dropped the build strategies upstream.
- Verified green standalone (no sibling Envoy present): extract 219/219 test files,
  smoke 33/33, transform 8/8, analyze engine suite 0 failures, `glean doctor` ok.
- Note for future re-syncs: `tools/sync-extract.sh` pointed at an envoy checkout
  will re-copy `strategies/build/` to disk, but envoy's `build/` gitignore rule
  means a plain `git add` there still won't track them — fix envoy's `.gitignore`
  or use `git add -f`. In this repo the files are tracked normally.
- Files: `VERSION`, `.gitignore`, `extract/strategies/build/*` (17), `README.md`.

## 2026-07-05 — standalone repo scaffolding: CLAUDE.md + CI workflow
- Added `CLAUDE.md` (project instructions for the standalone repo: layout, the
  "don't hand-edit vendored trees, re-sync from upstream" rule, doc + testing
  conventions, mawk-safety + symlink + `GLEAN_*` invariants).
- Added `.github/workflows/ci.yml` — inert in the upstream Envoy repo (GitHub
  only runs root `.github/`), active once glean is its own repo. Jobs: `smoke`
  (tests/smoke.sh), `transform` (transform/tests/test_melt.sh), `extract-suite`
  (extract/tests/run_tests.sh), `analyze-engine` (engine tests on gawk, excluding
  the un-vendored browse/dashboard tests), and `docs` (require the core docs).
  Paths are glean-root-relative. Validated: YAML parses (5 jobs), docs check
  passes, the analyze loop runs (only the known mawk-sensitive `test_correctness`
  fails locally — the CI job installs gawk for exactly that).
- Files: `glean/CLAUDE.md`, `glean/.github/workflows/ci.yml`.

## 2026-07-05 — prep for extraction to a standalone repository (revised Phase 5)
- Decision: rather than hard-cutting the `Envoy*` trees in place, glean is
  extracted into its own repo; Envoy stays intact as upstream. Made the tree
  self-documenting/standalone-ready:
  - Copied the design doc into the tree (`docs/0001-rename-and-simplification.md`)
    and repointed the `README`/`HANDOFF` links to it (they referenced the
    envoy-root `../docs/...`, which dangles at repo root).
  - Documented the standalone model in `README`/`HANDOFF`: vendored
    `extract/`/`analyze/`/`transform/`/`lib/` are canonical; `tools/sync-*.sh`
    require an Envoy checkout via `ENVOY_EXTRACT_SRC`/`ENVOY_ANALYZE_SRC`/
    `ENVOY_CAPTURE_SRC` (they error with that hint otherwise); extraction recipe
    (`git subtree split --prefix=glean`).
- Verified: `glean/` copied out of the envoy tree (no sibling `Envoy*`) runs
  fully — `doctor` resolves both engines, smoke 33/33, melt unit test 8/8; sync
  scripts fail helpfully standalone and work with the env overrides.
- Files: `glean/docs/0001-rename-and-simplification.md`, `glean/README.md`,
  `glean/HANDOFF.md`.

## 2026-07-05 — Phase 4: user-facing surface (README, completion, man, installer)
- Added the glean-native rename-plane deliverables: `README.md` (one-tool story +
  command/env reference), `completions/glean.bash` (verb + dataset/capture/path
  completion), `man/glean.1` (renders clean), and `install.sh` (puts `glean` on
  PATH + drops the completion and man page; supports `--uninstall`; installs in
  place, nothing copied out of tree).
- Fixed a symlink-safety bug surfaced by the installer: glean resolved its
  vendored `extract/`/`analyze/`/`transform/` from `dirname(BASH_SOURCE)`, which
  is the *symlink* path when run via a PATH launcher, so it failed with
  "transform module not found". Now resolves the real script dir once
  (`GLEAN_ROOT`, readlink-aware) and all three resolvers use it. Verified `glean`
  runs correctly via the installed symlink.
- Confirmed glean's own env surface is entirely `GLEAN_*`. Smoke → 33 checks
  (adds an install+symlink-launcher guard); all pass.
- Files: `glean/README.md`, `glean/completions/glean.bash`, `glean/man/glean.1`,
  `glean/install.sh`, `glean/glean`, `glean/tests/smoke.sh`.

## 2026-07-05 — import the melt/transform from source (was hand-copied)
- The extract-output transform — the tidy melt (`_core_melt_tidy`) plus the
  schema-union helpers (`_core_union_header`, `_core_align_rows`) — is now
  **imported from EnvoyCapture's `lib/_core.sh`** and vendored to
  `glean/transform/melt.sh` by new `tools/sync-melt.sh`, instead of the earlier
  hand-copied awk in `glean/glean`. `glean` sources the module and calls the
  canonical `_core_*` functions; the three hand-written duplicates
  (`_melt_tidy`/`_union_header`/`_align_rows`) are removed (`_col_overlap`, which
  is glean-specific, stays). A sibling-EnvoyCapture fallback keeps glean working
  before a sync. Added a transform unit test (`glean/transform/tests/test_melt.sh`,
  8 checks) adapted from EnvoyCapture's tidy-melt integration assertions. Smoke
  still 32/32. Version 0.6 → 0.7-proto.
- Files: `glean/glean`, `glean/transform/melt.sh` (vendored),
  `glean/transform/tests/test_melt.sh`, `glean/tools/sync-melt.sh`.

## 2026-07-05 — re-vendor extract engine: +3 everyday-command strategies
- Re-synced `glean/extract/` from upstream after adding `df`, `ps-aux`, and
  `mount` strategies (catalog 202 → 205). glean now auto-detects these common
  inputs: `df -h` (previously `unsorted` at conf 30 → now `df` at 92), `ps aux`
  (`ps-aux`, 90), and `mount` (90) — each producing a tidy one-row-per-record
  dataset with `#N` provenance. Verified end-to-end via `glean run`.
- Files: `glean/extract/**` (re-vendored), `glean/extract/VENDOR.json`.

## 2026-07-05 — schema reconciliation (union columns vs the .v2 split)
- `_store_append` now reconciles a same-typed capture whose column set differs
  from the existing dataset instead of always splitting to a variant. If the
  column overlap (Jaccard) ≥ `GLEAN_RECONCILE_OVERLAP` (default 60%), the two are
  **unioned**: the dataset's header grows to the union of columns, existing rows
  are blank-filled for new columns, and incoming rows are blank-filled for
  missing ones — so same-typed rows (and their `#N` indices) stay in one table
  that `show`/`stats`/`source` see whole. Below the threshold it still splits to
  a numbered variant (`free.v2`). New awk helpers `_col_overlap`/`_union_header`/
  `_align_rows`. Verified both branches (default unions the trimmed `free`;
  threshold 99 forces the `.v2` split). Smoke → 32 checks; all pass. Version
  0.5 → 0.6-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`.

## 2026-07-05 — stats: vendor the analyze engine, wire `glean stats`
- Vendored the analyze engine from `EnvoyAnalyze/` into `glean/analyze/` (entry
  point + `lib/` + `profiles/` + tests + samples) via new
  `glean/tools/sync-analyze.sh`; it reuses the already-vendored shared libs at
  `glean/lib/` (same `../lib` mechanism as the extract engine). The big
  `pipeline/` dir and the `browse`/`dashboard` tools are intentionally NOT
  vendored — glean only needs the analyze engine.
- New `glean stats <dataset> [analyze-args...]` runs the vendored engine over a
  dataset's TSV (default = key findings; pass `--all`, a numbered analysis list,
  `--format json`, etc.). `doctor` now reports the analyze engine and warns if
  `gawk` is absent (this box has `mawk`; core analyses still work).
- Also vendored the engine's `completions/`, `schemas/`, and `docs/` (needed by
  its test suite) — a first pass omitted them and regressed
  `test_completions`/`test_json_schema` (they pass upstream). Vendored analyze
  **engine tests: 26/27 pass** (excluding `browse`/`dashboard` tests and the two
  browse-backed tests `test_help_overlay`/`test_mdx`, since those tools aren't
  vendored). The single remaining failure, `test_correctness`, **also fails
  upstream** in this `mawk` environment — an environment issue, not a vendoring
  regression. `glean stats` itself is verified end-to-end via the smoke test
  (29 checks; all pass).
- Files: `glean/analyze/**` (vendored), `glean/tools/sync-analyze.sh`,
  `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.
- **Remaining:** schema reconciliation (union columns vs the `.v2` variant split).

## 2026-07-05 — Store model Stages B + C: controlled dirs + export/import
Completes the git-core directive.
- **Stage B — controlled directories.** `glean control [<dir>]` marks a directory
  as its own capture instance (`<dir>/.glean` with a `CONTROLLED` marker).
  Store resolution now walks up from CWD: `GLEAN_WORKSPACE` override → nearest
  controlled dir → global store. Captures run inside a controlled dir (or a
  subdir) route to its instance, and each capture commit **snapshots the
  directory's contents as context** (`context/manifest.tsv`: path/size/mtime/sha1,
  excluding `.glean`/`.git`). `glean instances` lists controlled dirs (from a
  registry in the global store); `glean uncontrol` releases one (data kept).
- **Stage C — export / import.** `glean export [<file>]` bundles the whole store
  (all datasets + capture commits + tags) into a portable `git bundle`;
  `glean import <file> [<dest>]` reconstitutes it elsewhere. Verified: after a
  move, the imported store's datasets, capture log, and per-row `#N → source`
  provenance are all browsable.
- Fixed a `set -e` escape: the controlled-dir context snapshot in `_ingest` ran
  as a bare `func || true` (current shell), so an internal failure aborted before
  the guard; now wrapped in a subshell.
- Smoke test → 27 checks (adds control/subdir-routing/context/instances +
  export/import round-trip); all pass. Version 0.4 → 0.5-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`,
  `glean/CHANGELOG.md`.
- **Still deferred:** `stats` (vendor envoy-analyze) and schema reconciliation.

## 2026-07-04 — Store model Stage A: global store + per-row provenance
Implements the fuller "git core" directive (row→source traceability, global
store, multi-user).
- **Global store by default:** captures go to `$GLEAN_HOME` (or `~/.glean`) so you
  can capture from any directory without being in a workspace. `GLEAN_WORKSPACE`
  is an explicit override (wins; used by tests). `doctor` reports which store and
  the next row index.
- **Per-row provenance with a visible `#N` index:** every dataset row gets a
  globally-unique index as its first column (shown by `show`). New
  `glean source <#N>` maps a row back to the exact captured input that produced
  it (prints the capture meta + stored `output.txt`). Provenance recorded in
  `provenance.tsv` (`#` → dataset → capture); a monotonic counter in
  `.next_row_id`.
- **Multi-user safe:** a `mkdir`-based store lock (stale-PID break, configurable
  `GLEAN_LOCK_TIMEOUT`) serialises concurrent writers; `git init` uses
  double-checked locking so parallel first-writers to a shared store don't race.
  Verified: 8 concurrent captures into a fresh shared store → 8 distinct indices,
  0 duplicates, git fsck clean.
- `_ingest` now assigns `#N`, writes provenance, and commits under the lock; both
  `run` and pipe-`inject` go through it. Smoke test → 17 checks (adds `#N`,
  `source`, concurrency); all pass. Version 0.3 → 0.4-proto.
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.
- **Still pending (proposal Stages B/C + analyze):** controlled directories,
  export/import, `stats`, schema reconciliation.

## 2026-07-04 — Phase-3: git core — capture-as-commit + restore
- The workspace is now a **git repo**: every capture is one commit tagged
  `capture-<id>`, replacing the flat-TSV-only store. Added verbs:
  - `glean run [--] <cmd>` — execute a binary, capture combined stdout+stderr,
    auto-detect + file it, and commit the capture (records `captures/<id>/meta.tsv`
    + `output.txt`).
  - `glean log` — list captures (id, timestamp, source, strategy, dataset, command).
  - `glean restore <id|latest>` — check a capture's committed tree back out
    (detached) to bring that run back up; `latest` returns to `main`.
- Refactored the extract→classify→melt→store core into a shared `_ingest` used by
  both `run` and pipe-`inject`; both now commit. `doctor` reports git-backed.
- Chosen model: simplified **linear git history** (one commit per capture) rather
  than EnvoyCapture's per-run + `__dataset`/`__results`/`__scripts` orphan-branch
  machinery (proposal 0001 §7).
- Smoke test extended to 11 checks incl. run→log→restore→restore-latest; all pass.
- Still deferred to Phase-3 cont.: `stats` (vendor envoy-analyze) and schema
  reconciliation (union columns vs `.v2` split).
- Files: `glean/glean`, `glean/tests/smoke.sh`, `glean/HANDOFF.md`.

## 2026-07-04 — Phase-2 fix: relayout to extract/ + lib/, vendor missing deps
- The first Phase-2 vendor (below) under-copied: the cross-suite shared libs
  (`envoy_version.sh`, `envoy_progress.sh`, …) and `EnvoyExtract/tools/` were left
  out, so 13 suite tests regressed (`--version`, `-V`, `--progress`,
  `new_strategy.sh`/`review_strategy.sh`) — all green upstream but failing
  vendored. Also, nesting the engine at `lib/extract/` put its `../lib` at the
  confusing `lib/lib`.
- Fix: moved the vendored engine to `glean/extract/` and the shared libs to
  `glean/lib/` (the engine's `../lib`), mirroring the upstream engine-dir +
  sibling-`lib/` layout so the suite resolves paths unchanged. `sync-extract.sh`
  now also vendors `tools/` and the repo-root `lib/*.sh`. All 4 previously-failing
  files pass in the new location (21/21, 8/8, 13/13, 21/21). `glean` `_find_engine`
  updated to `extract/envoy-extract`. **Full vendored suite now genuinely green:
  216/216 test files passed, 1103 assertions, 0 failed (exit 0)** — correcting an
  earlier premature "green" claim that was based on a partial run (the full run
  had in fact exited 1 with the 13 failures above).
- Files: `glean/extract/**` (relocated + `tools/`), `glean/lib/*.sh` (shared),
  `glean/tools/sync-extract.sh`, `glean/extract/README.md`, `glean/glean`,
  `glean/HANDOFF.md`.

## 2026-07-04 — Phase-2: vendor the extract engine into lib/extract/
- Vendored the full extract engine (entry point + `lib/` + all 202 strategies +
  tests + samples; ~1,145 files) from `EnvoyExtract/` into `glean/lib/extract/`
  so the tree is self-contained and runnable without the sibling project.
- Added `tools/sync-extract.sh` — refreshes the vendored copy from `EnvoyExtract/`
  (source of truth until the Phase-5 hard cut) and writes `lib/extract/VENDOR.json`
  (source git SHA, timestamp, component list, strategy/file counts) so drift is
  visible. Supports `--runtime-only`. Added `lib/extract/README.md` (do-not-edit +
  how-to-sync note).
- `glean` `_find_engine` now resolves the vendored copy first; the
  sibling-`EnvoyExtract/` walk-up is demoted to a transition fallback.
- Confirmed the strategy/engine suite passes in the new location
  (`bash glean/lib/extract/tests/run_tests.sh`) and `glean/tests/smoke.sh` still
  passes against the vendored engine.
- Files: `glean/lib/extract/**` (vendored), `glean/tools/sync-extract.sh`,
  `glean/lib/extract/README.md`, `glean/glean`, `glean/HANDOFF.md`.

## 2026-07-04 — Phase-1 prototype
- New `glean/` tree (proposal 0001): single-binary `glean` implementing the
  product's one path — `cmd | glean` auto-detects format via the real extract
  engine (`--emit-meta`, all 198 strategies), melts to one row per record, and
  files it into a per-type dataset. Verbs: default inject, `ls`, `show`,
  `triage`, `doctor`, `help`.
- Minimal flat-TSV store under `$GLEAN_WORKSPACE` (default `./.glean`); differing
  headers split to numbered variants (git store + schema reconciliation deferred
  to Phase 3). Engine resolved via sibling `EnvoyExtract/` fallback until Phase 2
  copies it under `glean/lib/extract/`.
- Files: `glean/glean`, `glean/HANDOFF.md`, `glean/CHANGELOG.md`,
  `glean/tests/smoke.sh`.
