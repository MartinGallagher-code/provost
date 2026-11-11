# Reviewing what a parsing template makes of a capture

You are shown one capture of a command-line tool's output (its lines
numbered from 0, `N |text`), the parsing template another writer made for
the tool, and what that template makes of this capture: each table it
yields, with the lines it read, and the lines it set aside. The tables are
filed as data, so a person can query them without reading the capture.

Decide whether the tables represent the capture **correctly and completely**.
Reply with JSON only, no prose and no code fence:

```json
{"verdict": "PASS"}
```

or

```json
{"verdict": "FIX", "fixes": ["<one concrete change to the template>", "..."]}
```

## What to check, in this order

The template already reads most lines (that was checked before you were
asked). What a coverage check cannot see is **structure**. Look for:

1. **A parent the tables do not keep.** A line that governs the rows under
   it (a section title, a group or unit header, a function or file name
   above its entries, a parent node of a tree, a trunk or bond above its
   members, a caller above its callees, an indentation level or depth) must
   become a column of those rows, or the rows can no longer be told apart.
   Rows that would be ambiguous without their parent are the commonest
   fault.
2. **A record split apart.** One record (one entity's fields) spread over
   two tables, or over several rows, when the capture prints it as one
   unit; or two kinds of record glued into one table, so half the columns
   are empty on every row.
3. **A header half applied.** A table whose header names some columns but
   not others, a second layout of the same table read with the first
   layout's columns, or values sitting under the wrong column names.
4. **A line kind misread.** A pattern that matches a line it was not meant
   for, so its values land in the wrong columns (a summary line read as a
   row, a unit or a total read as a name).
5. **Data set aside.** A line listed as set aside that carries values (a
   count, a total, a status, an error) is data, not decoration, unless the
   tables already hold the same values.

Column names should be the tool's printed names where it prints them, and a
value keeps its unit. Do not ask for anything else: no renaming for taste,
no re-typing of values, no new columns computed from others, no splitting of
free text that the tool prints as one message.

## The fixes

- Say **PASS** when the tables are right, or wrong only in ways listed above
  as "do not ask". A template is reused on every later capture of the tool,
  so do not ask for changes to fit this capture's particular values.
- Otherwise list at most **five** fixes, the most important first. Each fix
  names what is wrong and what the template should do instead, specifically
  enough for the writer to act without seeing your reasoning: "lines 12-30
  are the members of the trunk named on line 11: add a `trunk` column to the
  members table, filled from the trunk line above (this needs a format-2
  parser)", not "keep the hierarchy".
- Point at line numbers. Say when a fix needs a format-2 parser (records
  that span lines, a parent carried down to the rows under it).
