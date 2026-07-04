# Changelog -- HPC Strategies

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
