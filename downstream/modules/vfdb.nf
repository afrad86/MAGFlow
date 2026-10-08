process VFDB_SEARCH {
    tag "${sample}:${mag}"
    publishDir "${params.outdir}/15_vfdb/${params.batch_id}", mode: 'copy', overwrite: false

    input:
    tuple val(sample), val(participant), val(visit), val(mag), val(species), path(genome), path(proteins)
    val database
    val minIdentity
    val minQueryCover
    val evalue

    output:
    path("${sample}__${mag}_vfdb.tsv"), emit: table

    script:
    """
    set -euo pipefail
    diamond blastp --query '${proteins}' --db '${database}' \\
      --out vfdb.raw.tsv --outfmt 6 qseqid sseqid pident length qlen slen evalue bitscore stitle \\
      --evalue '${evalue}' --id ${minIdentity} --query-cover ${minQueryCover} \\
      --max-target-seqs 25 --threads ${task.cpus}
    python3 '${projectDir}/scripts/normalize_vfdb.py' \\
      --input vfdb.raw.tsv --output '${sample}__${mag}_vfdb.tsv' \\
      --sample '${sample}' --participant '${participant}' --visit '${visit}' --mag '${mag}'
    """
}
