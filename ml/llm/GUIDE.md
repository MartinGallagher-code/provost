# Labelling guide: how a capture's lines become data

You are labelling the output of a command-line tool so a small model can learn
from it. For every line, say what the line *is* and which pieces of it are the
values a person would want, one per spreadsheet cell. Work from the text alone,
the way a careful person reading the output would.

## Input

The capture comes with its tool name and its lines numbered from 0. Each line is
shown as `N |text`: the text starts right after the `|` (leading spaces are part
of the line). Line numbers count every line, blank ones too.

## Output

One JSON object, and nothing else:

```json
{"name": "<tool name>",
 "lines": [
   {"n": 0, "role": "header", "cells": ["NAME", "STATUS", "AGE"]},
   {"n": 1, "role": "row",    "cells": ["web-1", "Running", "5d"]},
   {"n": 2, "role": "blank",  "cells": []}
 ],
 "notes": "one or two sentences: what the output is, and anything you were unsure of"}
```

Give every line exactly once, in order.

## Roles

| role | the line is | cells |
|---|---|---|
| `blank` | empty or only spaces | `[]` |
| `header` | the column names of a table | each column name |
| `row` | one record of a table (with or without a header) | each value, one per column |
| `cont` | a table row wrapped onto the next line (continues the row above) | the continued value(s) |
| `kv` | one key and its value (`Name: web`, `size = 4`, `Status ....... ok`) | `[key, value]` (or `[key, v1, v2]` when one key has several distinct values) |
| `section` | a heading that names what follows (`Disks:`, `== Summary ==`, `[mysqld]`) | `[title]` |
| `skip` | anything that isn't data: rules (`-----`, `====`), banners, prose sentences, prompts, footers like `(3 rows)` | `[]` |

When a line could be read two ways, prefer the reading that makes the most lines
of the capture consistent. A run of similar lines without a header is still
`row`s.

## Cells

- **Copy every cell verbatim** from the line, character for character. Cells
  must appear in the line in order, without overlapping. Don't fix typos,
  units, case or spacing *inside* a value.
- **One value, one cell.** Keep multi-word values whole: `5 minutes ago`,
  `Mounted on`, `80/tcp, 443/tcp`, `Up 2 hours (healthy)`. A timestamp is
  one value: `Jan 25 00:52`, `2024-06-14 10:22:01 UTC`, `Jul  7 14:25:33`.
  A number keeps its unit: `512m`, `1.2 GiB`, `40%`.
- **Don't drop words.** A word that reads like filler (`is healthy`,
  `in 2m1s`) belongs to the value next to it, not to nothing.
- **Separators are not values.** Leave out `:` `=` `|` `->` dot leaders,
  column rules, and the spaces between columns.
- **Brackets and quotes:** either keep them or drop them (`[512m]` or `512m`);
  both count as the same split.
- **Table rows line up with their header.** When a table has a header, each row
  has exactly one cell per header column, left to right; use `null` for a
  column that is empty on that row. A header with a column that has no name
  (the first column of `free`, say) uses `null` in the header for it.
- **A table without a header:** give the rows a consistent number of cells.
- **Structured values** (a path, a URL, an ARN, `user@host`, a version like
  `v2.11.3+a1b2c3d4`) are one value unless the output itself spaces them out.
- **Syslog / log lines:** timestamp, host, program, pid (`CRON[1442]:` is
  `CRON` and `1442`), then the message. Split the message further only when it has a clear fixed layout
  repeated across lines (fields separated by runs of spaces, or `key=value`
  pairs); free text stays one value.
- **`key=value` pairs on one line** (`a=1 b=2`, `icmp_seq=3 ttl=56`,
  `high = +80.0°C, crit = +100.0°C`): every key and every value is its own
  cell (`a`, `1`, `b`, `2`). The line is `kv` when it's a single pair,
  otherwise `row`. Anything before the pairs (a device, a label) is a cell too.
- **Pipe tables** (`| a | b |`, psql/mysql output): the pipes are separators,
  each column is a cell, the `+----+` rules are `skip`.
- **Bracketed tags** at the start of a log line (`[INFO]`, `[D][api:102]:`)
  are cells; progress bars (`[=====>   ]`, `||||....`) are decoration, not
  cells.

## Checking your work

After writing a capture's JSON, run the checker on it and fix anything it
reports until it prints `ok`:

```bash
python3 ml/llm/check.py LABEL.json NUMBERED_INPUT.txt
```
