# Running provost from a test framework

provost files whatever a command prints, so any harness that runs a command
can file its results. These recipes do it for the harnesses people ask about,
and each one carries the run's context onto every row it files: the test, the
system, the scheduler's job id, its exit status.

| Recipe | When to use it | Files |
|---|---|---|
| [A generic wrapper](wrapper.md) | any harness that runs a command (a shell loop, make, a scheduler script) | `provost-wrap`, `run-suite.sh` |
| [ReFrame](reframe.md) | ReFrame checks: each test's output as it finishes, and the perflogs after a run | `provost_reframe.py`, `stream_check.py` |
| [pytest](pytest.md) | pytest suites: each test's printed output, or the JUnit XML report | `provost_pytest.py` |
| [GitLab CI](gitlab-ci.md) | a CI job that keeps its store as an artifact | `gitlab-ci.yml` |

Every file is in [`docs/integrations/examples/`](https://github.com/MartinGallagher-code/provost/tree/main/docs/integrations/examples)
and is shown whole on its page, to copy as it is.

## How the context becomes columns

Each recipe opens the output it files with a `#%` prologue, one `key=value`
a line, and files it with `--context-columns`:

```
#% test=StreamCheck
#% system=cluster
#% sched.job=4412
#% rc=0
Function,Rate
Copy,2000
```

Every row the capture files then carries `test`, `system`, `sched.job` and
`rc` as columns, after `#` and `capture`. Where a key is one of the
[run manifest](../usage.md#run-manifest)'s (`test`, `sched.job`, `run.id`,
`req`, `build.commit`, `sut`), the recipes use that name, so `provost
check-manifest` can say which runs still lack one.

## None of it can fail a test

A harness's verdict is the test's, never provost's. Every recipe passes the
test's own exit status through, and if provost is missing or cannot file
the output, it warns and carries on.

## Tested on every pull request

`tests/integrations.sh` runs every recipe here in CI against a stand-in
(a one-line benchmark, a throwaway store) and checks that the rows land with
their context columns. It also checks that each file shown on these pages is
the file in `examples/`, so the pages cannot drift from what was tested.
ReFrame is pinned to the version tested (`reframe-hpc==4.7.4`); it is a CI
dependency only, never provost's.
