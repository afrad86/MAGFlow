# MAGFlow

MAGFlow is a Nextflow DSL2 workflow for processing paired-end Illumina metagenomic reads and producing metagenome-assembled genomes (MAGs), MAG annotations, taxonomy, quality estimates, and abundance tables. The main workflow is `main.nf`; its stages are composed from reusable modules under `modules/` and `subworkflows/`.

The CATI AMR, virulence, functional, and longitudinal genome-comparison analyses are a **separate downstream workflow**. They consume MAGFlow outputs and do not run as part of `main.nf`. See [CATI downstream analyses](#cati-downstream-analyses) below.

## Workflow

```text
Paired FASTQ + metadata
        │
        ├── fastp quality control and trimming
        ├── Bowtie2 host-read removal (Samtools)
        ├── metaSPAdes assembly
        ├── Bowtie2 contig indexing and read mapping
        ├── MetaBAT2 ─┐
        ├── CONCOCT ──┼── DAS Tool MAG selection
        └── MaxBin2 ──┘
                       ├── CheckM2 quality assessment
                       ├── GTDB-Tk taxonomy
                       ├── Bakta MAG annotation
                       ├── CoverM abundance estimation
                       └── MAG summary table
```

The selected assembler is currently `metaspades`. The main workflow accepts visit labels `D1`, `M1`, `M2`, `M4`, and `M6` (case-insensitive; values are normalized to uppercase). Other visit labels, including M12 and M24, currently require updating the validation list in `main.nf` before those rows can run.

## Input metadata

The default metadata file is `input/metadata.csv`. It must be a CSV with a `sample` column. `participant_id`, `visit`, `r1`, and `r2` are optional.

```csv
sample,r1,r2,participant_id,visit
51448#107,51448#107_1.fastq.gz,51448#107_2.fastq.gz,P001,D1
51448#108,/data/fastq/51448#108_R1.fastq.gz,/data/fastq/51448#108_R2.fastq.gz,P001,M1
```

FASTQ paths in `r1` and `r2` may be absolute or relative to `params.fastq_dir`. Supply both columns together. If both are omitted, MAGFlow looks for `${sample}_1.fastq.gz` and `${sample}_2.fastq.gz` under `params.fastq_dir`. `participant_id` defaults to `sample`; an omitted visit is left blank. Preserve the same participant ID across visits when you want participant-level longitudinal summaries downstream.

## Configure paths and references

Before a run, set the site-specific paths in `nextflow.config`:

```groovy
params {
    metadata  = 'input/metadata.csv'
    fastq_dir = '/path/to/paired_fastq_files'
    scratch   = '/path/to/scratch/allocation'
    outdir    = "${params.scratch}/MAGFlow_results"
}
```

Set `reference_root` and `reference_host` in `conf/references.config` to the host Bowtie2 index prefix available on the cluster. MAGFlow checks for all six `.bt2` index files before starting. The `submit_nextflow.sh` wrapper sets `OUTDIR` to `results/` by default and passes it as `--outdir`; set `OUTDIR` when you want results elsewhere. `params.scratch` controls the Nextflow work directory (`${params.scratch}/MAGFlow_work`).

For Farm22, `conf/farm22.config` selects LSF and loads the cluster software modules and named Conda environments. Its current default task queue is `long`; the `submit_nextflow.sh` driver itself is submitted to `basement`.

## Run on Farm22

From the MAGFlow checkout on Farm22:

```bash
cd ~/pipelines/MAGFlow
mkdir -p logs
export OUTDIR=/path/to/MAGFlow_results
bsub < submit_nextflow.sh
```

The wrapper loads the Farm22 environment and Java, records the run information and Git commit, and launches `main.nf` with the `farm22` profile and `-resume`. It writes LSF stdout/stderr and Nextflow report files under `logs/`. The driver job requests the `basement` queue; the workflow submits individual analysis tasks to LSF using the process settings in `conf/farm22.config`.

Useful monitoring commands:

```bash
bjobs
tail -f logs/nextflow.<JOB_ID>.out
python3 utils/magflow_status.py
```

The status dashboard reads the latest `trace_*.txt` from `~/pipelines/MAGFlow/logs/`. The run also writes an HTML report, trace, timeline, and DAG into `logs/`.

### Resume and cache

The wrapper always enables `-resume`. Keep both the Nextflow cache and work directory if a run may be resumed:

* Cache: `~/pipelines/MAGFlow/.nextflow/cache/` (default for this launch directory)
* Task work files: `${params.scratch}/MAGFlow_work/`

`-resume` reuses completed tasks only when their input, command, configuration, and software-related task hashes match. Do not remove the cache or work directory before resuming.

## Results

The core workflow publishes results under `params.outdir` (set by `OUTDIR` in the Farm22 wrapper). The standalone CATI downstream workflow writes its results under the same `MAGFlow_results/` root, using stages 14–18:

```text
MAGFlow_results/
├── 00_pipeline_info/
├── 01_fastp/
├── 02_host_removal/
│   ├── reads/
│   ├── logs/
│   └── metrics/
├── 03_assembly/
│   ├── contigs/
│   ├── scaffolds/
│   ├── graphs/
│   └── reports/
├── 04_mapping/
│   ├── index/
│   ├── bam/
│   ├── bai/
│   ├── logs/
│   └── reports/
├── 05_binning/
│   ├── metabat2/
│   ├── concoct/
│   └── maxbin2/
├── 06_dastool/
├── 07_checkm2/
├── 08_gtdbtk/
├── 09_summary/
├── 10_bakta/
├── 11_abundance/
├── 12_kraken2/                     # present in the deployed CATI results
├── 13_bracken/                     # present in the deployed CATI results
├── 14_amrfinderplus/<batch_id>/    # downstream
├── 15_vfdb/<batch_id>/             # downstream
├── 16_eggnog/<batch_id>/           # downstream
├── 17_fastani/<batch_id>/          # downstream
└── 18_summary/
    ├── batches/<batch_id>/
    └── cumulative/
```

Stages 12–13 are shown because they are present in the deployed CATI `MAGFlow_results` directory; they are not invoked by `main.nf` in this Git checkout. Stages 14–18 are written by the separate downstream workflow described below. The core summary stage creates `mag_summary.tsv` per sample by combining CheckM2 quality, GTDB-Tk taxonomy, Bakta annotation, and normalized CoverM abundance. Detailed tool results remain in their numbered stage directories. Nextflow's intermediate task files are in `MAGFlow_work`, not in the published results tree.

## CATI downstream analyses

The CATI feature analyses were added later as an **independent Nextflow DSL2 workflow** in `downstream/`. They read MAGFlow results and do not rerun or alter the core `main.nf` workflow. The downstream workflow has its own `main.nf`, configuration, modules, LSF launchers, state, work directory, and Nextflow cache.

| Analysis | Tool and input | Result |
| --- | --- | --- |
| Antimicrobial resistance | NCBI AMRFinderPlus on MAG nucleotide FASTAs | AMR determinants and resistance classes |
| Virulence factors | DIAMOND search of predicted proteins against VFDB Set A | VFDB protein matches with identity, query coverage, and E-value |
| Functional annotation | eggNOG-mapper on predicted proteins | Gene-level ortholog, COG, GO, EC, KEGG, and other available annotations |
| Longitudinal MAG comparison | FastANI on MAG FASTAs, grouped by stable participant ID and GTDB species | Directional genome-pair ANI and matching-fragment support across visits |

AMRFinderPlus detects genetic determinants and does not establish phenotypic antimicrobial resistance. A VFDB homology match does not by itself establish pathogenicity or expression. eggNOG provides gene-level annotation, not gene expression or measured pathway activity. FastANI is a MAG-to-MAG genome-relatedness analysis; it is not a read-level strain-mixture or minor-variant caller. Interpret all results with their evidence fields, MAG quality, and database versions.

### Input manifests and incremental processing

The manifest builder scans `09_summary/**/mag_summary.tsv`, matches MAG FASTAs in `06_dastool`, and resolves predicted proteins from either `10_bakta` or `10_prokka`. It reports MAGs whose input files cannot be matched. The manifest columns are:

| Column | Meaning |
| --- | --- |
| `sample` | Sample/visit identifier |
| `participant_id` | Stable participant identifier used to group longitudinal comparisons |
| `visit` | Visit label, such as D1, M1, M2, or M6 |
| `mag_id` | MAG identifier, unique within a sample |
| `species` | GTDB-Tk species label |
| `mag_fasta` | Existing DAS Tool MAG FASTA path |
| `protein_fasta` | Existing Bakta or Prokka protein FASTA path |

Participant IDs must stay stable across visits. The builder removes a final `_<visit>` suffix from a summary `participant_id` when present; review that the resulting IDs represent the same person across visits. MAGs without a species assignment still receive AMR, VFDB, and eggNOG analyses, but are omitted from FastANI comparisons.

The production Farm22 launcher rebuilds both the complete current inventory and a pending-only manifest before each batch. It compares each `(sample, mag_id)` to the processed checkpoint using input file size and modification time. AMRFinderPlus, VFDB, and eggNOG process only new or changed MAG records. FastANI reads all genomes in participant/species groups containing pending MAGs, but calculates only pairs involving at least one pending MAG; old-to-old pairs are not repeated. An individual AMRFinderPlus, VFDB, eggNOG, or FastANI task failure is ignored by Nextflow so the other analyses continue and partial per-tool outputs can be collated. The launcher checks the completed trace: if any task failed, it does not merge cumulative tables or advance the processed checkpoint. Resubmitting the same batch with `-resume` retries failed tasks and reuses successful cached tasks. Only a failure-free run is finalized. The workflow assumes MAGFlow results are append-only; removed MAGs are not automatically pruned from cumulative results.

The manifest scan does not assume a fixed number of participants, samples, or visit labels. New visits and participants enter the downstream inventory when their MAGFlow summaries and MAG inputs are present. The **current core `main.nf`** still validates visits against D1, M1, M2, M4, and M6, so add future labels there before running the core workflow on M12 or M24 data.

Downstream outputs are kept in the numbered stages after the core MAGFlow results:

```text
MAGFlow_results/
├── 14_amrfinderplus/<batch_id>/
├── 15_vfdb/<batch_id>/
├── 16_eggnog/<batch_id>/
├── 17_fastani/<batch_id>/
└── 18_summary/
    ├── batches/<batch_id>/
    └── cumulative/
```

Each batch keeps per-tool output and normalized batch tables. The cumulative cohort tables under `18_summary/cumulative/` are:

* `amr_features.tsv` — sample, participant, visit, MAG, determinant/class, method, identity/coverage, coordinates, and evidence fields.
* `virulence_features.tsv` — sample, participant, visit, MAG, protein query, VFDB subject, identity, query coverage, E-value, and score.
* `functional_annotations.tsv` — sample, participant, visit, MAG, gene ID, ortholog, COG, GO, EC, KEGG, and other available eggNOG fields.
* `strain_pairwise_fastani.tsv` — participant, species, query/reference sample, visit, MAG, ANI, and matching-fragment support.

AMR, VFDB, and eggNOG outputs retain header-only per-MAG tables when no passing hit is found. A missing feature row means no passing hit was reported; it does not establish biological absence. Downstream task work files, logs, checkpoint state, and Nextflow cache are separate from the core MAGFlow workflow.

The eggNOG normalizer accepts both `#query` and `#query_name` annotation headers. It is staged as a task input, so a normalizer update invalidates old eggNOG task-cache results and regenerates the normalized tables on a resumed run.

### Databases and software

Databases are external, user-managed resources. The workflow does not download or silently update them during an analysis. On Farm22, the launchers currently use:

| Resource | Farm22 location / preparation |
| --- | --- |
| AMRFinderPlus database | `/data/pam/ha7g/scratch/databases/cati_downstream/amrfinderplus/4.2.7/latest`; prepare with `amrfinder_update` using the compatible AMRFinderPlus release. |
| VFDB Set A DIAMOND database | Prefix `/data/pam/ha7g/scratch/databases/cati_downstream/vfdb/VFDB_setA_pro`; build from the protein FASTA with `diamond makedb`. |
| eggNOG-mapper data | `/data/pam/ha7g/scratch/databases/cati_downstream/eggnog`; download data for the selected eggNOG-mapper release and retain its version. |
| FastANI | No external database; comparisons use the supplied MAG FASTAs. |

The downstream environment definitions pin AMRFinderPlus 4.2.7, DIAMOND 2.1.9, eggNOG-mapper 2.1.12, FastANI 1.34, and Python 3.12 for normalization. On Farm22 the pre-created environments are under `/data/pam/ha7g/scratch/conda_envs/`. Keep database snapshots stable during a run and retain their versions and fingerprints with the batch. If a database or analysis parameter changes after a batch has been processed, use a separate analysis series or deliberately reset its state before reprocessing; the processed checkpoint will not automatically make old MAGs pending.

Prepare databases once in locations readable by the Farm22 compute nodes. The generic commands are:

```bash
amrfinder_update -d /path/to/amrfinderplus/data
diamond makedb --in /path/to/VFDB_setA_pro.fas --db /path/to/vfdb/VFDB_setA_pro
download_eggnog_data.py -y --data_dir /path/to/eggnog
```

Use the installed AMRFinderPlus software release to prepare its database. Do not run database downloads or updates as part of an analysis job.

### Farm22 execution, resources, and monitoring

The driver launcher uses the same LSF `#BSUB` directive style as the main MAGFlow launcher and submits the Nextflow driver to `basement` (one CPU, 8 GB, up to 30 days). Nextflow submits tool tasks separately. Downstream task resource requests and software versions are listed in [Farm22 software and resource settings](#farm22-software-and-resource-settings). `normal` is used for tasks under 12 hours; the 24-hour eggNOG and FastANI processes use `long`.

Submit the production run from the standalone downstream checkout:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
bsub < submit_cati_downstream.sh
```

The production launcher rebuilds manifests automatically, chooses or resumes the batch directory, runs Nextflow with `-resume`, and only merges results after a successful analysis. Downstream logs and Nextflow reports are written directly under `MAGFlow_logs/` with `CATI_downstream` filename prefixes; task work files are written directly under `MAGFlow_work/`, matching the core MAGFlow layout. State and checkpoints remain under `CATI_downstream_state/`. The downstream Nextflow cache is `~/pipelines/MAGFlow-downstream-cati/downstream/.nextflow/cache/`. Preserve both cache and work directories for resume. The launcher prevents concurrent smoke and production runs because they share the same cache and work directory.

To validate selected sample visits before a production run, list exact sample IDs (one per line) in `CATI_downstream_smoke_test/sample_ids.txt`, then submit:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
bsub < submit_cati_downstream_smoke_test.sh
```

The smoke test runs **all MAGs for each listed sample ID**, writes into a separate smoke-test results/state area, and does not update the production checkpoint or cumulative tables. Nextflow may reuse tasks only if their complete task hashes match; group-level FastANI tasks may differ between the smoke cohort and full cohort.

Monitor a run with the downstream status dashboard:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
python3 scripts/cati_downstream_status.py
python3 scripts/cati_downstream_status.py --watch 30
```

The dashboard is read-only. For each tool, it reports sample visits as completed, running (at least one MAG/group task is executing), pending (tasks are queued, not yet submitted, or have no trace row), failed, or aborted. These states are counted separately. It also reports LSF RUN/PEND counts. For a smoke run, pass its explicit manifest so expected MAGs are counted correctly:

```bash
python3 scripts/cati_downstream_status.py \
  --root /data/pam/ha7g/scratch/projects/metagenomics/CATI/CATI_downstream_smoke_test \
  --state-dir /data/pam/ha7g/scratch/projects/metagenomics/CATI/CATI_downstream_smoke_test/state \
  --trace /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/trace_CATI_downstream_smoke_JOBID.txt \
  --manifest /data/pam/ha7g/scratch/projects/metagenomics/CATI/CATI_downstream_smoke_test/state/smoke_manifest.tsv
```

The launchers also write per-run Nextflow logs, trace, report, timeline, and DAG directly under `MAGFlow_logs/`, using `CATI_downstream` or `CATI_downstream_smoke` filename prefixes to distinguish them from core MAGFlow logs.

Key parameters are set in `downstream/nextflow.config` or passed to the standalone workflow:

| Parameter | Default | Purpose |
| --- | ---: | --- |
| `--vfdb_min_identity` | 80 | Minimum DIAMOND percent identity |
| `--vfdb_min_query_cover` | 70 | Minimum query protein coverage, percent |
| `--vfdb_evalue` | `1e-10` | DIAMOND E-value cutoff |
| `--eggnog_sensitivity` | `sensitive` | eggNOG-mapper search sensitivity |
| `--eggnog_options` | empty | Additional options supported by the installed eggNOG-mapper version |
| `--amrfinder_organism` | empty | Optional valid NCBI organism group when known |

### FastANI interpretation and limitations

The workflow compares assembled MAGs from the same participant and GTDB species; same-sample comparisons are excluded. Results are directional, so query/reference fragment support can differ. FastANI is not a within-sample haplotype or minor-variant caller. It does not impose a universal ANI threshold for calling strain persistence or replacement. Consider ANI together with matching-fragment fraction, MAG completeness/contamination, and study-specific criteria. A MAG without a contig long enough for FastANI's 3 kb fragments is skipped for that comparison. For read-level strain mixtures or low-abundance strains, a separate read-based workflow such as StrainPhlAn or inStrain is required.

The [downstream folder](downstream/) contains the independent Nextflow entrypoint, launchers, scripts, environments, and example input manifest.

## Farm22 software and resource settings

The core MAGFlow tasks use settings from `conf/farm22.config`; CATI downstream tasks use settings from `downstream/nextflow.config`. The workflows submit separate LSF tasks, while their top-level launchers run in `basement`.

### Core MAGFlow tasks

Core tasks use the `long` queue unless the Farm22 configuration is changed.

| Process | CPUs | Memory | Wall time |
| --- | ---: | ---: | ---: |
| FASTP | 8 | 8 GB | 2 h |
| BOWTIE2_HOST_REMOVAL | 16 | 32 GB | 4 h |
| METASPADES | 16 | 128 GB | 48 h |
| BOWTIE2_BUILD_INDEX / BOWTIE2_MAP | 16 | 32 GB | 24 h |
| METABAT2 | 8 | 8 GB | 2 h |
| CONCOCT | 4 | 8 GB | 8 h |
| MAXBIN2 | 16 | 8 GB | 8 h |
| DASTOOL | 16 | 32 GB | 6 h |
| CHECKM2 | 16 | 32 GB | 2 h |
| GTDBTK | 8 | 128 GB | 6 h |
| BAKTA | 8 | 32 GB | 6 h |
| COVERM | 8 | 16 GB | 4 h |

The Farm22 configuration loads fastp, Bowtie2, Samtools, metaSPAdes, MetaBAT2, CONCOCT, DAS Tool, CheckM2, GTDB-Tk, and Bakta from modules. MaxBin2 and CoverM use the Conda environments configured in that file. Update module names, environment paths, queues, or resources there when the cluster installation changes.

### CATI downstream tasks

The downstream profile uses `normal` for tasks under 12 hours and `long` for the 24-hour eggNOG and FastANI tasks. Memory is requested per LSF task (`perJobMemLimit = true`).

| Process | CPUs | Memory | Wall time | Queue | Software |
| --- | ---: | ---: | ---: | --- | --- |
| AMRFINDER | 8 | 12 GB | 4 h | normal | AMRFinderPlus 4.2.7 |
| VFDB_SEARCH | 8 | 12 GB | 4 h | normal | DIAMOND 2.1.9; VFDB Set A database |
| EGGNOG_ANNOTATE | 16 | 48 GB | 24 h | long | eggNOG-mapper 2.1.12 |
| STRAIN_FASTANI | 16 | 24 GB | 24 h | long | FastANI 1.34 |
| COLLATE_FEATURES | 2 | 3 GB | 1 h | normal | Python 3.12 |

The CATI driver launcher requests one CPU and 8 GB in `basement` for up to 30 days; individual tool tasks receive the requests shown above. On Farm22, the corresponding Conda environments are under `/data/pam/ha7g/scratch/conda_envs/`. Database files are stored separately under `/data/pam/ha7g/scratch/databases/cati_downstream/` and are not included in the software environments. See [Databases and software](#databases-and-software) for the database paths and preparation notes.

## Repository layout

```text
main.nf                 Main DSL2 workflow
nextflow.config         Parameters, default paths, profiles, workDir, trace settings
conf/                   Farm22, reference, and test-profile configuration
modules/                Individual Nextflow processes
subworkflows/           Composed workflow stages
bin/                    Helper scripts made available to pipeline tasks
utils/magflow_status.py Farm22 trace-based dashboard
submit_nextflow.sh      LSF launcher for the main workflow
downstream/             Independent CATI feature-analysis workflow
```

## Current checkout versus existing result folders

This README describes the `main.nf` and modules in this Git checkout. That entrypoint runs Bakta and does not currently invoke Prokka, Kraken2, or Bracken. If an existing Farm22 `MAGFlow_results` directory contains `10_prokka`, `12_kraken2`, or `13_bracken`, those outputs came from a different pipeline revision or deployment than the main workflow described here. Check that the Farm22 checkout and Git commit match this repository before relying on the directory list as a description of the code being submitted.

The CATI downstream workflow expects MAGFlow summary, MAG FASTA, and predicted protein inputs. Its complete workflow and Farm22 instructions are included in the [CATI downstream analyses](#cati-downstream-analyses) section above.
