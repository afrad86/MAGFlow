#!/usr/bin/env bash
#BSUB -J CATI_downstream
#BSUB -q basement
#BSUB -n 1
#BSUB -M 8192MB
#BSUB -R "select[mem>=8192MB] rusage[mem=8192MB]"
#BSUB -W 720:00
#BSUB -o /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/CATI_downstream/nextflow.%J.out
#BSUB -e /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/CATI_downstream/nextflow.%J.err

set -euo pipefail

if ! type module >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
fi

module load PaM/environment
module load cellgen/java/23.0.2
module load ISG/conda
export PATH="${HOME}/software:${PATH}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
downstream_dir="$(cd -- "${script_dir}" && pwd)"
CATI_ROOT="${CATI_ROOT:-/data/pam/ha7g/scratch/projects/metagenomics/CATI}"
export CATI_ROOT
export MAGFLOW_RESULTS_DIR="${MAGFLOW_RESULTS_DIR:-${CATI_ROOT}/MAGFlow_results}"
export CATI_DOWNSTREAM_LOG_DIR="${CATI_DOWNSTREAM_LOG_DIR:-${CATI_ROOT}/MAGFlow_logs/CATI_downstream}"
export CATI_DOWNSTREAM_RESULTS_DIR="${CATI_DOWNSTREAM_RESULTS_DIR:-${MAGFLOW_RESULTS_DIR}}"
export CATI_DOWNSTREAM_WORK_DIR="${CATI_DOWNSTREAM_WORK_DIR:-${CATI_ROOT}/MAGFlow_work/CATI_downstream}"
export CATI_DOWNSTREAM_STATE_DIR="${CATI_DOWNSTREAM_STATE_DIR:-${CATI_ROOT}/CATI_downstream_state}"
export CATI_PENDING_MANIFEST="${CATI_PENDING_MANIFEST:-${CATI_ROOT}/CATI_downstream_manifest.tsv}"

AMRFINDER_DB="${AMRFINDER_DB:-/data/pam/ha7g/scratch/databases/cati_downstream/amrfinderplus/4.2.7/latest}"
VFDB_DB="${VFDB_DB:-/data/pam/ha7g/scratch/databases/cati_downstream/vfdb/VFDB_setA_pro}"
EGGNOG_DATA="${EGGNOG_DATA:-/data/pam/ha7g/scratch/databases/cati_downstream/eggnog}"

mkdir -p "${CATI_DOWNSTREAM_LOG_DIR}" "${CATI_DOWNSTREAM_RESULTS_DIR}" \
    "${CATI_DOWNSTREAM_WORK_DIR}" "${CATI_DOWNSTREAM_STATE_DIR}"
cd "${downstream_dir}"

RUN_ID="${LSB_JOBID:-$(date +%Y%m%d_%H%M%S)}"
echo "=================================================="
echo "CATI downstream started : $(date)"
echo "Run ID                  : ${RUN_ID}"
echo "Host                    : $(hostname)"
echo "Directory               : $(pwd)"
echo "MAGFlow inputs           : ${MAGFLOW_RESULTS_DIR}"
echo "Results root             : ${CATI_DOWNSTREAM_RESULTS_DIR}"
echo "Work directory           : ${CATI_DOWNSTREAM_WORK_DIR}"
echo "State directory          : ${CATI_DOWNSTREAM_STATE_DIR}"
module list
echo "Nextflow                 : $(nextflow -version | head -1)"
java -version 2>&1 | head -1
if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Git commit               : $(git rev-parse --short HEAD)"
fi
echo "=================================================="

# Prevent concurrent jobs from rebuilding or consuming the same manifests.
exec 9>"${CATI_DOWNSTREAM_STATE_DIR}/submission.lock"
if ! flock -n 9; then
    echo "ERROR: Another CATI downstream job is already running." >&2
    exit 3
fi

# Build the complete inventory and pending-only manifest from the latest
# MAGFlow results before selecting a batch output directory.
"${script_dir}/scripts/rebuild_cati_manifest.sh"

if ! sed -n '2p' "${CATI_PENDING_MANIFEST}" | grep -q .; then
    echo "No new or changed MAG records are pending; no analysis submitted."
    exit 0
fi

# Retain the same output directory on a failed rerun with the same manifest.
# After successful finalization, the active marker is removed; a later batch
# gets its own timestamped output directory.
manifest_hash="$(sha256sum "${CATI_PENDING_MANIFEST}" | awk '{print $1}')"
active_batch="${CATI_DOWNSTREAM_STATE_DIR}/active_batch.tsv"
batch_id=""
if [[ -s "${active_batch}" ]]; then
    IFS=$'\t' read -r previous_hash previous_batch < "${active_batch}" || true
    if [[ "${previous_hash:-}" == "${manifest_hash}" && -n "${previous_batch:-}" ]]; then
        batch_id="${previous_batch}"
        echo "Resuming batch directory: ${batch_id}"
    fi
fi

if [[ -z "${batch_id}" ]]; then
    if [[ ! -s "${CATI_DOWNSTREAM_STATE_DIR}/processed_manifest.tsv" ]]; then
        batch_id="initial"
    else
        batch_id="batch_${RUN_ID}_$(cut -c1-8 <<<"${manifest_hash}")"
    fi
    printf '%s\t%s\n' "${manifest_hash}" "${batch_id}" > "${active_batch}.tmp"
    mv "${active_batch}.tmp" "${active_batch}"
fi

"${script_dir}/scripts/run_cati_batch.sh" "${batch_id}" \
    --amrfinder_db "${AMRFINDER_DB}" \
    --vfdb_db "${VFDB_DB}" \
    --eggnog_data "${EGGNOG_DATA}" \
    --trace_file "${CATI_DOWNSTREAM_LOG_DIR}/trace_${RUN_ID}.txt" \
    -with-report "${CATI_DOWNSTREAM_LOG_DIR}/report_${RUN_ID}.html" \
    -with-timeline "${CATI_DOWNSTREAM_LOG_DIR}/timeline_${RUN_ID}.html" \
    -with-dag "${CATI_DOWNSTREAM_LOG_DIR}/dag_${RUN_ID}.html"

rm -f "${active_batch}"
echo "=================================================="
echo "CATI downstream finished: $(date)"
echo "Batch ID                : ${batch_id}"
echo "Results root            : ${CATI_DOWNSTREAM_RESULTS_DIR}"
echo "=================================================="
