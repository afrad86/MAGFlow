#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="${MAGFLOW_RESULTS_DIR:-/lustre/scratch124/pam/teams/team216/ha7/projects/metagenomics/CATI/MAGFlow_results}"
state_dir="${CATI_DOWNSTREAM_STATE_DIR:-${HOME}/pipelines/CATI_downstream_state}"
full_manifest="${state_dir}/current_manifest.tsv"
processed_manifest="${state_dir}/processed_manifest.tsv"
pending_manifest="${1:-${HOME}/pipelines/CATI_downstream_manifest.tsv}"

python3 "${script_dir}/build_manifest.py" \
  --results-dir "${results_dir}" \
  --output "${full_manifest}" \
  --previous-manifest "${processed_manifest}" \
  --new-output "${pending_manifest}"
