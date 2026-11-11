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
