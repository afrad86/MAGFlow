process STRAIN_FASTANI {
    tag "${participant}:${species}"
    publishDir "${params.outdir}/17_fastani/${params.batch_id}", mode: 'copy', overwrite: false

    input:
    tuple val(participant), val(species), val(records), path(genomes, stageAs: '?/*')

    output:
    path("${participant}__${species.replaceAll(/[^A-Za-z0-9_.-]+/, '_')}_fastani.tsv"), emit: table

    script:
    def groupLabel = "${participant}__${species.replaceAll(/[^A-Za-z0-9_.-]+/, '_')}"
    // Nextflow binds a single `path` value as a scalar, but a multi-file
    // `path` value as a collection. Normalize it before pairing with records.
    def genomeFiles = genomes instanceof Collection ? genomes.toList() : [genomes]
    if (records.size() != genomeFiles.size()) {
        throw new IllegalStateException("${records.size()} MAG records but ${genomeFiles.size()} staged genome files for ${participant}/${species}")
    }
    def rows = records.withIndex().collect { record, i ->
        "${record[0]}\t${record[1]}\t${record[2]}\t${record[3] ? 'NEW' : 'OLD'}\t${genomeFiles[i]}"
    }.join('\n')
    def rowsB64 = rows.getBytes('UTF-8').encodeBase64().toString()
    """
    set -euo pipefail
    python3 -c 'import base64,sys;sys.stdout.buffer.write(base64.b64decode(sys.argv[1]))' '${rowsB64}' > genome_manifest.tsv
    # FastANI uses 3 kb fragments by default and can crash on an empty query
    # list or FASTAs without any contig long enough to yield a fragment.
    python3 '${projectDir}/scripts/filter_fastani_genomes.py' --manifest genome_manifest.tsv \
      --new new_genomes.eligible.txt --old old_genomes.eligible.txt --all all_genomes.eligible.txt
    if [ -s new_genomes.eligible.txt ] && [ -s all_genomes.eligible.txt ]; then
      fastANI --ql new_genomes.eligible.txt --rl all_genomes.eligible.txt --output fastani.new.raw.tsv --threads ${task.cpus}
    else
      : > fastani.new.raw.tsv
    fi
    cp fastani.new.raw.tsv fastani.raw.tsv
    if [ -s old_genomes.eligible.txt ] && [ -s new_genomes.eligible.txt ]; then
      fastANI --ql old_genomes.eligible.txt --rl new_genomes.eligible.txt --output fastani.old_new.raw.tsv --threads ${task.cpus}
      cat fastani.old_new.raw.tsv >> fastani.raw.tsv
    fi
    python3 '${projectDir}/scripts/normalize_fastani.py' \\
      --input fastani.raw.tsv --manifest genome_manifest.tsv \\
      --output '${groupLabel}_fastani.tsv' --participant '${participant}' --species '${species}'
    """.stripIndent()
}
