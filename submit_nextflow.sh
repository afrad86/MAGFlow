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

cd ~/pipelines/MAGFlow

mkdir -p logs
RUN_ID=$(date +%Y%m%d_%H%M%S)

echo "=================================================="
echo "MAGFlow started : $(date)"
echo "Host            : $(hostname)"
echo "Directory       : $(pwd)"
echo "=================================================="

~/software/nextflow run main.nf \
    -profile farm22 \
    -resume \
    "$@" \
    -with-report logs/report_${RUN_ID}.html \
    -with-trace logs/trace_${RUN_ID}.txt \
    -with-timeline logs/timeline_${RUN_ID}.html \
    -with-dag logs/dag_${RUN_ID}.html

echo "=================================================="
echo "MAGFlow finished: $(date)"
echo "=================================================="
