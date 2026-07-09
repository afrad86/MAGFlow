MAGFlow

MAGFlow is a modular Nextflow DSL2 pipeline for reconstructing metagenome-assembled genomes (MAGs) from Illumina paired-end metagenomic sequencing data.

The pipeline is designed for scalability, reproducibility, and execution on HPC clusters using the LSF scheduler. Each analysis stage is implemented as an independent module, allowing components to be developed, tested, and replaced with minimal changes to the overall workflow.

⸻

Features

* Modular Nextflow DSL2 architecture
* Metadata validation before execution
* FASTQ quality control with fastp
* Host read removal using Bowtie2
* Metagenome assembly using metaSPAdes
* Designed for HPC execution with LSF
* Automatic result organisation
* Git version control and GitHub integration

⸻

Pipeline

Raw FASTQ
    │
    ▼
Metadata validation
    │
    ▼
FASTP
    │
    ▼
Host removal (Bowtie2)
    │
    ▼
metaSPAdes
    │
    ▼
Read mapping
    │
    ▼
Coverage estimation
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
 MetaBAT2       MaxBin2       CONCOCT
    └──────────────┴──────────────┘
                 │
                 ▼
              DASTool
                 │
                 ▼
              CheckM2
                 │
                 ▼
              GTDB-Tk
                 │
                 ▼
        MAG abundance estimation

⸻

Current Status

Completed

* Metadata validation
* FASTQ validation
* Visit validation
* Bowtie2 reference validation
* FASTP module
* Bowtie2 host removal module
* metaSPAdes assembly module

Planned

* Read mapping
* Coverage calculation
* MetaBAT2
* MaxBin2
* CONCOCT
* DASTool
* CheckM2
* GTDB-Tk
* MAG abundance estimation

⸻

Project Structure

MAGFlow/
├── assets/
├── conf/
├── input/
├── modules/
│   ├── preprocessing/
│   └── assembly/
├── subworkflows/
├── main.nf
├── nextflow.config
└── submit_nextflow.sh

⸻

Input Metadata

The pipeline expects a CSV metadata file.

Example:

sample,participant_id,visit
51448#107,P001,D1
51448#108,P001,M1
51448#109,P002,D1

Supported visit values:

* D1
* M1
* M2
* M4
* M6

⸻

Running MAGFlow

Submit the pipeline to the LSF scheduler:

bsub < submit_nextflow.sh

⸻

Output Structure

MAGFlow_results/
├── 01_fastp/
├── 02_host_removal/
├── 03_assembly/
├── 04_mapping/
├── 05_metabat2/
├── 06_maxbin2/
├── 07_concoct/
├── 08_dastool/
├── 09_checkm2/
├── 10_gtdbtk/
└── 11_abundance/

⸻

Requirements

* Nextflow
* Java 17+
* fastp
* Bowtie2
* Samtools
* metaSPAdes

Additional software will be incorporated as new modules are added.

⸻

Development Roadmap

Version	Milestone
v0.1.0	Pipeline framework
v0.2.0	FASTP + Host removal + metaSPAdes
v0.3.0	Read mapping
v0.4.0	MetaBAT2
v0.5.0	MaxBin2
v0.6.0	CONCOCT
v0.7.0	DASTool
v0.8.0	CheckM2
v0.9.0	GTDB-Tk
v1.0.0	Stable MAGFlow release

⸻

License

A license will be added before the first stable release.

⸻

Author

Hassan Afrad

GitHub: https://github.com/afrad86