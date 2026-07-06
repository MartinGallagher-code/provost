# Changelog -- EnvoyExtract/tools

## 2026-03-06 (Initial creation)
- Created `new_strategy.sh` -- strategy scaffolding tool that auto-generates strategy stubs from sample files with proper headers (## Name:, ## Description:, ## Version:, ## Priority:, ## Technique:, ## Sample:), function stubs (strategy_detect, strategy_extract), and corresponding sample directories
- Created `review_strategy.sh` -- human spot-check workflow tool that runs a strategy against its sample, shows detected fields/values, prompts user to accept/reject/skip each field, and outputs an accuracy report
- Created `HANDOFF.md` and `CHANGELOG.md` for the tools directory
- Files: `new_strategy.sh`, `review_strategy.sh`, `HANDOFF.md`, `CHANGELOG.md`
