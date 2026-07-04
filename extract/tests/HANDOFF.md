# Handoff — EnvoyExtract/tests

## Status: Complete (144 test files, all passing)

Test suite for the Multi-Format Extractor v3.0. All planned tests have been implemented, including edge-case, performance, encoding, malformed input, advanced dedup, replay, v3.0-v4.2 feature tests, validation/snapshot/critique-fix/generic-mode tests, error path tests, interface tests (subcommands, piped output, provenance), and per-strategy tests (126 strategies).

## Structure

- `helpers.sh` -- assertion functions (`assert_eq`, `assert_contains`, etc.), `run_mfe` wrapper, `run_test`/`print_summary` framework
- `run_tests.sh` -- test runner that executes all test files
- `test_mfe.sh` -- 22 core engine tests for envoy-extract (CLI flags, error handling, formats, stdin)
- `test_edge_cases.sh` -- 10 edge-case tests (max-input-size file rejected/accepted/stdin, empty file no crash/no spurious stdout, whitespace-only file no crash/no spurious stdout, very long line >64KB, single field extraction/count)
- `test_performance.sh` -- 4 performance tests (10K-line colons input, 1K-key JSON input with 60s timeout, list-strategies benchmark, single-strategy fast path)
- `test_encoding.sh` -- 4 encoding tests (UTF-8 multi-byte, CSV BOM, mixed ASCII/UTF-8, UTF-8 JSON format)
- `test_malformed.sh` -- 10 malformed input tests (truncated JSON, mismatched CSV quotes, partial CSV, YAML tabs, TOML unclosed brackets + partial extraction, XML unclosed tags + partial extraction, INI duplicate sections + partial extraction)
- `test_dedup_advanced.sh` -- 3 advanced dedup tests (multi-strategy overlap, count verification, 120+ fields)
- `test_replay.sh` -- 4 replay tests (non-existent strategy, malformed spec, empty spec, round-trip identity)
- `test_new_features.sh` -- 20 feature tests: 15 v3.0 (priority, confidence, verbose, first-match, max-strategies, rename, delimiter, aggregate, stream, chain, plugin-dir, list priority, JSONL) + 5 v3.1 (near-miss feedback, near-miss confidence detail, plain format without fields, JSON format without fields, early format validation)
- `test_v32_features.sh` -- 21 v3.2 feature tests (--version, --count, --quiet, --names, --sort, field-by-name, validation, error cases, verbose hints, replay)
- `test_cross_strategy.sh` -- 18 cross-strategy false-positive tests (v3.3: yaml/colons, http-headers/colons, ini/equals, journald/syslog, etc.)
- `test_flag_combinations.sh` -- 24 flag interaction tests (v3.3: --sort+--names, --rename+--aggregate, --first-match+--min-confidence, etc.; multi-char --delimiter with |||/::=/ -> ; --output+--format json/csv/yaml)
- `test_chain_dataflow.sh` -- 5 chain data flow verification tests (v3.3: colons|equals, csv|colons, chain+rename/sort/aggregate/count)
- `test_error_paths.sh` -- 18 error path tests (missing input, invalid flags, flag conflicts, non-existent strategies, --no-dedup, --output, --profile, binary detection)
- `test_v34_features.sh` -- 15 v3.4 feature tests (YAML format, XML format, auto-tune confidence fallback/best-match/conflicts, interactive flag/conflicts)
- `test_critique_fixes.sh` -- 11 critique fix tests (cache, escape globals, source guard, chain version, ini detect, renames, aggregate, validation)
- `test_snapshot_regression.sh` -- 18 snapshot regression tests (representative format round-trips as safety net for refactoring)
- `test_validation.sh` -- 7 strategy validation tests (--validate-strategy valid/invalid, --validate-all)
- `test_generic_mode.sh` -- 21 generic mode tests (v4.1: --generic flag, format exclusion, flag conflicts, compatibility, _tech_* unit tests)
- `test_interface.sh` -- 21 interface tests (v3.0: subcommand dispatch, backward compat, piped output JSON default, grouped help, version, field provenance)
- `test_plugin_dir.sh` -- 7 plugin directory tests (basic extraction, list-strategies, high-confidence override, nonexistent dir, empty dir, multiple plugins, explicit strategy)
- `test_strategy_*.sh` -- per-strategy tests (detection, extraction, field selection)

## Current Test Count: 685

