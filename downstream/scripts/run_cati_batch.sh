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
trace_file="${CATI_DOWNSTREAM_TRACE_FILE:-${log_dir}/trace_${run_id}.txt}"
nextflow_bin="${HOME}/software/nextflow"
batch_id="${1:?Usage: run_cati_batch.sh BATCH_ID --amrfinder_db PATH --vfdb_db PREFIX --eggnog_data DIR}"
shift

# Honor an explicitly supplied trace path as well as the standard Farm22 path.
nextflow_args=("$@")
for ((i = 0; i < ${#nextflow_args[@]}; i++)); do
  case "${nextflow_args[i]}" in
    --trace_file)
      trace_file="${nextflow_args[i + 1]:-}"
      break
      ;;
    --trace_file=*)
      trace_file="${nextflow_args[i]#*=}"
      break
      ;;
  esac
done

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
echo "Nextflow trace        : ${trace_file}"
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

# Ignored tool failures allow all independent analyses and partial collation to
# finish. Do not merge partial data or advance the processed checkpoint; keep
# active_batch intact so a later submission resumes this batch and retries the
# failed tasks while reusing successful tasks from Nextflow's cache.
if [[ ! -s "${trace_file}" ]]; then
  echo "ERROR: Nextflow trace is missing or empty: ${trace_file}" >&2
  exit 2
fi
if ! python3 "${script_dir}/check_trace_failures.py" "${trace_file}"; then
  echo "ERROR: One or more analysis tasks failed. Partial per-tool outputs are retained; cumulative tables and processed checkpoint were not updated." >&2
  echo "Resubmit the same batch with -resume after reviewing the failed tasks." >&2
  exit 1
fi

"${script_dir}/finalize_cati_batch.sh" \
  "${batch_id}" "${pending_manifest}" "${full_manifest}"
