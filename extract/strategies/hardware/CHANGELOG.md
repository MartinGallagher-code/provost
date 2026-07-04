# Changelog -- Hardware Strategies

## 2026-03-20
- Initial creation: added 6 hardware extraction strategies
  - `lspci.sh` — PCI device info from lspci verbose output
  - `lscpu.sh` — CPU topology from lscpu output
  - `numactl.sh` — NUMA topology from numactl --hardware
  - `ibstat.sh` — InfiniBand adapter info from ibstat/ibstatus
  - `dmidecode.sh` — BIOS/system/processor/memory from dmidecode
  - `hwloc.sh` — Hardware topology from lstopo text output
