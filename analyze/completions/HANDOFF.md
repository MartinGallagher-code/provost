# EnvoyAnalyze/completions/ HANDOFF

## Purpose
Bash completion scripts for `envoy-analyze` and `envoy-browse` (per ENV-062). Source these from `/etc/bash_completion.d/` (system-wide) or from a user's shell rc.

## Contents
- `envoy-analyze.bash` — completion for flags, subcommands, and directory arguments
- `envoy-browse.bash` — completion for the interactive browser launcher

## Install
Completions are installed automatically when you run `pip install provost-data` and are placed in the bash completion directory. To test interactively:

```
source provost/completions/provost.bash
```

## Recent Changes

- 2026-06-14: `envoy-browse.bash` completes live watch flags (`--watch`, `--interval`, `--change-token`, `--settle-ms`, `--no-preserve-view`).

## Status
Shipped as part of ENV-062 (2026-04-17). Keep in sync with new flags added by ENV-027, ENV-030, ENV-109, and the ongoing v3.1 additions (`--compare`, `--threshold`, `--mode`, `--summary`, `--timeseries`).
