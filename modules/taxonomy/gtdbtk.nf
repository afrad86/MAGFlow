process GTDBTK {

    tag "${sample}"

    publishDir "${params.outdir}/08_gtdbtk",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${sample}_gtdbtk") {
                return "${sample}/${filename}"
            }

            if (filename == "${sample}.gtdbtk.version.txt") {
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
        path("${sample}_gtdbtk"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.gtdbtk.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    ###########################################################################
    # Version
    ###########################################################################

    {
        echo "========================================"
        echo "MAGFlow GTDB-Tk"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which gtdbtk
        echo

        gtdbtk --version

    } > ${sample}.gtdbtk.version.txt 2>&1

    ###########################################################################
    # Run GTDB-Tk
    ###########################################################################

    gtdbtk classify_wf \
        --genome_dir ${dastool_dir}/${sample}_DASTool_bins \
        --extension fa \
        --out_dir ${sample}_gtdbtk \
        --cpus ${task.cpus}
    """
}