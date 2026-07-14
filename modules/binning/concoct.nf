process CONCOCT {

    tag "${sample}"

    publishDir "${params.outdir}/05_binning/concoct/${sample}",
        mode: 'copy',
        overwrite: true,
        pattern: "${sample}_concoct/bins/*"

    publishDir "${params.outdir}/05_binning/concoct/${sample}",
        mode: 'copy',
        overwrite: true,
        pattern: "*.concoct.version.txt"

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
        path("${sample}_concoct"),
        emit: bins
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.concoct.version.txt"),
        emit: version
    )

    script:
    """
    set -euo pipefail

    {
        echo "========================================"
        echo "MAGFlow CONCOCT"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        which concoct
        echo

        concoct --version

    } > ${sample}.concoct.version.txt 2>&1

    mkdir -p ${sample}_concoct
    mkdir -p ${sample}_concoct/concoct_output
    mkdir -p ${sample}_concoct/bins

    ###############################################################################
    # 1. Cut contigs
    ###############################################################################

    cut_up_fasta.py \
        ${contigs} \
        -c 10000 \
        -o 0 \
        --merge_last \
        -b ${sample}_concoct/contigs_10K.bed \
        > ${sample}_concoct/contigs_10K.fa

    ###############################################################################
    # 2. Coverage table
    ###############################################################################

    concoct_coverage_table.py \
        ${sample}_concoct/contigs_10K.bed \
        ${bam} \
        > ${sample}_concoct/coverage_table.tsv

    ###############################################################################
    # 3. Run CONCOCT
    ###############################################################################

    concoct \
        --composition_file ${sample}_concoct/contigs_10K.fa \
        --coverage_file ${sample}_concoct/coverage_table.tsv \
        -b ${sample}_concoct/concoct_output/

    ###############################################################################
    # 4. Merge cut-up contigs
    ###############################################################################

    merge_cutup_clustering.py \
        ${sample}_concoct/concoct_output/clustering_gt1000.csv \
        > ${sample}_concoct/clustering_merged.csv

    ###############################################################################
    # 5. Extract bins
    ###############################################################################

    extract_fasta_bins.py \
        ${contigs} \
        ${sample}_concoct/clustering_merged.csv \
        --output_path ${sample}_concoct/bins

    ###############################################################################
    # 6. Validate output
    ###############################################################################

    if ls ${sample}_concoct/bins/*.fa >/dev/null 2>&1; then
        echo "CONCOCT produced bins."
    else
        echo "[WARNING] \$(date): CONCOCT produced no bins for ${sample}."
        touch ${sample}_concoct/bins/NO_BINS.txt
    fi
    """
}
