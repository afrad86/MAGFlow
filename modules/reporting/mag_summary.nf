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
        val(intervention_arm),
        path(checkm2_dir),
        path(gtdbtk_dir),
        val(prokka_results),
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
    def visit_value = visit?.trim() ? visit : "NA"
    """
    set -euo pipefail

    mkdir -p ${sample}_summary
    mkdir -p ${sample}_prokka

    ###########################################################################
    # Reconstruct Prokka directory
    ###########################################################################

    ${prokka_results.collect { mag, prokka_dir ->
        "ln -sfn ${prokka_dir} ${sample}_prokka/${mag}_prokka"
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
        echo "Participant: ${participant_id}"
        echo "Visit     : ${visit}"
        echo "Arm       : ${intervention_arm}"
        echo

        python3 --version

    } > ${sample}.summary.version.txt 2>&1

    ###########################################################################
    # Merge summary
    ###########################################################################

    python3 ${projectDir}/bin/merge_summary.py \
        --checkm2 ${checkm2_dir}/quality_report.tsv \
        --gtdbtk ${gtdbtk_dir}/gtdbtk.bac120.summary.tsv \
        --prokka ${sample}_prokka \
        --coverm ${coverm_dir}/mag_abundance.normalized.tsv \
        --sample ${sample} \
        --participant ${participant_id} \
        --visit ${visit_value} \
        --intervention-arm ${intervention_arm} \
        --output ${sample}_summary/mag_summary.tsv
    """
}