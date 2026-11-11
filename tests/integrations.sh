#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# The framework recipes in docs/integrations/ (PV-023), each run as a user
# would run it, against a stand-in benchmark and a throwaway store: the rows
# must land with the context columns the recipe promises. Also checks that
# every file a page shows is the file in docs/integrations/examples/, so the
# pages cannot drift from what is tested here.
#
# ReFrame, pytest and PyYAML are needed for their parts; a part whose tool is
# missing is skipped, unless PROVOST_INTEGRATIONS_REQUIRE=1 (as CI sets it),
# when a missing tool is a failure.
#   bash tests/integrations.sh
set -euo pipefail
unset PROVOST_HOME PROVOST_CONTEXT_COLUMNS PROVOST_MANIFEST_PROFILE PROVOST_MANIFEST_STRICT \
      PROVOST_MULTI PROVOST_MIN_CONFIDENCE PROVOST_PLUGIN_DIR PROVOST_QUIET
export PROVOST_ASYNC=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DOCS="$ROOT/docs/integrations"
EX="$DOCS/examples"
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
# provost-wrap and the Python recipes call "provost": the checkout's, by PATH.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexec bash %q "$@"\n' "$ROOT/provost" > "$TMP/bin/provost"
chmod +x "$TMP/bin/provost"
export PATH="$TMP/bin:$PATH"
unset PROVOST

pass=0; fail=0; skipped=0
check () { # desc, expected-substring, actual
    if grep -qF -- "$2" <<< "$3"; then echo "  ok   $1"; pass=$((pass+1))
    else echo "  FAIL $1"; echo "       want substring: $2"; echo "       got: $3"; fail=$((fail+1)); fi
}
check_not () { # desc, forbidden-substring, actual
    if grep -qF -- "$2" <<< "$3"; then echo "  FAIL $1"; echo "       must NOT contain: $2"; echo "       got: $3"; fail=$((fail+1))
    else echo "  ok   $1"; pass=$((pass+1)); fi
}
# needs DESC CMD... -- 0 if CMD runs; else skip the part (or fail it, in CI)
needs () {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then return 0; fi
    if [[ "${PROVOST_INTEGRATIONS_REQUIRE:-0}" == 1 ]]; then
        echo "  FAIL $desc is not installed (PROVOST_INTEGRATIONS_REQUIRE=1)"; fail=$((fail+1))
    else
        echo "  skip $desc is not installed"; skipped=$((skipped+1))
    fi
    return 1
}
sq () { tr -s ' \t' '  '; }
store () { export PROVOST_WORKSPACE="$TMP/$1/.provost"; }

echo "== the pages show the example files exactly =="
out="$("$PY" - "$DOCS" <<'EOF'
import pathlib, re, sys
docs = pathlib.Path(sys.argv[1])
shown = set()
for page in sorted(docs.glob('*.md')):
    text = page.read_text()
    for m in re.finditer(r'<!-- file: (\S+) -->\n```[a-z]*\n(.*?)```\n', text, re.S):
        name, block = m.group(1), m.group(2)
        shown.add(name)
        f = docs / name
        if not f.is_file():
            print(f'MISSING {page.name}: {name}')
        elif f.read_text() != block:
            print(f'DIFFERS {page.name}: {name}')
    for name in re.findall(r'<!-- file: (\S+) -->', text):
        if name not in shown:
            print(f'NO-BLOCK {page.name}: {name}')
for f in sorted((docs / 'examples').iterdir()):
    if f.is_file() and f'examples/{f.name}' not in shown:
        print(f'UNSHOWN examples/{f.name}')
print(f'{len(shown)} file(s) shown')
EOF
)"
check "every example file is shown on a page" "6 file(s) shown" "$out"
check_not "...exactly as it is in examples/" "DIFFERS" "$out"
check_not "...with no marker that lacks its block" "NO-BLOCK" "$out"
check_not "...and no example left unshown" "UNSHOWN" "$out"
check "the index links every recipe page" "wrapper.md reframe.md pytest.md gitlab-ci.md" \
    "$(grep -o '([a-z-]*\.md)' "$DOCS/index.md" | tr -d '()' | paste -sd ' ' -)"
check "mkdocs.yml has the pages in its nav" "5" "$(grep -c 'integrations/[a-z-]*\.md' "$ROOT/mkdocs.yml")"
check "the README links the integrations page" "(docs/integrations/index.md)" "$(grep -o "(docs/integrations/index.md)" "$ROOT/README.md")"

