#!/usr/bin/env python3
"""Build the downstream manifest from published MAGFlow summary, MAG and annotation outputs."""
import argparse
import csv
import sys
from collections import Counter
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
            mag_dir = base / f'{mag}_{tool}'
            expected = mag_dir / f'{mag}.faa'
            if expected.is_file():
                return expected
            # Prokka may use a generated locus tag as the FAA filename
            # (for example, 0_prokka/PROKKA_09252026.faa). The enclosing
            # per-MAG directory still provides an unambiguous association.
            if mag_dir.is_dir():
                faa_files = sorted(mag_dir.glob('*.faa'))
                if len(faa_files) == 1:
                    return faa_files[0]
                if len(faa_files) > 1:
                    return None
        matches = sorted(base.rglob(f'{mag}.faa'))
        if len(matches) == 1:
            return matches[0]
    return None


def stable_participant_id(participant, visit):
    """Remove a visit suffix when metadata embeds the visit in the ID."""
    suffix = f'_{visit}' if visit else ''
    if suffix and participant.endswith(suffix):
        return participant[:-len(suffix)]
    return participant


def manifest_rows(path):
    with path.open(newline='', encoding='utf-8') as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


def record_key(row):
    return (row['sample'], row['mag_id'])


def record_signature(row):
    # File size and mtime catch updated MAG/protein files without checksumming
    # the full 40+ GB sequence collection on every manifest refresh.
    fields = ('participant_id', 'visit', 'species', 'mag_fasta', 'protein_fasta',
              'mag_size_bytes', 'mag_mtime_ns', 'protein_size_bytes', 'protein_mtime_ns')
    return tuple(row.get(field, '') for field in fields)


def write_manifest(path, header, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results-dir', required=True, type=Path,
                        help='Existing MAGFlow_results directory with 06_dastool, 09_summary and 10_bakta/10_prokka.')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--previous-manifest', type=Path,
                        help='Manifest successfully processed in earlier downstream batches.')
    parser.add_argument('--new-output', type=Path,
                        help='Write only new or changed MAG records here; requires --previous-manifest.')
    args = parser.parse_args()
    if bool(args.previous_manifest) != bool(args.new_output):
        die('--previous-manifest and --new-output must be supplied together.')
    root = args.results_dir.resolve()
    summaries = sorted((root / '09_summary').rglob('mag_summary.tsv'))
    if not summaries:
        die(f'No 09_summary/**/mag_summary.tsv files under {root}')

    header = ['sample', 'participant_id', 'visit', 'mag_id', 'species', 'mag_fasta', 'protein_fasta',
              'mag_size_bytes', 'mag_mtime_ns', 'protein_size_bytes', 'protein_mtime_ns']
    rows, missing = [], []
    for summary in summaries:
        with summary.open(newline='', encoding='utf-8') as handle:
            reader = csv.DictReader(handle, delimiter='\t')
            required = {'sample', 'participant_id', 'visit', 'mag_id', 'species'}
            if not required.issubset(reader.fieldnames or []):
                die(f'{summary} needs columns: {", ".join(sorted(required))}')
            for row in reader:
                sample, mag = row['sample'].strip(), row['mag_id'].strip()
                participant = row['participant_id'].strip()
                visit = row['visit'].strip()
                fasta = find_mag(root, sample, mag)
                protein = find_proteins(root, sample, mag)
                # Some older Prokka summary-generation runs can include the
                # annotation's generated locus tag as a row, even though it
                # is not a DASTool MAG. Keep the DASTool MAG as the unit of
                # analysis and omit only this recognizable annotation-only row.
                if fasta is None and mag.startswith('PROKKA_') and protein is not None:
                    continue
                if fasta is None or protein is None:
                    missing.append(f'{sample}/{mag}: MAG={fasta or "missing"}, protein={protein or "missing"}')
                    continue
                species = row.get('species', '').strip() or 'NA'
                fasta_stat, protein_stat = fasta.stat(), protein.stat()
                rows.append([sample, stable_participant_id(participant, visit), visit, mag,
                             species, str(fasta), str(protein), str(fasta_stat.st_size),
                             str(fasta_stat.st_mtime_ns), str(protein_stat.st_size),
                             str(protein_stat.st_mtime_ns)])

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

    full_rows = [dict(zip(header, row)) for row in rows]
    write_manifest(args.output, header, rows)
    print(f'Wrote complete manifest: {len(rows)} MAG records to {args.output}')
    report_counts(full_rows, 'Current full cohort')

    if args.new_output:
        previous = {}
        if args.previous_manifest.exists():
            for old_row in manifest_rows(args.previous_manifest):
                previous[record_key(old_row)] = old_row
        pending = [row for row in full_rows
                   if record_key(row) not in previous
                   or record_signature(row) != record_signature(previous[record_key(row)])]
        pending_rows = [[row.get(column, '') for column in header] for row in pending]
        write_manifest(args.new_output, header, pending_rows)
        print(f'Wrote pending manifest: {len(pending)} new or changed MAG records to {args.new_output}')
        report_counts(pending, 'Pending batch')


def report_counts(rows, label):
    sample_visits = {(row['sample'], row['participant_id'], row['visit']) for row in rows}
    participants = {row['participant_id'] for row in rows}
    participants_by_visit = Counter((row['visit'], row['participant_id']) for row in rows)
    print(f'{label} sample visits: {len(sample_visits)}')
    print(f'{label} participants: {len(participants)}')
    print('Visit\tSample visits\tParticipants')
    for visit in sorted({row['visit'] for row in rows}):
        sample_count = sum(1 for sample, participant, current_visit in sample_visits
                          if current_visit == visit)
        participant_count = sum(1 for current_visit, participant in participants_by_visit
                                if current_visit == visit)
        print(f'{visit}\t{sample_count}\t{participant_count}')


if __name__ == '__main__':
    main()
