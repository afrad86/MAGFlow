# MAGFlow downstream CATI feature analyses

This is an independent Nextflow DSL2 entrypoint for the four CATI feature-generation analyses. It does not change or invoke the completed `../main.nf` pipeline. Inputs are the existing per-MAG FASTA and predicted protein FASTA from Bakta or Prokka, plus complete-current and pending-only MAG manifests built from MAGFlow outputs. Batch outputs are published under the configured `--outdir`; the Farm22 runner also merges compact cohort tables into a persistent state directory after successful runs.

## Analyses

1. **AMR:** NCBI AMRFinderPlus on the MAG nucleotide sequence. This detects genetic determinants; it does not establish phenotypic resistance.
2. **Virulence:** DIAMOND protein alignment to a user-provided VFDB protein snapshot. The default identity/query-coverage filters are 80%/70%; select and record thresholds before interpreting hits. A homology hit alone does not establish that a MAG is pathogenic or that a factor is expressed.
3. **Function:** eggNOG-mapper annotations for Bakta or Prokka proteins. The output is gene-level annotation, not measured gene expression or pathway abundance. Join `sample`/`mag_id` to existing MAG abundance when constructing sample-level functional summaries.
4. **Longitudinal genome comparison:** FastANI all-vs-all comparisons are limited to MAGs from the same participant and the same supplied GTDB species, with same-sample comparisons removed. Output is directional, retains fragment support, and is intended as genome-relatedness evidence across visits.

## Input manifest

