nextflow.enable.dsl=2

include { GTDBTK } from '../../modules/taxonomy/gtdbtk'

workflow GTDBTK_WORKFLOW {

    take:
    bins

    main:

    GTDBTK(bins)

    emit:

    results = GTDBTK.out.results
    version = GTDBTK.out.version
}