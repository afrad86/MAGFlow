#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
downstream_dir="$(cd -- "${script_dir}/.." && pwd)"
CATI_ROOT="${CATI_ROOT:-/data/pam/ha7g/scratch/projects/metagenomics/CATI}"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${CATI_ROOT}/CATI_downstream_state}"
pending_manifest="${CATI_PENDING_MANIFEST:-${CATI_ROOT}/CATI_downstream_manifest.tsv}"
full_manifest="${state_dir}/current_manifest.tsv"
work_dir="${CATI_DOWNSTREAM_WORK_DIR:-${CATI_ROOT}/CATI_downstream_work}"
results_dir="${CATI_DOWNSTREAM_RESULTS_DIR:-${MAGFLOW_RESULTS_DIR:-${CATI_ROOT}/MAGFlow_results}}"
batch_id="${1:?Usage: run_cati_batch.sh BATCH_ID --amrfinder_db PATH --vfdb_db PREFIX --eggnog_data DIR}"
shift

for required_file in "${pending_manifest}" "${full_manifest}"; do
  if [[ ! -s "${required_file}" ]]; then
    echo "ERROR: Required manifest is missing or empty: ${required_file}" >&2
    exit 2
  fi
done

if ! sed -n '2p' "${pending_manifest}" | grep -q .; then
  echo "No new or changed MAG records are pending; nothing to run."
  exit 0
fi

mkdir -p "${results_dir}"

nextflow run "${downstream_dir}/main.nf" \
  -profile farm22,conda \
  --input "${pending_manifest}" \
  --all_input "${full_manifest}" \
  --outdir "${results_dir}" \
  --batch_id "${batch_id}" \
  --work_dir "${work_dir}" \
  "$@" \
  -resume

"${script_dir}/finalize_cati_batch.sh" \
  "${batch_id}" "${pending_manifest}" "${full_manifest}"
