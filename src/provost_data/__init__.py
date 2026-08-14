# SPDX-FileCopyrightText: 2026 Martin Gallagher
#
# SPDX-License-Identifier: GPL-3.0-only

"""provost — turn command output into data.

This package is a thin launcher around the Bash implementation: the complete
provost tree (the ``provost`` entry point plus its extract/analyze/transform
engines) ships inside the wheel under ``provost_data/_bundle`` and is exec'd in
place, exactly as a git-checkout install runs it. All behaviour, commands, and
``PROVOST_*`` environment variables are those of the bundled tool.
"""

import os
import shutil
import sys

__all__ = ["bundle_dir", "provost_script", "main"]

# Exit statuses for launch failures (the launched provost's own exit status is
# whatever the tool returns — os.execv never comes back on success).
EXIT_BROKEN_INSTALL = 70  # EX_SOFTWARE: the bundled tree is missing
EXIT_NO_BASH = 127        # command-not-found convention


def bundle_dir():
    """Absolute path of the bundled provost tree inside this package."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "_bundle")


def provost_script():
    """Absolute path of the bundled ``provost`` entry-point script."""
    return os.path.join(bundle_dir(), "provost")


def main(argv=None):
    """Replace the current process with the bundled provost.

    Returns an exit status only when provost cannot be launched (no bash on
    PATH, or the bundled tree is missing); on success ``os.execv`` does not
    return.
    """
    if argv is None:
        argv = sys.argv[1:]
    script = provost_script()
    if not os.path.isfile(script):
        print("provost: bundled script not found at %s" % script, file=sys.stderr)
        return EXIT_BROKEN_INSTALL
    bash = shutil.which("bash")
    if bash is None:
        print("provost: bash is required but was not found on PATH", file=sys.stderr)
        return EXIT_NO_BASH
    os.execv(bash, [bash, script] + list(argv))
