#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
downstream_dir="$(cd -- "${script_dir}/.." && pwd)"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${HOME}/pipelines/CATI_downstream_state}"
pending_manifest="${CATI_PENDING_MANIFEST:-${HOME}/pipelines/CATI_downstream_manifest.tsv}"
full_manifest="${state_dir}/current_manifest.tsv"
work_dir="${CATI_DOWNSTREAM_WORK_DIR:-${HOME}/pipelines/CATI_downstream_work}"
batch_outdir="${1:?Usage: run_cati_batch.sh BATCH_OUTDIR --amrfinder_db PATH --vfdb_db PREFIX --eggnog_data DIR}"
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

mkdir -p "${batch_outdir}"

nextflow run "${downstream_dir}/main.nf" \
  -profile farm22,conda \
  --input "${pending_manifest}" \
  --all_input "${full_manifest}" \
  --outdir "${batch_outdir}" \
  --work_dir "${work_dir}" \
  "$@" \
  -resume

"${script_dir}/finalize_cati_batch.sh" \
  "${batch_outdir}" "${pending_manifest}" "${full_manifest}"
