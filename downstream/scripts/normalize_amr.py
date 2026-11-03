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


# Each logical field must be matched by at least one of these raw AMRFinderPlus headers.
# AMRFinderPlus renames columns between major versions, so an unmatched field means the
# normalizer is out of date and must fail loudly instead of writing empty columns.
REQUIRED = {
    'gene_symbol': ('Element symbol', 'Gene symbol'),
    'element_type': ('Type', 'Element type'),
    'class': ('Class',),
    'method': ('Method',),
    'identity_percent': ('% Identity to reference', '% Identity to reference sequence', '% Identity'),
    'coverage_percent': ('% Coverage of reference', '% Coverage of reference sequence', '% Coverage'),
    'accession': ('Closest reference accession', 'Accession of closest sequence', 'Accession'),
}


def check_headers(fieldnames):
    present = {key(k) for k in fieldnames if k is not None}
    missing = [f for f, names in REQUIRED.items() if not any(key(n) in present for n in names)]
    if missing:
        raise SystemExit('normalize_amr.py: AMRFinderPlus columns not recognised for %s. '
                         'Raw headers: %s. Update REQUIRED/aliases for the installed AMRFinderPlus version.'
                         % (', '.join(missing), list(fieldnames)))


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
        if reader.fieldnames:
            check_headers(reader.fieldnames)
        for row in reader:
            if not value(row, 'Element symbol', 'Gene symbol'):
                raise SystemExit('normalize_amr.py: hit without a gene symbol in %s' % a.input)
            writer.writerow({
                'sample': a.sample, 'participant_id': a.participant, 'visit': a.visit, 'mag_id': a.mag,
                'gene_symbol': value(row, 'Element symbol', 'Gene symbol'),
                'element_type': value(row, 'Type', 'Element type'),
                'element_subtype': value(row, 'Subtype', 'Element subtype'),
                'class': value(row, 'Class'), 'subclass': value(row, 'Subclass'),
                'method': value(row, 'Method'),
                'target_sequence': value(row, 'Element name', 'Sequence name', 'Target sequence name'),
                'target_length': value(row, 'Target length'),
                'reference_length': value(row, 'Reference sequence length'),
                'identity_percent': value(row, '% Identity to reference', '% Identity to reference sequence', '% Identity'),
                'coverage_percent': value(row, '% Coverage of reference', '% Coverage of reference sequence', '% Coverage'),
                'accession': value(row, 'Closest reference accession', 'Accession of closest sequence', 'Accession'),
                'product': value(row, 'Closest reference name', 'Name of closest sequence', 'Product'),
                'contig_id': value(row, 'Contig id'), 'start': value(row, 'Start'),
                'stop': value(row, 'Stop'), 'strand': value(row, 'Strand'),
            })


if __name__ == '__main__':
    main()