The manifest builder reads `09_summary/**/mag_summary.tsv`, matches MAG FASTAs in `06_dastool`, and resolves protein FASTAs from either `10_bakta` or `10_prokka` (including Prokka files whose basename differs from the MAG ID but are inside that MAG's annotation directory). It stops with a list of any MAGs that cannot be matched. If a summary's `participant_id` ends in `_<visit>` (for example, `CTNH_062_22_2_M6` with visit `M6`), the helper removes that exact suffix so longitudinal comparisons use `CTNH_062_22_2` as the stable participant key. It leaves other participant IDs unchanged. You can also create manifests manually with the exact headers shown in [`input_manifest.example.tsv`](input_manifest.example.tsv); for manual manifests, `participant_id` must be stable across visits:

| Column | Meaning |
| --- | --- |
| `sample` | CATI sample identifier |
| `participant_id` | Stable participant identifier used to scope longitudinal comparisons |
| `visit` | Visit label, for example `D1`, `M1`, `M2`, or `M6` |
| `mag_id` | MAG/bin identifier, unique within a sample |
| `species` | GTDB-Tk species label; comparisons are restricted to identical labels |
| `mag_fasta` | Path to the existing DAS Tool MAG FASTA |
| `protein_fasta` | Path to the existing Bakta or Prokka `.faa` for that MAG |

Use absolute paths, or paths resolvable from the directory where Nextflow is launched. The MAG and protein FASTA paths must refer to the same MAG. To avoid mistaken longitudinal comparisons, do not derive `participant_id` from visit-specific sample IDs; populate it from the CATI manifest. MAGs with unassigned species (`NA`) still receive AMR, virulence and function analyses but are omitted from pairwise genome comparisons.

## Databases and references

All databases are external, user-managed resources; this workflow does not download or silently update them during analysis.

* **AMRFinderPlus:** install the AMRFinderPlus software and prepare a fixed database snapshot with its `amrfinder_update` utility. Pass the resulting database directory as `--amrfinder_db`. Record software/database versions and update date in the run record. [NCBI AMRFinderPlus](https://github.com/ncbi/amr) and [NCBI AMR resources](https://www.ncbi.nlm.nih.gov/pathogens/antimicrobial-resistance/).
* **VFDB:** download a VFDB protein FASTA snapshot (the curated Set A is a conservative starting point; broader Set B adds more reference sequences), then build a DIAMOND protein database with `diamond makedb`. Pass the database prefix without the `.dmnd` suffix as `--vfdb_db`. Record the VFDB release/date and exact set used. [VFDB](http://www.mgc.ac.cn/VFs/).
* **eggNOG-mapper:** provide its downloaded database directory as `--eggnog_data`. The database is large and versioned separately from the software; use the download instructions for the pinned eggNOG-mapper release and retain the release identifier. [eggNOG-mapper documentation](https://github.com/eggnogdb/eggnog-mapper).
* **FastANI:** no external reference database is required. Each comparison uses the supplied MAG genomes. [FastANI](https://github.com/ParBLiSS/FastANI).

Typical preparation commands (run once in a database location accessible to Farm22; retain the resulting versions and checksums):

```bash
amrfinder_update -d /path/to/amrfinderplus/data
diamond makedb --in VFDB_setA_pro.fas --db /path/to/vfdb/vfdb_setA
download_eggnog_data.py -y --data_dir /path/to/eggnog-mapper/data
```

## Software and execution

Pinned Conda environment files are in `envs/`. The `conda` profile enables Conda; the Farm22 profile selects the LSF executor, uses `normal` by default and assigns the 24-hour eggNOG and FastANI tasks to `long`. It uses pre-created tool environments under `/data/pam/ha7g/scratch/conda_envs/`. Ensure the execution environment can access all input files and databases. For an HPC site with a separate resource policy, tune the per-process CPU, memory and time requests in `nextflow.config` before starting a run.

The environment pins are AMRFinderPlus 4.2.7, DIAMOND 2.1.9, eggNOG-mapper 2.1.12, FastANI 1.34, and Python 3.12 for table normalization. AMRFinderPlus software and database versions must be compatible; update the database with the same installed software release. The tools run once per MAG (and FastANI once per participant/species group), so this launches many independent tasks for the full CATI MAG collection.

### Farm22 CPU, memory and LSF requests

The downstream task queues follow the Farm22 walltime limits: tasks budgeted below 12 hours use `normal`; the 24-hour eggNOG and FastANI tasks use `long` (maximum 48 hours). The `bsub < submit_cati_downstream.sh` driver uses the same LSF `#BSUB` directive format as MAGFlow: it runs in `basement` for up to 720 hours (30 days), with one CPU and 8 GB for Nextflow orchestration; each analysis task is submitted separately by Nextflow to LSF. The downstream config also copies MAGFlow's `executor.perJobMemLimit = true`, so the configured memory request is interpreted per job on Farm22. Nextflow's `cpus`, `memory`, `time`, and `queue` settings are translated to LSF `bsub` requests by its LSF executor; the pipeline does not inject another scheduler's directives.

| Process | CPU | Memory per job | Walltime | Queue | Rationale |
| --- | ---: | ---: | ---: | --- | --- |
| AMRFINDER | 8 | 12 GB | 4 h | normal | One MAG nucleotide FASTA per task; CPU doubled and memory raised by 50% from the previous allocation. |
| VFDB_SEARCH | 8 | 12 GB | 4 h | normal | One MAG protein FASTA searched against the compact VFDB Set A database; CPU doubled and memory raised by 50%. |
| EGGNOG_ANNOTATE | 16 | 48 GB | 24 h | long | Database-heavy per-MAG task; CPU doubled and memory increased by 50%, with a 24-hour long-queue limit. |
| STRAIN_FASTANI | 16 | 24 GB | 24 h | long | A participant/species group can contain many MAG pairs; CPU doubled and memory increased by 50%. |
| COLLATE_FEATURES | 2 | 3 GB | 1 h | normal | Combines compact normalized tables after the annotation tasks; CPU doubled and memory raised by 50%. |

These requests apply a 40% or greater memory margin over the previous allocations, rounded up to practical values. The input to these tools is the assembled MAG genome or predicted proteins, not the original deep-sequencing FASTQ files. Sequencing depth therefore does not directly multiply per-task input size here; the larger concern is the number of MAGs and, for FastANI, the number of genomes grouped for a participant/species. No task currently requests 64 GB or more, so `hugemem` is not selected. If the first production trace shows a task needs 64 GB or more, route it to `hugemem` (64–512 GB). Tune from Nextflow trace/report peak memory and runtime after the first batch.

On Farm22, submit the LSF job from this standalone downstream folder. The submission script rebuilds the pending manifest, runs Nextflow as an LSF driver job, sends only pending MAGs to AMR, virulence and function, uses the complete manifest for incremental strain comparisons, and merges/checkpoints results only if Nextflow succeeds. Downstream outputs are added as stages 14–18 inside the existing `MAGFlow_results`; logs and work files use downstream-specific subdirectories. Create these directories once before the first submission (the LSF stdout/stderr directory must exist before `bsub`):

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
mkdir -p /data/pam/ha7g/scratch/projects/metagenomics/CATI/{MAGFlow_logs/CATI_downstream,MAGFlow_work/CATI_downstream,CATI_downstream_state}
bsub < submit_cati_downstream.sh
```

### Smoke test before the initial full run

To validate the pipeline on a few real sample visits first, use the separate `submit_cati_downstream_smoke_test.sh` LSF launcher. It builds a private full inventory and selects **all MAGs for each listed sample ID**. It writes results under `MAGFlow_results/CATI_downstream_smoke_test/`, logs under `MAGFlow_logs/CATI_downstream_smoke_test/`, and manifests under `CATI_downstream_smoke_test/state/`. It does not call the production finalizer and does not modify `CATI_downstream_state/processed_manifest.tsv` or cumulative production tables. The production initial run will therefore still see the complete cohort as pending.

Create a text file with one exact sample ID per line (blank lines and lines beginning with `#` are ignored), then submit:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
mkdir -p /data/pam/ha7g/scratch/projects/metagenomics/CATI/{MAGFlow_logs/CATI_downstream_smoke_test,MAGFlow_work/CATI_downstream,CATI_downstream_smoke_test}
cat > /data/pam/ha7g/scratch/projects/metagenomics/CATI/CATI_downstream_smoke_test/sample_ids.txt <<'EOF'
SAMPLE_ID_1
SAMPLE_ID_2
EOF
bsub < submit_cati_downstream_smoke_test.sh
```

Replace the example IDs with exact IDs present in the current MAGFlow results. The launcher rejects unknown or duplicate IDs. Check the LSF output/error files and the per-run trace/report/timeline/DAG in `MAGFlow_logs/CATI_downstream_smoke_test/`, then inspect the stage outputs in `MAGFlow_results/CATI_downstream_smoke_test/`. Run the normal `bsub < submit_cati_downstream.sh` only after the smoke results look good. Both launchers share the normal downstream `.nextflow/cache/` and `MAGFlow_work/CATI_downstream/`, and use a lock to prevent overlap. Nextflow can reuse only tasks whose complete task hashes match; stages that depend on the selected cohort or group composition may run again in the full cohort. The smoke run does not automatically merge its results into production tables.

### Check downstream progress

After submitting the LSF job, open another Farm22 terminal, go to the downstream folder, and run:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
python3 scripts/cati_downstream_status.py
```

The dashboard reads the newest `trace_<job-id>.txt` in `MAGFlow_logs/CATI_downstream/` and uses the compact `MAGFLOW STATUS` layout: run lineage, sample and task totals, Completed, Running, Failed, Aborted and LSF Jobs sections. Counts are **sample-visit based**: a visit counts as completed for an analysis only after all of that visit's pending MAG tasks for the tool finish. Running includes active, queued and not-yet-submitted sample visits, so Completed + Running equals the batch sample total when there are no failures or aborts; failed and aborted visits are listed separately by sample ID. The submission script saves the batch manifests under `CATI_downstream_state/batches/` so the dashboard keeps a stable sample denominator for the run. Refresh it at a 30-second interval while the run is active with:

```bash
python3 scripts/cati_downstream_status.py --watch 30
```

Press `Ctrl-C` to stop refreshing. To inspect one specific run, pass its trace explicitly with `--trace /path/to/trace_<job-id>.txt`. The dashboard is read-only; it does not submit, stop, or resume jobs.

The script uses the installed AMRFinderPlus database, VFDB Set A DIAMOND prefix, and eggNOG data under `/data/pam/ha7g/scratch/databases/cati_downstream/`. It submits the Nextflow driver to `basement`; AMRFINDER, VFDB_SEARCH and COLLATE_FEATURES use `normal`, while EGGNOG_ANNOTATE and STRAIN_FASTANI use `long`. Logs are kept under `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/CATI_downstream/`: LSF stdout/stderr are `nextflow.<job-id>.out/.err`, and each run has its own Nextflow engine log, trace, report, timeline and DAG named with the LSF job ID. Results are grouped by numbered analysis stage directly in `MAGFlow_results/`; each stage contains a batch-specific subdirectory. Nextflow task work files are kept in `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_work/CATI_downstream/`. For caching, this follows MAGFlow's setup: the launcher changes into its pipeline directory and does not set a custom cache location, so Nextflow uses its default `.nextflow/cache/` there. The downstream cache is therefore `~/pipelines/MAGFlow-downstream-cati/downstream/.nextflow/cache/`, while MAGFlow's is `~/pipelines/MAGFlow/.nextflow/cache/`. These are separate pipeline caches. The downstream runner uses the same `~/software/nextflow` executable and `-resume` option as MAGFlow. Manifests and processed checkpoints are in `CATI_downstream_state/`; cumulative merged tables are in `MAGFlow_results/18_summary/cumulative/`.

The submission script always enables Nextflow `-resume` and reuses the same batch ID and persistent work directory if the same pending manifest is retried after a failure. It fingerprints the AMRFinder, VFDB and eggNOG database paths using their canonical paths and file size/modification metadata; those fingerprints are included in the corresponding task scripts so database changes at a fixed path invalidate those task cache entries. The same fingerprints are included in the active batch identity so a database update during a failed batch gets a separate output directory. Each batch records the canonical database paths and fingerprints in `CATI_downstream_state/batches/<batch_id>/database_fingerprints.tsv`. Submit the same `bsub < submit_cati_downstream.sh` command again; completed tasks are reused and failed/incomplete tasks are retried. A new batch ID is created when the pending manifest or database fingerprints change, and overlapping CATI downstream jobs are prevented. If a database changes after a batch was successfully processed, the processed manifest will not automatically make old MAGs pending; start a separate analysis series or deliberately reset that series' processed checkpoint to reprocess the cohort. If Nextflow fails, it will not merge outputs or advance the processed checkpoint. Keep both the downstream `.nextflow/cache/` directory and the work directory so the task cache and task outputs remain available for resume.

The result layout mirrors MAGFlow's numbered result stages:

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

For the CATI Farm22 paths, the repeatable shortcut is:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
./scripts/rebuild_cati_manifest.sh
```

This scans `/data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_results` and writes the complete inventory to `CATI_downstream_state/current_manifest.tsv` and only new or changed MAGs to `CATI_downstream_manifest.tsv`, both under the CATI directory. It compares against `processed_manifest.tsv`, which advances only after successful analysis and table merging. To use a different results directory, set `MAGFLOW_RESULTS_DIR`; to change the state or pending manifest path, set `CATI_DOWNSTREAM_STATE_DIR` or `CATI_PENDING_MANIFEST`.

### Adding visits or participants later

The manifest builder scans all `09_summary/**/mag_summary.tsv` files under the supplied results directory; it does not assume a fixed number of samples, participants, or visit labels. On the first build, every MAG is pending, so the initial downstream analysis covers the current cohort once. After a batch succeeds and is finalized, the processed checkpoint records the complete inventory. Later builds put only new or changed `(sample, mag_id)` records in the pending manifest; file size and modification time are checked so updated inputs are reprocessed without hashing the full sequence collection. New M6, M12, M24 visits or new participants therefore enter the pending batch automatically.

AMR, VFDB and eggNOG receive only pending MAG records. FastANI receives the complete inventory for groups containing pending MAGs, but compares only new-to-old, old-to-new, or new-to-new pairs; old-to-old pairs are not recalculated. After success, the finalizer replaces previous rows for affected MAGs, appends the batch rows, and preserves unrelated prior rows in the cumulative tables. The submission script creates a unique batch ID and keeps the same persistent work directory with `-resume`. Removed MAGs are not currently detected or pruned from cumulative tables; the workflow assumes MAGFlow results are append-only. If MAGFlow outputs are removed or retracted, use a new analysis series or prune the corresponding cumulative rows explicitly. If database snapshots or analysis parameters change, start a separate state/output series so cumulative results do not mix incompatible runs.

Keep the work directory because it contains Nextflow intermediates (including eggNOG search files) required for resume; it may be much larger than the compact published tables. If the pending manifest has zero records, skip Nextflow and finalization. Do not run the original `main.nf` for this task.

### Main parameters

| Parameter | Default | Purpose |
| --- | --- | --- |
| `--vfdb_min_identity` | `80` | Minimum DIAMOND percent identity |
| `--vfdb_min_query_cover` | `70` | Minimum fraction of query protein covered, in percent |
| `--vfdb_evalue` | `1e-10` | DIAMOND E-value cutoff |
| `--eggnog_sensitivity` | `sensitive` | eggNOG-mapper DIAMOND sensitivity mode |
| `--eggnog_options` | empty | Additional eggNOG-mapper arguments; keep them version-compatible and recorded |
| `--amrfinder_organism` | empty | Optional NCBI AMRFinderPlus organism group. Supply only a valid NCBI taxonomy group when known; otherwise omit it. |

AMRFinderPlus uses its curated thresholds by default. Results should not be interpreted as clinical susceptibility calls.

## Outputs

Each batch has its own tool outputs under `MAGFlow_results/14_amrfinderplus/`, `15_vfdb/`, `16_eggnog/`, and `17_fastani/`; normalized batch tables are under `MAGFlow_results/18_summary/batches/<batch_id>/`. The Farm22 runner merges four cumulative tab-separated cohort tables under `MAGFlow_results/18_summary/cumulative/`:

* `amr_features.tsv` — sample, participant, visit, MAG, determinant/class, method, identity/coverage and coordinates/evidence fields.
* `virulence_features.tsv` — sample, participant, visit, MAG, protein query, VFDB subject, identity, query coverage, E-value and score.
* `functional_annotations.tsv` — sample, participant, visit, MAG, gene ID, ortholog, COG, GO, EC, KEGG and other available eggNOG fields.
* `strain_pairwise_fastani.tsv` — participant, species, query/reference sample, visit, MAG, ANI and matching-fragment support.

AMR/VFDB/eggNOG outputs include header-only rows when no features are found for a MAG, so absence of rows in the cohort table means no passing hit was reported. It does not prove biological absence.

## Strain-analysis decision and limitations

This workflow uses **FastANI on assembled MAG genomes**, rather than StrainPhlAn. The available products are MAG sequences and Bakta/Prokka annotations; using them avoids introducing a second read-processing/marker database workflow and supports resumable comparisons. FastANI estimates average nucleotide identity for genome pairs; it is not a within-sample haplotype or minor-variant caller. Comparisons are restricted to the same participant and species label and are emitted in query-to-reference direction (the reverse direction can have different fragment support). Fragment fraction should be considered alongside ANI, especially for incomplete or contaminated MAGs. MAGs that fail FastANI's alignment criteria may not appear as a comparison row. A fixed ANI threshold for “same strain” is intentionally not imposed: interpretation depends on species, genome quality, coverage, and the study's prespecified definition of strain persistence/replacement.

For read-level within-sample strain mixtures or low-abundance strains, use a separate read-based method such as StrainPhlAn or inStrain with the original metagenomic reads and required marker/reference resources. That is a different analysis design and is not claimed by this MAG-pair workflow.

## Reproducibility notes

Keep the manifest, parameters, Nextflow trace, software environments, database release/checksum metadata and run command with each run. Database updates must be treated as input changes; record them and use a separate state/output series. The Farm22 default intentionally appends downstream stages 14–18 under `MAGFlow_results/`; it does not overwrite the existing MAGFlow stages 00–13.
