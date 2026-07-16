process BAKTA {

    tag "${sample}"

    publishDir "${params.outdir}/10_bakta",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${sample}_bakta") {
                return "${sample}/${filename}"
            }

            if (filename == "${sample}.bakta.version.txt") {
                return "${sample}/${filename}"
            }

            return null
        }

    input:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(dastool_dir)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_bakta"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.bakta.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    mkdir -p ${sample}_bakta

    ###########################################################################
    # Version
    ###########################################################################

    {
        echo "========================================"
        echo "MAGFlow Bakta"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which bakta
        echo

        bakta --version

    } > ${sample}.bakta.version.txt 2>&1


    ###########################################################################
    # Annotate all MAGs
    ###########################################################################

    shopt -s nullglob

    genomes=( ${dastool_dir}/${sample}_DASTool_bins/*.fa )

    if [ \${#genomes[@]} -eq 0 ]; then
        echo "ERROR: No MAG FASTA files found."
        exit 1
    fi

    for genome in "\${genomes[@]}"
    do

        mag=\$(basename "\$genome" .fa)

        bakta \
            --threads ${task.cpus} \
            --output ${sample}_bakta/\${mag} \
            "\$genome"

    done
    """
}
