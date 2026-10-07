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
        "${record[0]}\t${record[1]}\t${record[2]}\t${record[3] ? 'NEW' : 'OLD'}\t${genomes[i]}"
    }.join('\n')
    def rowsB64 = rows.getBytes('UTF-8').encodeBase64().toString()
    """
    set -euo pipefail
    python3 -c 'import base64,sys;sys.stdout.buffer.write(base64.b64decode(sys.argv[1]))' '${rowsB64}' > genome_manifest.tsv
    awk -F '\t' '\$4 == "NEW" {print \$5}' genome_manifest.tsv > new_genomes.txt
    awk -F '\t' '\$4 == "OLD" {print \$5}' genome_manifest.tsv > old_genomes.txt
    cut -f5 genome_manifest.tsv > all_genomes.txt
    fastANI --ql new_genomes.txt --rl all_genomes.txt --output fastani.new.raw.tsv --threads ${task.cpus}
    cp fastani.new.raw.tsv fastani.raw.tsv
    if [ -s old_genomes.txt ]; then
      fastANI --ql old_genomes.txt --rl new_genomes.txt --output fastani.old_new.raw.tsv --threads ${task.cpus}
      cat fastani.old_new.raw.tsv >> fastani.raw.tsv
    fi
    python3 '${projectDir}/scripts/normalize_fastani.py' \\
      --input fastani.raw.tsv --manifest genome_manifest.tsv \\
      --output '${groupLabel}_fastani.tsv' --participant '${participant}' --species '${species}'
    """.stripIndent()
}
