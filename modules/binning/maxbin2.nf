process MAXBIN2 {

    tag "${sample}"

    publishDir "${params.outdir}/05_binning/maxbin2",
        mode: 'copy',
        overwrite: true

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(contigs),
        path(reads_r1),
        path(reads_r2)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_maxbin2"),
        emit: bins
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.maxbin2.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow MaxBin2"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        run_MaxBin.pl -version

    } > ${sample}.maxbin2.version.txt 2>&1

    mkdir -p ${sample}_maxbin2

    run_MaxBin.pl \
        -contig ${contigs} \
        -reads ${reads_r1} \
        -reads2 ${reads_r2} \
        -out ${sample}_maxbin2/${sample} \
        -thread ${task.cpus}

    if ls ${sample}_maxbin2/*.fasta >/dev/null 2>&1 || \
       ls ${sample}_maxbin2/*.fa >/dev/null 2>&1
    then
        echo "MaxBin2 produced bins."
    else
        echo "[WARNING] \$(date): MaxBin2 produced no bins for ${sample}."
        touch ${sample}_maxbin2/NO_BINS.txt
    fi
    """
}
