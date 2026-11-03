#!/usr/bin/env python3
"""Fail if key columns of the downstream tables are blank, so a silent normalizer
failure (e.g. a renamed tool column) is caught before a batch is merged."""
import argparse
import csv
import os
import sys

# table -> columns that must be filled in (almost) every row
REQUIRED = {
    'amr_features.tsv': ['gene_symbol', 'element_type', 'class', 'method', 'identity_percent',
                         'coverage_percent', 'accession'],
    'virulence_features.tsv': ['query_gene_id', 'vfdb_subject_id', 'identity_percent',
                               'query_coverage_percent', 'bitscore', 'subject_description'],
    'strain_pairwise_fastani.tsv': ['species', 'ani_percent', 'matching_fragments',
                                    'query_fragments', 'query_fragment_fraction'],
}
MAX_BLANK_FRACTION = 0.01


def check(path, columns):
    problems, rows = [], 0
    blank = {c: 0 for c in columns}
    with open(path, newline='', encoding='utf-8', errors='replace') as f:
        reader = csv.DictReader(f, delimiter='\t')
        absent = [c for c in columns if c not in (reader.fieldnames or [])]
        if absent:
            return [f'{os.path.basename(path)}: columns missing: {", ".join(absent)}']
        for row in reader:
            rows += 1
            for c in columns:
                if (row.get(c) or '').strip() in ('', 'NA'):
                    blank[c] += 1
    if rows:
        for c, n in blank.items():
            if n / rows > MAX_BLANK_FRACTION:
                problems.append(f'{os.path.basename(path)}: {n}/{rows} rows have a blank "{c}"')
    return problems


def main():
    p = argparse.ArgumentParser()
    p.add_argument('tables_dir')
    a = p.parse_args()
    problems = []
    for name, cols in REQUIRED.items():
        path = os.path.join(a.tables_dir, name)
        if os.path.exists(path):
            problems += check(path, cols)
    if problems:
        sys.exit('validate_tables.py FAILED:\n  ' + '\n  '.join(problems))
    print('validate_tables.py: key columns are filled in', a.tables_dir)


if __name__ == '__main__':
    main()
