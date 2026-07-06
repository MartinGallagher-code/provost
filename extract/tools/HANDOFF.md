# Handoff -- EnvoyExtract/tools

## Purpose

Developer tools for creating and verifying EnvoyExtract strategies. These are not part of the runtime extraction pipeline; they assist strategy authors during development.

## Tools

### new_strategy.sh -- Strategy Scaffolding

Auto-generates a strategy stub from a sample file with proper headers and function stubs.

**Usage:**
```
new_strategy.sh --name NAME --category CATEGORY --sample FILE [OPTIONS]
```

**What it creates:**
- `strategies/<category>/<name>.sh` -- strategy file with `strategy_detect()` and `strategy_extract()` stubs, proper metadata headers, and detect hints from the sample file
- `samples/<name>/sample1.txt` -- copy of the provided sample file

**Options:** `--description`, `--priority`, `--technique`, `--version`, `--force`

### review_strategy.sh -- Strategy Review (Human Spot-Check)

Interactive workflow for verifying a strategy's extraction accuracy against its sample file.

**Usage:**
```
review_strategy.sh STRATEGY_NAME [OPTIONS]
```

**Workflow:**
1. Finds the strategy file and its sample
2. Runs extraction with `envoy-extract -s NAME -r SAMPLE`
3. For each extracted field, prompts accept/reject/skip
4. Outputs an accuracy report (percentage of accepted vs rejected)

**Options:** `--sample FILE` (override), `--auto` (non-interactive), `--format csv|text`

## Next Steps

- Add batch review mode (review multiple strategies in sequence)
- Add golden output comparison (diff against expected output files)
- Integrate with `envoy-extract validate` for comprehensive strategy health checks
