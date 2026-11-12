# ntc-templates fixtures

Two templates and their test fixtures from
[ntc-templates](https://github.com/networktocode/ntc-templates) 9.3.0, for
`ml/tests/test_templates.py` (PV-039): provost's TextFSM support must read
each capture into the records ntc-templates expects.

| File | From |
|---|---|
| `NAME.textfsm` | `ntc_templates/templates/NAME.textfsm`, the 9.3.0 package |
| `NAME.raw`, `NAME.yml` | `tests/cisco_ios/<command>/NAME.raw` and `.yml`, tag `v9.3.0` |
| `NAME.tsv` | the `.yml`'s `parsed_sample` as the tables `provost template test` prints: the template's Values in order, lower-cased; a list joined with `, ` |

They are ntc-templates' files, under the Apache License 2.0 (`LICENSE` here,
and `LICENSES/Apache-2.0.txt`; `REUSE.toml` says which files). This README is
provost's own.
