# Handoff — EnvoyExtract/samples

## Status: Complete (~281 files)

Sample input files organized by strategy for testing and documentation. All 126 strategies have sample data (1-3 files each), plus edge-case samples for dedup verification and robustness testing.

## Structure

Each strategy has a subdirectory with a `basic.*` file plus additional realistic samples:

### 7zip/
- `basic.txt` -- 7-Zip benchmark with two dictionary sizes, average, and total ratings

### aligned-columns/
- `basic.txt` -- ps-like columnar output
- `df.txt` -- `df -h` output with Filesystem/Size/Used/Avail/Use%/Mounted columns
- `mount.txt` -- mount output with Filesystem/Type/MountPoint/Options columns

### apache-access/
- `basic.txt` -- Apache/nginx combined access log (3 lines)
- `combined.txt` -- Apache combined log with IPs, methods, URIs, status codes, user agents
- `ipv6.txt` -- Access log with various IP addresses and HTTP/2

### apache-error/
- `basic.txt` -- Apache/nginx error log (3 lines, error/warn/notice)
- `segfault.txt` -- Error log with segfault, proxy failure, SSL errors
- `php.txt` -- PHP fatal errors, warnings, parse errors

### aws-cli-table/
- `basic.txt` -- AWS CLI DescribeInstances table with Instance/Type/State/Zone columns

### blank-line-records/
- `basic.txt` -- blank-line-separated server records (Name/IP/Status)
- `lspci.txt` -- PCI device records with Slot/Class/Vendor/Device/Rev fields
- `interfaces.txt` -- Network interface config blocks (Name/Type/State/Address)

### cobertura/
- `basic.xml` -- Cobertura XML coverage report with 2 packages, line-rate/branch-rate/lines-covered attributes

### colons/
- `basic.txt` -- simple key: value pairs
- `system-info.txt` -- lscpu-style system info (Architecture, CPU, Model, Cache)
- `network.txt` -- Network config with Interface/HW addr/inet addr/MTU

### compiler-diagnostics/
- `basic.txt` -- GCC/Clang error/warning/note output with summary
- `rust.txt` -- Rust compiler errors (mismatched types, borrow checker)
- `msvc.txt` -- C++ compiler errors (no matching function, undeclared identifier)

### coverage/
- `basic.txt` -- pytest-cov/coverage.py table format with TOTAL
- `lcov.txt` -- lcov summary with lines/functions/branches percentages
- `go-cover.txt` -- Go test coverage table format

### csv/
- `basic.csv` -- 3-column CSV with header
- `bom.csv` -- CSV with UTF-8 BOM (EF BB BF) prefix
- `multiline.csv` -- CSV with multi-line quoted fields
- `employees.csv` -- Employee data (name, department, title, salary, start_date)

### cuda-bandwidthtest/
- `basic.txt` -- CUDA bandwidth test with Tesla V100-SXM2-32GB, H2D/D2H/D2D bandwidth, PINNED memory

### curl-headers/
- `basic.txt` -- curl -v verbose output with request/response headers
- `redirect.txt` -- curl output showing 301 redirect followed by 200
- `post.txt` -- curl POST request with Authorization and JSON content type

### dns-record/
- `basic.txt` -- dig DNS query output with A/AAAA/NS records
- `mx.txt` -- dig MX record output with 3 mail exchangers
- `nslookup.txt` -- dig output with CNAME and multiple A records

### docker-ps/
- `basic.txt` -- docker ps output with 2 containers (nginx, postgres)
- `wide.txt` -- docker ps with 5 containers including ports and names
- `all.txt` -- docker ps -a showing running and exited containers

### elasticsearch/
- `basic.json` -- Elasticsearch search response with 2 hits, _shards, took, _source fields

### env-vars/
- `basic.txt` -- environment variable assignments (KEY=value)
- `export.txt` -- `export` command output with export prefix
- `paths.txt` -- PATH-like environment variables (GOPATH, JAVA_HOME, etc.)

### equals/
- `basic.txt` -- environment variable style key=value
- `config.txt` -- Application config with key=value pairs
- `properties.txt` -- Java-style .properties file (spring.datasource.url=...)

