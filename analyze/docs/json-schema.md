# provost-analyze JSON output schema (v1.0)

`provost-analyze --format json` returns a single JSON object with a stable envelope. This document is the authoritative reference. See also `schemas/provost-analyze-output.json` (JSON Schema draft 2020-12).

## Envelope

```json
{
  "schema_version": "1.0",
  "provost_analyze_version": "3.1",
  "items": [ ... ]
}
```

| Field                   | Type    | Required | Description                                                                        |
|-------------------------|---------|----------|------------------------------------------------------------------------------------|
| `schema_version`        | string  | yes      | The schema version this document targets. Currently `"1.0"`.                       |
| `provost_analyze_version` | string  | yes      | The tool version that produced the output (e.g. `"3.1"`).                          |
| `items`                 | array   | yes      | One object per analysis item; order matches plain output.                          |

## Item object

```json
{
  "id": 7,
  "tag": "ADVANCED",
  "kind": "correlation",
  "title": "Strongest correlations",
  "body": "Volume vs Height  r=0.94\n..."
}
```

| Field   | Type    | Required | Description                                                                        |
|---------|---------|----------|------------------------------------------------------------------------------------|
| `id`    | integer | yes      | 1-based index into the item list. Stable within one run; not stable across runs.   |
| `tag`   | string  | yes      | One of `"GOOD"`, `"ADVANCED"`, `"DIAGNOSTIC"`, `"NOISY"`.                          |
| `kind`  | string  | yes      | Machine-friendly category (see "Known kinds" below). May be extended additively.   |
| `title` | string  | yes      | Short human-friendly label, e.g. `"Dataset overview"`.                              |
| `body`  | string  | yes      | Free-text body. May be empty. May contain embedded newlines (`\n`).                |

## Known kinds

The `kind` field is machine-readable but its value set is **open**: new kinds may appear in any minor version. Consumers should treat unknown kinds as generic analysis items.

Current kinds (non-exhaustive): `overview`, `col_types`, `missing`, `missing_rank`, `summary_stats`, `histogram`, `sparkline`, `anomaly`, `shape`, `top_values`, `group_summary`, `corr_matrix`, `corr_pairs`, `regression`, `quality`, `suggested_drops`, `zero_variance`, `numeric_exclusion`, `bimodality`, `benford`, `monotonicity`, `trend`, `oscillation`, `cramers_v`, `threshold_check`, `comparison`, `summary_verdict`, `generic`.

## Evolution policy

- **Additive**: new optional fields on the envelope or item may appear at any time. Consumers must ignore unknown fields.
- **New kinds**: allowed at any time. Consumers must not hard-fail on unknown kinds.
- **Removals / retypes**: bump `schema_version` to `"2.0"`. Consumers should pin to a major version.

## Example

```bash
provost-analyze --format json --all samples/trees.csv | jq .
```

## Validating

```bash
provost-analyze --format json samples/trees.csv | jq 'has("schema_version") and has("items")'
# → true
```

A sample JSON Schema is in [schemas/provost-analyze-output.json](../schemas/provost-analyze-output.json). `tests/test_json_schema.sh` validates multiple sample datasets against the required fields.
