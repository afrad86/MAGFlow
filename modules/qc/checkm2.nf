process CHECKM2 {

    tag "${sample}"

    publishDir "${params.outdir}/07_checkm2",
    mode: 'copy',
    overwrite: true,
    saveAs: { filename ->

        if (filename == "${sample}_checkm2") {
            return "${sample}/${filename}"
        }

        if (filename == "${sample}.checkm2.version.txt") {
            return "${sample}/${filename}"
        }

        return null
    }

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(dastool_dir)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_checkm2"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.checkm2.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow CheckM2"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which checkm2
        echo

        checkm2 --help | head -5

    } > ${sample}.checkm2.version.txt 2>&1

    checkm2 predict \
        --input ${dastool_dir}/${sample}_DASTool_bins \
        --extension fa \
        --output-directory ${sample}_checkm2 \
        --threads ${task.cpus}
    """
}