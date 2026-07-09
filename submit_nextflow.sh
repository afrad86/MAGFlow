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

echo "=================================================="
echo "MAGFlow started : $(date)"
echo "Host            : $(hostname)"
echo "Directory       : $(pwd)"
echo "=================================================="

~/software/nextflow run main.nf \
    -profile farm22 \
    "$@" \
    -with-report logs/report.html \
    -with-trace logs/trace.txt \
    -with-timeline logs/timeline.html \
    -with-dag logs/dag.html

echo "=================================================="
echo "MAGFlow finished: $(date)"
echo "=================================================="