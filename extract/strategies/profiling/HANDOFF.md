# Handoff -- EnvoyExtract/strategies/profiling

## Status: Complete (13 strategies)

Performance profiling and tracing tool extraction strategies.

## Strategies

| File | Format | Description |
|------|--------|-------------|
| `vtune.sh` | Intel VTune | Hotspot and threading analysis summaries |
| `uprof.sh` | AMD uProf | CPU profiling reports |
| `tau.sh` | TAU profiling | pprof format output |
| `hpctoolkit.sh` | HPCToolkit | hpcrun/hpcprof summaries |
| `scorep.sh` | Score-P / Scalasca | Performance report summaries |
| `likwid.sh` | LIKWID | `likwid-perfctr` hardware counter output |
| `nvprof.sh` | nvprof / Nsight | GPU profiling summaries |
| `papi.sh` | PAPI | Hardware performance counter output |
| `gprof.sh` | GNU gprof | Flat profile and call graph |
| `perf-report.sh` | perf report | Symbol overhead analysis |
| `ltrace-summary.sh` | ltrace summary | Library call tracing statistics |
| `perf-stat.sh` | perf stat | Hardware counter values and timing |
| `valgrind-summary.sh` | Valgrind memcheck | Memory leak and heap summaries |
