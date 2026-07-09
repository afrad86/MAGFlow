process FASTP {

    tag "${sample}"

    publishDir "${params.outdir}/01_fastp", mode: 'copy'

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
      path("${sample}.trimmed_R1.fastq.gz"),
      path("${sample}.trimmed_R2.fastq.gz"),
      emit: reads

path("${sample}.fastp.html"), emit: html

path("${sample}.fastp.json"), emit: json

    script:
    """
    fastp \
        --in1 ${reads_r1} \
        --in2 ${reads_r2} \
        --out1 ${sample}.trimmed_R1.fastq.gz \
        --out2 ${sample}.trimmed_R2.fastq.gz \
        --thread ${task.cpus} \
        --html ${sample}.fastp.html \
        --json ${sample}.fastp.json \
        --report_title "MAGFlow : ${sample}"
    """
}
