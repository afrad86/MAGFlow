process MAG_SUMMARY {

    tag "${sample}"

    publishDir "${params.outdir}/09_summary",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${sample}_summary") {
                return "${sample}/${filename}"
            }

            if (filename == "${sample}.summary.version.txt") {
                return "${sample}/${filename}"
            }

            return null
        }

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(checkm2_dir),
        path(gtdbtk_dir)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_summary"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.summary.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    mkdir -p ${sample}_summary

    {
        echo "========================================"
        echo "MAGFlow MAG Summary"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
    } > ${sample}.summary.version.txt

    cp ${checkm2_dir}/quality_report.tsv ${sample}_summary/
    cp ${gtdbtk_dir}/gtdbtk.bac120.summary.tsv ${sample}_summary/
    """
}
