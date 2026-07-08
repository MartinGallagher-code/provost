# text-inputs — free-form output glean intentionally does NOT parse

These captures are **prose / free text**, not tabular or record-structured data
(version banners, status narratives, config displays that read as sentences).
glean's job is to tidy *structured* command output; forcing a parser onto text
like this only invents fake columns.

They are kept here — **out of `tests/corpus/inputs/`** — so the coverage harness
(`run.sh`) and its manifest/goldens never treat them as things-to-tidy. They
carry **no `expected.tsv` row, no golden, and no test**. Move an input here (and
drop its manifest row + `expected/<name>.tsv`) whenever review decides it is
"just text."
