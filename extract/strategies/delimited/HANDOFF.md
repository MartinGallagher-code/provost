# Handoff — EnvoyExtract/strategies/delimited

## Status: Complete — every strategy in this directory is generic by location

Delimiter-based and record-structured text format strategies. Generic mode is directory-based: everything in `strategies/delimited/` (and `strategies/structured/`) runs under `envoy-extract --generic`; nothing else does.

## Strategies (8)

aligned-columns, blank-line-records, colons, equals, fixed-width, indented-hierarchy, repeated-blocks, vertical-line

## Generic Mode

Every strategy in this category runs under `envoy-extract --generic` by virtue of its location. They implement fundamental text parsing patterns that apply broadly across unknown formats — a strategy that keys on one tool's output does not belong here.

## Next Steps

All planned strategies implemented. Phase 2 refactoring: consider updating `blank-line-records.sh` and `repeated-blocks.sh` to use `_tech_*` functions from `lib/_techniques.sh`. See `strategies/HANDOFF.md` for full strategy table.
