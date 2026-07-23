# SPDX-FileCopyrightText: 2026 Martin Gallagher
#
# SPDX-License-Identifier: GPL-3.0-only

"""Unit tests for the glean_data launcher — run via `python -m pytest`.

Coverage of glean_data is enforced at 100% (branch coverage included) by the
pytest/coverage configuration in pyproject.toml.
"""

import os
import runpy
import shutil
import sys

import pytest

import glean_data


def test_bundle_dir_is_inside_package():
    d = glean_data.bundle_dir()
    assert os.path.isabs(d)
    assert os.path.basename(d) == "_bundle"
    assert os.path.dirname(d) == os.path.dirname(os.path.abspath(glean_data.__file__))


def test_glean_script_is_in_bundle_dir():
    s = glean_data.glean_script()
    assert os.path.dirname(s) == glean_data.bundle_dir()
    assert os.path.basename(s) == "glean"


def test_main_execs_bash_with_bundled_script(monkeypatch):
    calls = {}
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: "/bin/bash")
    monkeypatch.setattr(
        os, "execv", lambda path, args: calls.update(path=path, args=args)
    )
    assert glean_data.main(["show", "df"]) is None
    assert calls["path"] == "/bin/bash"
    assert calls["args"] == ["/bin/bash", glean_data.glean_script(), "show", "df"]


def test_main_defaults_argv_to_sys_argv(monkeypatch):
    calls = {}
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: "/bin/bash")
    monkeypatch.setattr(
        os, "execv", lambda path, args: calls.update(path=path, args=args)
    )
    monkeypatch.setattr(sys, "argv", ["glean", "ls"])
    assert glean_data.main() is None
    assert calls["args"] == ["/bin/bash", glean_data.glean_script(), "ls"]


def test_main_reports_missing_bundle(monkeypatch, capsys):
    monkeypatch.setattr(os.path, "isfile", lambda p: False)
    assert glean_data.main([]) == glean_data.EXIT_BROKEN_INSTALL
    err = capsys.readouterr().err
    assert "bundled script not found" in err
    assert glean_data.glean_script() in err


def test_main_reports_missing_bash(monkeypatch, capsys):
    monkeypatch.setattr(os.path, "isfile", lambda p: True)
    monkeypatch.setattr(shutil, "which", lambda cmd: None)
    assert glean_data.main([]) == glean_data.EXIT_NO_BASH
    assert "bash is required" in capsys.readouterr().err


def test_dunder_main_exits_with_main_status(monkeypatch):
    monkeypatch.setattr(glean_data, "main", lambda: 3)
    with pytest.raises(SystemExit) as excinfo:
        runpy.run_module("glean_data", run_name="__main__")
    assert excinfo.value.code == 3


def test_dunder_main_importable_without_running():
    import glean_data.__main__  # noqa: F401  (covers the __name__ guard's false branch)
