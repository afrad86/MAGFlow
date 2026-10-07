#!/usr/bin/env python3
"""Merge one completed batch into cumulative CATI feature tables."""
import argparse
import csv
import os
import tempfile
from pathlib import Path


TABLES = {
    'amr_features.tsv': 'mag',
    'virulence_features.tsv': 'mag',
    'functional_annotations.tsv': 'mag',
    'strain_pairwise_fastani.tsv': 'strain',
}


def read_header(path):
    if not path.is_file():
        return None
    with path.open(newline='', encoding='utf-8') as handle:
        return next(csv.reader(handle, delimiter='\t'), None)


def read_pending_keys(path):
    with path.open(newline='', encoding='utf-8') as handle:
        reader = csv.DictReader(handle, delimiter='\t')
        required = {'sample', 'mag_id'}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f'{path} must contain sample and mag_id columns')
        return {(row['sample'], row['mag_id']) for row in reader}


def touches_pending(row, kind, pending):
    if kind == 'mag':
        return (row.get('sample', ''), row.get('mag_id', '')) in pending
    return (
        (row.get('query_sample', ''), row.get('query_mag_id', '')) in pending
        or (row.get('reference_sample', ''), row.get('reference_mag_id', '')) in pending
    )


def merge_table(name, kind, previous_dir, batch_dir, output_dir, pending):
    previous_path = previous_dir / name
    batch_path = batch_dir / name
    previous_header = read_header(previous_path)
    batch_header = read_header(batch_path)
    if batch_header is None:
        raise FileNotFoundError(f'Batch table not found: {batch_path}')
    if previous_header is not None and previous_header != batch_header:
        raise ValueError(f'Column mismatch between previous and batch {name}')

    output_path = output_dir / name
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rows_written = 0
    with tempfile.NamedTemporaryFile('w', newline='', encoding='utf-8',
                                     dir=output_path.parent, delete=False) as handle:
        writer = csv.DictWriter(handle, fieldnames=batch_header, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        if previous_header is not None:
            with previous_path.open(newline='', encoding='utf-8') as previous_handle:
                for row in csv.DictReader(previous_handle, delimiter='\t'):
                    if not touches_pending(row, kind, pending):
                        writer.writerow(row)
                        rows_written += 1
        with batch_path.open(newline='', encoding='utf-8') as batch_handle:
            for row in csv.DictReader(batch_handle, delimiter='\t'):
                writer.writerow(row)
                rows_written += 1
        temporary = Path(handle.name)
    os.replace(temporary, output_path)
    print(f'{name}: {rows_written} rows')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--previous-dir', required=True, type=Path,
                        help='Cumulative tables directory; it may not exist on the initial batch.')
    parser.add_argument('--batch-dir', required=True, type=Path,
                        help='tables/ directory from the completed downstream batch output.')
    parser.add_argument('--pending-manifest', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path,
                        help='Destination for updated cumulative tables.')
    args = parser.parse_args()
    pending = read_pending_keys(args.pending_manifest)
    if not pending:
        raise ValueError('Pending manifest contains no MAG records; nothing to merge.')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, kind in TABLES.items():
        merge_table(name, kind, args.previous_dir, args.batch_dir, args.output_dir, pending)


if __name__ == '__main__':
    main()
