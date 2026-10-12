#!/usr/bin/env python3
"""Report failed/aborted Nextflow tasks and return nonzero if any are present."""
import argparse
import csv
from collections import Counter
from pathlib import Path


BAD_STATUSES = {"FAILED", "ABORTED", "CANCELLED"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()

    with args.trace.open(newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames or not {"name", "status"}.issubset(reader.fieldnames):
            parser.error(f"Not a valid Nextflow trace file: {args.trace}")
        failures = []
        for row in reader:
            status = (row.get("status") or "").strip().upper()
            if status in BAD_STATUSES:
                failures.append(row)

    if not failures:
        print(f"No failed or aborted tasks in {args.trace}")
        return 0

    counts = Counter((row.get("name", "unknown").split("(", 1)[0].strip(),
                      (row.get("status") or "UNKNOWN").strip().upper())
                     for row in failures)
    print(f"Found {len(failures)} failed/aborted task(s) in {args.trace}:")
    for (process, status), count in sorted(counts.items()):
        print(f"  {process} {status}: {count}")
    for row in failures:
        print(f"  {row.get('status', 'UNKNOWN')}: {row.get('name', 'unknown')}"
              f" (task {row.get('task_id', '?')}, workdir {row.get('workdir', '?')})")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
