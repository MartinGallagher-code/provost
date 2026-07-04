# Changelog -- Filesystem Strategies

## 2026-07-02
- Added `ls-l.sh` (priority 21): parses `ls -l` / `ls -la` long listings into permissions/links/owner/group/size/date/name (handles the ACL `+`/`@`/`.` marker, skips the `total N` line). Fixes the previous mis-parse where the `tar-listing` strategy (built for tar `-v`, which has no link-count/group columns) shifted every field. Paired with a tightened `tar-listing` detector (see `../misc/tar-listing.sh` / EnvoyExtract CHANGELOG).

## 2026-03-20
- Initial creation of filesystem strategy category with 4 strategies:
  - `lustre-lfs.sh` — Lustre lfs df / getstripe / quota extraction
  - `gpfs.sh` — GPFS/Spectrum Scale mmlsfs / mmdf extraction
  - `beegfs.sh` — BeeGFS beegfs-ctl storage target extraction
  - `nfsstat.sh` — nfsstat RPC and per-operation stats extraction
- All strategies: priority 15, confidence 85, version 1.0
