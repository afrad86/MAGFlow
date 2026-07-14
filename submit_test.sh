#!/bin/bash
#BSUB -J MAGFlow_test
#BSUB -q basement
#BSUB -n 1
#BSUB -M 4096MB
#BSUB -R "select[mem>=4096MB] rusage[mem=4096MB]"
#BSUB -W 04:00
#BSUB -o logs/test.%J.out
#BSUB -e logs/test.%J.err

set -euo pipefail

cd ~/pipelines/MAGFlow

mkdir -p logs
RUN_ID=$(date +%Y%m%d_%H%M%S)

echo "=================================================="
echo "MAGFlow TEST started : $(date)"
echo "Host                 : $(hostname)"
echo "Directory            : $(pwd)"
echo "=================================================="

~/software/nextflow run main.nf \
    -profile test \
    -resume \
    "$@" \
    -with-report logs/test_report_${RUN_ID}.html \
    -with-trace logs/test_trace_${RUN_ID}.txt \
    -with-timeline logs/test_timeline_${RUN_ID}.html \
    -with-dag logs/test_dag_${RUN_ID}.html

echo "=================================================="
echo "MAGFlow TEST finished : $(date)"
echo "=================================================="
