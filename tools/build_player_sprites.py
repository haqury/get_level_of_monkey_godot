#!/usr/bin/env python3
"""Entry point: rebuild from source_spritesheet.jpg (see regenerate_player_from_sheet.py)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from regenerate_player_from_sheet import main  # noqa: E402

if __name__ == "__main__":
    main()
