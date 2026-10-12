#!/usr/bin/env python3
"""Select all MAG records belonging to sample IDs listed one per line."""
import argparse
import csv
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--samples', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()

    selected = []
    for line in args.samples.read_text(encoding='utf-8').splitlines():
        sample = line.strip()
        if sample and not sample.startswith('#'):
            selected.append(sample)
    sample_ids = set(selected)
    if not sample_ids:
        parser.error(f'no sample IDs found in {args.samples}')
    if len(sample_ids) != len(selected):
        parser.error(f'duplicate sample IDs in {args.samples}')

    with args.manifest.open(newline='', encoding='utf-8') as handle:
        reader = csv.DictReader(handle, delimiter='\t')
        if not reader.fieldnames or 'sample' not in reader.fieldnames:
            parser.error(f'{args.manifest} has no sample column')
        rows = list(reader)
        header = reader.fieldnames

    available = {row['sample'] for row in rows}
    missing = sorted(sample_ids - available)
    if missing:
        parser.error('sample IDs absent from current MAGFlow inventory: ' + ', '.join(missing))
    chosen = [row for row in rows if row['sample'] in sample_ids]
    if not chosen:
        parser.error('selection produced no MAG records')

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=header, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        writer.writerows(chosen)
    print(f'Selected sample visits: {len({row["sample"] for row in chosen})}')
    print(f'Selected MAG records: {len(chosen)}')
    print(f'Wrote smoke manifest: {args.output}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, csv.Error) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        raise SystemExit(2)
