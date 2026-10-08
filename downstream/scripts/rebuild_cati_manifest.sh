#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CATI_ROOT="${CATI_ROOT:-/data/pam/ha7g/scratch/projects/metagenomics/CATI}"
results_dir="${MAGFLOW_RESULTS_DIR:-${CATI_ROOT}/MAGFlow_results}"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${CATI_ROOT}/CATI_downstream_state}"
full_manifest="${state_dir}/current_manifest.tsv"
processed_manifest="${state_dir}/processed_manifest.tsv"
pending_manifest="${1:-${CATI_PENDING_MANIFEST:-${CATI_ROOT}/CATI_downstream_manifest.tsv}}"

python3 "${script_dir}/build_manifest.py" \
  --results-dir "${results_dir}" \
  --output "${full_manifest}" \
  --previous-manifest "${processed_manifest}" \
  --new-output "${pending_manifest}"
