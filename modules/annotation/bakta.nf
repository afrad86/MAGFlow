process BAKTA {

    tag "${sample}:${mag}"

    publishDir "${params.outdir}/10_bakta",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${mag}_bakta") {
                return "${sample}/${filename}"
            }

            if (filename == "${mag}.bakta.version.txt") {
                return "${sample}/${filename}"
            }

            return null
        }

    input:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        val(mag),
        path(genome)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        val(mag),
        path("${mag}_bakta"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        val(mag),
        path("${mag}.bakta.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow Bakta"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "MAG       : ${mag}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which bakta
        echo

        bakta --version

    } > ${mag}.bakta.version.txt 2>&1

    bakta \
        --threads ${task.cpus} \
        --output ${mag}_bakta \
        ${genome}
    """
}