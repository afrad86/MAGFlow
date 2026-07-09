/*
 * ============================================================================
 * MAGFlow
 * Subworkflow: Preprocessing
 * ============================================================================
 */

include { FASTP } from '../../modules/preprocessing/fastp'
include { BOWTIE2_HOST_REMOVAL } from '../../modules/preprocessing/bowtie2_host_removal'

workflow PREPROCESSING {

    take:
    samples_ch

    main:

    fastp_out = FASTP(samples_ch)

    host_removed_out = BOWTIE2_HOST_REMOVAL(fastp_out.reads)

    emit:

    reads = host_removed_out.reads

    fastp_html = fastp_out.html

    fastp_json = fastp_out.json

    bowtie2_log = host_removed_out.log

    bowtie2_metrics = host_removed_out.metrics

}
