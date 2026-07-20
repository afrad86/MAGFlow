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
        path(gtdbtk_dir),
        val(bakta_results),
        path(coverm_dir)
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
    mkdir -p ${sample}_bakta

    ###########################################################################
    # Reconstruct Bakta directory
    ###########################################################################

    ${bakta_results.collect { mag, bakta_dir ->
        "ln -s ${bakta_dir} ${sample}_bakta/${mag}_bakta"
    }.join('\n')}

    ###########################################################################
    # Version
    ###########################################################################

    {
        echo "========================================"
        echo "MAGFlow MAG Summary"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo

        python3 --version

    } > ${sample}.summary.version.txt 2>&1

    ###########################################################################
    # Merge summary
    ###########################################################################

    python3 ${projectDir}/bin/merge_summary.py \
        --checkm2 ${checkm2_dir}/quality_report.tsv \
        --gtdbtk ${gtdbtk_dir}/gtdbtk.bac120.summary.tsv \
        --bakta ${sample}_bakta \
        --coverm ${coverm_dir}/mag_abundance.normalized.tsv \
        --sample ${sample} \
        --participant ${participant_id} \
        --visit ${visit} \
        --output ${sample}_summary/mag_summary.tsv
    """
}