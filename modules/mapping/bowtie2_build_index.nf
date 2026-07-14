process BOWTIE2_BUILD_INDEX {

    tag "${sample}"

    publishDir "${params.outdir}/04_mapping/index",
        mode: 'copy',
        overwrite: true,
        pattern: "*.bt2"

    publishDir "${params.outdir}/04_mapping/reports",
        mode: 'copy',
        overwrite: true,
        pattern: "*.bowtie2_build.version.txt"

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(contigs)
    )

    output:

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("*.bt2"),
        emit: index

    tuple val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bowtie2_build.version.txt"),
        emit: version

    script:
    """
    set -euo pipefail

    module load bowtie2/2.5.1--py38he00c5e5_2

    echo "Sample: ${sample}" > ${sample}.bowtie2_build.version.txt
    bowtie2-build --version >> ${sample}.bowtie2_build.version.txt 2>&1

    bowtie2-build \
        ${contigs} \
        ${sample}

    for file in \
        ${sample}.1.bt2 \
        ${sample}.2.bt2 \
        ${sample}.3.bt2 \
        ${sample}.4.bt2 \
        ${sample}.rev.1.bt2 \
        ${sample}.rev.2.bt2
    do
        if [[ ! -f \$file ]]; then
            echo "ERROR: Missing Bowtie2 index file: \$file" >&2
            exit 1
        fi
    done
    """
}