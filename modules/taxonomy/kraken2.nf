/*
 * ============================================================================
 * MAGFlow
 * Module: Kraken2 Read-Level Taxonomic Classification
 * ============================================================================
 */

process KRAKEN2 {

    tag "${sample}"

    publishDir "${params.outdir}/12_kraken2",
        mode: 'copy',
        overwrite: true

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(reads_r1),
        path(reads_r2)
    )

    output:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.kraken2.report.tsv"),
        emit: report
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.kraken2.output.tsv"),
        emit: output
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.kraken2.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow Kraken2"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo
        which kraken2
        kraken2 --version
    } > ${sample}.kraken2.version.txt 2>&1

    kraken2 \
        --db ${params.kraken2_db} \
        --threads ${task.cpus} \
        --paired \
        --use-names \
        --report-zero-counts \
        --report ${sample}.kraken2.report.tsv \
        --output ${sample}.kraken2.output.tsv \
        ${reads_r1} ${reads_r2}
    """
}
