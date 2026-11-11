# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""pytest plugin: file each test's printed output with provost.

With ``--provost``, the standard output pytest captured from each test is kept
with a ``#%`` prologue (the test id, its outcome and its duration), and when the
session ends every one is filed by one ``provost batch``: a capture each, one
commit. A test's output goes to the dataset ``pytest.<function name>``, so the
cases of a parametrized test share one dataset and the ``test`` column tells
them apart. Filing never changes pytest's exit status.

Enable it with this file importable (beside ``conftest.py``, say) and either
``pytest -p provost_pytest --provost`` or ``pytest_plugins = ["provost_pytest"]``
in ``conftest.py``. ``PROVOST`` names the provost to call.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile


def _word(key, value):
    """One ``key=value`` word of a prologue, quoted the way provost reads it."""
    value = str(value)
    if ' ' in value or '\t' in value or value.startswith('"'):
        value = '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return f'{key}={value}'


def pytest_addoption(parser):
    group = parser.getgroup('provost')
    group.addoption('--provost', action='store_true',
                    help="file each test's captured stdout with provost")
    group.addoption('--provost-context', action='append', default=[], metavar='KEY=VALUE',
                    help='a column for every row filed (repeatable)')


def pytest_configure(config):
    if config.getoption('provost'):
        config.pluginmanager.register(_ProvostFiler(config), 'provost-filer')


class _ProvostFiler:
    def __init__(self, config):
        self.context = [kv.split('=', 1) for kv in config.getoption('provost_context') if '=' in kv]
        self.dir = tempfile.mkdtemp(prefix='provost-pytest-')
        self.inputs = []   # (dataset, path), in the order the tests ran

    def pytest_runtest_logreport(self, report):
        # The call phase holds the test's own output; a setup that failed or
        # skipped never reaches it, so it is filed from there instead.
        if report.when != 'call' and not (report.when == 'setup' and not report.passed):
            return
        output = report.capstdout
        if not output.strip():
            return
        func = report.nodeid.split('::')[-1].split('[')[0]
        name = 'pytest.' + (re.sub(r'[^A-Za-z0-9._-]', '_', func) or 'test')
        context = [('test', report.nodeid), ('outcome', report.outcome),
                   ('duration', f'{report.duration:.6f}')] + self.context
        path = os.path.join(self.dir, f'{len(self.inputs):05d}.txt')
        with open(path, 'w', encoding='utf-8') as f:
            f.writelines(f'#% {_word(k, v)}\n' for k, v in context)
            f.write(output)
        self.inputs.append((name, path))

    def pytest_sessionfinish(self, session):
        try:
            if not self.inputs:
                return
            exe = shutil.which(os.environ.get('PROVOST', 'provost'))
            if exe is None:
                print('provost-pytest: provost not found; nothing filed', file=sys.stderr)
                return
            listing = ''.join(f'{name}\t{path}\n' for name, path in self.inputs)
            done = subprocess.run([exe, 'batch', '--context-columns', '--from', '-'],
                                  input=listing, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if done.returncode != 0:
                print(f'provost-pytest: provost batch did not file everything:\n{done.stdout}',
                      file=sys.stderr)
        finally:
            shutil.rmtree(self.dir, ignore_errors=True)
