# MAGFlow

MAGFlow is a Nextflow DSL2 workflow for processing paired-end Illumina metagenomic reads. It produces read-level taxonomic profiles, metagenome-assembled genomes (MAGs), MAG quality, taxonomy and annotation, and MAG abundance tables. The main workflow is `main.nf`; its stages are composed from reusable modules under `modules/` and `subworkflows/`.

This README describes the Farm22 production revision of the workflow, which processed the CATI stool metagenomes. The CATI AMR, virulence, functional and longitudinal genome-comparison analyses are a **separate downstream workflow** that consumes MAGFlow results and is not part of `main.nf`. It lives in the `downstream/` folder of the GitHub `main` branch (checked out on Farm22 as `~/pipelines/MAGFlow-downstream-cati`) and is documented in that README.

## Workflow

```text
Paired FASTQ + metadata
        │
        ├── fastp quality control and trimming
        ├── Bowtie2 host-read removal (Samtools)
        │        │
        │        ├── Kraken2 read classification ── Bracken (species level)
        │        │
        │        └── metaSPAdes assembly
        │               ├── Bowtie2 contig indexing and read mapping
        │               ├── MetaBAT2 ─┐
        │               ├── CONCOCT ──┼── DAS Tool MAG selection
        │               └── MaxBin2 ──┘
        │                              ├── CheckM2 quality assessment
        │                              ├── GTDB-Tk taxonomy
        │                              ├── Prokka MAG annotation
        │                              ├── CoverM abundance estimation
        │                              └── MAG summary table
```

Kraken2 and Bracken run on the host-removed reads in parallel with assembly. They are not part of the MAG summary table.

The workflow accepts the visit labels in `params.valid_visits` (default `D1`, `M1`, `M2`, `M4`, `M6`, `M12`, `M24`, `M36`; case-insensitive, normalised to uppercase). Add labels in `nextflow.config` or pass `--valid_visits`; a label outside the list stops the run with a message naming the allowed values.

## Input metadata

The default metadata file is `input/metadata.csv`. It must be a CSV with a `sample` column. `participant_id`, `visit`, `r1` and `r2` are optional.

```csv
sample,r1,r2,participant_id,visit
51448#107,51448#107_1.fastq.gz,51448#107_2.fastq.gz,P001,D1
51448#108,/data/fastq/51448#108_R1.fastq.gz,/data/fastq/51448#108_R2.fastq.gz,P001,M1
```

FASTQ paths in `r1` and `r2` may be absolute or relative to `params.fastq_dir`. Supply both columns together. If both are omitted, MAGFlow looks for `${sample}_1.fastq.gz` and `${sample}_2.fastq.gz` under `params.fastq_dir`. `participant_id` defaults to `sample`; an omitted visit is left blank. Keep the same participant ID across visits when you want participant-level longitudinal summaries downstream.

## Configure paths and references

Site-specific defaults are set in `nextflow.config` and `conf/references.config`. The current Farm22 values are:

| Setting | Value |
| --- | --- |
| `params.metadata` | `input/metadata.csv` |
| `params.fastq_dir` | `/data/pam/ha7g/scratch/projects/metagenomics/CATI/fastq` |
| `params.scratch` (work directory root) | `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_work` (override with `NXF_WORK`) |
| `params.outdir` | `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_results` (override with `MAGFLOW_OUTDIR`) |
| `params.kraken2_db` | `/data/pam/ha7g/scratch/databases/kraken2_standard` |
| `params.reference_host` (Bowtie2 index prefix) | `/lustre/scratch124/pam/teams/team216/shared/references/genomes/human/GRCh38/bowtie2/GRCh38_noalt_as` |

The host Bowtie2 index is a shared group resource in `team216/shared`; leave it in place. MAGFlow checks that all six `.bt2` index files exist before starting. Bracken is run with read length 150 and species level (`-r 150 -l S`), set in `modules/taxonomy/bracken.nf`. The Kraken2 database must contain the matching `database150mers.kmer_distrib` file; it does.

## Run on Farm22

```bash
cd ~/pipelines/MAGFlow
bsub < submit_nextflow.sh
```

`submit_nextflow.sh` loads the Farm22 environment and Java, records the run information and Git commit, and launches `main.nf` with the `farm22` profile and `-resume`. `resume_nextflow.sh` is a resume-specific launcher. Both write LSF output and the Nextflow report, trace, timeline and DAG files to `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/`. The driver job requests the `basement` queue; the workflow submits the individual analysis tasks to LSF using `conf/farm22.config`.

Useful monitoring commands:

```bash
bjobs
tail -f /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/nextflow.<JOB_ID>.out
python3 utils/magflow_status.py
```

### Resume and cache

Keep both the Nextflow cache (`~/pipelines/MAGFlow/.nextflow/cache/`) and the work directory (`MAGFlow_work/`) if a run may be resumed. `-resume` reuses completed tasks only when their inputs, commands, configuration and staged scripts match. Do not clear the work directory before a resume, and do not edit module scripts or `task.cpus` of finished processes, because that changes their task hashes.

