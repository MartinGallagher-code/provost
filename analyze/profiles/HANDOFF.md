# Handoff — EnvoyAnalyze/profiles

## Overview

Storage directory for saved envoy-analyze selection profiles. Profiles are created with `--save NAME` and loaded with `--profile NAME`.

## Format

Each profile is a plain text `.profile` file containing a comma-delimited list of analysis item numbers (e.g., `1,2,3,5,9`).

## Notes

- Directory is created by envoy-analyze on first use
- Profile location can be overridden with `--profile-dir DIR`