### fixed-width/
- `basic.txt` -- fixed-width column table with dash separator
- `report.txt` -- Employee report with Name/Department/Location/Salary
- `accounting.txt` -- Accounting ledger with Account/Description/Debit/Credit/Balance

### git-log/
- `basic.txt` -- git log output (2 commits, full format)
- `oneline.txt` -- git log --oneline format (7 commits)
- `merge.txt` -- git log showing merge commit with parent hashes

### google-benchmark/
- `basic.txt` -- Google Benchmark console output (5 benchmarks)
- `throughput.txt` -- Serialization/deserialization benchmarks (json/protobuf/msgpack)
- `multithread.txt` -- Multi-threaded queue and hashmap benchmarks

### grafana-dashboard/
- `basic.json` -- Grafana dashboard JSON with 2 panels, schemaVersion, templating

### gpu-burn/
- `basic.txt` -- Two-GPU burn test with summary (Tesla V100-SXM2-32GB, 60 seconds)

### har/
- `basic.har` -- HTTP Archive with 2 entries (GET + POST), creator, log version

### http-headers/
- `basic.txt` -- HTTP 200 response with headers
- `cookies.txt` -- HTTP response with Set-Cookie and security headers
- `cache.txt` -- HTTP 304 response with Cache-Control and ETag headers

### indented-hierarchy/
- `basic.txt` -- indentation-based system information
- `lsusb.txt` -- USB device tree with Bus/Port/Device hierarchy
- `device-tree.txt` -- Hardware device tree (platform/soc/memory/storage)

### ini/
- `basic.ini` -- INI config with [database] and [server] sections
- `php.ini` -- PHP configuration with [PHP]/[Date]/[Session] sections
- `git-config.txt` -- Git config INI with [user]/[core]/[pull]/[alias]

### ioping/
- `basic.txt` -- Block device latency statistics

### iostat/
- `basic.txt` -- macOS iostat output with 2 disks
- `linux.txt` -- Linux iostat with Device: header (tps, kB_read/s, kB_wrtn/s)
- `extended.txt` -- iostat -x extended output (rrqm/s, wrqm/s, await, %util)

### iozone/
- `basic.txt` -- Iozone filesystem benchmark with single file size, all operations

### journald/
- `basic.txt` -- systemd journal output (3 lines)
- `multiunit.txt` -- Multiple systemd units (nginx, postgresql, app.service restart)
- `boot.txt` -- Boot sequence journal entries (journald, udevd, networkd, sshd)

### json/
- `basic.json` -- flat JSON object
- `nested.json` -- Deeply nested JSON (server.tls.enabled, database.primary.host)
- `array.json` -- JSON array of objects (id, name, role, active)

### junit-xml/
- `basic.txt` -- JUnit XML test report with 3 testcases (1 failure)

### jsonl/
- `basic.jsonl` -- Simple JSONL with name/age/city fields
- `logs.jsonl` -- Log-style JSONL (timestamp, level, service, message, status)
- `events.jsonl` -- Event tracking JSONL (event, user_id, page, duration_ms)

### kubectl/
- `basic.txt` -- kubectl get pods output with 3 pods
- `wide.txt` -- kubectl get pods -o wide with IP and NODE columns
- `services.txt` -- kubectl get services with TYPE/CLUSTER-IP/EXTERNAL-IP/PORT(S)

### lsblk/
- `basic.txt` -- lsblk with single disk and three partitions
- `multi-disk.txt` -- lsblk with multiple SATA and NVMe disks

### lmbench/
- `basic.txt` -- lmbench 3.0 summary with system parameters, processor, integer, context switch, communication, and memory latency sections

### make-stats/
- `basic.txt` -- ninja-style build output (5 steps)
- `cmake.txt` -- CMake build output (12 steps: compile + link)
- `errors.txt` -- Build output with FAILED step and linker error

### markdown-frontmatter/
- `basic.md` -- Markdown with YAML frontmatter (title, date, author, tags, draft)
- `docs-page.md` -- Documentation page with layout, sidebar_position, description, version, category

