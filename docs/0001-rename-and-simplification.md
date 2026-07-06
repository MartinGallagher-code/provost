# Proposal 0001 — Rename Envoy to **Glean** and rebuild as a minimal single-binary tool

- **Status:** Draft (for discussion)
- **Date:** 2026-07-04
- **Branch:** `claude/extraction-feature-naming-2d16xi`
- **Author:** scoped with Claude
- **Supersedes:** the three-binary `envoy-*` product shape

---

## 1. Summary

Retire the **Envoy** suite (three binaries, ~55 subcommands, satellite tools, and a
3,500-file scenario corpus) and replace it with a single rebranded tool, **Glean**,
built fresh in a new `glean/` tree. Glean keeps only the one workflow the product is
actually about:

> **Pipe command output in → auto-detect its format → present it as a clean, typed dataset → optionally analyze it.**

This is today's `envoy-capture inject` path, promoted to be *the* product.

Confirmed decisions driving this proposal:

1. **Rename the binaries *and* rebrand** — `envoy-*` → `glean`. Not a doc-only reskin.
2. **Keep all 198 extract strategies** — the "throw anything at it" auto-detect breadth is the value.
3. **Keep analyze** — statistics stay in-tool.
4. **New tree** — build `glean/` fresh from the one path rather than mutating the `Envoy*` trees in place.

---

## 2. Why

The current repo has accreted far past its core. The scenario we care about —
auto-capture-format + present-dataset — is a single path through three binaries:

| Today | Lines / surface |
|---|---|
| `envoy-capture` | 347 lines, **40 subcommands** |
| `envoy-extract` | 794 lines, 198 strategies, ~40 flags, 6 subcommands |
| `envoy-analyze` | 1,411 lines, ~9 analysis modes |
| satellites | `envoy-browse`, `envoy-filedb`, `envoy-tnt` |
| `scenarios/` | 3,575 files (3,269 "Generic") — most of the repo by file count |

Most of `envoy-capture`'s 40 verbs (`goto`/`next`/`prev`/`home`, `watch`, `process`,
`scripts`, `results`, `merge`, `search`, `tag`/`untag`, `register`, `archive`,
`push`/`pull`, `gc`, `verify`, `destroy`, …) are navigation, lifecycle, and
git-plumbing surface that the core scenario never touches. Cutting to the one path
removes the maintenance surface without removing the product.

**Why a fresh tree, not a mutation:** the cut commands share library code with the
kept path, so "delete 50 verbs" means tracing shared internals — slow and error-prone.
Adding ~6 verbs to a clean tree that reuses the extract engine and the tidy-melt
presenter is far cleaner than deleting 50 from the existing one.

---

## 3. The name

**Glean** — to gather what's worth keeping from a field of raw material. It describes
what auto-detection actually does: *purposeful selection* of structure from noisy
command output (strategy dispatch + confidence scoring), as opposed to Sift's passive
"let it fall through a mesh." Short, lowercase, four letters, types fast as a CLI
prefix, no known collision with an existing terminal tool, and it passes the tagline
test with no explanation: **"Glean turns command output into data."**

---

## 4. Target command surface

One binary, `glean`. The pipe *is* the capture; auto-detect *is* the extract; `show`
*is* the present. No `init` — the workspace auto-creates on first use.

```bash
# THE core verb — capture + auto-detect + present into a typed dataset
free -m | glean                 # routed by detected type → dataset 'free'
df -h   | glean
cat metrics.txt | glean --silent

glean ls                        # list datasets: name, type, rows, cleanliness
glean show free                 # present one dataset as a tidy table
glean triage                    # low-confidence / unmatched bucket
glean stats free                # statistics on a dataset (survivor of envoy-analyze)

glean doctor                    # dependency / environment check
glean help
```

That is the entire surface: **default verb + 5 subcommands + doctor/help.**

### 4.1 Command mapping (Envoy → Glean)

| Glean | Replaces | Notes |
|---|---|---|
| `glean` (default, stdin) | `envoy-capture inject` | extract → classify → route → record, in one step |
| `glean ls` | `envoy-capture dataset` / `list` | list datasets with cleanliness score |
| `glean show <name>` | `envoy-capture show` + tidy present | one dataset as a tidy table |
| `glean triage` | `envoy-capture triage` | unmatched / low-confidence rows |
| `glean stats <name>` | `envoy-analyze` (core modes) | stats / summary / correlation / anomaly kept; browse UI dropped |
| `glean doctor` | `envoy-capture doctor` | dependency + wiring check |
| *(none)* | `init` | implicit — auto-create workspace on first `glean` |

### 4.2 Explicitly dropped

`run`, `watch`, `process`/`reprocess`, `scripts`, `results`, `goto`/`next`/`prev`/`home`,
`search`, `log`, `diff`, `merge`, `rename`, `tag`/`tags`/`untag`, `register`/`unregister`,
`dirs`, `archive`/`archives`, `push`/`pull`, `gc`, `verify`, `destroy`, `export`, and the
satellites `envoy-browse` / `envoy-filedb` / `envoy-tnt`.

