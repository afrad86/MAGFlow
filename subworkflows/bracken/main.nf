nextflow.enable.dsl=2

include { BRACKEN } from '../../modules/taxonomy/bracken'

workflow BRACKEN_WORKFLOW {

    take:
    kraken_report

    main:
    BRACKEN(kraken_report)

    emit:
    results = BRACKEN.out.results
    report  = BRACKEN.out.report
    version = BRACKEN.out.version
}
