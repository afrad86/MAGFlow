process METABAT2 {

    tag "${sample}"

    publishDir "${params.outdir}/05_binning/metabat2/${sample}",
        mode: 'copy',
        overwrite: true,
        pattern: "${sample}_metabat2/*"

    publishDir "${params.outdir}/05_binning/metabat2/${sample}",
        mode: 'copy',
        overwrite: true,
        pattern: "*.metabat2.version.txt"

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(contigs),
        path(bam),
        path(bai)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_metabat2"),
        emit: bins
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.metabat2.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

{
    echo "========================================"
    echo "MAGFlow MetaBAT2"
    echo "========================================"
    echo "Date      : \$(date)"
    echo "Host      : \$(hostname)"
    echo "Sample    : ${sample}"
    echo "CPUs      : ${task.cpus}"
    echo "Memory    : ${task.memory.toGiga()} GB"
    echo

    which metabat2

    echo

    metabat2 -h | head -20 || true

} > ${sample}.metabat2.version.txt 2>&1

    mkdir -p ${sample}_metabat2

    jgi_summarize_bam_contig_depths \
        --outputDepth depth.txt \
        ${bam}

    metabat2 \
        -i ${contigs} \
        -a depth.txt \
        -o ${sample}_metabat2/bin \
        -t ${task.cpus}

    if ls ${sample}_metabat2/*.fa >/dev/null 2>&1; then
        echo "MetaBAT2 produced bins."
    else
        echo "[WARNING] \$(date): MetaBAT2 produced no bins for ${sample}."
        touch ${sample}_metabat2/NO_BINS.txt
    fi
    """
}
