# ReFrame

Two routes, which work together:

- **Each test's output**, filed as the test finishes, by a post-run hook that
  every check gets from one mixin class. Use it for what the benchmark itself
  printed: every row it files names the test, system, partition and job.
- **The perflogs**, filed after the run with `provost batch`. Use them for
  the performance values ReFrame extracted, with their references and units.

Tested with ReFrame 4.7 (`pip install reframe-hpc==4.7.4`).

## Each test's output: the ProvostCapture mixin

Save this beside your checks as `provost_reframe.py`:

<!-- file: examples/provost_reframe.py -->
```python
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""File each ReFrame test's output with provost, the test's context as columns.

Mix ``ProvostCapture`` into a test. Once its job has finished, the job's
standard output is filed into a provost dataset, with a ``#%`` prologue naming
the test, system, partition, programming environment, scheduler job id and the
job's exit code; every row the capture files carries them as columns. Filing
never fails or slows a test's verdict: if provost is missing or refuses the
output, ReFrame logs a warning and the test goes on to its sanity check.

Tested with ReFrame 4.7 (``reframe-hpc==4.7.4``).
"""
import os
import shutil
import subprocess

import reframe as rfm
import reframe.utility.typecheck as typ
from reframe.core.builtins import run_after, variable
from reframe.core.logging import getlogger


def _word(key, value):
    """One ``key=value`` word of a prologue, quoted the way provost reads it."""
    value = str(value)
    if ' ' in value or '\t' in value or value.startswith('"'):
        value = '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return f'{key}={value}'


class ProvostCapture(rfm.RegressionMixin):
    #: The provost to run: a command on PATH, or a path.
    provost = variable(str, value=os.environ.get('PROVOST', 'provost'))

    #: The dataset to file into; empty means the test's class name.
    provost_dataset = variable(str, value='')

    #: More KEY=VALUE context for every row (a requirement id, a build commit).
    provost_context = variable(typ.Dict[str, str], value={})

    # A post-run hook runs once the job has finished (ReFrame waits for it
    # first), so the output is complete and the exit code is known.
    @run_after('run')
    def file_with_provost(self):
        log = getlogger()
        exe = shutil.which(self.provost)
        if exe is None:
            log.warning(f'{self.name}: provost not found ({self.provost}); output not filed')
            return

        path = os.path.join(self.stagedir, self.job.stdout)
        try:
            with open(path, 'rb') as f:
                output = f.read()
        except OSError as err:
            log.warning(f'{self.name}: no output to file with provost: {err}')
            return
        if not output.strip():
            return

        context = {
            'test': self.name,
            'system': self.current_system.name,
            'partition': self.current_partition.name,
            'environ': self.current_environ.name,
            'sched.job': self.job.jobid,
            'rc': self.job.exitcode,
            **self.provost_context,
        }
        prologue = ''.join(f'#% {_word(k, v)}\n' for k, v in context.items()
                           if v is not None and str(v) != '')
        name = self.provost_dataset or type(self).__name__
        done = subprocess.run(
            [exe, '--sync', '-q', '--context-columns', '--name', name],
            input=prologue.encode() + output,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if done.returncode != 0:
            log.warning(f'{self.name}: provost could not file the output: '
                        f'{done.stdout.decode(errors="replace").strip()}')
```

Then add `ProvostCapture` to a check's bases. `provost_context` adds columns of
your own, and `provost_dataset` names the dataset (default: the class name):

<!-- file: examples/stream_check.py -->
```python
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""A ReFrame check that files its output with provost (the recipe's example).

The executable stands in for a real benchmark: it prints a small table, as
STREAM or OSU would. Run it with the provost_reframe.py module beside it:

    reframe -c stream_check.py -r
"""
import os
import sys

import reframe as rfm
import reframe.utility.sanity as sn
from reframe.core.builtins import (parameter, performance_function, run_after,
                                   sanity_function)

sys.path.insert(0, os.path.dirname(__file__))
from provost_reframe import ProvostCapture  # noqa: E402


@rfm.simple_test
class StreamCheck(rfm.RunOnlyRegressionTest, ProvostCapture):
    valid_systems = ['*']
    valid_prog_environs = ['*']
    threads = parameter([1, 2])
    executable = 'printf'

    @run_after('init')
    def set_output(self):
        # Function,Best Rate MB/s -- the shape of STREAM's results table.
        bw = 1000 * self.threads
        self.executable_opts = [
            f"'Function,Rate\\nCopy,{bw}\\nScale,{bw - 10}\\nAdd,{bw + 5}\\n'"
        ]
        self.provost_context = {'req': 'REQ-12', 'threads': str(self.threads)}

    @sanity_function
    def validate(self):
        return sn.assert_found(r'^Copy,', self.stdout)

    @performance_function('MB/s')
    def copy_bw(self):
        return sn.extractsingle(r'^Copy,(\d+)', self.stdout, 1, float)
```

```console
$ reframe -c stream_check.py -r
$ provost show StreamCheck
#  capture  test                   system   partition  environ  sched.job  rc  req     threads  n  Function  Rate
1  c0001    StreamCheck %threads=2  generic  default    builtin  2940       0   REQ-12  2        1  Copy      2000
...
```

The hook runs after ReFrame has waited for the job, so on a cluster it runs on
the node ReFrame itself runs on, reading the job's output from the stage
directory; provost needs to be installed there, not on the compute nodes.
`sched.job` is the scheduler's job id (Slurm's, PBS's, or the process id for
the local scheduler) and `rc` the job's exit code. A failure to file is a
warning in ReFrame's log and never changes a test's result.

To keep a failing test's output too, nothing more is needed: the hook runs
before the sanity check, so a test that then fails has already been filed.

## The perflogs

ReFrame 4's `filelog` handler writes one perflog per test under
`perflogs/SYSTEM/PARTITION/TEST.log`, appending on every run. Give each run a
directory of its own, so no line is filed twice, then file them all in one
commit, a dataset per test:

```bash
run="perflogs/$(date -u +%Y%m%dT%H%M%SZ)"
reframe -c checks/ -r --perflogdir "$run"
find "$run" -name '*.log' \
  | awk '{ n = $0; sub(/.*\//, "", n); sub(/\.log$/, "", n); print "rfm-perf." n "\t" $0 }' \
  | provost batch --from -
```

Each perflog line becomes a row (`result`, `jobid`, `system`, `partition`,
and each performance variable's `_value`, `_unit` and `_ref`). provost reads
ReFrame 4's `|`-separated perflogs and the `key=value` ones ReFrame 3 wrote.
