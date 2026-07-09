/*
 * ============================================================================
 * MAGFlow
 * Module: Bowtie2 Host Removal
 * Purpose: Remove host (human) reads from paired-end metagenomic FASTQ files.
 * ============================================================================
 */

process BOWTIE2_HOST_REMOVAL {

    tag "${participant_id}_${visit}"

    publishDir "${params.outdir}/02_host_removal/reads",
        mode: 'copy',
        pattern: "*.host_removed_*.fastq.gz"

    publishDir "${params.outdir}/02_host_removal/logs",
        mode: 'copy',
        pattern: "*.bowtie2.log"

    publishDir "${params.outdir}/02_host_removal/metrics",
        mode: 'copy',
        pattern: "*.bowtie2.metrics.txt"

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(reads_r1),
        path(reads_r2)
    )

    output:
tuple val(sample),
      val(participant_id),
      val(visit),
      path("${sample}.host_removed_R1.fastq.gz"),
      path("${sample}.host_removed_R2.fastq.gz"),
      emit: reads

path("${sample}.bowtie2.log"), emit: log

path("${sample}.bowtie2.metrics.txt"), emit: metrics

    script:
    """
    bowtie2 \
        --very-sensitive \
        --threads ${task.cpus} \
        --met-file ${sample}.bowtie2.metrics.txt \
        -x ${params.reference_host} \
        -1 ${reads_r1} \
        -2 ${reads_r2} \
        2> ${sample}.bowtie2.log \
    | samtools view \
        -b \
        -f 12 \
        -F 256 \
    | samtools fastq \
        -1 ${sample}.host_removed_R1.fastq.gz \
        -2 ${sample}.host_removed_R2.fastq.gz \
        -0 /dev/null \
        -s /dev/null \
        -n

    gzip -t ${sample}.host_removed_R1.fastq.gz
    gzip -t ${sample}.host_removed_R2.fastq.gz
    """
}
