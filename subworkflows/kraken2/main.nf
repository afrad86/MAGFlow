nextflow.enable.dsl=2

include { KRAKEN2 } from '../../modules/taxonomy/kraken2'

workflow KRAKEN2_WORKFLOW {

    take:
    reads

    main:
    KRAKEN2(reads)

    emit:
    report = KRAKEN2.out.report
    output = KRAKEN2.out.output
    version = KRAKEN2.out.version
}
