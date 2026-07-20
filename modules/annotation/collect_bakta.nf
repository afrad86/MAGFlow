process COLLECT_BAKTA {

    tag "${sample}"

    publishDir "${params.outdir}/10_bakta",
        mode: 'copy',
        overwrite: true

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        val(mag),
        path(bakta_dir)
    )

    output:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_bakta"),
        emit: results
    )

    script:
    """
    mkdir -p ${sample}_bakta

    cp -r ${bakta_dir} ${sample}_bakta/
    """
}
