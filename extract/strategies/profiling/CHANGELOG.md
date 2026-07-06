# Changelog -- EnvoyExtract/strategies/profiling

## 2026-03-31 (2 new profiling strategies)
- Added `perf-stat.sh` -- extracts hardware counter values from `perf stat` output (task-clock, context-switches, cpu-cycles, instructions, branches, cache loads/misses, timing)
- Added `valgrind-summary.sh` -- extracts memory leak/heap summary from Valgrind memcheck output (heap in-use, allocs/frees, definitely/indirectly/possibly lost, error summary)
- Files: `perf-stat.sh`, `valgrind-summary.sh`
- Samples: `samples/perf-stat/sample1.txt`, `samples/valgrind-summary/sample1.txt`

## 2026-03-20 (Initial: 11 profiling strategies)
- Created `profiling/` strategy category with 11 strategies:
  - `vtune.sh` — Intel VTune summary
  - `uprof.sh` — AMD uProf
  - `tau.sh` — TAU pprof format
  - `hpctoolkit.sh` — HPCToolkit hpcrun/hpcprof
  - `scorep.sh` — Score-P / Scalasca
  - `likwid.sh` — LIKWID likwid-perfctr
  - `nvprof.sh` — nvprof / Nsight Systems GPU
  - `papi.sh` — PAPI hardware counters
  - `gprof.sh` — GNU gprof flat profile
  - `perf-report.sh` — perf report text output
  - `ltrace-summary.sh` — ltrace summary
