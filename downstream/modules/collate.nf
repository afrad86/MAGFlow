process COLLATE_FEATURES {
    tag 'cohort feature tables'
    publishDir "${params.outdir}/tables", mode: 'copy', overwrite: false

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
