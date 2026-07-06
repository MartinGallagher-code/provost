# Handoff -- EnvoyExtract/strategies/hardware

## Status: Complete (6 strategies)

Cluster and hardware inventory extraction strategies for HPC node characterization.

## Strategies

| File | Format | Description |
|------|--------|-------------|
| `lspci.sh` | lspci verbose | PCIe device topology |
| `lscpu.sh` | lscpu | CPU topology and cache hierarchy |
| `numactl.sh` | numactl --hardware | NUMA topology and memory |
| `ibstat.sh` | ibstat/ibstatus | InfiniBand HCA status |
| `dmidecode.sh` | dmidecode | BIOS/hardware inventory |
| `hwloc.sh` | hwloc lstopo | Hardware topology text output |
