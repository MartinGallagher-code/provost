# Handoff — EnvoyExtract/samples/lmbench

## Status: Complete

Sample lmbench benchmark output for testing the lmbench extraction strategy.

## Files

- `basic.txt` -- lmbench 3.0 summary with all 6 sections: Basic system parameters, Processor/Processes, Basic integer operations, Context switching, Local Communication latencies, Memory latencies

## Notes

- Output matches the format produced by `lmbench-run` or the lmbench summary tool
- Single host (server1) with Linux 5.4.0-8 on x86_64
- Covers all extracted field categories: system (host/os/mhz), processor (null_call/null_io/fork/exec/sh), integer (bit/add/mul/div/mod), context (2p/0K, 2p/16K, 2p/64K), communication (pipe/af_unix/udp/tcp/tcp_conn), memory (l1/l2/main/rand)
