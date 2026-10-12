#!/usr/bin/env python3
"""Write FastANI query/reference lists for staged MAGs with usable fragments."""

import argparse
import csv
from pathlib import Path


def longest_contig(path: Path) -> int:
    longest = current = 0
    with path.open() as fasta:
        for line in fasta:
            if line.startswith(">"):
                longest = max(longest, current)
                current = 0
            else:
                current += len(line.strip())
    return max(longest, current)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--new", required=True)
    parser.add_argument("--old", required=True)
    parser.add_argument("--all", dest="all_genomes", required=True)
    args = parser.parse_args()

    eligible = {"NEW": [], "OLD": []}
    with open(args.manifest, newline="") as manifest:
        for line_number, row in enumerate(csv.reader(manifest, delimiter="\t"), start=1):
            if len(row) != 5 or row[3] not in eligible:
                raise ValueError(f"Malformed genome manifest row {line_number}: {row!r}")
            path = Path(row[4])
            if not path.is_file():
                raise FileNotFoundError(f"Staged MAG FASTA not found on row {line_number}: {path}")
            if longest_contig(path) >= 3000:
                eligible[row[3]].append(str(path))

    for output, status in ((args.new, "NEW"), (args.old, "OLD")):
        Path(output).write_text("".join(f"{path}\n" for path in eligible[status]))
    all_paths = eligible["NEW"] + eligible["OLD"]
    Path(args.all_genomes).write_text("".join(f"{path}\n" for path in all_paths))


if __name__ == "__main__":
    main()
