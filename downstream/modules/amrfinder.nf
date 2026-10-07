process AMRFINDER {
    tag "${sample}:${mag}"
    publishDir "${params.outdir}/per_mag/amr", mode: 'copy', overwrite: false

    input:
    tuple val(sample), val(participant), val(visit), val(mag), val(species), path(genome)
    val database

    output:
    path("${sample}__${mag}_amr.tsv"), emit: table

    script:
    def organismArg = params.amrfinder_organism ? "--organism '${params.amrfinder_organism}'" : ''
    """
    set -euo pipefail
    amrfinder --nucleotide '${genome}' --database '${database}' \\
      --threads ${task.cpus} ${organismArg} --output amrfinder.raw.tsv
    python3 '${projectDir}/scripts/normalize_amr.py' \\
      --input amrfinder.raw.tsv --output '${sample}__${mag}_amr.tsv' \\
      --sample '${sample}' --participant '${participant}' --visit '${visit}' --mag '${mag}'
    """
}
