# Common-tool tidy corpus

A curated corpus of **common Linux tool outputs** plus a batch harness, used to
drive glean toward its design goal: turn any tool output into tidy data with a
**minimum of strategies** — ideally the ~12 generic parsers, no per-tool rule.

- `inputs/<tool>.txt` — a representative captured output for each tool. These are
  the regression inputs; keep them stable.
- `expected.tsv` — the correctness manifest: for each input, the expected tidy
  shape (`table` = strict data-row count, `kv` = key/value snapshot; plus a
  minimum column count).
- `expected/<tool>.tsv` — frozen golden tidy output, written **only** for tools
  that currently come out correctly tidy (so the golden gate tracks the covered
  set exactly).
- `run.sh` — the batch harness (one script, all inputs).

## Running

```bash
bash tests/corpus/run.sh                 # report: full vs --generic winner, tidy? per tool
bash tests/corpus/run.sh --golden        # regression: diff generic tidy output vs goldens
bash tests/corpus/run.sh --update-golden # re-freeze goldens for the covered tools
```

`run.sh` runs each input through the extract engine twice — **full** mode (all
205 strategies) and **`--generic`** mode (only the ~12 fundamental parsers) — then
melts the result and checks it against the manifest. The `--generic` column is
the one that matters: it measures how well glean tidies each tool *without a
bespoke strategy*.

## Tested tools & current coverage

**Generic-only tidy: 13 / 22.** In full mode all 22 are handled (a bespoke
strategy wins), but the goal is to retire those in favour of the generic parsers.

| Tool | kind | generic-tidy | generic parser | note |
|---|---|:---:|---|---|
| ps aux | table | ✅ | aligned-columns | |
| df -h | table | ✅ | aligned-columns | |
| top | table | ✅ | aligned-columns | |
| iostat | table | ✅ | aligned-columns | |
| netstat -tulpn | table | ✅ | aligned-columns | |
| ss -tulpn | table | ✅ | aligned-columns | |
| lsblk | table | ✅ | aligned-columns | |
| docker ps | table | ✅ | aligned-columns | columns approximate (spaces in COMMAND/STATUS) |
| systemctl list-units | table | ✅ | aligned-columns | |
| /proc/meminfo | kv | ✅ | yaml | |
| lscpu | kv | ✅ | key-value | |
| env | kv | ✅ | equals | |
| ip addr | kv | ✅ | indented-hierarchy | |
| free | table | ❌ | (yaml steals) | over-eager `yaml` matches `Mem:`/`Swap:` lines |
| mount | table | ❌ | (csv steals) | `X on Y type Z (opts)` sentence form; `csv` mis-wins |
| dmesg | table | ❌ | (json steals) | `[ts] message`; needs a 2-col split, `json` mis-wins |
| sensors | kv | ❌ | (yaml steals) | multi-section `label: +val°C` |
| vmstat | table | ❌ | aligned-columns | two-line header (group row + field row) |
| who | table | ❌ | aligned-columns | no header row → first data row consumed as header |
| ip route | table | ❌ | aligned-columns | no header; `default via … dev …` key-ish lines |
| ls -l | table | ❌ | aligned-columns | no header + space-bearing date column |
| uptime | kv | ❌ | (none) | single line; needs field extraction (load avgs, users) |

## Known gaps → next work

The remaining 9 fall into three root causes:

1. **Over-eager high-precedence parsers** (`json`/`yaml`/`csv`, priority 10–14)
   win before `aligned-columns` and mis-handle `free`, `mount`, `dmesg`,
   `sensors`. Fix: tighten their `detect()` so they don't claim
   whitespace-columnar / sentence input.
2. **No header row** (`who`, `ip route`, `ls -l`): `aligned-columns` assumes line
   one is the header. Fix: a headerless columnar mode that synthesises `c1..cN`.
3. **Irregular structure** (`vmstat` two-line header, `uptime` single line): need
   targeted structural handling.

The whole point of the corpus is to make this measurable: as the generic parsers
improve, `run.sh` moves tools from ❌ to ✅ and a new golden is frozen — with the
full extract suite (`extract/tests/run_tests.sh`) kept green the whole way.
