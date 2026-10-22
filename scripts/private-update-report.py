#!/usr/bin/env python3
"""Local-only PaperDesk Care metrics report (not a website endpoint)."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "website"))
from private_update_stats import DB_PATH, read_report


def main():
    parser = argparse.ArgumentParser(description="Private PaperDesk Care download statistics")
    parser.add_argument("--db", type=Path, default=DB_PATH)
    args = parser.parse_args()
    data = read_report(db_path=args.db)
    print(json.dumps(data, indent=2, ensure_ascii=False))
    print("\nNote: distinct installations are anonymous IDs, not individual people.", file=sys.stderr)
    print("Only Care-tagged transfers are counted; older clients are not retroactively included.", file=sys.stderr)


if __name__ == "__main__":
    main()
