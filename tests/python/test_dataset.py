# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

"""Tests for provost_data.load / load_df (PV-031) — run via `python -m pytest`.

They read a real store, filed by this checkout's provost, so they need bash and
git, as provost does. pandas is needed for the load_df tests (CI installs it);
without it they are skipped, and the 100% coverage gate then fails, so a run
that skips them cannot pass.
"""

import gc
import math
import os
import shutil
import subprocess
import sys

import pytest

import provost_data
from provost_data import _dataset

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROVOST = os.path.join(REPO, "provost")

COLUMNS = ["#", "capture", "n", "k", "v", "w"]


def _file(env, text, name):
    subprocess.run(
        ["bash", PROVOST, "--sync", "--name", name],
        input=text.encode(), env=env, check=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


@pytest.fixture(scope="module")
def project(tmp_path_factory):
    """A controlled-style directory whose .provost store holds 'blanks' (two
    captures, blank cells mid-row and at the end of a row)."""
    root = tmp_path_factory.mktemp("project")
    store = root / ".provost"
    env = dict(os.environ, PROVOST_WORKSPACE=str(store),
               PROVOST_HOME=str(root / "home"), PROVOST_ASYNC="0")
    _file(env, "k\tv\tw\nx\t\ty\nz\t1\t\n", "blanks")
    _file(env, "k\tv\tw\nq\t2\t3\n", "blanks")
    return root


@pytest.fixture
def store(project):
    return str(project / ".provost")


@pytest.fixture(autouse=True)
def provost_on_path(monkeypatch):
    """Run this checkout's provost, as a git checkout's user would: no bundled
    tree, provost on PATH."""
    monkeypatch.setattr(provost_data, "provost_script", lambda: os.path.join(REPO, "no-bundle", "provost"))
    monkeypatch.setenv("PATH", REPO + os.pathsep + os.environ.get("PATH", ""))
    monkeypatch.delenv("PROVOST_WORKSPACE", raising=False)


def test_load_returns_rows_as_dicts(store):
    rows = provost_data.load("blanks", store=store)
    assert [list(r) for r in rows] == [COLUMNS] * 3
    assert rows[0] == {"#": "1", "capture": "c0001", "n": "1", "k": "x", "v": None, "w": "y"}
    assert rows[2] == {"#": "3", "capture": "c0002", "n": "1", "k": "q", "v": "2", "w": "3"}


def test_blank_cells_are_none_never_zero(store):
    rows = provost_data.load("blanks", store=store)
    assert rows[0]["v"] is None            # blank mid-row
    assert rows[1]["w"] is None            # blank at the end of a row
    assert rows[1]["v"] == "1"


@pytest.mark.parametrize("capture", ["c0002", 2, "2"])
def test_load_one_capture(store, capture):
    rows = provost_data.load("blanks", store=store, capture=capture)
    assert [r["#"] for r in rows] == ["3"]


def test_load_capture_with_no_rows_is_empty(store):
    assert provost_data.load("blanks", store=store, capture=9) == []


def test_store_may_be_a_controlled_directory(project):
    assert len(provost_data.load("blanks", store=project)) == 3   # a Path, too


def test_store_defaults_to_the_one_provost_uses(store, monkeypatch):
    monkeypatch.setenv("PROVOST_WORKSPACE", store)
    assert len(provost_data.load("blanks")) == 3


def test_store_expands_home(store, monkeypatch):
    monkeypatch.setenv("HOME", os.path.dirname(store))
    assert len(provost_data.load("blanks", store="~/.provost")) == 3


def test_no_such_store(tmp_path):
    with pytest.raises(provost_data.ProvostError, match="no provost store at") as e:
        provost_data.load("blanks", store=tmp_path / "nowhere")
    assert e.value.returncode is None


def test_no_such_dataset_is_provosts_own_error(store):
    with pytest.raises(provost_data.ProvostError, match="no such dataset: nope") as e:
        provost_data.load("nope", store=store)
    assert e.value.returncode == 1
    assert "try 'provost ls'" in e.value.stderr


def test_a_bad_name_is_refused(store):
    with pytest.raises(provost_data.ProvostError, match="invalid dataset name") as e:
        provost_data.load("../x", store=store)
    assert e.value.returncode == 2


def test_runs_the_bundled_tree_under_bash(store, monkeypatch):
    monkeypatch.setattr(provost_data, "provost_script", lambda: PROVOST)
    assert _dataset._command() == [shutil.which("bash"), PROVOST]
    assert len(provost_data.load("blanks", store=store)) == 3


def test_bundled_tree_without_bash(monkeypatch):
    monkeypatch.setattr(provost_data, "provost_script", lambda: PROVOST)
    monkeypatch.setattr(shutil, "which", lambda cmd: None)
    with pytest.raises(provost_data.ProvostError, match="bash is required"):
        provost_data.load("blanks")


def test_no_provost_anywhere(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda cmd: None)
    with pytest.raises(provost_data.ProvostError, match="cannot find provost"):
        provost_data.load("blanks")


def _fake_provost(tmp_path, monkeypatch, script):
    fake = tmp_path / "bin"
    fake.mkdir()
    (fake / "provost").write_text("#!/bin/sh\n" + script)
    (fake / "provost").chmod(0o755)
    monkeypatch.setenv("PATH", str(fake) + os.pathsep + os.environ["PATH"])


def test_a_silent_failure_names_the_exit_status(tmp_path, monkeypatch):
    _fake_provost(tmp_path, monkeypatch, "exit 3\n")
    with pytest.raises(provost_data.ProvostError, match="exited with status 3") as e:
        provost_data.load("blanks")
    assert e.value.returncode == 3 and e.value.stderr == ""


def test_the_arguments_provost_is_given(tmp_path, monkeypatch):
    _fake_provost(tmp_path, monkeypatch, 'printf "%s\\n" "$@"\n')
    assert provost_data.load("ds", capture=7) == [{"show": "ds"}, {"show": "--tsv"},
                                                  {"show": "--capture"}, {"show": "7"}]


def test_parse_no_output_at_all():
    assert _dataset._parse("x", "") == ([], [])


def test_parse_without_a_final_newline():
    assert _dataset._parse("x", "a\tb\n1\t2") == (["a", "b"], [["1", "2"]])


def test_parse_pads_a_short_row_with_none():
    assert _dataset._parse("x", "a\tb\tc\n1\n")[1] == [["1", None, None]]


def test_parse_refuses_a_row_wider_than_the_header():
    with pytest.raises(provost_data.ProvostError, match="dataset 'x': line 3 has 3 cells for 2 columns"):
        _dataset._parse("x", "a\tb\n1\t2\n1\t2\t3\n")


def test_the_garbage_collector_is_left_as_it_was_found(store):
    assert gc.isenabled()
    assert len(provost_data.load("blanks", store=store)) == 3
    assert gc.isenabled()
    with pytest.raises(provost_data.ProvostError):
        _dataset._parse("x", "a\n1\t2\n")             # an error on the way out
    assert gc.isenabled()
    gc.disable()
    try:
        with _dataset._gc_paused():
            pass
        assert not gc.isenabled()
    finally:
        gc.enable()


def test_parse_keeps_a_value_exactly():
    # quotes, spaces, a lone carriage return and a would-be number keep as is
    text = 'a\tb\tc\n"q"\t 007 \tx\ry\n'
    assert _dataset._parse("x", text)[1] == [['"q"', " 007 ", "x\ry"]]


def test_undecodable_bytes_do_not_stop_a_load(tmp_path, monkeypatch):
    _fake_provost(tmp_path, monkeypatch, "printf 'a\\n\\377\\n'\n")
    assert provost_data.load("x") == [{"a": "�"}]


# --- load_df -----------------------------------------------------------------

def test_load_df_without_pandas_says_how_to_install(monkeypatch):
    monkeypatch.setitem(sys.modules, "pandas", None)    # import pandas fails
    with pytest.raises(ImportError, match=r"pip install 'provost\[pandas\]'"):
        provost_data.load_df("blanks")


def test_load_df_returns_a_dataframe(store):
    pd = pytest.importorskip("pandas")
    df = provost_data.load_df("blanks", store=store)
    assert isinstance(df, pd.DataFrame)
    assert list(df.columns) == COLUMNS
    assert len(df) == 3
    assert list(df["#"]) == [1, 2, 3]                      # numbers become numeric
    assert list(df["capture"]) == ["c0001", "c0001", "c0002"]   # strings stay strings
    assert list(df["k"]) == ["x", "z", "q"]


def test_load_df_blank_is_nan_never_zero(store):
    pytest.importorskip("pandas")
    df = provost_data.load_df("blanks", store=store)
    assert math.isnan(df["v"][0]) and df["v"][1] == 1 and df["v"][2] == 2
    assert df["w"][0] == "y" and df["w"][2] == "3"         # 'y' keeps w a string column
    assert df["w"].isna().tolist() == [False, True, False]
    assert 0 not in df["v"].tolist()


def test_load_df_one_capture(store):
    pytest.importorskip("pandas")
    df = provost_data.load_df("blanks", store=store, capture="c0002")
    assert list(df["#"]) == [3]


def test_load_df_capture_with_no_rows_keeps_the_columns(store):
    pytest.importorskip("pandas")
    df = provost_data.load_df("blanks", store=store, capture=9)
    assert df.empty and list(df.columns) == COLUMNS


def test_load_df_errors_are_loads(store):
    pytest.importorskip("pandas")
    with pytest.raises(provost_data.ProvostError, match="no such dataset"):
        provost_data.load_df("nope", store=store)