echo "== a shell harness: run-suite.sh =="
store suite
mkdir -p "$TMP/suite/t"
printf 'printf "size,bw\\n1,10\\n2,20\\n"\n' > "$TMP/suite/t/bw.sh"
printf 'printf "op,lat\\nput,3\\n"; exit 4\n' > "$TMP/suite/t/lat.sh"
out="$(bash "$EX/run-suite.sh" "$TMP/suite/t" 2>&1; echo "rc=$?")"
check "run-suite passes each test's output through" "2,20" "$out"
check "...reports the failing test" "FAIL lat" "$out"
check "...and exits non-zero" "rc=1" "$out"
check "...counting one failure" "1 test(s) failed" "$out"
check "each test files its own dataset" "suite.bw 2 suite.lat 1" "$(provost ls 2>/dev/null | sq | paste -sd ' ' -)"
out="$(provost show suite.lat | sq)"
check "...with test, host and run.id as columns, and rc" "# capture test host run.id rc n op lat" "$out"
check "...the failing test's status on its row" "lat $(uname -n)" "$out"
check "...rc=4" " 4 1 put 3" "$out"

echo "== pytest: the provost_pytest plugin and the JUnit XML report =="
if needs "pytest" "$PY" -c 'import pytest'; then
    store pytest; mkdir -p "$TMP/pytest/p"; cd "$TMP/pytest/p"
    cp "$EX/provost_pytest.py" .
    printf '[pytest]\n' > pytest.ini      # not provost's own pyproject settings
    cat > test_bench.py <<'EOF'
import pytest

@pytest.mark.parametrize('n', [1, 2])
def test_bw(n):
    print('size,bw')
    print(f'{n},{n * 10}')

def test_quiet():
    assert True

def test_fails():
    print('size,bw\n9,0')
    assert False
EOF
    out="$("$PY" -m pytest -q -p provost_pytest --provost --provost-context 'run.id=r 42' \
            --junitxml=report.xml 2>&1; echo "rc=$?")"
    check "pytest's own verdict is kept (a test failed: exit 1)" "rc=1" "$out"
    check "...and its summary" "1 failed, 3 passed" "$out"
    check "a dataset per test function, a quiet test files nothing" "pytest.test_bw 2 pytest.test_fails 1" \
        "$(provost ls 2>/dev/null | sq | paste -sd ' ' -)"
    out="$(provost show pytest.test_bw | sq)"
    check "...with the test id, outcome, duration and --provost-context as columns" \
        "# capture test outcome duration run.id n size bw" "$out"
    check "...a row per parametrized case" "test_bench.py::test_bw[2] passed" "$out"
    check "...a value with a space" "r 42 1 2 20" "$out"
    check "a failed test's output is filed with outcome=failed" "test_bench.py::test_fails failed" \
        "$(provost show pytest.test_fails | sq)"
    check "the whole session is one commit" "1" \
        "$(git -C "$PROVOST_WORKSPACE" log --oneline | grep -c 'batch' || true)"
    printf '#%% run.id=42\n' | cat - report.xml | provost -q --context-columns --name junit
    out="$(provost show junit | sq)"
    check "the JUnit XML gives a row per test case, run.id a column" "run.id n classname name" "$out"
    check "...the failure's message" "test_fails" "$out"
    check "...four cases" "4" "$(provost show junit | tail -n +2 | wc -l | tr -d ' ')"
    out="$(PROVOST=/nonexistent "$PY" -m pytest -q -p provost_pytest --provost -k test_bw 2>&1; echo "rc=$?")"
    check "with no provost, the plugin says so" "provost not found; nothing filed" "$out"
    check "...and pytest still passes" "rc=0" "$out"
    cd "$ROOT"
fi

echo "== ReFrame: the ProvostCapture hook, and the perflogs =="
if needs "ReFrame (reframe-hpc)" reframe --version; then
    store reframe; mkdir -p "$TMP/reframe/r"; cd "$TMP/reframe/r"
    echo "  ReFrame $(reframe --version)"
    out="$(reframe -c "$EX/stream_check.py" -r --perflogdir "$TMP/reframe/r/perflogs/run1" \
            --prefix "$TMP/reframe/r" 2>&1; echo "rc=$?")"
    check "the example check passes" "PASSED" "$out"
    check_not "...with no warning from the hook" "provost could not file" "$out"
    out="$(provost show StreamCheck | sq)"
    check "each test's output is filed with its context as columns" \
        "# capture test system partition environ sched.job rc req threads n Function Rate" "$out"
    check "...one capture per test case" "2" "$(provost log 2>/dev/null | grep -c inject || true)"
    check "...the parameter's own row" "StreamCheck %threads=2 generic default builtin" "$out"
    check "...the job's exit code (0) and provost_context's columns" " 0 REQ-12 2 1 Copy 2000" "$out"
    check "check-manifest sees the manifest keys the hook set" "c0001 incomplete test.version,build.commit,sut" \
        "$(provost check-manifest c0001 2>/dev/null | sq)"
    find "$TMP/reframe/r/perflogs/run1" -name '*.log' \
      | awk '{ n = $0; sub(/.*\//, "", n); sub(/\.log$/, "", n); print "rfm-perf." n "\t" $0 }' \
      | provost batch --from - >/dev/null 2>&1
    out="$(provost show rfm-perf.StreamCheck | sq)"
    check "the perflogs file as a dataset per test" "rfm-perf.StreamCheck 2" "$(provost ls 2>/dev/null | sq)"
    check "...with the performance variable's value and unit as columns" "copy_bw_value copy_bw_unit" "$out"
    check "...the measured value" "2000.0 MB/s" "$out"
    # A check whose job fails still has its output filed, before sanity fails it.
    cat > "$TMP/reframe/r/fail_check.py" <<'EOF'
