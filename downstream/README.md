# MAGFlow downstream CATI feature analyses

This is an independent Nextflow DSL2 entrypoint for the four CATI feature-generation analyses. It does not change or invoke the completed `../main.nf` pipeline. Inputs are the existing per-MAG FASTA and predicted protein FASTA from Bakta or Prokka, plus current and pending metadata manifests. Batch outputs are published under the new `--outdir`; the Farm22 runner also merges compact cohort tables into a persistent state directory after successful runs.

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

Pinned Conda environment files are in `envs/`. The `conda` profile enables those environments; `farm22` selects the LSF executor and `long` queue. Ensure the execution environment can access all input files and databases. For an HPC site with a separate resource policy, tune the per-process CPU, memory and time requests in `nextflow.config` before starting a run.

The environment pins are AMRFinderPlus 4.2.7, DIAMOND 2.1.9, eggNOG-mapper 2.1.12, FastANI 1.34, and Python 3.12 for table normalization. AMRFinderPlus software and database versions must be compatible; update the database with the same installed software release. The tools run once per MAG (and FastANI once per participant/species group), so this launches many independent tasks for the full CATI MAG collection.

On Farm22, rebuild the pending manifest, then launch a batch with the wrapper below. It runs Nextflow from this standalone downstream folder, sends only pending MAGs to AMR, virulence and function, uses the complete manifest for incremental strain comparisons, and merges/checkpoints results only if Nextflow succeeds:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
./scripts/rebuild_cati_manifest.sh
./scripts/run_cati_batch.sh ~/pipelines/CATI_downstream_batches/initial \
  --amrfinder_db /path/to/amrfinderplus/data/latest \
  --vfdb_db /path/to/vfdb/vfdb_setA \
  --eggnog_data /path/to/eggnog-mapper/data
```

Choose a new batch output directory for each successful or resumed batch. The merged cumulative tables are kept in `~/pipelines/CATI_downstream_state/tables/`. Each batch output directory also retains that batch's per-MAG and per-group files. If Nextflow fails, the wrapper will not merge outputs or advance the processed checkpoint; fix the issue and rerun with the same pending manifest and batch output directory.

For the CATI Farm22 paths, the repeatable shortcut is:

```bash
cd ~/pipelines/MAGFlow-downstream-cati/downstream
./scripts/rebuild_cati_manifest.sh
```

This scans the standard CATI `MAGFlow_results` directory and writes two manifests: the complete current inventory at `~/pipelines/CATI_downstream_state/current_manifest.tsv`, and only new or changed MAGs at `~/pipelines/CATI_downstream_manifest.tsv`. It compares against `processed_manifest.tsv`, which is advanced only after a successful analysis and table merge. It reports counts for both the full cohort and pending batch. To use a different results directory, set `MAGFLOW_RESULTS_DIR`; to change the state directory, set `CATI_DOWNSTREAM_STATE_DIR`; to write the pending manifest elsewhere, pass its path as the first argument.

### Adding visits or participants later

The manifest builder scans all `09_summary/**/mag_summary.tsv` files under the supplied results directory; it does not assume a fixed number of samples, participants, or visit labels. On the first build, every MAG is pending, so the initial downstream analysis covers the current cohort once. After a batch succeeds and is finalized, the processed checkpoint records the complete inventory. Later builds put only new or changed `(sample, mag_id)` records in the pending manifest; file size and modification time are checked so updated inputs are reprocessed without hashing the full sequence collection. New M6, M12, M24 visits or new participants therefore enter the pending batch automatically.

AMR, VFDB and eggNOG receive only pending MAG records. FastANI receives the complete inventory for groups containing pending MAGs, but compares only new-to-old, old-to-new, or new-to-new pairs; old-to-old pairs are not recalculated. After success, the finalizer replaces previous rows for affected MAGs, appends the batch rows, and preserves unrelated prior rows in the cumulative tables. Use a new batch `--outdir` for each run and the same persistent `--work_dir` with `-resume`. If database snapshots or analysis parameters change, start a separate state/output series so cumulative results do not mix incompatible runs.

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

Each batch output directory retains that batch's per-MAG and per-group normalized tables under `per_mag/` and `per_group/`. The Farm22 runner merges four cumulative tab-separated cohort tables under `~/pipelines/CATI_downstream_state/tables/`:

* `amr_features.tsv` — sample, participant, visit, MAG, determinant/class, method, identity/coverage and coordinates/evidence fields.
* `virulence_features.tsv` — sample, participant, visit, MAG, protein query, VFDB subject, identity, query coverage, E-value and score.
* `functional_annotations.tsv` — sample, participant, visit, MAG, gene ID, ortholog, COG, GO, EC, KEGG and other available eggNOG fields.
* `strain_pairwise_fastani.tsv` — participant, species, query/reference sample, visit, MAG, ANI and matching-fragment support.

AMR/VFDB/eggNOG outputs include header-only rows when no features are found for a MAG, so absence of rows in the cohort table means no passing hit was reported. It does not prove biological absence.

## Strain-analysis decision and limitations

This workflow uses **FastANI on assembled MAG genomes**, rather than StrainPhlAn. The available products are MAG sequences and Bakta/Prokka annotations; using them avoids introducing a second read-processing/marker database workflow and supports resumable comparisons. FastANI estimates average nucleotide identity for genome pairs; it is not a within-sample haplotype or minor-variant caller. Comparisons are restricted to the same participant and species label and are emitted in query-to-reference direction (the reverse direction can have different fragment support). Fragment fraction should be considered alongside ANI, especially for incomplete or contaminated MAGs. MAGs that fail FastANI's alignment criteria may not appear as a comparison row. A fixed ANI threshold for “same strain” is intentionally not imposed: interpretation depends on species, genome quality, coverage, and the study's prespecified definition of strain persistence/replacement.

For read-level within-sample strain mixtures or low-abundance strains, use a separate read-based method such as StrainPhlAn or inStrain with the original metagenomic reads and required marker/reference resources. That is a different analysis design and is not claimed by this MAG-pair workflow.

## Reproducibility notes

Keep the manifest, parameters, Nextflow trace, software environments, database release/checksum metadata and run command with each run. Database updates must be treated as input changes; record them and use a new output directory. The workflow does not alter or overwrite the completed MAGFlow outputs unless the user explicitly points `--outdir` into an existing result directory.