### markdown-table/
- `basic.md` -- Markdown pipe-delimited table
- `alignment.md` -- Table with left/center/right column alignments
- `wide.md` -- Wide table with 8 columns (Name through Links)

### nmap/
- `basic.txt` -- nmap scan with 3 open ports
- `network-scan.txt` -- Multi-host scan (two IPs with different port states)
- `service-detect.txt` -- nmap -sV service version detection

### npm-list/
- `basic.txt` -- npm list tree output
- `outdated.txt` -- npm list with package versions
- `global.txt` -- npm list -g global packages

### openssl/
- `basic.txt` -- openssl x509 certificate
- `chain.txt` -- Certificate chain (leaf + intermediate CA)
- `expired.txt` -- Expired certificate with past Not After date

### openssl-speed/
- `basic.txt` -- openssl speed benchmark with three algorithms and throughput table

### perf-bench/
- `basic.txt` -- Three sub-benchmarks: sched/pipe, mem/memcpy, futex/hash

### perf-stat/
- `basic.txt` -- perf stat with 4 counters
- `detailed.txt` -- perf stat -d with L1-dcache-loads and cache metrics
- `comparison.txt` -- perf stat for benchmark run

### pip-list/
- `basic.txt` -- pip list tabular output
- `freeze.txt` -- pip freeze output (package==version)
- `outdated.txt` -- pip list --outdated with Version/Latest columns

### proc-stat/
- `basic.txt` -- /proc/meminfo-style key:value
- `cpuinfo.txt` -- /proc/cpuinfo fields (processor, vendor_id, model_name, etc.)
- `meminfo.txt` -- /proc/meminfo fields (MemTotal, MemFree, Cached, Swap, etc.)

### qperf/
- `basic.txt` -- qperf network bandwidth and latency benchmark (tcp_bw, tcp_lat, udp_bw, udp_lat)

### redis-benchmark/
- `basic.txt` -- Three commands (PING_INLINE, SET, GET) with throughput and latency summaries

### repeated-blocks/
- `basic.txt` -- network interface blocks (eth0/eth1/lo)
- `ipaddr.txt` -- ip addr show output with Interface/State/MTU/inet/inet6
- `ifconfig.txt` -- ifconfig-style output with Interface/Type/Status/IP/MAC

### sanitizer/
- `basic.txt` -- AddressSanitizer heap-buffer-overflow
- `tsan.txt` -- ThreadSanitizer data race report
- `ubsan.txt` -- UndefinedBehaviorSanitizer integer overflow and out-of-bounds

### smartctl/
- `basic.txt` -- Western Digital Blue HDD with PASSED health, power-on hours, temperature
- `ssd.txt` -- Samsung SSD 870 EVO with wear leveling and total LBAs written
- `failing.txt` -- HGST HDD with FAILED health, high read error rate, reallocated sectors

### sockperf/
- `basic.txt` -- sockperf TCP ping-pong latency test with total run stats, avg-latency, percentile coverage (p50-p99.999)

### ss/
- `basic.txt` -- ss -tuln output with TCP/UDP/IPv6 listeners
- `extended.txt` -- Multiple services including MySQL, Redis
- `ipv6.txt` -- IPv6-only listeners

### spec-cpu/
- `basic.txt` -- SPEC CPU 2017 Integer Rate Result with 10 benchmarks (500.perlbench_r through 557.xz_r), base/peak rates, and SPECrate2017_int_base/peak summary scores

### sql-result/
- `basic.txt` -- MySQL CLI table output with 3 rows (id, username, score columns)

### syslog/
- `basic.txt` -- BSD/RFC 3164 syslog (sshd, cron, kernel)
- `auth.txt` -- Authentication syslog (sshd accept/fail, sudo)
- `daemon.txt` -- Daemon syslog (cron, ntpd, dhclient, postfix)

### test-summary/
- `basic.txt` -- pytest output (42 passed, 2 failed, 1 skipped)
- `jest.txt` -- Jest output with Test Suites and Tests summary
- `gotest.txt` -- Go test output with PASS/FAIL/SKIP results
- `gtest.txt` -- Google Test output with test suites and PASSED/FAILED summary

