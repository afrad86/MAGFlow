#!/usr/bin/env python3
"""Combine per-MAG/group normalized tables into four cohort-level TSVs."""
import csv
import glob
import os


TABLES = [
    ('*_amr.tsv', 'amr_features.tsv'),
    ('*_vfdb.tsv', 'virulence_features.tsv'),
    ('*_eggnog.tsv', 'functional_annotations.tsv'),
    ('*_fastani.tsv', 'strain_pairwise_fastani.tsv'),
]


def main():
    for pattern, output in TABLES:
        files = sorted(glob.glob(pattern))
        header = None
        with open(output, 'w', newline='') as dst:
            writer = None
            for path in files:
                with open(path, newline='') as src:
                    reader = csv.reader(src, delimiter='\t')
                    current_header = next(reader, None)
                    if current_header is None:
                        continue
                    if header is None:
                        header = current_header
                        writer = csv.writer(dst, delimiter='\t', lineterminator='\n')
                        writer.writerow(header)
                    elif current_header != header:
                        raise ValueError(f'Inconsistent columns in {path}')
                    writer.writerows(reader)
            if header is None:
                # A nonempty manifest should always produce at least one file per analysis.
                raise RuntimeError(f'No input tables found for {output} in {os.getcwd()}')


if __name__ == '__main__':
    main()
