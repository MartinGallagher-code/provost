# Parsing templates

provost works out the format of most output by itself. Some output it reads
badly: a report whose lines all differ, a banner the engine takes for a header,
a block of `Key: value` lines inside a table. For those, you can write a
**template**: a small JSON file of regular expressions, one per kind of line,
that says how to read one tool's output. provost then applies it to every
capture of that tool, offline and the same way every time.

You do not need `--llm` for this. `--llm` is one way to get a template (Claude
writes it); writing it yourself is another, and the template is the same kind
of file either way. provost applies a template that fits whether or not
`--llm` is on, and applying one sends nothing anywhere.

- [A first template](#a-first-template)
- [The format](#the-format)
- [Where provost looks, and when it uses one](#where-provost-looks-and-when-it-uses-one)
- [Testing a template](#testing-a-template)
- [TextFSM templates](#textfsm-templates)
- [Settings](#settings)

## A first template

Say a tool prints this, and you saved one run of it as `volumes.txt`:

```text
Volumes on host alpha
NAME     SIZE   USED   MOUNT
data     500G   120G   /srv/data
backup   2T     1.5T   /srv/backup
logs     100G   80G    /var/log
```

This template reads it: the banner is decoration, the second line is the
table's header, and each line after it is a row of four named values.

```json
{
  "format": 1,
  "tool": "volumes",
  "detect": "^Volumes on host ",
  "skip": ["^Volumes on host "],
  "decoration": ["Volumes a"],
  "blocks": [
    {
      "name": "volumes",
      "kind": "table",
      "header": "^NAME\\s+SIZE\\s+USED\\s+MOUNT$",
      "line": "^(?P<name>\\S+)\\s+(?P<size>\\S+)\\s+(?P<used>\\S+)\\s+(?P<mount>/\\S*)$"
    }
  ]
}
```

Try it on the saved output before you use it. `provost template test` files
nothing; it shows what the template makes of the capture:

```bash
provost template test volumes.json volumes.txt
```

```text
template   volumes.json (format 1)
detect     line 1: Volumes on host alpha
coverage   100% of 5 non-blank lines: 4 read, 1 skipped (0 decoration, 1 of a kind judged decoration, 0 of a kind not judged: counted as unread), 0 unread

table 1: volumes (table, 3 rows, read from lines 2-5)
name	size	used	mount
data	500G	120G	/srv/data
backup	2T	1.5T	/srv/backup
logs	100G	80G	/var/log
```

Then put it where provost looks. Your own directory, named in
`PROVOST_TEMPLATE_DIRS`, serves every store:

```bash
mkdir -p ~/provost-templates && cp volumes.json ~/provost-templates/
export PROVOST_TEMPLATE_DIRS=~/provost-templates
provost run volumes            # or: volumes | provost
```

Or put it in a store's `llm-templates/` directory, and it is committed with the
store's next capture, so the store carries its own parsers. Either way, the
next capture of the tool is read by the template, and its `meta.tsv` says so:

```text
llm_template	filed by template volumes.json
template	/home/jo/provost-templates/volumes.json
```

## The format

A format-1 template is one JSON object:

| Key | Needed | What it is |
|---|---|---|
| `format` | yes | `1` |
| `tool` | no | the tool's name. A capture with no `--name` is filed under it |
| `detect` | no | a pattern that recognises the tool's output: provost tries the template on any capture where it matches one of the first 200 lines. Without it, the template is used only for a capture named for it (below) |
| `skip` | no | patterns for lines that carry no data: rules, banners, prompts |
| `decoration` | no | the kinds of skipped line you have judged to be decoration (see [The skip audit](#the-skip-audit)) |
| `blocks` | yes | one or more blocks, each a table or a key/value list |

Each block:

| Key | Needed | What it is |
|---|---|---|
| `name` | no | the block's name (`block1`, `block2`, ... by default) |
| `kind` | yes | `table` (one row per line) or `kv` (one key and value per line) |
| `line` | yes | the pattern for one data line, with a named group (`(?P<name>...)`) for each value |
| `header` | no | a pattern for the block's header line or lines: read, and not a row |
| `columns` | no | display names for the groups: `{"pid": "process id"}` |

How a capture is read, line by line:

1. A blank line is passed over. A line longer than 4,096 characters is left
   unread.
2. A line any `skip` pattern matches is skipped.
3. Otherwise the blocks are tried in order. A line a block's `header` matches
   is a header line. A line its `line` pattern matches **in full** is a data
   line. The first block that matches takes the line.
4. Any other line is unread.

The patterns are Python regular expressions. `line` must match the whole line;
`detect`, `skip` and `header` match anywhere in it, so anchor them with `^`
when you mean the start. In JSON every backslash is doubled: `\s` is written
`"\\s"`. A value is trimmed of spaces at both ends.

### Tables

A `table` block makes one row per data line, with a column per named group, in
the order the groups appear. The volumes template above is one.

### Key/value lists

A `kv` block's `line` has two groups, `key` and `value`, and the block makes
one record: each key is a column. A key that comes again gets `_2`, `_3`.

```text
Battery report for host alpha
-----------------------------
State:    charging
Charge:   87%
Cycles:   412
Health:   Good
```

```json
{
  "format": 1,
  "tool": "battery",
  "detect": "^Battery report for host ",
  "skip": ["^-+$", "^Battery report for host "],
  "decoration": ["Battery a"],
  "blocks": [
    {"name": "battery", "kind": "kv",
     "line": "^(?P<key>[A-Z][a-z]+):\\s+(?P<value>\\S.*)$"}
  ]
}
```

### Several blocks

A template can have several blocks, for output that holds more than one kind of
data. Each block that yields at least one row becomes a dataset of its own,
named `NAME.BLOCK`, under the one capture. The `mcstatus` template shipped with
provost (`extract/llm/templates/mcstatus.json`) has a `players` table and a
`status` key/value block, so a capture of it files `mcstatus.players` and
`mcstatus.status`.

### The skip audit

A `skip` pattern could swallow lines that matter: a version, a count, a
warning. So a skipped line is counted as read only when it is plainly
decoration:

- a line with no letter or digit (a rule of dashes, box glyphs) always is;
- a line that carries a word or a number is, when its **kind** is in the
  template's `decoration` list. Until then it counts as unread when provost
  measures the template.

A line's kind is its first word, and the rest of the line folded to its shape:
`Volumes on host alpha` and `Volumes on host beta` are both `Volumes a`. You do
not have to work it out: `provost template test` lists every skipped kind not
yet in `decoration`, quoted, ready to paste:

```text
set aside, of a kind not judged decoration (1, counted as unread; a kind added to the template's "decoration" list counts as decoration):
  "Volumes a"  (1 line; line 1: Volumes on host alpha)
```

### Notes

Nothing that carries information is dropped. Every skipped or unread line that
has a word or a number in it (the banner above, a summary, an error between the
rows) is filed beside the template's datasets as `NAME.notes`, with its line
number and whether it was skipped or unread.

### Format 2

For records that span lines (indented attribute blocks, a title that becomes a
column), a template can carry a small Python parser instead of patterns:
`{"format": 2, "detect": "...", "parser": "def parse(lines): ..."}`. It runs in
a box (a separate interpreter, a few pure modules, no files or network, a CPU
and memory limit). Claude writes these under `--llm`; `extract/llm/GUIDE.md`
describes what `parse` returns. The `ip-addr` template shipped with provost is
one.

## Where provost looks, and when it uses one

provost looks in three places, in this order:

1. the store's `llm-templates/` directory (committed with the captures);
2. the directories in `PROVOST_TEMPLATE_DIRS`, separated by colons
   (`PROVOST_LLM_TEMPLATE_DIRS`, its older name, is read too);
3. the templates shipped with provost (`extract/llm/templates/`).

It picks one by **name** first: `NAME.json` (or `NAME.textfsm`) for a capture
filed with `--name NAME`, or for `provost run NAME ...`. If none is named for
the capture, it tries every template whose `detect` pattern matches one of the
first 200 lines, and takes the one that covers most of the capture.

A template is tried:

- on a capture the quality gate would hold, before segmenting it and before the
  layout model;
- on a **generic** parse the gate passed (aligned columns, CSV, text lines),
  before that parse is trusted: the gate cannot see a title read as the header,
  and a template written for the tool's layout can;
- never in place of an exact-format parser (JSON, XML, ...) or a tool-specific
  one, except YAML, which a template may better (plain `Label: text` output is
  valid YAML).

What the template yields is measured like any parse, and filed only when it
passes the same gate:

- against a capture the gate would hold, it must keep at least 10 points more
  of the input's data lines than the held parse;
- against a generic parse the gate passed, it must keep that parse's share of
  the data lines within 10 points (20 against `text-lines` and `line-records`,
  which keep every line by design);
- lines the template marks as decoration (as the skip audit allows) are not
  counted against it;
- each block must also pass the gate's shape checks.

When a template is not used, `meta.tsv` says why (`llm_template declined: ...`)
whenever one was found. A capture with no template for it says nothing.

`--no-templates` (`PROVOST_TEMPLATES=0`) turns all of this off for a capture.
`--llm` goes further: when no template fits, it has Claude write one, which
sends the capture's text to the Anthropic API. It cannot be combined with
`--no-templates`.

### The time limit

Python's regular expressions backtrack, and a pattern such as `(a+)+$` can run
for hours on a long enough line. So one template may take at most
`PROVOST_TEMPLATE_TIMEOUT` seconds (10) on one capture. Past that, it is
declined, `meta.tsv` says so, and provost reads the capture without it:

```text
llm_template	declined: template slow.json does not fit: it took longer than 10s on this capture (the limit, PROVOST_TEMPLATE_TIMEOUT)
```

## Testing a template

```bash
provost template test TEMPLATE CAPTURE [EXPECTED.tsv] [--tables]
```

It applies the template to a saved capture and prints:

- the line its `detect` pattern matches (or that it matches none, so provost
  would use it only for a capture named for it);
- its coverage, as the gate counts it;
- each table it makes;
- the skipped lines of a kind not in `decoration`;
- every line it leaves unread.

`--tables` prints the tables alone. Check them, save them, and that is the
expected output: from then on, with `EXPECTED.tsv` given, `template test`
compares, prints a diff when the tables differ, and exits 1. Keep each template
with a capture and its expected tables, and a test run catches a change to the
template that reads them differently (the `.raw` and `.yml` pattern of
ntc-templates):

```bash
provost template test volumes.json volumes.txt --tables > volumes.expected.tsv
provost template test volumes.json volumes.txt volumes.expected.tsv
```

One table is written as plain TSV, a header and its rows. Several are each
written under a `# table: NAME` line, with a blank line between them. A
key/value block is written as two columns, `key` and `value`.

It exits 0 when the template reads the capture (and its tables are the
expected ones), 1 when it does not (it reads nothing, the tables differ, it ran
past the time limit, or a TextFSM `Error` rule fired), and 2 when it cannot be
tried (a file that cannot be read, a pattern that does not compile, TextFSM not
installed).

## TextFSM templates

provost also reads [TextFSM](https://github.com/google/textfsm) templates, the
format of the [ntc-templates](https://github.com/networktocode/ntc-templates)
collection (about a thousand templates for network devices). This needs the
optional `textfsm` package, in the Python that runs provost:

```bash
pip install 'provost[textfsm]'
```

(With a git checkout of provost, `pip install textfsm` for the `python3` on
your `PATH`, or set `PROVOST_PYTHON` to the interpreter that has it.)

A TextFSM template is a file named `NAME.textfsm` in one of the directories
above. It has no `detect` pattern, so provost uses it only for a capture
**named** for it:

```bash
pip install ntc-templates
cp "$(python3 -c 'import ntc_templates, os; print(os.path.dirname(ntc_templates.__file__))')/templates/cisco_ios_show_version.textfsm" ~/provost-templates/
provost --name cisco_ios_show_version show-version.txt
```

It makes one table, named after the template. Its columns are the template's
`Value` names in lower case (as ntc-templates gives them), and a `List` value's
items are joined with `, `. A line a rule with a `Value` matches is read; one
that only rules without a `Value` match is skipped; any other is unread. An
`Error` rule that fires declines the template.

TextFSM templates pick the values they name out of the output and pass the rest
by, so a template that reads 9 lines of a 32-line `show version` is doing its
job. provost therefore records a TextFSM template's coverage but does not
compare it with the engine's: its table still passes the gate's shape checks,
and every line it does not read that carries a word or a number is kept in
`NAME.notes`. `provost template test` works on TextFSM templates too.

ntc-templates and TextFSM are licensed under the Apache License 2.0.

## Settings

| Setting | Default | What it does |
|---|---|---|
| `--templates`, `--no-templates`, `PROVOST_TEMPLATES` | on (`1`) | apply a template that fits |
| `PROVOST_TEMPLATE_DIRS` | none | your own template directories, colon-separated |
| `PROVOST_LLM_TEMPLATE_DIRS` | none | the older name of `PROVOST_TEMPLATE_DIRS` (both are read) |
| `PROVOST_TEMPLATE_TIMEOUT` | `10` | whole seconds one template may take on one capture (1 to 3600) |
| `PROVOST_PYTHON` | `python3` | the Python that applies templates (the pip launcher sets it to its own) |
| `--llm`, `PROVOST_LLM` | off | when none fits, have Claude write one ('provost help advanced', TEMPLATES) |
