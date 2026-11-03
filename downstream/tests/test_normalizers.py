"""Run each normalizer on a small example in the current tool output format."""
import csv
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
IDS = ['--sample', 'S1', '--participant', 'P1', '--visit', 'D1', '--mag', '1']

AMR4_HEADER = ['Protein id', 'Contig id', 'Start', 'Stop', 'Strand', 'Element symbol', 'Element name', 'Scope',
               'Type', 'Subtype', 'Class', 'Subclass', 'Method', 'Target length', 'Reference sequence length',
               '% Coverage of reference', '% Identity to reference', 'Alignment length',
               'Closest reference accession', 'Closest reference name', 'HMM accession', 'HMM description']
AMR4_ROW = ['NA', 'NODE_1', '10', '900', '+', 'tet(M)', 'tetracycline resistance', 'core', 'AMR', 'AMR',
            'TETRACYCLINE', 'TETRACYCLINE', 'EXACTX', '300', '300', '100.00', '99.50', '300',
            'WP_000001.1', 'tet protein', 'NA', 'NA']


def write_tsv(path, rows):
    path.write_text('\n'.join('\t'.join(r) for r in rows) + '\n')


def run(script, *args):
    return subprocess.run([sys.executable, str(SCRIPTS / script), *map(str, args)],
                          capture_output=True, text=True)


def read(path):
    return list(csv.DictReader(open(path), delimiter='\t'))


def test_amr_4x_columns_are_filled(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [AMR4_HEADER, AMR4_ROW])
    assert run('normalize_amr.py', '--input', raw, '--output', out, *IDS).returncode == 0
    r = read(out)[0]
    assert (r['gene_symbol'], r['element_type'], r['identity_percent'], r['coverage_percent'],
            r['accession'], r['product']) == ('tet(M)', 'AMR', '99.50', '100.00', 'WP_000001.1', 'tet protein')


def test_amr_old_columns_still_work(tmp_path):
    old = {'Gene symbol': 'tet(M)', 'Element type': 'AMR', 'Class': 'TETRACYCLINE', 'Method': 'EXACTX',
           '% Identity to reference sequence': '99.5', '% Coverage of reference sequence': '100',
           'Accession of closest sequence': 'WP_1', 'Name of closest sequence': 'x'}
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [list(old), list(old.values())])
    assert run('normalize_amr.py', '--input', raw, '--output', out, *IDS).returncode == 0
    assert read(out)[0]['gene_symbol'] == 'tet(M)'


def test_amr_unknown_columns_fail_loudly(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [['Contig id', 'Start', 'Stop', 'Renamed symbol', 'Class', 'Method'],
                    ['NODE_1', '1', '2', 'tet(M)', 'TETRACYCLINE', 'EXACTX']])
    res = run('normalize_amr.py', '--input', raw, '--output', out, *IDS)
    assert res.returncode != 0 and 'not recognised' in res.stderr


def test_amr_header_only_is_fine(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [AMR4_HEADER])
    assert run('normalize_amr.py', '--input', raw, '--output', out, *IDS).returncode == 0
    assert read(out) == []


def test_vfdb_malformed_input_fails(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [['a', 'b', 'c']])
    assert run('normalize_vfdb.py', '--input', raw, '--output', out, *IDS).returncode != 0


def test_vfdb_good_row(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [['g1', 'VF1', '90', '100', '200', '300', '1e-5', '250', 'toxin']])
    assert run('normalize_vfdb.py', '--input', raw, '--output', out, *IDS).returncode == 0
    assert read(out)[0]['query_coverage_percent'] == '50.0000'


def test_eggnog_missing_columns_fail(tmp_path):
    raw, out = tmp_path / 'raw.tsv', tmp_path / 'out.tsv'
    write_tsv(raw, [['#query', 'seed_ortholog'], ['g1', 'x']])
    assert run('normalize_eggnog.py', '--input', raw, '--output', out, *IDS).returncode != 0


def test_validate_tables_catches_blank_columns(tmp_path):
    cols = ['gene_symbol', 'element_type', 'class', 'method', 'identity_percent', 'coverage_percent', 'accession']
    write_tsv(tmp_path / 'amr_features.tsv', [cols, ['', '', 'X', 'Y', '', '', '']])
    res = run('validate_tables.py', tmp_path)
    assert res.returncode != 0 and 'gene_symbol' in res.stderr
    write_tsv(tmp_path / 'amr_features.tsv', [cols, ['a', 'AMR', 'X', 'Y', '1', '2', 'acc']])
    assert run('validate_tables.py', tmp_path).returncode == 0
