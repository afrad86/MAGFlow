process STRAIN_FASTANI {
    tag "${participant}:${species}"
    publishDir "${params.outdir}/per_group/strain", mode: 'copy', overwrite: false

    input:
    tuple val(participant), val(species), val(records), path(genomes, stageAs: '?/*')

    output:
    path("${participant}__${species.replaceAll(/[^A-Za-z0-9_.-]+/, '_')}_fastani.tsv"), emit: table

    script:
    def groupLabel = "${participant}__${species.replaceAll(/[^A-Za-z0-9_.-]+/, '_')}"
    def rows = records.withIndex().collect { record, i ->
        "${record[0]}\t${record[1]}\t${record[2]}\t${genomes[i]}"
    }.join('\n')
    def rowsB64 = rows.getBytes('UTF-8').encodeBase64().toString()
    """
    set -euo pipefail
    python3 -c 'import base64,sys;sys.stdout.buffer.write(base64.b64decode(sys.argv[1]))' '${rowsB64}' > genome_manifest.tsv
    cut -f4 genome_manifest.tsv > genome_list.txt
    touch fastani.raw.tsv
    fastANI --ql genome_list.txt --rl genome_list.txt --output fastani.raw.tsv --threads ${task.cpus}
    python3 '${projectDir}/scripts/normalize_fastani.py' \\
      --input fastani.raw.tsv --manifest genome_manifest.tsv \\
      --output '${groupLabel}_fastani.tsv' --participant '${participant}' --species '${species}'
    """.stripIndent()
}
