# Handoff — EnvoyExtract/samples/ycsb

## Status
Complete — 1 sample file.

## Files
- `basic.txt` — YCSB benchmark output with OVERALL, READ, UPDATE, CLEANUP, and GC sections

## Notes
- Includes all standard YCSB sections: OVERALL (runtime, throughput), READ/UPDATE (operations, latency percentiles), CLEANUP, GC stats
- `Return=OK` lines are included to verify the strategy correctly skips them
