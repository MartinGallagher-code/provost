# Changelog -- HPC Strategies

## 2026-11-10 (PV-030: HPC benchmark outputs)
- Added `hpl.sh` -- one row per HPL test (tv, matrix_n, nb, p, q, time_s, gflops, residual, check; start/end time where printed); HPL 2.x and HPC Challenge's HPL section
- Added `stream.sh` -- one row per STREAM kernel from the full printout (function, best_rate_mb_s, avg/min/max_time_s, array_size, threads, validation)
- Added `ior.sh` -- one row per IOR Results row (test, access, bw_mib_s, iops, latency_s, block_kib, xfer_kib, open_s, wr_rd_s, close_s, total_s, iter); IOR 3.x and 4.x
- Added `mdtest.sh` -- one row per mdtest SUMMARY operation (summary, operation, max, min, mean, std_dev, unit, iterations); mdtest 3.x (` :` after the name) and 4.x
- Added `lst-stat.sh` -- one row per lnet_selftest `lst stat` sample, group, metric and direction (avg, min, max, unit)
- Each is bespoke because no generic parser keeps its rows even when forced (see the strategy headers); OSU, ReFrame perflogs, JUnit XML, perfquery and ibstat go through generic parsers or a hint row instead
- Samples: `samples/{hpl,stream,ior,mdtest,lst-stat}/`

## 2026-03-31 (2 new Kubernetes resource monitoring strategies)
- Added `kubectl-top-nodes.sh` -- extracts node resource usage from `kubectl top nodes` (name, cpu_cores, cpu_pct, mem_bytes, mem_pct)
- Added `kubectl-top-pods.sh` -- extracts pod resource usage from `kubectl top pods` (namespace, name, cpu, memory); supports both namespaced and non-namespaced output
- Files: `kubectl-top-nodes.sh`, `kubectl-top-pods.sh`
- Samples: `samples/kubectl-top-nodes/sample1.txt`, `samples/kubectl-top-pods/sample1.txt`

## 2026-03-20 (Initial HPC strategies)
- Added `mpi-profile.sh` — extracts MPI profiling data from mpiP summaries and Intel MPI statistics (comm_size, total_time, mpi_time, mpi_percent, callsite function breakdown)
- Added `mpi-ranklog.sh` — parses multi-rank interleaved MPI output with rank prefixes (`[0]`, `[rank N]`, `[i,j]`, `Rank N:`), extracts num_ranks, per-rank line/error counts
- Added `mpi-display-map.sh` — parses Open MPI `--display-map` output, extracts num_nodes, per-node process binding (rank, slot, binding)
- Added `darshan.sh` — parses `darshan-parser` text output, extracts POSIX/MPI-IO/STDIO counters (bytes read/written, opens, reads, writes), totals, and metadata
- Files: `mpi-profile.sh`, `mpi-ranklog.sh`, `mpi-display-map.sh`, `darshan.sh`
