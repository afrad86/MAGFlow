#!/usr/bin/env python3
"""Write eggNOG-mapper's gene annotations with CATI sample/MAG identifiers."""
import argparse
import csv


OUTPUT_FIELDS = ['sample', 'participant_id', 'visit', 'mag_id', 'gene_id', 'seed_ortholog',
                 'evalue', 'score', 'eggNOG_OGs', 'max_annotated_level', 'COG_category',
                 'description', 'preferred_name', 'GO_terms', 'EC_number', 'KEGG_ko',
                 'KEGG_pathway', 'KEGG_module', 'KEGG_reaction', 'KEGG_rclass', 'BRITE',
                 'KEGG_TC', 'CAZy', 'BiGG_reaction', 'PFAMs']
MAP = {
    'query_name': 'gene_id', 'seed_ortholog': 'seed_ortholog', 'evalue': 'evalue',
    'score': 'score', 'eggNOG_OGs': 'eggNOG_OGs', 'max_annot_lvl': 'max_annotated_level',
    'COG_category': 'COG_category', 'Description': 'description', 'Preferred_name': 'preferred_name',
    'GOs': 'GO_terms', 'EC': 'EC_number', 'KEGG_ko': 'KEGG_ko', 'KEGG_Pathway': 'KEGG_pathway',
    'KEGG_Module': 'KEGG_module', 'KEGG_Reaction': 'KEGG_reaction', 'KEGG_rclass': 'KEGG_rclass',
    'BRITE': 'BRITE', 'KEGG_TC': 'KEGG_TC', 'CAZy': 'CAZy', 'BiGG_Reaction': 'BiGG_reaction',
    'PFAMs': 'PFAMs',
}


def main():
    p = argparse.ArgumentParser()
    for name in ('input', 'output', 'sample', 'participant', 'visit', 'mag'):
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    with open(a.input) as src:
        lines = src.readlines()
    header_at = next((i for i, line in enumerate(lines) if line.startswith('#query_name\t')), None)
    with open(a.output, 'w', newline='') as dst:
        writer = csv.DictWriter(dst, fieldnames=OUTPUT_FIELDS, delimiter='\t', lineterminator='\n')
        writer.writeheader()
        if header_at is None:
            return
        headers = lines[header_at].lstrip('#').rstrip('\r\n').split('\t')
        reader = csv.DictReader(lines[header_at + 1:], fieldnames=headers, delimiter='\t')
        for row in reader:
            if not row.get('query_name') or row['query_name'].startswith('#'):
                continue
            output = {'sample': a.sample, 'participant_id': a.participant,
                      'visit': a.visit, 'mag_id': a.mag}
            output.update({target: row.get(source, '') or '' for source, target in MAP.items()})
            writer.writerow(output)


if __name__ == '__main__':
    main()
