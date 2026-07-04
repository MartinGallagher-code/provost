# glean — Changelog

## 2026-07-04 — Phase-1 prototype
- New `glean/` tree (proposal 0001): single-binary `glean` implementing the
  product's one path — `cmd | glean` auto-detects format via the real extract
  engine (`--emit-meta`, all 198 strategies), melts to one row per record, and
  files it into a per-type dataset. Verbs: default inject, `ls`, `show`,
  `triage`, `doctor`, `help`.
- Minimal flat-TSV store under `$GLEAN_WORKSPACE` (default `./.glean`); differing
  headers split to numbered variants (git store + schema reconciliation deferred
  to Phase 3). Engine resolved via sibling `EnvoyExtract/` fallback until Phase 2
  copies it under `glean/lib/extract/`.
- Files: `glean/glean`, `glean/HANDOFF.md`, `glean/CHANGELOG.md`,
  `glean/tests/smoke.sh`.