import os
import sys

import reframe as rfm
import reframe.utility.sanity as sn
from reframe.core.builtins import sanity_function

sys.path.insert(0, os.environ['RECIPES'])
from provost_reframe import ProvostCapture  # noqa: E402


@rfm.simple_test
class FailCheck(rfm.RunOnlyRegressionTest, ProvostCapture):
    valid_systems = ['*']
    valid_prog_environs = ['*']
    executable = 'sh'
    executable_opts = ['-c', "'printf \"op,lat\\nput,3\\n\"; exit 5'"]

    @sanity_function
    def validate(self):
        return sn.assert_eq(self.job.exitcode, 0)
EOF
    out="$(RECIPES="$EX" reframe -c "$TMP/reframe/r/fail_check.py" -r --prefix "$TMP/reframe/r" 2>&1; echo "rc=$?")"
    check "a failing check fails in ReFrame as before" "FAILED" "$out"
    check "...its output is filed all the same" "FailCheck generic default builtin" \
        "$(provost show FailCheck | sq)"
    check "...rc=5" " 5 1 put 3" "$(provost show FailCheck | sq)"
    out="$(PROVOST=/nonexistent reframe -c "$EX/stream_check.py" -r --prefix "$TMP/reframe/r" 2>&1; echo "rc=$?")"
    check "with no provost the checks still pass" "PASSED" "$out"
    check "...and ReFrame logs a warning" "provost not found" "$out"
    cd "$ROOT"
fi

echo "== GitLab CI: the job's script, run with GitLab's variables stood in =="
if needs "PyYAML" "$PY" -c 'import yaml'; then
    store gitlab; P="$TMP/gitlab/project"; mkdir -p "$P/ci"
    cp "$EX/provost-wrap" "$P/ci/provost-wrap"
    printf '#!/bin/sh\nprintf "Function,Rate\\nCopy,11234.5\\nScale,11001.2\\n"\n' > "$P/run-benchmark.sh"
    chmod +x "$P/run-benchmark.sh"
    # The job's variables, then its script, as bash: GitLab expands $VARS the
    # same way. before_script installs provost from PyPI; the checkout's
    # provost on PATH stands in for it.
    "$PY" - "$EX/gitlab-ci.yml" > "$TMP/gitlab/job.sh" <<'EOF'
import shlex, sys, yaml
job = yaml.safe_load(open(sys.argv[1]))['benchmark']
assert job['before_script'] == ['pip install provost'], job['before_script']
assert job['artifacts'] == {'when': 'always', 'paths': ['provost-store/']}, job['artifacts']
for k, v in job['variables'].items():
    print(f'export {k}="{v}"')
for line in job['script']:
    print(line)
EOF
    out="$(cd "$P" && unset PROVOST_WORKSPACE && env CI_PROJECT_DIR="$P" CI_PIPELINE_ID=7001 CI_JOB_ID=88123 \
            CI_COMMIT_SHA=0123abcd CI_RUNNER_DESCRIPTION="shared runner 3" \
            bash -e "$TMP/gitlab/job.sh" 2>&1; echo "rc=$?")"
    check "the job's script runs" "rc=0" "$out"
    check "...and shows the dataset it filed" "Copy" "$out"
    check "the store is where the artifact path points" "benchmark" \
        "$(PROVOST_WORKSPACE="$P/provost-store" provost ls 2>/dev/null)"
    out="$(PROVOST_WORKSPACE="$P/provost-store" provost show benchmark | sq)"
    check "...rows carry the pipeline, job, commit and runner" \
        "# capture run.id sched.job build.commit sut rc n Function Rate" "$out"
    check "...with GitLab's values" "7001 88123 0123abcd shared runner 3 0 1 Copy 11234.5" "$out"
    printf '#!/bin/sh\necho "Function,Rate"; exit 9\n' > "$P/run-benchmark.sh"
    out="$(cd "$P" && unset PROVOST_WORKSPACE && env CI_PROJECT_DIR="$P" CI_PIPELINE_ID=7002 CI_JOB_ID=88124 \
            CI_COMMIT_SHA=0123abcd CI_RUNNER_DESCRIPTION=r bash -e "$TMP/gitlab/job.sh" 2>&1; echo "rc=$?")"
    check "a failing benchmark fails the job with its own status" "rc=9" "$out"
fi

echo "integrations: $pass passed, $fail failed, $skipped skipped"
[[ $fail -eq 0 ]]