### time-output/
- `basic.txt` -- /usr/bin/time output (real/user/sys)
- `verbose.txt` -- /usr/bin/time -v verbose (Elapsed, Max RSS, page faults, etc.)
- `multiple.txt` -- Multiple time command results

### traceroute/
- `basic.txt` -- Short 4-hop traceroute with one timeout
- `long.txt` -- Longer 7-hop traceroute with multiple timeouts

### toml/
- `basic.toml` -- TOML with sections, dotted sections, array tables
- `cargo.toml` -- Rust Cargo.toml (package, dependencies, profile)
- `pyproject.toml` -- Python pyproject.toml (project, tool, build-system)

### top-snapshot/
- `basic.txt` -- macOS top snapshot with 3 processes
- `linux-top.txt` -- Linux top with Processes/Load Avg/CPU/PhysMem + 5 processes
- `summary.txt` -- Top summary-only output (no process list)

### tsv/
- `basic.tsv` -- tab-separated values with header
- `benchmark.tsv` -- Benchmark data (test_name, iterations, mean_ns, etc.)
- `data.tsv` -- City population data (city, country, population, area, density)

### valgrind/
- `basic.txt` -- valgrind memcheck with heap/leak/error summaries
- `leaks.txt` -- Detailed leak report with definitely/possibly/reachable blocks
- `callgrind.txt` -- Invalid read error with heap summary and alloc counts

### vertical-line/
- `basic.txt` -- table with --- separator
- `mysql.txt` -- Database status table with --- separator
- `psql.txt` -- PostgreSQL schema table with === separator

### vmstat/
- `basic.txt` -- vmstat with 2 data rows
- `extended.txt` -- vmstat with 4 data rows (varying load)
- `timestamps.txt` -- vmstat output with consistent timestamps

### warc-headers/
- `basic.txt` -- WARC record with metadata
- `response.txt` -- WARC response record with payload digest and IP
- `multi-record.txt` -- Multiple WARC records (request + response)

### xml-attributes/
- `basic.xml` -- XML with tag attributes
- `svg.xml` -- SVG file with rect/circle/text/line/path attributes
- `pom.xml` -- Maven POM with dependency and plugin attributes

### xml-elements/
- `basic.xml` -- HTML with tag/text content
- `rss.xml` -- RSS feed with channel/item elements
- `config.xml` -- Application config with server/database/cache elements

### yaml/
- `basic.yaml` -- YAML with nested keys and arrays
- `block-scalars.yaml` -- YAML with | and > block scalar indicators
- `kubernetes.yaml` -- Kubernetes pod spec with metadata/spec/containers
- `docker-compose.yaml` -- Docker Compose with services/volumes/environment

### ycsb/
- `basic.txt` -- YCSB benchmark output with OVERALL, READ, UPDATE, CLEANUP, and GC sections

### ab/
- `basic.txt` -- ApacheBench HTTP benchmark output

### bonnie/
- `basic.txt` -- Bonnie++ filesystem benchmark (text format)
- `csv.txt` -- Bonnie++ CSV format output

### coremark/
- `basic.txt` -- CoreMark CPU benchmark output

### dd/
- `basic.txt` -- dd disk benchmark (Linux format)
- `macos.txt` -- dd disk benchmark (macOS format)

### dgemm/
- `basic.txt` -- DGEMM matrix multiply benchmark (single size)
- `multi-size.txt` -- DGEMM with multiple matrix sizes

### dmesg/
- `basic.txt` -- Standard boot sequence with timestamps, ACPI, PCI, EXT4, and systemd messages
- `boot-errors.txt` -- Boot with ACPI errors, SATA link down, Bluetooth firmware failure
- `network.txt` -- Network driver initialization and interface rename messages

### free/
- `basic.txt` -- free -h output with memory and swap
- `megabytes.txt` -- free -m output with numeric values
- `no-swap.txt` -- System with swap disabled (all zeros)

### fio/
- `basic.txt` -- fio storage benchmark (single job)
- `mixed-rw.txt` -- fio mixed read/write workload

### geekbench/
- `basic.txt` -- Geekbench CPU benchmark with per-test scores

