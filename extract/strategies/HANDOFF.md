# Handoff -- EnvoyExtract/strategies

## Status: Active (178 strategies, v4.0)

Individual strategy files for the Multi-Format Extractor. Each file defines `strategy_detect()` and `strategy_extract()` functions, plus metadata headers (`## Name:`, `## Description:`, `## Version:`, `## Priority:`). Strategies are organized into 17 categorized subdirectories.

## Directory Structure

| Subdirectory | Count | Description |
|-------------|-------|-------------|
| `benchmark/` | 42 | Performance/benchmarking tool output (incl. HPC: OSU, HPCG, NPB, IMB, IOR, b_eff) |
| `build/` | 16 | Build/test/CI tool output |
| `config/` | 11 | Configuration file formats |
| `container/` | 6 | Docker/Kubernetes tool output |
| `delimited/` | 7 | Delimiter-based text formats |
| `filesystem/` | 4 | HPC parallel filesystem output (Lustre, GPFS, BeeGFS, NFS) |
| `gpu/` | 3 | GPU/accelerator monitoring (nvidia-smi, rocm-smi, CUDA deviceQuery) |
| `hardware/` | 9 | Cluster/hardware inventory (lscpu, lspci, numactl, ibstat, dmidecode, hwloc, ethtool, lshw, xpu-smi) |
| `hpc/` | 10 | HPC schedulers & MPI (Slurm, PBS, LSF, SGE, Flux, HTCondor, MPI profiling, Darshan) |
| `logging/` | 6 | Log file formats |
| `misc/` | 5 | Miscellaneous formats |
| `network/` | 7 | Network/HTTP tool output |
| `profiling/` | 11 | Profiling tool output (VTune, gprof, perf report, TAU, LIKWID, etc.) |
| `scientific/` | 13 | Scientific data formats (HDF5, NetCDF, PDB, FITS, VTK, GROMACS, LAMMPS, VASP, Gaussian, AMBER, NAMD, CP2K, QE) |
| `security/` | 6 | Security scanning/crypto tool output |
| `structured/` | 9 | Structured data formats (JSON, YAML, etc.) |
| `system/` | 13 | System monitoring/info tool output |

## Strategy Catalog (178)

