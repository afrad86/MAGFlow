#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="${MAGFLOW_RESULTS_DIR:-/lustre/scratch124/pam/teams/team216/ha7/projects/metagenomics/CATI/MAGFlow_results}"
output_path="${1:-${HOME}/pipelines/CATI_downstream_manifest.tsv}"

python3 "${script_dir}/build_manifest.py" \
  --results-dir "${results_dir}" \
  --output "${output_path}"