### hcl/
- `basic.tf` -- Terraform config with provider, variable, resource (nested tags), output blocks

### hdparm/
- `basic.txt` -- hdparm disk timing (single device)
- `multi-device.txt` -- hdparm timing for multiple devices

### hpl/
- `basic.txt` -- HPL/LINPACK benchmark with two problem sizes

### iperf3/
- `basic.txt` -- iperf3 TCP bandwidth test
- `udp.txt` -- iperf3 UDP bandwidth test with jitter/loss

### mbw/
- `basic.txt` -- Memory Bandwidth Benchmark with MEMCPY/DUMB/MCBLOCK

### mlc/
- `basic.txt` -- Intel Memory Latency Checker with NUMA latency matrix and bandwidth

### mtr/
- `basic.txt` -- Five-hop route with one unresponsive hop (???)
- `long-route.txt` -- Eight-hop cross-country route (NYC to LAX via CDN edge)
- `packet-loss.txt` -- Route with significant packet loss on multiple hops

### mysqlslap/
- `basic.txt` -- Two benchmark runs with avg/min/max seconds, clients, queries per client

### netperf/
- `basic.txt` -- Netperf TCP_STREAM throughput test
- `rr.txt` -- Netperf TCP_RR request/response test

### pgbench/
- `basic.txt` -- pgbench PostgreSQL benchmark output

### strace-summary/
- `basic.txt` -- Five syscalls (read, write, open, close, fstat) with errors on open
- `complex.txt` -- Eight syscalls with futex, mmap, mprotect and higher call counts
- `minimal.txt` -- Two syscalls (read, write) with zero errors

### systemd-unit/
- `basic.txt` -- Systemd unit file with [Unit], [Service], and [Install] sections

### stream/
- `basic.txt` -- STREAM memory bandwidth benchmark (Copy/Scale/Add/Triad)

### stress-ng/
- `basic.txt` -- stress-ng single stressor
- `multi.txt` -- stress-ng multiple stressors

### sysbench/
- `basic.txt` -- sysbench CPU mode
- `memory.txt` -- sysbench memory mode
- `oltp.txt` -- sysbench OLTP database mode

### unixbench/
- `basic.txt` -- BYTE UNIX Benchmarks with system index score

### wrk/
- `basic.txt` -- wrk HTTP benchmark with latency distribution
- `errors.txt` -- wrk benchmark with socket errors

### cargo-test/
- `basic.txt` -- cargo test with 5 tests (4 passed, 1 failed)
- `all-pass.txt` -- cargo test with 3 tests all passing
- `filtered.txt` -- cargo test with 8 tests (6 passed, 1 failed, 1 ignored, 2 filtered out)

### docker-stats/
- `basic.txt` -- docker stats with 3 containers (web-app, redis-cache, postgres-db)
- `single.txt` -- docker stats with single container (nginx-proxy)
- `heavy.txt` -- docker stats with high-usage containers (java-backend, elasticsearch, monitoring-agent)

