# Round 4 variants: a second capture of every round-4 tool (2026-10-27)

One file per round-4 input, same stem: what the same command would print on
another machine or another day. Written by Claude helpers who read only the
original capture and `../manifest.tsv` (never a template, a parser, the
engine, the corpus or a rating), to the tool's documented format, with every
value changed, at least one count changed, widths shifted and optional parts
added or removed where the tool has them. Frozen in `../variants-SHA256SUMS`
before any template was applied to them.

Purpose: measure what a template stored from the original capture does on
the next capture of the same tool (`../../llm_round.sh --round4 --inputs
round4/variants`). Rated on `../CRITERIA.md`.

How they were made, as the helpers reported it:

- **Real output (tool run here on new scratch inputs, paths neutralised):**
  051, 053–058 (python, redis, ruby, stty), 042, 043, 045, 046, 048–050
  (php, podchecker, prtstat, pydoc, pytest, python). 052 started from a real
  run and was hand-edited.
- **Written to the format** (by hand or by small generators that reproduced
  the original's widths first): everything else.
- **A different subject where the subject is the data** (the output is fixed
  for a given argument): 019 `go doc container/list`, 042 `php --rc
  DatePeriod`, 046 `pydoc3 fnmatch`; and **an older tool version** where the
  output is fixed for a version: 011, 012, 014, 020, 023, 030, 032, 047. These
  are harder than "same command, new values": fields and lines the original
  had are absent.
- **Alignment corrected toward the real tool**, not the original's quirk:
  125 sp_who2 and 139 tasklist rows sit on the dash rule (the originals'
  rows are shifted 2 characters right of it).
- **Weak variants** (the tool's output barely varies): 044 (`head -80` of a
  fixed settings list), 059 (fixed groups; one syscall fewer), 045 and 029
  (fixed record structure; values only).
- **From memory, not checked against real output:** details of 002/003
  (bison token order), 004 (bun `toHaveLength` text), 005 (bundle env
  OpenSSL block), 008 (clang bitfield storage), 052 (3.14 additions), 060
  (systemd-delta diff block), 062 (helgrind lock announcement), 063, 103,
  030.
