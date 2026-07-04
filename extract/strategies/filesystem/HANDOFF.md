# Handoff -- EnvoyExtract/strategies/filesystem

## Status: Complete (4 strategies)

HPC parallel filesystem monitoring extraction strategies.

## Strategies

| File | Format | Description |
|------|--------|-------------|
| `lustre-lfs.sh` | Lustre lfs output | `lfs df`, `lfs getstripe`, `lfs quota` |
| `gpfs.sh` | GPFS/Spectrum Scale | `mmlsfs`, `mmdf` output |
| `beegfs.sh` | BeeGFS | `beegfs-ctl` output |
| `nfsstat.sh` | nfsstat | NFS performance counters |