### docker-compose/
- `basic.txt` -- Docker Compose with 3 services (web/api/db), images, ports, environment, volumes, depends_on, restart
### properties/
- `basic.properties` -- Java properties with db, server, logging settings (# comments)
- `database.properties` -- Java properties with pool and JDBC settings (! comments)

### protobuf-text/
- `basic.txt` -- Protocol Buffers text format with nested config block and repeated endpoints blocks

### proc-meminfo/
- `basic.txt` -- /proc/meminfo with 12 standard fields (MemTotal through Writeback)
- `server.txt` -- /proc/meminfo with 27 fields including anon/file active/inactive, slab, hugepages
- `minimal.txt` -- /proc/meminfo with 7 core fields (MemTotal, MemFree, MemAvailable, Buffers, Cached, SwapTotal, SwapFree)

### terraform-plan/
- `basic.txt` -- terraform plan with 1 create, 1 update, 1 destroy
- `create-only.txt` -- terraform plan with 2 creates, 0 changes, 0 destroys
- `large.txt` -- terraform plan with module-scoped resources (3 create, 1 update, 1 destroy)

### Edge-Case Samples

- `edge-cases/empty.txt` -- empty file (0 bytes)
- `edge-cases/binary.bin` -- binary content (non-text)
- `edge-cases/long-lines.txt` -- file with very long lines (15KB)
- `edge-cases/headers-only.txt` -- columnar header with no data rows
- `edge-cases/dedup-overlap.txt` -- content matching both colons and equals strategies

### ansible-output/
- `basic.txt` -- Ansible playbook with 3 hosts, 4 tasks, and PLAY RECAP with ok/changed/unreachable/failed/skipped counts

### crontab/
- `basic.txt` -- Crontab with env vars (SHELL, PATH, MAILTO), 4 scheduled jobs, and 1 @reboot shortcut

### iptables/
- `basic.txt` -- iptables listing with INPUT (4 rules), FORWARD (empty), OUTPUT (1 rule) chains with policies

### jwt/
- `basic.txt` -- JWT token with RS256 header and payload containing sub, name, admin, iat, exp, iss, roles

### pem-chain/
- `basic.pem` -- PEM certificate chain with 2 certificates (Baltimore CyberTrust Root, Let's Encrypt Authority X3)

### tar-listing/
- `basic.txt` -- tar listing with 7 entries (2 directories, 5 files) with permissions, owner, size, date, path

### cargo-tree/
- `basic.txt` -- cargo tree output with root (myapp v0.1.0) and 15 dependencies including serde, tokio, clap

### github-actions/
- `basic.txt` -- GitHub Actions log with 3 groups (npm ci, npm test, npm run build), 1 error with file/line, 1 warning, 1 notice

### go-mod-graph/
- `basic.txt` -- go mod graph output with 7 edges between github.com/user/myapp and its dependencies (gin, pq, zap)

### k8s-events/
- `basic.txt` -- kubectl get events with 7 events (Scheduled, Pulling, Pulled, Created, Started, Unhealthy, Killing)

### openmetrics/
- `basic.txt` -- OpenMetrics format with # TYPE, # UNIT, # HELP, counter/histogram metrics, and # EOF marker

### redis-cli/
- `basic.txt` -- Redis CLI INFO server output with # Server section header, 11 key:value pairs (redis_version, tcp_port, uptime, memory)

### sqlite-output/
- `basic.txt` -- SQLite pipe-delimited output with id|name|email|age header and 3 data rows
- `column.txt` -- SQLite column mode output with dash separators and 3 data rows

## Next Steps

All planned samples have been created.

### vtune/
- `basic.txt` -- Intel VTune Profiler summary with hotspots table

### uprof/
- `basic.txt` -- AMD uProf performance report with IPC, cache, branch metrics

### tau/
- `basic.txt` -- TAU pprof tabular output with calls, exclusive/inclusive time

### hpctoolkit/
- `basic.txt` -- HPCToolkit hpcprof summary with function inclusive/exclusive percentages

### scorep/
- `basic.txt` -- Score-P report with MPI region visits, time, percentages

### likwid/
- `basic.txt` -- LIKWID likwid-perfctr output with event counters and metric tables

### nvprof/
- `basic.txt` -- nvprof GPU profiling with kernel and API call sections

### papi/
- `basic.txt` -- PAPI hardware performance counter report

### gprof/
- `basic.txt` -- GNU gprof flat profile with function timing data

### perf-report/
- `basic.txt` -- perf report symbol overhead table with shared objects

### ltrace-summary/
- `basic.txt` -- ltrace summary of library call statistics

### amber/
- `basic.txt` -- AMBER molecular dynamics output (pmemd mdout) with NSTEP thermo blocks, energy decomposition, density/volume, wall time

### namd/
- `basic.txt` -- NAMD molecular dynamics output with ETITLE/ENERGY: columns, TIMING, WallClock

### cp2k/
- `basic.txt` -- CP2K DFT output with SCF convergence, ENERGY| total, QUICKSTEP module, DBCSR, functional

### qe/
- `basic.txt` -- Quantum ESPRESSO pw.x output with total energy (Ry), forces, pressure, k-points, ecutwfc/ecutrho, convergence