The `envoy-extract` engine is **kept in full** (all 198 strategies) but is no longer a
user-facing binary — it becomes the internal auto-detect library behind `glean`. Its
power-user flags (`--strategy`, `--min-confidence`, `--rename`, `--chain`, …) may be
exposed as advanced flags on the default verb; default UX stays flagless.

---

## 5. Target repo layout

```
glean/
├── glean                    # single entry point (~400–500 lines)
├── lib/
│   ├── capture/             # git-based store (kept subset of EnvoyCapture/lib)
│   ├── extract/             # the auto-detect engine (all of EnvoyExtract/lib)
│   │   └── strategies/      # all 198 strategies, unchanged
│   ├── present/             # tidy melt / dataset renderer
│   └── analyze/             # kept core of EnvoyAnalyze
├── man/man1/glean.1         # one man page (was 6)
├── completions/glean.{bash,zsh,fish}
├── docs/                    # slimmed to the one workflow
├── tests/                   # tests for the ~6 verbs + strategy suite (carried over)
├── HANDOFF.md
└── CHANGELOG.md
```

Three `Envoy*` top-level dirs collapse to one `glean/` tree. `scenarios/`, `web/`, and
`tickets/` are **archived to a sibling repo** rather than carried forward (open question
6.4 — could instead be deleted).

---

## 5a. Store model (added after the git-core directive)

The user's "git core" directive expanded the store requirements beyond a simple
capture-commit. The model, built in stages:

- **Row → source traceability.** Every dataset row carries a globally-unique,
  **visible** `#N` index (first column). `glean source <#N>` maps it back to the
  exact captured input that produced it (`provenance.tsv` → `captures/<id>/output.txt`).
- **Global store by default.** Captures go to `$GLEAN_HOME` (or `~/.glean`) so a
  user need not be in any particular directory. `GLEAN_WORKSPACE` is an explicit
  override. A shared, group-writable `GLEAN_HOME` supports multiple users; a
  `mkdir` lock + double-checked `git init` serialise concurrent writers.
- **Controlled directories** *(Stage B)*. `glean control <dir>` marks a directory
  as its own capture instance; commands run within it (or a subdir) route there,
  and the commit's context includes the directory's contents. Resolution walks up
  from CWD to find a controlling instance, else falls back to the global store.
- **Export / import** *(Stage C)*. Bundle an instance (datasets + capture commits)
  into a portable file, import it into another repository, and browse it there
  with the same `ls`/`show`/`log`/`source`/`restore`.

Status: **Stages A, B, C all done.** Stage A — global store, per-row provenance,
multi-user lock (verified under 8-way concurrency). Stage B — `control`/`instances`/
`uncontrol`, CWD walk-up resolution, directory-context snapshots. Stage C —
`export`/`import` via `git bundle` (datasets + capture log + per-row provenance
survive the move). Verified end-to-end by `glean/tests/smoke.sh` (27 checks).

## 6. The rename plane

Renaming the binaries touches nearly every file. Inventory of what must move together
so CI stays green:

- **Binary + prefix:** `envoy-capture`/`-extract`/`-analyze` → `glean`; all internal
  `envoy_*` lib source names and sourced paths.
- **Env vars:** `CAPTURE_INJECT_MIN_CONFIDENCE`, `CAPTURE_INJECT_VARIANT_OVERLAP`, and
  siblings → `GLEAN_*`. Provide a one-release compatibility shim that reads the old
  names with a deprecation warning.
- **Man pages:** regenerate via the generator (CI enforces drift-free man pages); one
  `glean.1` replaces six.
- **Completions:** one `glean.*` set replaces the per-tool completions.
- **Packaging / install:** `install.sh`, `packaging/`, `pyproject.toml`, `VERSION`
  wiring, `release.sh`.
- **CI gates that will fail if not updated in-step:**
  - `Handoff Check` — every top-level dir needs `HANDOFF.md`; the new `glean/` dir must ship one in its first commit.
  - New-top-level-dir rule — `glean/` needs `HANDOFF.md` **and** `CHANGELOG.md` in the same commit as its first tracked file.
  - Man-page drift test.
  - The three subproject CHANGELOG enforcement — retired along with the `Envoy*` dirs.
- **Docs / README:** rewrite the three-stage "Capture → Extract → Analyze" framing into
  the single-tool `glean` story; keep the pipeline as an internal concept.

---

## 7. Phased plan

Each phase is independently reviewable; the repo stays shippable between phases.

**Phase 0 — Proposal & sign-off** (this document).

**Phase 1 — New tree skeleton.** ✅ *Done — see `glean/`.* Entry point implements the
default verb (`| glean`) plus `ls`/`show`/`triage`/`doctor`/`help`, wiring the real
extract engine via `--emit-meta`, tidy-melt present, and a minimal flat-TSV store.
`glean/tests/smoke.sh` passes; the new dir ships `HANDOFF.md` + `CHANGELOG.md`.

