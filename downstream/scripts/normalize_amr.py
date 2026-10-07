#!/usr/bin/env python3
"""Normalize AMRFinderPlus output while retaining its evidence fields."""
import argparse
import csv


def key(text):
    return ''.join(ch.lower() for ch in text if ch.isalnum())


def value(row, *names):
    lookup = {key(k): v for k, v in row.items() if k is not None}
    for name in names:
        if key(name) in lookup:
            return lookup[key(name)]
    return ''


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--sample', required=True)
    p.add_argument('--participant', required=True)
    p.add_argument('--visit', required=True)
    p.add_argument('--mag', required=True)
    a = p.parse_args()
    fields = ['sample', 'participant_id', 'visit', 'mag_id', 'gene_symbol', 'element_type',
              'element_subtype', 'class', 'subclass', 'method', 'target_sequence',
              'target_length', 'reference_length', 'identity_percent', 'coverage_percent',
              'accession', 'product', 'contig_id', 'start', 'stop', 'strand']
    with open(a.input, newline='') as src, open(a.output, 'w', newline='') as dst:
        writer = csv.DictWriter(dst, fieldnames=fields, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        reader = csv.DictReader(src, delimiter='\t')
        for row in reader:
            writer.writerow({
                'sample': a.sample, 'participant_id': a.participant, 'visit': a.visit, 'mag_id': a.mag,
                'gene_symbol': value(row, 'Gene symbol'),
                'element_type': value(row, 'Element type'),
                'element_subtype': value(row, 'Element subtype'),
                'class': value(row, 'Class'), 'subclass': value(row, 'Subclass'),
                'method': value(row, 'Method'),
                'target_sequence': value(row, 'Sequence name', 'Target sequence name'),
                'target_length': value(row, 'Target length'),
                'reference_length': value(row, 'Reference sequence length'),
                'identity_percent': value(row, '% Identity to reference sequence', '% Identity'),
                'coverage_percent': value(row, '% Coverage of reference sequence', '% Coverage'),
                'accession': value(row, 'Accession of closest sequence', 'Accession'),
                'product': value(row, 'Name of closest sequence', 'Product'),
                'contig_id': value(row, 'Contig id'), 'start': value(row, 'Start'),
                'stop': value(row, 'Stop'), 'strand': value(row, 'Strand'),
            })


if __name__ == '__main__':
    main()
