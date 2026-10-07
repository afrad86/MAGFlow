#!/usr/bin/env python3
"""Build the downstream manifest from published MAGFlow summary, MAG and annotation outputs."""
import argparse
import csv
import sys
from pathlib import Path


def die(message):
    print(f'ERROR: {message}', file=sys.stderr)
    raise SystemExit(2)


def find_mag(root, sample, mag):
    directory = root / '06_dastool' / f'{sample}_dastool' / f'{sample}_DASTool_bins'
    candidates = [directory / mag]
    if Path(mag).suffix.lower() not in {'.fa', '.fasta', '.fna', '.gz'}:
        candidates.extend(directory / f'{mag}{suffix}' for suffix in ('.fa', '.fasta', '.fna', '.fa.gz', '.fasta.gz', '.fna.gz'))
    return next((p for p in candidates if p.is_file()), None)


def find_proteins(root, sample, mag):
    for stage in ('10_bakta', '10_prokka'):
        base = root / stage / sample
        if not base.is_dir():
            continue
        for tool in ('bakta', 'prokka'):
            expected = base / f'{mag}_{tool}' / f'{mag}.faa'
            if expected.is_file():
                return expected
        matches = sorted(base.rglob(f'{mag}.faa'))
        if len(matches) == 1:
            return matches[0]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results-dir', required=True, type=Path,
                        help='Existing MAGFlow_results directory with 06_dastool, 09_summary and 10_bakta/10_prokka.')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = args.results_dir.resolve()
    summaries = sorted((root / '09_summary').rglob('mag_summary.tsv'))
    if not summaries:
        die(f'No 09_summary/**/mag_summary.tsv files under {root}')

    header = ['sample', 'participant_id', 'visit', 'mag_id', 'species', 'mag_fasta', 'protein_fasta']
    rows, missing = [], []
    for summary in summaries:
        with summary.open(newline='', encoding='utf-8') as handle:
            reader = csv.DictReader(handle, delimiter='\t')
            required = {'sample', 'participant_id', 'visit', 'mag_id', 'species'}
            if not required.issubset(reader.fieldnames or []):
                die(f'{summary} needs columns: {", ".join(sorted(required))}')
            for row in reader:
                sample, mag = row['sample'].strip(), row['mag_id'].strip()
                fasta = find_mag(root, sample, mag)
                protein = find_proteins(root, sample, mag)
                if fasta is None or protein is None:
                    missing.append(f'{sample}/{mag}: MAG={fasta or "missing"}, protein={protein or "missing"}')
                    continue
                species = row.get('species', '').strip() or 'NA'
                rows.append([sample, row['participant_id'].strip(), row['visit'].strip(), mag,
                             species, str(fasta), str(protein)])

    if missing:
        die('Could not match all summary MAGs to published sequence/annotation files:\n  ' + '\n  '.join(missing[:30])
            + (f'\n  ... and {len(missing) - 30} more' if len(missing) > 30 else ''))
    unique = set()
    for row in rows:
        key = (row[0], row[3])
        if key in unique:
            die(f'Duplicate sample/MAG identifier in summaries: {key[0]}/{key[1]}')
        unique.add(key)
    if not rows:
        die('No MAG rows found in the summary tables.')

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)
    print(f'Wrote {len(rows)} MAG records to {args.output}')


if __name__ == '__main__':
    main()
