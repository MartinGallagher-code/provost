# Handoff — EnvoyExtract/strategies/delimited

## Status: Complete (8 strategies, all tagged Technique: yes)

Delimiter-based and record-structured text format strategies. All 8 are tagged with `## Technique: yes` and are included in `--generic` mode as fundamental extraction techniques.

## Strategies (8)

aligned-columns, blank-line-records, colons, equals, fixed-width, indented-hierarchy, repeated-blocks, vertical-line

## Generic Mode

All 8 strategies in this category are tagged `## Technique: yes` and run under `envoy-extract --generic`. They implement fundamental text parsing patterns that apply broadly across unknown formats.

## Next Steps

All planned strategies implemented. Phase 2 refactoring: consider updating `blank-line-records.sh` and `repeated-blocks.sh` to use `_tech_*` functions from `lib/_techniques.sh`. See `strategies/HANDOFF.md` for full strategy table.
