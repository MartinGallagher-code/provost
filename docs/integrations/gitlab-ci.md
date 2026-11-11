# GitLab CI

A job that runs a benchmark through [`provost-wrap`](wrapper.md) and keeps
the store as an artifact. Commit `provost-wrap` to your repository as
`ci/provost-wrap` (executable), and put your benchmark's command in place of
`./run-benchmark.sh`:

<!-- file: examples/gitlab-ci.yml -->
```yaml
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# A GitLab CI job that runs a benchmark through provost-wrap and keeps the
# provost store as a job artifact. Commit provost-wrap as ci/provost-wrap
# (executable), and put the benchmark's command in place of
# ./run-benchmark.sh.
benchmark:
  stage: test
  image: python:3.12
  variables:
    PROVOST_HOME: "$CI_PROJECT_DIR/provost-store"
  cache:
    # Carry the store from one pipeline to the next, best effort: a missed
    # cache starts a new store, and every job's artifact still holds its own.
    key: provost-store
    paths:
      - provost-store/
  before_script:
    - pip install provost
  script:
    - >-
      ci/provost-wrap --name benchmark
      run.id="$CI_PIPELINE_ID" sched.job="$CI_JOB_ID"
      build.commit="$CI_COMMIT_SHA" sut="$CI_RUNNER_DESCRIPTION"
      -- ./run-benchmark.sh
    - provost show benchmark
  artifacts:
    when: always
    paths:
      - provost-store/
```

- Every row the job files carries the pipeline (`run.id`), the job
  (`sched.job`), the commit (`build.commit`) and the runner (`sut`), named
  as the [run manifest](../usage.md#run-manifest) names them.
- The job fails when the benchmark fails (the wrapper keeps its status), and
  `artifacts: when: always` keeps the store either way.
- The cache carries the store between pipelines when GitLab finds it; when it
  does not, a fresh store starts, and each job's artifact still holds what
  that job filed. For a store that must never lose a run, push it to a git
  remote of its own instead (`git -C provost-store push`).

The same shape works in any CI system: set `PROVOST_HOME` inside the
workspace, call the wrapper, keep the directory.
