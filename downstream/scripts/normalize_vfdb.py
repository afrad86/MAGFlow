#!/usr/bin/env python3
"""Normalize VFDB DIAMOND hits; thresholds are applied by DIAMOND before this step."""
import argparse
import csv


def main():
    p = argparse.ArgumentParser()
    for name in ('input', 'output', 'sample', 'participant', 'visit', 'mag'):
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    fields = ['sample', 'participant_id', 'visit', 'mag_id', 'query_gene_id', 'vfdb_subject_id',
              'identity_percent', 'alignment_length', 'query_length', 'subject_length',
              'query_coverage_percent', 'evalue', 'bitscore', 'subject_description']
    with open(a.output, 'w', newline='', encoding='utf-8') as dst:
        writer = csv.DictWriter(dst, fieldnames=fields, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        with open(a.input, newline='', encoding='utf-8', errors='replace') as src:
            seen = written = 0
            for row in csv.reader(src, delimiter='\t'):
                if not row:
                    continue
                seen += 1
                if len(row) < 9:
                    continue
                written += 1
                qlen = float(row[4]) if row[4] else 0.0
                aligned = int(float(row[3])) if row[3] else 0
                writer.writerow({
                    'sample': a.sample, 'participant_id': a.participant, 'visit': a.visit, 'mag_id': a.mag,
                    'query_gene_id': row[0], 'vfdb_subject_id': row[1],
                    'identity_percent': row[2], 'alignment_length': row[3],
                    'query_length': row[4], 'subject_length': row[5],
                    'query_coverage_percent': f'{100.0 * aligned / qlen:.4f}' if qlen else '',
                    'evalue': row[6], 'bitscore': row[7], 'subject_description': row[8],
                })
            if seen and not written:
                raise SystemExit('normalize_vfdb.py: %d input rows but none have the expected 9 columns' % seen)


if __name__ == '__main__':
    main()
