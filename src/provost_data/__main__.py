# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

"""Make ``python -m provost_data`` behave like the ``provost`` command."""

import sys

from provost_data import main

if __name__ == "__main__":
    sys.exit(main())
