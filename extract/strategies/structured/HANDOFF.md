# Handoff — EnvoyExtract/strategies/structured

## Status: Complete — every strategy in this directory is generic by location

Structured data format strategies. Parses well-defined data interchange formats. Generic mode is directory-based: everything in `strategies/structured/` (and `strategies/delimited/`) runs under `envoy-extract --generic`.

## Strategies (12)

cobertura (XML), csv, grafana-alerts, grafana-dashboard, har, json, jsonl, markdown-frontmatter, prometheus-query, toml, tsv, xml-attributes, xml-elements, yaml

## Generic Mode

All strategies here run under `envoy-extract --generic` by virtue of their location; a strategy that keys on one tool's output does not belong in this directory.

## Next Steps

All planned strategies implemented. See `strategies/HANDOFF.md` for full strategy table.
