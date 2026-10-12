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
log_dir="${CATI_DOWNSTREAM_LOG_DIR:-${CATI_ROOT}/MAGFlow_logs/CATI_downstream}"
run_id="${CATI_DOWNSTREAM_RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
nextflow_log="${log_dir}/nextflow_${run_id}.log"
nextflow_bin="${HOME}/software/nextflow"
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

mkdir -p "${results_dir}" "${log_dir}" "${work_dir}"
cd "${downstream_dir}"
echo "Nextflow work directory: ${work_dir}"
echo "Nextflow engine log   : ${nextflow_log}"
echo "Nextflow task cache   : ${downstream_dir}/.nextflow/cache"
echo "Resume mode           : enabled (-resume)"

"${nextflow_bin}" -log "${nextflow_log}" run "${downstream_dir}/main.nf" \
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
