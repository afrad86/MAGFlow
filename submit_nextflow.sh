#!/bin/bash
#BSUB -J MAGFlow
#BSUB -q basement
#BSUB -n 1
#BSUB -M 8192MB
#BSUB -R "select[mem>=8192MB] rusage[mem=8192MB]"
#BSUB -W 720:00
#BSUB -o logs/nextflow.%J.out
#BSUB -e logs/nextflow.%J.err

set -euo pipefail

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

cd ~/pipelines/MAGFlow

mkdir -p logs

RUN_ID=$(date +%Y%m%d_%H%M%S)

# Default output directory
OUTDIR="${OUTDIR:-$PWD/results}"

mkdir -p "$OUTDIR"

echo "=================================================="
echo "MAGFlow started : $(date)"
echo "Run ID          : ${RUN_ID}"
echo "Host            : $(hostname)"
echo "Directory       : $(pwd)"
echo "Output          : ${OUTDIR}"
echo

echo "Nextflow        : $(~/software/nextflow -version | head -1)"
echo "Java            : $(java -version 2>&1 | head -1)"

if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Git commit      : $(git rev-parse --short HEAD)"
fi

echo "=================================================="

~/software/nextflow run main.nf \
    -profile farm22 \
    -resume \
    --outdir "$OUTDIR" \
    "$@" \
    -with-report logs/report_${RUN_ID}.html \
    -with-trace logs/trace_${RUN_ID}.txt \
    -with-timeline logs/timeline_${RUN_ID}.html \
    -with-dag logs/dag_${RUN_ID}.html

echo "=================================================="
echo "MAGFlow finished: $(date)"
echo "=================================================="
