# Writing a parsing template for one tool's output

You are given one capture of a command-line tool's output, its lines numbered
from 0 (`N |text`: the text starts right after the `|`). Write a **template**:
a small set of regular expressions that turns this output, and every future
output of the same tool, into tidy tables. Reply with the JSON template
only: no prose, no code fence.

The template will be applied, offline and deterministically, to many future
captures whose values differ from this one: other hosts, counts, names,
dates, row numbers, and more or fewer rows. Write patterns for the **layout**,
never for this capture's particular values.

## Format

```json
{
  "format": 1,
  "tool": "<short tool name>",
  "detect": "<regex found in any output of this tool, e.g. its header line or banner>",
  "skip": ["<regex for decoration lines: rules, banners, prompts, footers, prose>"],
  "blocks": [
    {"name": "<what the rows are, e.g. processes>",
     "kind": "table",
     "header": "<regex matching the table's header line(s); optional>",
     "line": "<regex matching ONE data line, with a named group per column>",
     "columns": {"<group>": "<the column's name as printed, e.g. Mounted on>"}},
    {"name": "<e.g. summary>",
     "kind": "kv",
     "line": "<regex matching ONE key/value line, with groups key and value>"}
  ]
}
```

## How it is applied

- **Each non-blank line is classified in this order:**
  1. it is decoration when any `skip` pattern finds a match in it;
  2. otherwise the first block whose `header` finds a match takes it as a
     header line;
  3. otherwise the first block whose `line` matches the **whole line** takes
     it as data;
  4. anything else is uncovered.
- **Put more specific blocks before more general ones**, because the first
  match wins.
- **What each kind of block produces:**
  - a `table` block makes one row per data line, from its named groups, in
    their order;
  - a `kv` block makes one record of key → value pairs.
- **Patterns are Python `re` syntax**, and group names must be identifiers.
  Use `columns` to give a column its printed name (`Mounted on`, `%CPU`).
- **The template must cover at least 80% of the capture's non-blank lines**
  as skip, header or data lines, or it is rejected.

## What a value is

- **One value, one group.** Keep multi-word values whole: `5 minutes ago`,
  `Mounted on`, `Up 2 hours (healthy)`. A timestamp is one value
  (`Jan 25 00:52`, `2024-06-14 10:22:01 UTC`). A number keeps its unit
  (`512m`, `1.2 GiB`, `40%`).
- **Separators and decoration are not values.** Leave `:`, `=`, `|`, `->`,
  dot leaders, rules, progress bars and tree glyphs outside the groups.
- **`key=value` pairs on a line:** give each value its own group, named after
  its key (`(?P<ttl>\d+)` for `ttl=56`).
- **Syslog and log lines:** timestamp, host, program, pid, then the message
  (one group, unless it has a fixed layout repeated across lines).
- **Empty columns:** make the group optional so a row with an empty cell
  still matches. For example, `(?:\s+(?P<reason>\S+))?` for a column that
  is sometimes blank.

## Writing patterns that generalise

- **Columns:** match them by what separates them (runs of two or more
  spaces, tabs, a fixed delimiter) and by what they contain. `\S+` for a
  single token, `\S(?:.*?\S)?` for a value that may hold single spaces,
  `\d+` and `[\d.]+[KMGT]?` for numbers. Don't depend on exact column
  widths unless the tool pads to fixed widths.
- **No literal data values** (host names, IDs, dates) in `line` patterns.
  Literal words are fine where the tool always prints them (`Status:`, `dev`,
  `via`).
- **`detect` should match the stable part of the output:** a header line, a
  banner, a fixed label. Never a value.
- **When the output has several sections** (a summary block, then a table, or
  several tables), give each its own block.
- **Section titles and lines that carry no data go in `skip`.**
