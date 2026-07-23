# SPDX-FileCopyrightText: 2026 Martin Gallagher
#
# SPDX-License-Identifier: GPL-3.0-only

"""Make ``python -m glean_data`` behave like the ``glean`` command."""

import sys

from glean_data import main

if __name__ == "__main__":
    sys.exit(main())
