include { BAKTA } from '../../modules/annotation/bakta'

workflow BAKTA_WORKFLOW {

    take:
    dastool_results

    main:

    BAKTA(
        dastool_results
    )

    emit:

    results = BAKTA.out.results

    version = BAKTA.out.version
}
