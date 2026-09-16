# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

"""Unit tests for the provost_data launcher — run via `python -m pytest`.

Coverage of provost_data is enforced at 100% (branch coverage included) by the
pytest/coverage configuration in pyproject.toml.
"""

import os
import runpy
import shutil
import sys

import pytest

import provost_data


def test_bundle_dir_is_inside_package():
    d = provost_data.bundle_dir()
    assert os.path.isabs(d)
    assert os.path.basename(d) == "_bundle"
    assert os.path.dirname(d) == os.path.dirname(os.path.abspath(provost_data.__file__))


def test_provost_script_is_in_bundle_dir():
    s = provost_data.provost_script()
    assert os.path.dirname(s) == provost_data.bundle_dir()
    assert os.path.basename(s) == "provost"


def test_main_execs_bash_with_bundled_script(monkeypatch):
    calls = {}
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: "/bin/bash")
    monkeypatch.setattr(
        os, "execv", lambda path, args: calls.update(path=path, args=args)
    )
    assert provost_data.main(["show", "df"]) is None
    assert calls["path"] == "/bin/bash"
    assert calls["args"] == ["/bin/bash", provost_data.provost_script(), "show", "df"]


def test_main_defaults_argv_to_sys_argv(monkeypatch):
    calls = {}
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: "/bin/bash")
    monkeypatch.setattr(
        os, "execv", lambda path, args: calls.update(path=path, args=args)
    )
    monkeypatch.setattr(sys, "argv", ["provost", "ls"])
    assert provost_data.main() is None
    assert calls["args"] == ["/bin/bash", provost_data.provost_script(), "ls"]


def test_main_reports_missing_bundle(monkeypatch, capsys):
    monkeypatch.setattr(os.path, "isfile", lambda p: False)
    assert provost_data.main([]) == provost_data.EXIT_BROKEN_INSTALL
    err = capsys.readouterr().err
    assert "bundled script not found" in err
    assert provost_data.provost_script() in err


def test_main_reports_missing_bash(monkeypatch, capsys):
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: None)
    assert provost_data.main([]) == provost_data.EXIT_NO_BASH
    assert "bash is required" in capsys.readouterr().err


def test_dunder_main_exits_with_main_status(monkeypatch):
    monkeypatch.setattr(provost_data, "main", lambda: 3)
    with pytest.raises(SystemExit) as excinfo:
        runpy.run_module("provost_data", run_name="__main__")
    assert excinfo.value.code == 3


def test_dunder_main_importable_without_running():
    import provost_data.__main__  # noqa: F401  (covers the __name__ guard's false branch)
