process DASTOOL {

    tag "${sample}"

    publishDir "${params.outdir}/06_dastool",
        mode: 'copy',
        overwrite: true

    input:
    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(contigs),
        path(metabat2_bins),
        path(concoct_bins),
        path(maxbin2_bins)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_dastool"),
        emit: bins
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.dastool.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    ###############################################################################
    # 1. Version
    ###############################################################################

    {
        echo "========================================"
        echo "MAGFlow DAS Tool"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which DAS_Tool
        echo

        DAS_Tool --version

    } > ${sample}.dastool.version.txt 2>&1

    mkdir -p ${sample}_dastool

    ###############################################################################
    # 2. Generate contig2bin tables
    ###############################################################################

    fasta_to_contig2bin.py \
        -i ${metabat2_bins} \
        -o ${sample}_dastool/metabat2.tsv

    fasta_to_contig2bin.py \
        -i ${concoct_bins} \
        -o ${sample}_dastool/concoct.tsv

    fasta_to_contig2bin.py \
        -i ${maxbin2_bins} \
        -o ${sample}_dastool/maxbin2.tsv

    ###############################################################################
    # 3. Build DAS Tool input
    ###############################################################################

    INPUTS=""
    LABELS=""

    add_input () {

        FILE=\$1
        LABEL=\$2

        if [ -s "\$FILE" ]; then

            if [ -z "\$INPUTS" ]; then

                INPUTS="\$FILE"
                LABELS="\$LABEL"

            else

                INPUTS="\${INPUTS},\${FILE}"
                LABELS="\${LABELS},\${LABEL}"

            fi
        fi
    }

    add_input ${sample}_dastool/metabat2.tsv metabat2
    add_input ${sample}_dastool/concoct.tsv concoct
    add_input ${sample}_dastool/maxbin2.tsv maxbin2

    ###############################################################################
    # 4. Run DAS Tool
    ###############################################################################

    if [ -n "\$INPUTS" ]; then

        DAS_Tool \
            -i "\$INPUTS" \
            -l "\$LABELS" \
            -c ${contigs} \
            -o ${sample}_dastool/${sample} \
            --score_threshold ${params.dastool_score_threshold} \
            --write_bins \
            -t ${task.cpus}

    else

        echo "[WARNING] No bins available for DAS Tool."

        touch ${sample}_dastool/NO_BINS.txt

    fi

    ###############################################################################
    # 5. Validate output
    ###############################################################################

    BIN_COUNT=\$(find ${sample}_dastool/${sample}_DASTool_bins \
        -type f \
        -name "*.fa" 2>/dev/null | wc -l)

    echo "DAS Tool produced \$BIN_COUNT MAG bin(s)."

    if [ "\$BIN_COUNT" -eq 0 ]; then
        echo "[ERROR] DAS Tool produced no MAG bins."
        exit 1
    fi
    """
}