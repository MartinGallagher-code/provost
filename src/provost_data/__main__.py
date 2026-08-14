# SPDX-FileCopyrightText: 2026 Martin Gallagher
#
# SPDX-License-Identifier: GPL-3.0-only

"""Make ``python -m provost_data`` behave like the ``provost`` command."""

import sys

from provost_data import main

if __name__ == "__main__":
    sys.exit(main())
