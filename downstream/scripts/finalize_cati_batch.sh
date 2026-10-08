#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CATI_ROOT="${CATI_ROOT:-/data/pam/ha7g/scratch/projects/metagenomics/CATI}"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${CATI_ROOT}/CATI_downstream_state}"
batch_id="${1:?Usage: finalize_cati_batch.sh BATCH_ID [PENDING_MANIFEST] [FULL_MANIFEST]}"
pending_manifest="${2:-${CATI_PENDING_MANIFEST:-${CATI_ROOT}/CATI_downstream_manifest.tsv}}"
full_manifest="${3:-${state_dir}/current_manifest.tsv}"
results_dir="${CATI_DOWNSTREAM_RESULTS_DIR:-${MAGFLOW_RESULTS_DIR:-${CATI_ROOT}/MAGFlow_results}}"
batch_tables_dir="${results_dir}/18_summary/batches/${batch_id}"
tables_dir="${CATI_DOWNSTREAM_TABLES_DIR:-${results_dir}/18_summary/cumulative}"

python3 "${script_dir}/merge_incremental_tables.py" \
  --previous-dir "${tables_dir}" \
  --batch-dir "${batch_tables_dir}" \
  --pending-manifest "${pending_manifest}" \
  --output-dir "${tables_dir}"

mkdir -p "${state_dir}"
cp "${full_manifest}" "${state_dir}/processed_manifest.tsv.tmp"
mv "${state_dir}/processed_manifest.tsv.tmp" "${state_dir}/processed_manifest.tsv"
head -n 1 "${full_manifest}" > "${pending_manifest}.tmp"
mv "${pending_manifest}.tmp" "${pending_manifest}"
echo "Updated cumulative CATI tables and processed-manifest checkpoint in ${state_dir}"