## Results

```text
MAGFlow_results/
├── 00_pipeline_info/
├── 01_fastp/
├── 02_host_removal/      reads/, logs/, metrics/
├── 03_assembly/          contigs/, graphs/, reports/
├── 04_mapping/           index/, bam/, bai/, logs/, reports/
├── 05_binning/           metabat2/, concoct/, maxbin2/
├── 06_dastool/
├── 07_checkm2/
├── 08_gtdbtk/
├── 09_summary/
├── 10_prokka/
├── 11_abundance/
├── 12_kraken2/
└── 13_bracken/
```

The downstream workflow adds `14_amrfinderplus/`, `15_vfdb/`, `16_eggnog/`, `17_fastani/` and `18_summary/` to the same root. The per-sample `mag_summary.tsv` in `09_summary` combines CheckM2 quality, GTDB-Tk taxonomy, annotation and normalised CoverM abundance. Nextflow's intermediate task files are in `MAGFlow_work`, not in the results tree. Large intermediate outputs such as BAM files and host-removed reads may be removed after a study is complete; keep contigs, bins, DAS Tool results and summaries.

## Software, environments and resources

Most tools are loaded as Farm22 modules in `conf/farm22.config`. Two processes use named Conda environments under `/data/pam/ha7g/scratch/conda_envs/`:

| Process | Environment | Contains |
| --- | --- | --- |
| MAXBIN2 | `magflow-binning` | MaxBin2 (`run_MaxBin.pl`), MetaBAT2, CONCOCT, DAS Tool, Bowtie2, Samtools |
| COVERM | `coverm` | CoverM, Samtools, minimap2, BWA |

Only MaxBin2 and CoverM are used from those environments; the other tools come from modules (DAS Tool and its helper scripts come from the `das_tool` module). Conda environments are not relocatable. If their location changes, recreate each one at its final path from an explicit package list:

```bash
conda list -p /old/path/ENV --explicit > ENV.txt
conda create -p /data/pam/ha7g/scratch/conda_envs/ENV --file ENV.txt
```

| Process | CPUs | Memory | Wall time | Software |
| --- | ---: | ---: | ---: | --- |
| FASTP | 8 | 8 GB | 1 h | fastp 0.23.4 |
| BOWTIE2_HOST_REMOVAL | 16 | 48 GB | 4 h | Bowtie2 2.5.1, Samtools 1.21 |
| BOWTIE2_BUILD_INDEX | 4 | 8 GB | 2 h | Bowtie2 2.5.1 |
| BOWTIE2_MAP | 16 | 48 GB | 6 h | Bowtie2 2.5.1, Samtools 1.21 |
| KRAKEN2 | 16 | 128 GB | 2 h | Kraken2 2.1.2 |
| BRACKEN | 2 | 8 GB | 1 h | Bracken 2.6.2 |
| METASPADES | 32 | 128 GB | 12 h | SPAdes 4.1.0 |
| METABAT2 | 4 | 12 GB | 1 h | MetaBAT2 2.15 |
| CONCOCT | 2 | 16 GB | 6 h | CONCOCT 1.1.0 |
| MAXBIN2 | 16 | 8 GB | 4 h | MaxBin2 (conda) |
| DASTOOL | 16 | 24 GB | 1 h | DAS Tool 1.1.7 |
| CHECKM2 | 16 | 32 GB | 1 h | CheckM2 1.0.1 |
| GTDBTK | 4 | 256 GB | 4 h | GTDB-Tk 2.7.1 |
| PROKKA | 8 | 24 GB | 6 h | Prokka 1.14.5 |
| COVERM | 8 | 16 GB | 4 h | CoverM (conda) |

A failed task is retried twice and then skipped (`errorStrategy` in `conf/farm22.config`), so one failing sample does not stop the others. The heavy steps (host removal, mapping, Kraken2, metaSPAdes, CheckM2, Prokka) get 1.5x memory and wall time on the retry; GTDB-Tk keeps its memory and gets 1.5x wall time. List skipped tasks after a run with `python3 ~/pipelines/MAGFlow-downstream-cati/downstream/scripts/check_trace_failures.py <trace file>`.

Update module names, environment paths, queues and resources in `conf/farm22.config` when the cluster installation changes.

## Repository layout

```text
main.nf                 Main DSL2 workflow
nextflow.config         Parameters, default paths, profiles, workDir, trace settings
conf/                   Farm22 and reference configuration
modules/                Individual Nextflow processes
subworkflows/           Composed workflow stages
bin/                    Helper scripts made available to pipeline tasks
scripts/                Housekeeping scripts (for example cleanup_batch.sh)
utils/magflow_status.py Farm22 trace-based status dashboard
submit_nextflow.sh      LSF launcher
resume_nextflow.sh      LSF resume launcher
```

## Author

Hassan Afrad — https://github.com/afrad86
