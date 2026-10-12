process COLLATE_FEATURES {
    tag 'cohort feature tables'
    // Re-running an incomplete batch with -resume must replace its partial
    // collated tables with the complete tables from the resumed run.
    publishDir "${params.outdir}/18_summary/batches/${params.batch_id}", mode: 'copy', overwrite: true

    input:
    path amrFiles
    path vfdbFiles
    path eggnogFiles
    path strainFiles

    output:
    path 'amr_features.tsv', emit: amr
    path 'virulence_features.tsv', emit: virulence
    path 'functional_annotations.tsv', emit: function
    path 'strain_pairwise_fastani.tsv', emit: strain

    script:
    """
    python3 '${projectDir}/scripts/collate.py'
    """
}
