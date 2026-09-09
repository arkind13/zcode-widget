"""Windows port of the macOS ZCodeWidget data paths.

The macOS app hardcodes NSHomeDirectory()-relative paths; on Windows the
ZCode CLI uses the same ~/.zcode/ layout under the user profile.
"""

from __future__ import annotations

import os
from pathlib import Path


def home() -> Path:
    # USERPROFILE is the real profile dir; HOME may be set by MSYS/Git Bash
    # to something else, so prefer USERPROFILE when present.
    return Path(os.environ.get("USERPROFILE") or Path.home())


ZCODE_DIR = home() / ".zcode"

DB_PATH = ZCODE_DIR / "cli" / "db" / "db.sqlite"

# Widget-owned files (Google OAuth tokens, client secret)
WIDGET_DIR = home() / ".zcode-widget"
