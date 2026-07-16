include { PIPELINE_INFO } from '../../modules/reporting/pipeline_info'

workflow PIPELINE_INFO_WORKFLOW {

    main:

    PIPELINE_INFO()

    emit:

    info = PIPELINE_INFO.out.info
}