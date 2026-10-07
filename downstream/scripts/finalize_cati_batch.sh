#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${HOME}/pipelines/CATI_downstream_state}"
batch_dir="${1:?Usage: finalize_cati_batch.sh BATCH_OUTDIR [PENDING_MANIFEST] [FULL_MANIFEST]}"
pending_manifest="${2:-${HOME}/pipelines/CATI_downstream_manifest.tsv}"
full_manifest="${3:-${state_dir}/current_manifest.tsv}"
tables_dir="${state_dir}/tables"

python3 "${script_dir}/merge_incremental_tables.py" \
  --previous-dir "${tables_dir}" \
  --batch-dir "${batch_dir%/}/tables" \
  --pending-manifest "${pending_manifest}" \
  --output-dir "${tables_dir}"

mkdir -p "${state_dir}"
cp "${full_manifest}" "${state_dir}/processed_manifest.tsv.tmp"
mv "${state_dir}/processed_manifest.tsv.tmp" "${state_dir}/processed_manifest.tsv"
head -n 1 "${full_manifest}" > "${pending_manifest}.tmp"
mv "${pending_manifest}.tmp" "${pending_manifest}"
echo "Updated cumulative CATI tables and processed-manifest checkpoint in ${state_dir}"
