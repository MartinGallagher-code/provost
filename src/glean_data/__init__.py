# SPDX-FileCopyrightText: 2026 Martin Gallagher
#
# SPDX-License-Identifier: GPL-3.0-only

"""glean — turn command output into data.

This package is a thin launcher around the Bash implementation: the complete
glean tree (the ``glean`` entry point plus its extract/analyze/transform
engines) ships inside the wheel under ``glean_data/_bundle`` and is exec'd in
place, exactly as a git-checkout install runs it. All behaviour, commands, and
``GLEAN_*`` environment variables are those of the bundled tool.
"""

import os
import shutil
import sys

__all__ = ["bundle_dir", "glean_script", "main"]

# Exit statuses for launch failures (the launched glean's own exit status is
# whatever the tool returns — os.execv never comes back on success).
EXIT_BROKEN_INSTALL = 70  # EX_SOFTWARE: the bundled tree is missing
EXIT_NO_BASH = 127        # command-not-found convention


def bundle_dir():
    """Absolute path of the bundled glean tree inside this package."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "_bundle")


def glean_script():
    """Absolute path of the bundled ``glean`` entry-point script."""
    return os.path.join(bundle_dir(), "glean")


def main(argv=None):
    """Replace the current process with the bundled glean.

    Returns an exit status only when glean cannot be launched (no bash on
    PATH, or the bundled tree is missing); on success ``os.execv`` does not
    return.
    """
    if argv is None:
        argv = sys.argv[1:]
    script = glean_script()
    if not os.path.isfile(script):
        print("glean: bundled script not found at %s" % script, file=sys.stderr)
        return EXIT_BROKEN_INSTALL
    bash = shutil.which("bash")
    if bash is None:
        print("glean: bash is required but was not found on PATH", file=sys.stderr)
        return EXIT_NO_BASH
    os.execv(bash, [bash, script] + list(argv))