**Phase 2 — Carry the engine.** ✅ *Done.* Vendored `EnvoyExtract`'s entry point +
`lib/` + all 202 strategies + `tools/` + tests + samples under **`glean/extract/`**, and
the cross-suite shared libs (`envoy_*.sh`) under **`glean/lib/`** (the engine's `../lib`),
via `glean/tools/sync-extract.sh` (re-syncable from an upstream checkout;
`VENDOR.json` records the source SHA). Full vendored suite green: **216/216 test files,
1103 assertions, 0 failed**. `glean` resolves the vendored engine first. Two fixes found
along the way: an upstream test portability bug (hardcoded `EnvoyExtract/` path → resolved
relative to the test dir), and a first-cut layout error (engine at `lib/extract/` left its
`../lib` at `lib/lib` and under-vendored the shared libs + `tools/` — corrected to the
`extract/` + `lib/` layout above).

> **Layout amendment to §5:** the engine lives at top-level `glean/extract/` (not
> `glean/lib/extract/`) so its `../lib` resolves cleanly to `glean/lib/`, matching how the
> engine finds its shared libs upstream. Future components (capture/present/analyze) follow
> the same top-level pattern.

**Phase 3 — The verbs + git core.** *In progress.* `ls`, `show`, `triage`, `doctor`,
`log`, `restore`, and `run` implemented; tidy-melt presenter ported. The **git core is
done**: the workspace is a git repo, every capture is one commit tagged `capture-<id>`,
`glean run` captures a binary's output as a commit and `glean restore` brings it back up
(a deliberate simplification of EnvoyCapture's per-run + `__dataset`/`__results`/`__scripts`
orphan-branch store down to one linear commit-per-capture history).
*Remaining:* `stats` (vendor envoy-analyze under `glean/analyze/`) and schema
reconciliation (union columns instead of the `.v2` variant split).

**Phase 4 — Rename plane.** ✅ *Done.* glean's own surface is entirely `GLEAN_*`;
shipped `glean/README.md`, `glean/completions/glean.bash`, `glean/man/glean.1`, and
`glean/install.sh` (installs in place + drops completion/man, `--uninstall`). Fixed a
symlink-safety bug (glean now resolves its real dir via `GLEAN_ROOT` so it finds its
vendored trees when run through a PATH symlink). The melt/transform was also imported
from source (`glean/transform/melt.sh` via `tools/sync-melt.sh`) rather than hand-copied.

**Phase 5 — Retire Envoy.** *Superseded by the standalone-repo split (2026-07-05):*
`glean` was extracted into its own repository instead of hard-cutting the `Envoy*`
trees in place, so the vendored trees here are already canonical. Removing the
`Envoy*` trees, satellites, and their CI gates is now a task in the upstream Envoy
monorepo, not this repo — out of scope here.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Cut commands share library code with the kept path | Fresh tree copies only what the kept path needs; nothing to untangle |
| Users/scripts depend on `envoy-*` names or env vars | Env-var compat shim for one release; document the rename; keep `envoy-*` as thin deprecated wrappers for one release if desired |
| Strategy suite regresses when relocated | Move tests with sources in Phase 2; gate the phase on a green suite |
| Losing history/value in `scenarios/` | Archive to a sibling repo, don't delete (open question 6.4) |
| Man-page / HANDOFF / CHANGELOG CI gates fail mid-migration | Phase boundaries chosen so each lands its required docs in the same commit |

---

## 9. Non-goals

- No change to the extraction *strategies* themselves or their detection behavior.
- No new analysis capability — analyze is carried, not extended.
- Not removing git-based storage; only the user-facing plumbing verbs around it.
- Not a rewrite in another language — this stays Bash + the existing engine.

---

## 10. Open questions

1. ~~**Deprecated wrappers?**~~ **Resolved: hard cut** — no `envoy-*` forwarding shims.
2. **Advanced extract flags** on the default verb (`--strategy`, `--min-confidence`,
   `--chain`) — expose now, or keep the surface flagless until asked?
3. **Analyze scope** — keep all core modes (stats/summary/correlation/anomaly) or trim
   to `stats`/`summary` only?
4. ~~**`scenarios/` / `web/` / `tickets/`**~~ **Resolved: archive** to a sibling repo (do not delete).
5. **Repo identity** — new `glean` repo, or rebrand this repo in place and prune?

---

## 11. Success criteria

- A single `glean` binary implements the full scenario end-to-end: `cmd | glean`,
  `ls`, `show`, `triage`, `stats`.
- All 198 strategies pass their suite in the new tree.
- One man page, one completion set, green CI (Handoff Check, man-page drift, changelog).
- Entry-point line count materially below the current ~2,550-line three-binary total.
- README tells one story: *Glean turns command output into data.*
