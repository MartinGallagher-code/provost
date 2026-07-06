# Handoff — EnvoyExtract/samples/qperf

## Status: Complete

Sample qperf output for the `qperf` extraction strategy.

## Files

- `basic.txt` -- qperf output with tcp_bw, tcp_lat, udp_bw, udp_lat sections; each section contains indented key = value lines with units (GB/sec, us, K/sec, % cpus)

## Notes

- qperf measures RDMA and IP performance (bandwidth and latency)
- Output format: section headers (`tcp_bw:`) followed by indented `key = value unit` lines
- Strategy extracts fields in `section.field` format with unit values joined by underscores