- Core engine: 22 tests
- Edge cases: 10 tests
- Performance: 4 tests
- Encoding: 4 tests
- Malformed input: 10 tests
- Advanced dedup: 3 tests
- Replay: 4 tests
- New features (v3.0+v3.1): 20 tests
- v3.2 features: 21 tests
- Cross-strategy false-positives: 18 tests
- Flag combinations: 24 tests
- Plugin directory: 7 tests
- Chain data flow: 5 tests
- Error paths: 18 tests
- v3.4 features: 15 tests
- Critique fixes: 11 tests
- Snapshot regression: 18 tests
- Strategy validation: 7 tests
- Generic mode (v4.1): 21 tests
- Interface (v4.2): 21 tests
- 7zip: 3 tests
- ab: 3 tests
- aligned-columns: 3 tests
- ansible-output: 3 tests
- apache-access: 4 tests
- apache-error: 4 tests
- aws-cli-table: 3 tests
- blank-line-records: 3 tests
- bonnie: 3 tests
- cargo-test: 3 tests
- cargo-tree: 3 tests
- cobertura: 3 tests
- colons: 5 tests
- crontab: 3 tests
- compiler-diagnostics: 3 tests
- coremark: 3 tests
- coverage: 3 tests
- csv: 4 tests
- cuda-bandwidthtest: 3 tests
- curl-headers: 3 tests
- dd: 3 tests
- dgemm: 3 tests
- dmesg: 3 tests
- dns-record: 3 tests
- docker-compose: 3 tests
- docker-inspect: 3 tests
- docker-ps: 3 tests
- docker-stats: 3 tests
- dockerfile: 4 tests
- elasticsearch: 3 tests
- env-vars: 4 tests
- equals: 4 tests
- fio: 4 tests
- fixed-width: 3 tests
- free: 3 tests
- geekbench: 3 tests
- github-actions: 3 tests
- git-log: 4 tests
- go-mod-graph: 3 tests
- go-test: 4 tests
- google-benchmark: 3 tests
- gpu-burn: 3 tests
- gradle-output: 3 tests
- grafana-dashboard: 3 tests
- hcl: 4 tests
- hdparm: 3 tests
- hpl: 3 tests
- har: 3 tests
- http-headers: 4 tests
- indented-hierarchy: 3 tests
- ini: 4 tests
- ioping: 3 tests
- iostat: 3 tests
- iozone: 3 tests
- iptables: 3 tests
- iperf3: 3 tests
- journald: 4 tests
- json: 5 tests
- junit-xml: 3 tests
- jwt: 3 tests
- jsonl: 4 tests
- k8s-events: 3 tests
- kubectl: 3 tests
- lsblk: 3 tests
- lmbench: 3 tests
- make-stats: 3 tests
- markdown-frontmatter: 4 tests
- markdown-table: 4 tests
- maven-output: 3 tests
- mbw: 3 tests
- mlc: 3 tests
- mtr: 3 tests
- mysqlslap: 3 tests
- netperf: 3 tests
- nginx-conf: 4 tests
- nmap: 3 tests
- npm-list: 4 tests
- openmetrics: 3 tests
- openssl: 3 tests
- openssl-speed: 3 tests
- perf-bench: 3 tests
- perf-stat: 3 tests
- pem-chain: 3 tests
- pgbench: 3 tests
- pip-list: 3 tests
- properties: 4 tests
- protobuf-text: 4 tests
- proc-meminfo: 3 tests
- proc-stat: 3 tests
- prometheus: 3 tests
- qperf: 3 tests
- redis-benchmark: 3 tests
- redis-cli: 3 tests
- repeated-blocks: 3 tests
- sanitizer: 3 tests
- smartctl: 3 tests
- sockperf: 3 tests
- spec-cpu: 3 tests
- sql-result: 3 tests
- sqlite-output: 4 tests
- ss: 3 tests
- strace-summary: 3 tests
- systemd-unit: 3 tests
- tar-listing: 3 tests
- stream: 4 tests
- stress-ng: 3 tests
- sysbench: 4 tests
- syslog: 4 tests
- terraform-plan: 3 tests
- test-summary: 3 tests
- time-output: 3 tests
- toml: 4 tests
- top-snapshot: 3 tests
- traceroute: 3 tests
- tsv: 4 tests
- unixbench: 3 tests
- valgrind: 3 tests
- vertical-line: 5 tests
- vmstat: 3 tests
- warc-headers: 4 tests
- wrk: 4 tests
- xml-attributes: 3 tests
- xml-elements: 3 tests
- yaml: 4 tests
- ycsb: 3 tests

## Running Tests

```bash
bash tests/run_tests.sh
```

## Next Steps

All planned tests have been implemented. All 145 test files pass (685 tests total).

Potential additions:
- Expect-based interactive mode tests (`-i/--interactive` has no automated coverage)
- Phase 2 refactoring tests when `blank-line-records.sh` / `repeated-blocks.sh` are updated to use `_tech_*` functions
