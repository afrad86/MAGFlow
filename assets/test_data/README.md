# MAGFlow Development Test Dataset

This directory contains sample sheets and documentation for the MAGFlow development datasets.

The FASTQ files are intentionally **not** stored in the Git repository. They are stored on the Farm22 shared filesystem.

## Original dataset

- Source: ENA
- Run accession: ERR2738830
- Platform: Illumina
- Data type: Human gut shotgun metagenome (paired-end)

## FASTQ location

/lustre/scratch124/pam/teams/team216/shared/MAGFlow_test_data/

## Current development dataset

Sample sheet:

MAGFlow_test_100k.csv

FASTQ files:

- MAGFlow_test_100k_R1.fastq.gz
- MAGFlow_test_100k_R2.fastq.gz

Location:

/lustre/scratch124/pam/teams/team216/shared/MAGFlow_test_data/subsets/100k/

Generation method:

- Tool: seqtk v1.3
- Random seed: 100
- Read pairs: 100,000

This dataset is intended for rapid MAGFlow development and debugging.
