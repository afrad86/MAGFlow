process METASPADES {

    tag "${sample}"

    publishDir "${params.outdir}/03_assembly/contigs",
        mode: 'copy',
        pattern: "*.contigs.fasta"

    publishDir "${params.outdir}/03_assembly/scaffolds",
        mode: 'copy',
        pattern: "*.scaffolds.fasta"

    publishDir "${params.outdir}/03_assembly/graphs",
        mode: 'copy',
        pattern: "*.assembly_graph_with_scaffolds.gfa"

    publishDir "${params.outdir}/03_assembly/reports",
        mode: 'copy',
        pattern: "*.metaspades.log"

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
          path("${sample}.contigs.fasta"),
          emit: contigs

    script:
    """
    metaspades.py \
        -1 ${reads_r1} \
        -2 ${reads_r2} \
        -t ${task.cpus} \
        -m ${task.memory.toGiga()} \
        -o spades_out

    cp spades_out/contigs.fasta ${sample}.contigs.fasta
    cp spades_out/scaffolds.fasta ${sample}.scaffolds.fasta
    cp spades_out/assembly_graph_with_scaffolds.gfa ${sample}.assembly_graph_with_scaffolds.gfa
    cp spades_out/spades.log ${sample}.metaspades.log
    """
}