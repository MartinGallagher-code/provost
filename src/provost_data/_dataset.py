# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

"""Read a provost dataset from Python: rows as dicts, or a pandas DataFrame.

Both read through the provost command itself (``provost show NAME --tsv``), so
provost stays the one reader of its store: nothing here opens the store's
files, and a dataset reads the same from Python as from the shell (PV-031).
"""

import contextlib
import gc
import os
import shutil
import subprocess

import provost_data

__all__ = ["ProvostError", "load", "load_df"]

PANDAS_HINT = (
    "provost_data.load_df needs pandas: pip install 'provost[pandas]' "
    "(or pip install pandas), or use provost_data.load for rows as dicts"
)


class ProvostError(RuntimeError):
    """provost could not be run, or refused the request.

    ``returncode`` is provost's exit status (None when it was not run) and
    ``stderr`` what it said.
    """

    def __init__(self, message, returncode=None, stderr=""):
        super().__init__(message)
        self.returncode = returncode
        self.stderr = stderr


def _command():
    """The start of the command line that runs provost: the tree bundled in
    this package under bash, else a ``provost`` on PATH (a git checkout)."""
    script = provost_data.provost_script()
    if os.path.isfile(script):
        bash = shutil.which("bash")
        if bash is None:
            raise ProvostError("bash is required but was not found on PATH")
        return [bash, script]
    found = shutil.which("provost")
    if found is None:
        raise ProvostError(
            "cannot find provost: the bundled tree is missing and there is "
            "no 'provost' on PATH"
        )
    return [found]


def _store_dir(store):
    """The store a ``store=`` argument names: the directory itself, or, for a
    controlled directory, the ``.provost`` store inside it."""
    path = os.path.abspath(os.path.expanduser(os.fspath(store)))
    inner = os.path.join(path, ".provost")
    if os.path.isdir(inner):
        return inner
    if os.path.isdir(path):
        return path
    raise ProvostError("no provost store at %s" % path)


def _run(args, store):
    """Run ``provost ARGS`` on the store, its output held."""
    env = dict(os.environ)
    if store is not None:
        env["PROVOST_WORKSPACE"] = _store_dir(store)
    return subprocess.run(
        _command() + args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def _tsv(name, store, capture):
    """``provost show NAME --tsv``'s output, as text."""
    args = ["show", name, "--tsv"]
    if capture is not None:
        args += ["--capture", str(capture)]
    proc = _run(args, store)
    err = proc.stderr.decode("utf-8", "replace").strip()
    if proc.returncode != 0:
        raise ProvostError(
            err or "provost show exited with status %d" % proc.returncode,
            proc.returncode,
            err,
        )
    return proc.stdout.decode("utf-8", "replace")


@contextlib.contextmanager
def _gc_paused():
    """The garbage collector off for the block, and left as it was found.

    The rows are lists and dicts holding only strings: no cycles for it to
    find, and its passes over them took two thirds of the time a load of a
    million rows took.
    """
    enabled = gc.isenabled()
    gc.disable()
    try:
        yield
    finally:
        if enabled:
            gc.enable()


def _parse(name, text):
    """(header, rows) from a dataset's TSV: each row a list of its cells, a
    blank cell None, a short row padded with None."""
    if text.endswith("\n"):
        text = text[:-1]
    lines = text.split("\n") if text else []
    if not lines:
        return [], []
    header = lines[0].split("\t")
    width = len(header)
    rows = []
    with _gc_paused():
        for number, line in enumerate(lines[1:], 2):
            cells = line.split("\t")
            if len(cells) > width:
                raise ProvostError(
                    "dataset '%s': line %d has %d cells for %d columns"
                    % (name, number, len(cells), width)
                )
            cells += [""] * (width - len(cells))
            rows.append([v or None for v in cells])
    return header, rows


def load(name, store=None, capture=None):
    """A provost dataset's rows, as a list of dicts (standard library only).

    Each row maps column name to value, columns in the order ``provost show``
    gives them, starting with ``#`` (the row's index in the store, which
    ``provost source`` takes) and ``capture``. Every value is the string
    provost stored, or None for a blank cell: a blank is never read as 0.

    name     the dataset, as ``provost ls`` lists it
    store    a store directory, or a controlled directory (its ``.provost``
             is used); default: the store ``provost`` would use here
             (``PROVOST_WORKSPACE``, a controlled directory, else the global
             store)
    capture  only the rows one capture filed: ``"c0007"`` or ``7``

    Raises ProvostError when provost cannot be run or refuses (no such
    dataset, no such store, a bad name); its message is provost's own.
    """
    header, rows = _parse(name, _tsv(name, store, capture))
    with _gc_paused():
        return [dict(zip(header, row)) for row in rows]


def _types(name, store):
    """{column: type}, the column types provost recorded for the dataset at
    capture (``provost show NAME --types --tsv``, PV-040). Empty when none
    are recorded, and when the provost run predates them (it refuses
    ``--types``): the columns are then read as they were before."""
    proc = _run(["show", name, "--types", "--tsv"], store)
    if proc.returncode != 0:
        return {}
    header, rows = _parse(name, proc.stdout.decode("utf-8", "replace"))
    if header[:2] != ["column", "type"]:
        return {}
    return {row[0]: row[1] for row in rows}


# The recorded types load_df makes numeric; every other recorded type (text,
# version, datetime, quantity, mixed, ...) keeps its strings.
NUMERIC_TYPES = ("integer", "decimal")


def load_df(name, store=None, capture=None):
    """A provost dataset as a pandas DataFrame (``pip install 'provost[pandas]'``).

    The same rows and columns as :func:`load`. A blank cell is NaN. A
    column's dtype follows the type provost recorded for it at capture
    (``provost show NAME --types``): an integer or decimal column becomes
    numeric (it keeps its strings if a value is not a number after all);
    a column of any other type keeps its strings, even when every value it
    holds looks like a number. A column with no type recorded (``#``, the
    capture column, a dataset filed before provost 2.24.0) becomes numeric
    when every non-blank value is a number. Raises ImportError, with the
    install command, when pandas is not installed.
    """
    try:
        import pandas
    except ImportError:
        raise ImportError(PANDAS_HINT) from None
    header, rows = _parse(name, _tsv(name, store, capture))
    types = _types(name, store)
    frame = pandas.DataFrame(rows, columns=header)
    for column in header:
        kind = types.get(column, "empty")
        if kind != "empty" and kind not in NUMERIC_TYPES:
            continue
        try:
            frame[column] = pandas.to_numeric(frame[column])
        except (ValueError, TypeError):
            pass
    return frame
