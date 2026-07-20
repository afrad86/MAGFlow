#!/usr/bin/env python3

import argparse
import os
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert a directory of FASTA bins into a contig-to-bin table for DAS Tool."
    )
    parser.add_argument(
        "-i",
        "--input",
        required=True,
        help="Directory containing bin FASTA files"
    )
    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output TSV file"
    )
    return parser.parse_args()


def is_fasta(filename):
    extensions = (
        ".fa",
        ".fasta",
        ".fna",
        ".fas"
    )
    return filename.lower().endswith(extensions)


def main():
    args = parse_args()

    if not os.path.isdir(args.input):
        sys.exit(f"ERROR: '{args.input}' is not a directory")

    search_dir = args.input

    if os.path.isdir(os.path.join(args.input, "bins")):
        search_dir = os.path.join(args.input, "bins")
        print(f"[INFO] Found extracted bins directory: {search_dir}", file=sys.stderr)
    else:
        print(f"[INFO] No bins/ directory found; reading FASTA files from: {search_dir}", file=sys.stderr)

    with open(args.output, "w") as out:

        for fasta in sorted(os.listdir(search_dir)):

            if not is_fasta(fasta):
                continue

            bin_name = os.path.splitext(fasta)[0]

            fasta_path = os.path.join(search_dir, fasta)

            with open(fasta_path) as fh:

                for line in fh:

                    if line.startswith(">"):

                        contig = line[1:].strip().split()[0]

                        out.write(f"{contig}\t{bin_name}\n")


if __name__ == "__main__":
    main()
