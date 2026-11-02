process PROKKA {

    tag "${sample}:${mag}"

    publishDir "${params.outdir}/10_prokka",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${mag}_prokka") {
                return "${sample}/${filename}"
            }

            if (filename == "${mag}.prokka.version.txt") {
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
        path("${mag}_prokka"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        val(mag),
        path("${mag}.prokka.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow Prokka"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "MAG       : ${mag}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which prokka
        echo

        prokka --version

    } > ${mag}.prokka.version.txt 2>&1

    awk '
        /^>/ {
            printf ">contig_%d\\n", ++n
            next
        }
        {
            print
        }
    ' ${genome} > ${mag}.prokka_input.fa

    prokka \
        --outdir ${mag}_prokka \
        --prefix ${mag} \
        --cpus ${task.cpus} \
        --metagenome \
        --centre X \
        --compliant \
        ${mag}.prokka_input.fa
    """
}
