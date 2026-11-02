#!/bin/bash
#BSUB -J MAGFlow
#BSUB -q basement
#BSUB -n 1
#BSUB -M 8192MB
#BSUB -R "select[mem>=8192MB] rusage[mem=8192MB]"
#BSUB -W 720:00
#BSUB -o /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/nextflow.%J.out
#BSUB -e /data/pam/ha7g/scratch/projects/metagenomics/CATI/MAGFlow_logs/nextflow.%J.err

set -euo pipefail

PROJECT_NAME="CATI"
PROJECT_ROOT="/data/pam/ha7g/scratch/projects/metagenomics/${PROJECT_NAME}"
LOG_DIR="${PROJECT_ROOT}/MAGFlow_logs"
RESULTS_DIR="${PROJECT_ROOT}/MAGFlow_results"

export NXF_WORK="${PROJECT_ROOT}/MAGFlow_work"
export MAGFLOW_OUTDIR="${PROJECT_ROOT}/MAGFlow_results"


# ============================================================================
# Initialise Farm22 environment
# ============================================================================

if ! type module >/dev/null 2>&1; then
    source /etc/profile.d/modules.sh
fi

module load PaM/environment
module load cellgen/java/23.0.2


echo "=================================================="
echo "Environment"
echo "=================================================="
module list
echo
java -version
echo "=================================================="


# ============================================================================
# Project directories
# ============================================================================

cd ~/pipelines/MAGFlow

mkdir -p "${LOG_DIR}" "${RESULTS_DIR}" "${NXF_WORK}"


# ============================================================================
# Identify the correct previous production MAGFlow session
#
# We deliberately do NOT use bare -resume.
#
# This prevents Nextflow from accidentally resuming a preview/test session.
# ============================================================================

SESSION_ID=$(
python3 - <<'PY'
from pathlib import Path

history = Path(".nextflow/history")

if not history.exists():
    raise SystemExit(
        "ERROR: .nextflow/history does not exist."
    )

selected = None

for line in history.read_text().splitlines():

    if not line.strip():
        continue

    fields = line.split()

    # Expected:
    #
    # date time duration name status revision session command...
    #
    if len(fields) < 8:
        continue

    status = fields[4]
    session = fields[6]
    command = " ".join(fields[7:])

    # Successful runs only
    if status != "OK":
        continue

    # Must be the MAGFlow production workflow
    if "nextflow run main.nf" not in command:
        continue

    if "-profile farm22" not in command:
        continue

    # Never select preview runs
    if "-preview" in command:
        continue

    if "preview" in command.lower():
        continue

    # Never select compile/test runs
    if "compile" in command.lower():
        continue

    # Validate UUID
    if len(session) != 36 or session.count("-") != 4:
        continue

    # .nextflow/history is chronological.
    # Keep the latest valid production session.
    selected = session


if not selected:
    raise SystemExit(
        "ERROR: No successful production MAGFlow session was found."
    )

print(selected)
PY
)


# ============================================================================
# Run information
# ============================================================================

RUN_ID=$(date +%Y%m%d_%H%M%S)

echo "=================================================="
echo "MAGFlow resume started : $(date)"
echo "Run ID                 : ${RUN_ID}"
echo "Host                   : $(hostname)"
echo "Directory              : $(pwd)"
echo "Project                : ${PROJECT_NAME}"
echo "Output                 : ${RESULTS_DIR}"
echo "Work                   : ${NXF_WORK}"
echo "Logs                   : ${LOG_DIR}"
echo "Resume session         : ${SESSION_ID}"
echo "=================================================="


# ============================================================================
# Show the selected production run
# ============================================================================

echo
echo "Selected production session:"
echo "${SESSION_ID}"
echo

echo "Matching history entry:"
grep "${SESSION_ID}" .nextflow/history || true

echo
echo "=================================================="


# ============================================================================
# Software versions
# ============================================================================

echo "Nextflow        : $(~/software/nextflow -version | head -1)"
echo "Java            : $(java -version 2>&1 | head -1)"

if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Git commit      : $(git rev-parse --short HEAD)"
fi

echo "=================================================="


# ============================================================================
# Resume MAGFlow
# ============================================================================

~/software/nextflow run main.nf \
    -profile farm22 \
    -work-dir "${NXF_WORK}" \
    -resume "${SESSION_ID}" \
    -with-report "${LOG_DIR}/report_${RUN_ID}.html" \
    -with-trace "${LOG_DIR}/trace_${RUN_ID}.txt" \
    -with-timeline "${LOG_DIR}/timeline_${RUN_ID}.html" \
    -with-dag "${LOG_DIR}/dag_${RUN_ID}.html"


echo "=================================================="
echo "MAGFlow resume finished: $(date)"
echo "=================================================="