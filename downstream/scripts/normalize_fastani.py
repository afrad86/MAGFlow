#!/usr/bin/env python3
"""Convert fastANI all-vs-all output to directional, metadata-rich pair rows."""
import argparse
import csv
import os


def norm(path):
    return os.path.normpath(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--manifest', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--participant', required=True)
    p.add_argument('--species', required=True)
    a = p.parse_args()
    by_path, by_base = {}, {}
    with open(a.manifest, newline='') as src:
        for row in csv.reader(src, delimiter='\t'):
            if len(row) != 4:
                continue
            sample, visit, mag, path = row
            record = {'sample': sample, 'visit': visit, 'mag_id': mag, 'path': path}
            by_path[norm(path)] = record
            by_base.setdefault(os.path.basename(path), []).append(record)
    fields = ['participant_id', 'species', 'query_sample', 'query_visit', 'query_mag_id',
              'reference_sample', 'reference_visit', 'reference_mag_id', 'ani_percent',
              'matching_fragments', 'query_fragments', 'query_fragment_fraction']
    with open(a.output, 'w', newline='') as dst:
        writer = csv.DictWriter(dst, fieldnames=fields, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        if not os.path.exists(a.input):
            return
        with open(a.input, newline='') as src:
            for row in csv.reader(src, delimiter='\t'):
                if len(row) < 5:
                    continue
                query = by_path.get(norm(row[0]))
                reference = by_path.get(norm(row[1]))
                if query is None:
                    matches = by_base.get(os.path.basename(row[0]), [])
                    query = matches[0] if len(matches) == 1 else None
                if reference is None:
                    matches = by_base.get(os.path.basename(row[1]), [])
                    reference = matches[0] if len(matches) == 1 else None
                if query is None or reference is None or query['sample'] == reference['sample']:
                    continue
                matched, total = int(row[3]), int(row[4])
                writer.writerow({
                    'participant_id': a.participant, 'species': a.species,
                    'query_sample': query['sample'], 'query_visit': query['visit'],
                    'query_mag_id': query['mag_id'], 'reference_sample': reference['sample'],
                    'reference_visit': reference['visit'], 'reference_mag_id': reference['mag_id'],
                    'ani_percent': row[2], 'matching_fragments': matched, 'query_fragments': total,
                    'query_fragment_fraction': f'{matched / total:.6f}' if total else '',
                })


if __name__ == '__main__':
    main()
