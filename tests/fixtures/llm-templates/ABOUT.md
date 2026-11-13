# Two stored templates for smoke part `llm`

`tests/smoke.sh` (part `llm`, PV-010's checks) offers these two format-2
templates as a template directory and runs them on their round-4 inputs:

| File | Read on | Checks |
|---|---|---|
| `132-teamspeak-serverquery-clientlist.json` | `tests/benchmark/round4/inputs/132-teamspeak-serverquery-clientlist.txt` | a one-line block of six records is not a fragment |
| `020-golangci-lint-linters.json` | `tests/benchmark/round4/inputs/020-golangci-lint-linters.txt` | a stored template betters a yaml parse of its tool |

They are round 4's format-2 rewrites, byte for byte, from
`tests/benchmark/round4/llm-templates-f2/`. PV-042 (2.22.1) took the rest of the
benchmark rounds' LLM-written templates out of the tree; they are kept at commit
`d9c32f04`, and `tests/benchmark/README.md` says how to restore them.
