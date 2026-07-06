# Handoff — EnvoyExtract/tests/golden

## Status: Complete (124 golden output files)

Golden (expected) output files for snapshot regression tests in `test_snapshot_regression.sh`. Each file contains the expected field extraction output for a representative strategy/sample pair. If refactoring changes output, these files are updated to track the new canonical output.

## Contents

One `.txt` file per strategy (124 files), named `<strategy-name>.txt`. Each contains the expected plain-text extraction output when running that strategy against its `basic.*` sample file.

## Usage

The snapshot regression test (`test_snapshot_regression.sh`) runs `envoy-extract --strategy <name> samples/<name>/basic.*` and diffs against the corresponding golden file. Failures indicate unexpected output changes.

To update a golden file after an intentional change:
```bash
bash EnvoyExtract/envoy-extract --strategy <name> samples/<name>/basic.* > tests/golden/<name>.txt
```

## Next Steps

Golden files are updated automatically when strategies are intentionally changed. No pending work.
