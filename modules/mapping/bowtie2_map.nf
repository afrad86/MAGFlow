process BOWTIE2_MAP {

    tag "${sample}"

    publishDir "${params.outdir}/04_mapping/bam",
        mode: 'copy',
        overwrite: true,
        pattern: "*.sorted.bam"

    publishDir "${params.outdir}/04_mapping/bai",
        mode: 'copy',
        overwrite: true,
        pattern: "*.sorted.bam.bai"

    publishDir "${params.outdir}/04_mapping/logs",
        mode: 'copy',
        overwrite: true,
        pattern: "*.bowtie2.log"

    publishDir "${params.outdir}/04_mapping/reports",
        mode: 'copy',
        overwrite: true,
        pattern: "*.bowtie2.version.txt"

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(index_files),
        path(reads_r1),
        path(reads_r2)
    )

    output:

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.sorted.bam"),
        emit: bam

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.sorted.bam.bai"),
        emit: bai
    
    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.sorted.bam"),
        path("${sample}.sorted.bam.bai"),
        emit: alignment

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bowtie2.log"),
        emit: log

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bowtie2.version.txt"),
        emit: version

    script:
    """
    set -euo pipefail

    module load bowtie2/2.5.1--py38he00c5e5_2
    module load samtools/1.21

    {
        echo "========================================"
        echo "MAGFlow Bowtie2 Mapping"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo
        echo "Bowtie2:"
        bowtie2 --version
        echo
        echo "Samtools:"
        samtools --version
    } > ${sample}.bowtie2.version.txt 2>&1

    if [[ ! -f ${sample}.bowtie2.version.txt ]]; then
        echo "ERROR: Failed to create version file." >&2
        exit 1
    fi

    bowtie2 \
        -x ${sample} \
        -1 ${reads_r1} \
        -2 ${reads_r2} \
        -p ${task.cpus} \
        2> ${sample}.bowtie2.log \
    | samtools view \
        -@ ${task.cpus} \
        -b - \
    | samtools sort \
        -@ ${task.cpus} \
        -o ${sample}.sorted.bam

    samtools index \
        -@ ${task.cpus} \
        ${sample}.sorted.bam

    [[ -f ${sample}.sorted.bam ]] || { echo "ERROR: Missing sorted BAM."; exit 1; }
    [[ -f ${sample}.sorted.bam.bai ]] || { echo "ERROR: Missing BAM index."; exit 1; }
    [[ -f ${sample}.bowtie2.log ]] || { echo "ERROR: Missing Bowtie2 log."; exit 1; }
    """
}