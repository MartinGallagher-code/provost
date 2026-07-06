# EnvoyAnalyze/schemas/ HANDOFF

## Purpose
Machine-readable JSON Schema definitions describing the stable `--json` output contract for EnvoyAnalyze commands (ENV-064).

## Contents
- `envoy-analyze-output.json` — JSON Schema (draft 2020-12) for every `--json` payload emitted by `envoy-analyze`. The human-readable companion lives at `../docs/json-schema.md`.

## Usage
Consumers can validate piped output against this schema, e.g.:

```
envoy-analyze --json ... | jq . | ajv validate -s schemas/envoy-analyze-output.json
```

## Stability
This schema is part of the v1.0 stability contract (tracked by ENV-097). Breaking changes require a major bump in the suite version per the versioning policy (ENV-096).
