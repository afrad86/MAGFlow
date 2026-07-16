nextflow.enable.dsl=2

include { CHECKM2 } from '../../modules/qc/checkm2'

workflow CHECKM2_WORKFLOW {

    take:
    bins

    main:

    CHECKM2(bins)

    emit:

    results = CHECKM2.out.results
    version = CHECKM2.out.version
}