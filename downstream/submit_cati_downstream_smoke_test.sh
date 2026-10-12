#!/usr/bin/env bash
#BSUB -J CATI_downstream_smoke
#BSUB -q basement
#BSUB -n 1
#BSUB -M 8192MB
#BSUB -R "select[mem>=8192MB] rusage[mem=8192MB]"
#BSUB -W 720:00
#BSUB -o /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/CATI_downstream_smoke_test/nextflow.%J.out
#BSUB -e /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/CATI_downstream_smoke_test/nextflow.%J.err

set -euo pipefail

if ! type module >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
fi
module load PaM/environment
module load cellgen/java/23.0.2
module load ISG/conda
export PATH="${HOME}/software:${PATH}"

downstream_dir="${CATI_DOWNSTREAM_DIR:-$(pwd -P)}"
script_dir="${downstream_dir}"
if [[ ! -f "${downstream_dir}/main.nf" || ! -f "${script_dir}/scripts/database_fingerprint.sh" ]]; then
    echo "ERROR: Run bsub from the downstream directory, or set CATI_DOWNSTREAM_DIR." >&2
    exit 2
fi
source "${script_dir}/scripts/database_fingerprint.sh"
CATI_ROOT="${CATI_ROOT:-/data/pam/ha7g/scratch/projects/metagenomics/CATI}"
MAGFLOW_RESULTS_DIR="${MAGFLOW_RESULTS_DIR:-${CATI_ROOT}/MAGFlow_results}"
production_state="${CATI_DOWNSTREAM_STATE_DIR:-${CATI_ROOT}/CATI_downstream_state}"
smoke_root="${CATI_DOWNSTREAM_SMOKE_DIR:-${CATI_ROOT}/CATI_downstream_smoke_test}"
smoke_state="${smoke_root}/state"
smoke_outdir="${CATI_DOWNSTREAM_SMOKE_RESULTS_DIR:-${MAGFLOW_RESULTS_DIR}/CATI_downstream_smoke_test}"
smoke_log_dir="${CATI_DOWNSTREAM_SMOKE_LOG_DIR:-${CATI_ROOT}/MAGFlow_logs/CATI_downstream_smoke_test}"
work_dir="${CATI_DOWNSTREAM_WORK_DIR:-${CATI_ROOT}/MAGFlow_work/CATI_downstream}"
sample_file="${CATI_SMOKE_SAMPLES_FILE:-${smoke_root}/sample_ids.txt}"

AMRFINDER_DB="${AMRFINDER_DB:-/data/pam/ha7g/scratch/databases/cati_downstream/amrfinderplus/4.2.7/latest}"
VFDB_DB="${VFDB_DB:-/data/pam/ha7g/scratch/databases/cati_downstream/vfdb/VFDB_setA_pro}"
EGGNOG_DATA="${EGGNOG_DATA:-/data/pam/ha7g/scratch/databases/cati_downstream/eggnog}"

for required_path in "${MAGFLOW_RESULTS_DIR}/09_summary" "${sample_file}" \
    "${AMRFINDER_DB}" "${VFDB_DB}.dmnd" "${EGGNOG_DATA}"; do
    if [[ ! -e "${required_path}" ]]; then
        echo "ERROR: Required input is missing: ${required_path}" >&2
        exit 2
    fi
done

mkdir -p "${smoke_state}" "${smoke_outdir}" "${smoke_log_dir}" "${work_dir}" "${production_state}"

# Serialize smoke and production runs because they share Nextflow's cache and
# work directory. This lock is not used to write production checkpoints.
exec 9>"${production_state}/submission.lock"
if ! flock -n 9; then
    echo "ERROR: Another CATI downstream job is running; retry after it finishes." >&2
    exit 3
fi

RUN_ID="${LSB_JOBID:-$(date +%Y%m%d_%H%M%S)}"
full_manifest="${smoke_state}/current_manifest.tsv"
pending_manifest="${smoke_state}/smoke_manifest.tsv"
trace_file="${smoke_log_dir}/trace_${RUN_ID}.txt"
nextflow_bin="${HOME}/software/nextflow"

cd "${downstream_dir}"
echo "=================================================="
echo "CATI downstream smoke test started: $(date)"
echo "Run ID                    : ${RUN_ID}"
echo "Sample ID file            : ${sample_file}"
echo "MAGFlow inputs            : ${MAGFLOW_RESULTS_DIR}"
echo "Smoke results             : ${smoke_outdir}"
echo "Shared work directory     : ${work_dir}"
echo "Nextflow cache            : ${downstream_dir}/.nextflow/cache"
echo "Production state          : ${production_state} (checkpoint unchanged)"
module list
echo "Nextflow                  : $(${nextflow_bin} -version | head -1)"
java -version 2>&1 | head -1
echo "=================================================="

python3 "${script_dir}/scripts/build_manifest.py" \
    --results-dir "${MAGFLOW_RESULTS_DIR}" --output "${full_manifest}"
python3 "${script_dir}/scripts/select_smoke_manifest.py" \
    --manifest "${full_manifest}" --samples "${sample_file}" --output "${pending_manifest}"
cp "${sample_file}" "${smoke_state}/sample_ids_${RUN_ID}.txt"

AMRFINDER_DB_FINGERPRINT="$(fingerprint_path "${AMRFINDER_DB}")"
VFDB_DB_FINGERPRINT="$(fingerprint_path "${VFDB_DB}.dmnd")"
EGGNOG_DB_FINGERPRINT="$(fingerprint_path "${EGGNOG_DATA}")"

"${nextflow_bin}" -log "${smoke_log_dir}/nextflow_${RUN_ID}.log" run "${downstream_dir}/main.nf" \
    -profile farm22,conda \
    --input "${pending_manifest}" \
    --all_input "${full_manifest}" \
    --outdir "${smoke_outdir}" \
    --batch_id "smoke_${RUN_ID}" \
    --work_dir "${work_dir}" \
    --amrfinder_db "${AMRFINDER_DB}" \
    --amrfinder_db_fingerprint "${AMRFINDER_DB_FINGERPRINT}" \
    --vfdb_db "${VFDB_DB}" \
    --vfdb_db_fingerprint "${VFDB_DB_FINGERPRINT}" \
    --eggnog_data "${EGGNOG_DATA}" \
    --eggnog_db_fingerprint "${EGGNOG_DB_FINGERPRINT}" \
    --trace_file "${trace_file}" \
    -with-report "${smoke_log_dir}/report_${RUN_ID}.html" \
    -with-timeline "${smoke_log_dir}/timeline_${RUN_ID}.html" \
    -with-dag "${smoke_log_dir}/dag_${RUN_ID}.html" \
    -resume

echo "=================================================="
echo "CATI downstream smoke test finished: $(date)"
echo "Smoke results             : ${smoke_outdir}"
echo "Production checkpoint    : unchanged"
echo "=================================================="
