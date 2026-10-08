process EGGNOG_ANNOTATE {
    tag "${sample}:${mag}"
    publishDir "${params.outdir}/16_eggnog/${params.batch_id}", mode: 'copy', overwrite: false

    input:
    tuple val(sample), val(participant), val(visit), val(mag), val(species), path(genome), path(proteins)
    val dataDir
    val sensitivity
    val extraOptions

    output:
    path("${sample}__${mag}_eggnog.tsv"), emit: table

    script:
    """
    set -euo pipefail
    emapper.py --data_dir '${dataDir}' --input '${proteins}' --itype proteins \\
      --output eggnog --output_dir . --cpu ${task.cpus} --sensmode '${sensitivity}' ${extraOptions}
    python3 '${projectDir}/scripts/normalize_eggnog.py' \\
      --input eggnog.emapper.annotations --output '${sample}__${mag}_eggnog.tsv' \\
      --sample '${sample}' --participant '${participant}' --visit '${visit}' --mag '${mag}'
    """
}
