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
