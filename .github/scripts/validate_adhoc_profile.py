#!/usr/bin/env python3
"""CLI adapter for the shared Ad Hoc profile contract validator."""

from pathlib import Path
import sys

repository_root = Path(__file__).resolve().parents[2]
if str(repository_root) not in sys.path:
    sys.path.insert(0, str(repository_root))

from tools.ios_adhoc_profile_validation import main


if __name__ == "__main__":
    raise SystemExit(main())
