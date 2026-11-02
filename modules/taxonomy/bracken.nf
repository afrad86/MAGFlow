/*
 * ============================================================================
 * MAGFlow
 * Module: Bracken Read-Level Taxonomic Abundance Estimation
 * ============================================================================
 */

process BRACKEN {

    tag "${sample}"

    publishDir "${params.outdir}/13_bracken",
        mode: 'copy',
        overwrite: true

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(kraken_report)
    )

    output:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bracken.tsv"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bracken.report.tsv"),
        emit: report
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bracken.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow Bracken"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"

        echo "Bracken module: bracken/2.6.2"
        echo "Executable    : \$(which bracken)"

    } > ${sample}.bracken.version.txt

    bracken \
        -d ${params.kraken2_db} \
        -i ${kraken_report} \
        -o ${sample}.bracken.tsv \
        -w ${sample}.bracken.report.tsv \
        -r 150 \
        -l S \
        -t 0
    """
}