| File | Format | Sample |
|------|--------|--------|
| `7zip.sh` | 7-Zip compression benchmark output | `samples/7zip/` |
| `ab.sh` | ApacheBench HTTP benchmark output | `samples/ab/` |
| `aligned-columns.sh` | Whitespace-aligned columns (ps, df) | `samples/aligned-columns/` |
| `ansible-output.sh` | Ansible playbook recap output (play names, host ok/changed/failed counts) | `samples/ansible-output/` |
| `apache-access.sh` | Apache/nginx combined access log | `samples/apache-access/` |
| `apache-error.sh` | Apache/nginx error log | `samples/apache-error/` |
| `aws-cli-table.sh` | AWS CLI --output table format (pipe-delimited with border lines) | `samples/aws-cli-table/` |
| `block-records.sh` | Blank-line-separated records with key:value/key=value (merges blank-line-records + repeated-blocks) | `samples/blank-line-records/` |
| `bonnie.sh` | Bonnie++ filesystem benchmark output | `samples/bonnie/` |
| `cargo-tree.sh` | Rust cargo tree dependency output (root/dep name+version) | `samples/cargo-tree/` |
| `cobertura.sh` | Cobertura XML coverage reports | `samples/cobertura/` |
| `colons.sh` | Key: value pairs | `samples/colons/` |
| `crontab.sh` | Crontab entry parsing (schedule fields, commands, env vars) | `samples/crontab/` |
| `compiler-diagnostics.sh` | GCC/Clang error/warning/note output | `samples/compiler-diagnostics/` |
| `coremark.sh` | CoreMark CPU benchmark output | `samples/coremark/` |
| `coverage.sh` | Code coverage summaries (pytest-cov/lcov) | `samples/coverage/` |
| `csv.sh` | Comma-separated values | `samples/csv/` |
| `cuda-bandwidthtest.sh` | NVIDIA CUDA bandwidth test (H2D/D2H/D2D bandwidth) | `samples/cuda-bandwidthtest/` |
| `curl-headers.sh` | curl -v verbose output (request/response headers) | `samples/curl-headers/` |
| `dd.sh` | dd disk copy/benchmark output | `samples/dd/` |
| `dgemm.sh` | DGEMM matrix multiply benchmark output | `samples/dgemm/` |
| `dmesg.sh` | Kernel ring buffer (dmesg) timestamps and messages | `samples/dmesg/` |
| `dns-record.sh` | dig DNS query output | `samples/dns-record/` |
| `docker-ps.sh` | Docker ps container listing | `samples/docker-ps/` |
| `docker-compose.sh` | Docker Compose YAML service definitions | `samples/docker-compose/` |
| `docker-inspect.sh` | Docker inspect JSON container details (state, config, network) | `samples/docker-inspect/` |
| `docker-stats.sh` | Docker stats container resource usage (CPU, memory, pids) | `samples/docker-stats/` |
| `dockerfile.sh` | Dockerfile instruction parsing (FROM, ENV, ARG, CMD, multi-stage) | `samples/dockerfile/` |
| `elasticsearch.sh` | Elasticsearch search response JSON (hits, _shards, took) | `samples/elasticsearch/` |
| `env-vars.sh` | Environment variable assignments (KEY=value) | `samples/env-vars/` |
| `equals.sh` | Key=value pairs | `samples/equals/` |
| `fio.sh` | Flexible I/O Tester benchmark output | `samples/fio/` |
| `fixed-width.sh` | Fixed-width column format with header/separator | `samples/fixed-width/` |
| `free.sh` | Memory and swap usage from free -h / free -m output | `samples/free/` |
| `geekbench.sh` | Geekbench CPU benchmark output | `samples/geekbench/` |
| `github-actions.sh` | GitHub Actions log output (errors, warnings, notices, groups, run commands) | `samples/github-actions/` |
| `git-log.sh` | Git log output (full and oneline) | `samples/git-log/` |
| `google-benchmark.sh` | Google Benchmark console output | `samples/google-benchmark/` |
| `gradle-output.sh` | Gradle build output (build result, tasks, summary counts) | `samples/gradle-output/` |
| `grafana-dashboard.sh` | Grafana dashboard JSON exports (panels, schemaVersion, templating) | `samples/grafana-dashboard/` |
| `go-mod-graph.sh` | Go module dependency graph (edge from/to pairs, total_edges) | `samples/go-mod-graph/` |
| `exposition-format.sh` | Prometheus/OpenMetrics exposition format (# TYPE, # HELP, # UNIT, labels; merges prometheus + openmetrics) | `samples/prometheus/` |
| `gpu-burn.sh` | gpu_burn GPU stress test output | `samples/gpu-burn/` |
| `hcl.sh` | HCL (Terraform/Packer) configuration files | `samples/hcl/` |
| `hdparm.sh` | hdparm disk timing benchmark output | `samples/hdparm/` |
| `hpl.sh` | HPL/LINPACK benchmark output | `samples/hpl/` |
| `har.sh` | HTTP Archive (HAR) files (log, entries, request/response) | `samples/har/` |
| `http-headers.sh` | HTTP response headers | `samples/http-headers/` |
| `indented-hierarchy.sh` | Indentation-based hierarchical data with dot notation | `samples/indented-hierarchy/` |
| `iptables.sh` | iptables rule listing (chain names/policies, rule targets/protocols) | `samples/iptables/` |
| `ini.sh` | INI/config files with [section] support | `samples/ini/` |
| `ioping.sh` | ioping I/O latency benchmark output | `samples/ioping/` |
| `iozone.sh` | Iozone filesystem benchmark output | `samples/iozone/` |
| `iostat.sh` | iostat disk I/O statistics | `samples/iostat/` |
| `iperf3.sh` | iperf3 network bandwidth benchmark output | `samples/iperf3/` |
| `journald.sh` | systemd journal output | `samples/journald/` |
| `json.sh` | JSON (jq or awk fallback) | `samples/json/` |
| `jwt.sh` | JWT token payload extraction (header/payload base64url decoding) | `samples/jwt/` |
| `junit-xml.sh` | JUnit/xUnit XML test reports (suite attrs, testcase details, pass/fail status) | `samples/junit-xml/` |
| `jsonl.sh` | JSON Lines (one object per line) | `samples/jsonl/` |
| `k8s-events.sh` | Kubernetes kubectl events output (type, reason, object, message) | `samples/k8s-events/` |
| `kubectl.sh` | kubectl get resource listing | `samples/kubectl/` |
| `lsblk.sh` | Block device listing from lsblk output | `samples/lsblk/` |
| `lmbench.sh` | lmbench micro-benchmark suite summary output | `samples/lmbench/` |
| `make-stats.sh` | Build system output (make/ninja/cmake) | `samples/make-stats/` |
| `markdown-frontmatter.sh` | YAML frontmatter in Markdown files (Jekyll, Hugo, Gatsby, Astro) | `samples/markdown-frontmatter/` |
| `network-hops.sh` | Traceroute/mtr hop-by-hop network path statistics (merges traceroute + mtr) | `samples/traceroute/` |
| `maven-output.sh` | Maven build output (build result, time, memory, test results) | `samples/maven-output/` |
| `mbw.sh` | Memory Bandwidth Benchmark output | `samples/mbw/` |
| `mlc.sh` | Intel Memory Latency Checker output | `samples/mlc/` |
| `mysqlslap.sh` | mysqlslap MySQL benchmark output (avg/min/max, clients, queries) | `samples/mysqlslap/` |
| `netperf.sh` | Netperf network performance benchmark output | `samples/netperf/` |
| `nginx-conf.sh` | Nginx configuration file directives (server, location blocks) | `samples/nginx-conf/` |
| `nmap.sh` | nmap scan output | `samples/nmap/` |
| `npm-list.sh` | npm list tree output (package@version) | `samples/npm-list/` |
| `pipe-table.sh` | Pipe-delimited tables: SQL (+-+ borders, row${n}.field) or Markdown (|---| separator, flat field; merges sql-result + markdown-table) | `samples/sql-result/` |
| `openssl.sh` | openssl x509 -text certificate output | `samples/openssl/` |
| `openssl-speed.sh` | openssl speed algorithm throughput benchmark | `samples/openssl-speed/` |
| `perf-bench.sh` | perf bench kernel benchmark results | `samples/perf-bench/` |
| `perf-stat.sh` | perf stat performance counters | `samples/perf-stat/` |
| `pem-chain.sh` | PEM certificate chain files (cert type, size, openssl metadata) | `samples/pem-chain/` |
| `pgbench.sh` | pgbench PostgreSQL benchmark output | `samples/pgbench/` |
| `pip-list.sh` | pip list and pip freeze output | `samples/pip-list/` |
| `qperf.sh` | qperf network bandwidth and latency benchmark output | `samples/qperf/` |
| `redis-benchmark.sh` | redis-benchmark throughput/latency extraction | `samples/redis-benchmark/` |
| `redis-cli.sh` | Redis CLI output (INFO key:value with section headers, array results) | `samples/redis-cli/` |
| `properties.sh` | Java .properties files | `samples/properties/` |
| `protobuf-text.sh` | Protocol Buffers text format | `samples/protobuf-text/` |
| `proc-meminfo.sh` | /proc/meminfo memory statistics (MemTotal, MemFree, Swap, etc.) | `samples/proc-meminfo/` |
| `proc-stat.sh` | /proc-style key:value with numeric values and units | `samples/proc-stat/` |
| `sanitizer.sh` | AddressSanitizer/ThreadSanitizer/UBSan output | `samples/sanitizer/` |
| `sockperf.sh` | sockperf network latency benchmark output | `samples/sockperf/` |
| `smartctl.sh` | smartctl -a disk health and SMART attributes | `samples/smartctl/` |
| `spec-cpu.sh` | SPEC CPU 2017 benchmark result output | `samples/spec-cpu/` |
| `test-results.sh` | Go/Rust test output (go test + cargo test; test names, results, coverage, summary; merges go-test + cargo-test) | `samples/go-test/` |
| `sqlite-output.sh` | SQLite CLI output (pipe-delimited and column mode) | `samples/sqlite-output/` |
| `ss.sh` | Socket connections from ss -tuln output | `samples/ss/` |
| `strace-summary.sh` | strace -c syscall summary statistics | `samples/strace-summary/` |
| `systemd-unit.sh` | Systemd unit files ([Unit], [Service], [Install] sections) | `samples/systemd-unit/` |
| `tar-listing.sh` | tar archive listing output (permissions, owner, size, date, path) | `samples/tar-listing/` |
| `stream.sh` | STREAM memory bandwidth benchmark output | `samples/stream/` |
| `stress-ng.sh` | stress-ng system stress benchmark output | `samples/stress-ng/` |
| `sysbench.sh` | sysbench multi-mode benchmark output | `samples/sysbench/` |
| `syslog.sh` | BSD/RFC 3164 syslog format | `samples/syslog/` |
| `terraform-plan.sh` | Terraform plan resource actions and summary (add/change/destroy) | `samples/terraform-plan/` |
| `test-summary.sh` | pytest/Jest/Go test/Google Test summaries | `samples/test-summary/` |
| `time-output.sh` | /usr/bin/time real/user/sys output | `samples/time-output/` |
| `toml.sh` | TOML with section, dotted section, and array table support | `samples/toml/` |
| `top-snapshot.sh` | macOS top single-frame output | `samples/top-snapshot/` |
| `trivy.sh` | Trivy vulnerability scan output (severity counts, CVE details) | `samples/trivy/` |
| `tsv.sh` | Tab-separated values with header row | `samples/tsv/` |
| `unixbench.sh` | BYTE UNIX Benchmarks output | `samples/unixbench/` |
| `valgrind.sh` | Valgrind memcheck output | `samples/valgrind/` |
| `vertical-line.sh` | Tables with --- separator | `samples/vertical-line/` |
| `vmstat.sh` | vmstat output with abbreviated-to-full name mapping | `samples/vmstat/` |
| `warc-headers.sh` | WARC metadata fields | `samples/warc-headers/` |
| `wrk.sh` | wrk HTTP benchmark output | `samples/wrk/` |
| `xml.sh` | XML/HTML element text content and attribute key/value pairs (merges xml-elements + xml-attributes) | `samples/xml-elements/` |
| `yaml.sh` | YAML with dot-notation flattening and array indexing | `samples/yaml/` |
| `ycsb.sh` | Yahoo! Cloud Serving Benchmark (YCSB) throughput and latency output | `samples/ycsb/` |

### New HPC Strategies (v4.0)

| File | Format | Category |
|------|--------|----------|
| `slurm.sh` | Slurm scheduler (sacct, squeue, sinfo, scontrol) | `hpc/` |
| `pbs.sh` | PBS/Torque (qstat, pbsnodes) | `hpc/` |
| `lsf.sh` | IBM LSF (bjobs, bhosts, bqueues) | `hpc/` |
| `sge.sh` | SGE/UGE (qstat, qhost) | `hpc/` |
| `mpi-profile.sh` | MPI profiling (mpiP, Intel MPI stats) | `hpc/` |
| `mpi-ranklog.sh` | Multi-rank interleaved MPI output | `hpc/` |
| `mpi-display-map.sh` | Open MPI --display-map output | `hpc/` |
| `darshan.sh` | Darshan I/O characterization (darshan-parser) | `hpc/` |
| `osu-micro.sh` | OSU Micro-Benchmarks (latency, bandwidth, collectives) | `benchmark/` |
| `hpcg.sh` | HPCG benchmark output | `benchmark/` |
| `npb.sh` | NAS Parallel Benchmarks (CG, FT, IS, MG) | `benchmark/` |
| `imb.sh` | Intel MPI Benchmarks (PingPong, Allreduce) | `benchmark/` |
| `ior.sh` | IOR/mdtest parallel I/O benchmark | `benchmark/` |
| `beff.sh` | b_eff effective MPI bandwidth | `benchmark/` |
| `nvidia-smi.sh` | nvidia-smi GPU status (table and -q format) | `gpu/` |
| `rocm-smi.sh` | AMD rocm-smi GPU status | `gpu/` |
| `cuda-devicequery.sh` | CUDA deviceQuery GPU capabilities | `gpu/` |
| `vtune.sh` | Intel VTune hotspot/threading analysis | `profiling/` |
| `uprof.sh` | AMD uProf profiling reports | `profiling/` |
| `tau.sh` | TAU profiling (pprof format) | `profiling/` |
| `hpctoolkit.sh` | HPCToolkit hpcrun/hpcprof summaries | `profiling/` |
| `scorep.sh` | Score-P / Scalasca performance reports | `profiling/` |
| `likwid.sh` | LIKWID hardware counter output | `profiling/` |
| `nvprof.sh` | nvprof / Nsight Systems GPU profiling | `profiling/` |
| `papi.sh` | PAPI hardware performance counters | `profiling/` |
| `gprof.sh` | GNU gprof flat profile and call graph | `profiling/` |
| `perf-report.sh` | perf report symbol overhead | `profiling/` |
| `ltrace-summary.sh` | ltrace library call tracing | `profiling/` |
| `h5dump.sh` | HDF5 h5dump hierarchical data | `scientific/` |
| `ncdump.sh` | NetCDF ncdump climate/ocean data | `scientific/` |
| `pdb.sh` | Protein Data Bank structures | `scientific/` |
| `fits-header.sh` | FITS astronomy headers | `scientific/` |
| `vtk.sh` | VTK legacy visualization data | `scientific/` |
| `gromacs.sh` | GROMACS molecular dynamics | `scientific/` |
| `lammps.sh` | LAMMPS molecular dynamics | `scientific/` |
| `vasp.sh` | VASP ab initio materials science | `scientific/` |
| `gaussian.sh` | Gaussian quantum chemistry | `scientific/` |
| `lustre-lfs.sh` | Lustre lfs df/getstripe/quota | `filesystem/` |
| `gpfs.sh` | GPFS/Spectrum Scale mmlsfs/mmdf | `filesystem/` |
| `beegfs.sh` | BeeGFS beegfs-ctl | `filesystem/` |
| `nfsstat.sh` | NFS performance counters | `filesystem/` |
| `lspci.sh` | lspci PCIe device topology | `hardware/` |
| `lscpu.sh` | lscpu CPU topology | `hardware/` |
| `numactl.sh` | numactl NUMA topology | `hardware/` |
| `ibstat.sh` | InfiniBand HCA status | `hardware/` |
| `dmidecode.sh` | BIOS/hardware inventory | `hardware/` |
| `hwloc.sh` | hwloc lstopo hardware topology | `hardware/` |

## Adding a Strategy

1. Create `<name>.sh` with `## Name:`, `## Description:`, `## Version:` headers
2. Define `strategy_detect($text)` -- return 0 if applicable
3. Define `strategy_extract($text)` -- output `fieldname value` lines
4. `clean_text` from `envoy-extract` is available after sourcing

## Next Steps

- Add sample files for the 49 new HPC/scientific/profiling strategies
- Consider additional formats: Flux scheduler, HTCondor, Intel Advisor, ARM MAP, CephFS, WekaFS
