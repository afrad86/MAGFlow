#!/usr/bin/env python3

import argparse
from pathlib import Path


def main():

    parser = argparse.ArgumentParser(
        description="Convert a directory of bin FASTA files into a DAS Tool contig2bin table."
    )

    parser.add_argument(
        "-i",
        "--input",
        required=True,
        help="Directory containing FASTA bins"
    )

    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output TSV file"
    )

    args = parser.parse_args()

    input_dir = Path(args.input)

    if not input_dir.exists():
        raise FileNotFoundError(f"Input directory does not exist: {input_dir}")

    output_file = Path(args.output)

    # Ensure the output directory exists
    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Recursively search for FASTA files
    fasta_files = sorted(
        list(input_dir.rglob("*.fa")) +
        list(input_dir.rglob("*.fasta")) +
        list(input_dir.rglob("*.fna"))
    )

    with open(output_file, "w") as out:

        for fasta in fasta_files:

            bin_name = fasta.stem

            with open(fasta) as fh:

                for line in fh:

                    if line.startswith(">"):

                        contig = line[1:].strip().split()[0]

                        # Restore original CONCOCT contig names
                        if ".concoct_part_" in contig:
                            contig = contig.split(".concoct_part_")[0]

                        out.write(f"{contig}\t{bin_name}\n")

if __name__ == "__main__":
    main()