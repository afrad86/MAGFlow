nextflow.enable.dsl=2

include { AMRFINDER } from './modules/amrfinder'
include { VFDB_SEARCH } from './modules/vfdb'
include { EGGNOG_ANNOTATE } from './modules/eggnog'
include { STRAIN_FASTANI } from './modules/fastani'
include { COLLATE_FEATURES } from './modules/collate'

workflow {
    if (!params.input) error 'Set --input to the pending (new or changed MAGs) manifest.'
    if (!params.all_input) error 'Set --all_input to the complete current MAG manifest for longitudinal strain comparisons.'
    if (!params.outdir) error 'Set --outdir to the CATI downstream results root.'
    if (!params.batch_id) error 'Set --batch_id to a unique identifier for this downstream batch.'
    if (!params.amrfinder_db || !file(params.amrfinder_db).exists()) {
        error 'Set --amrfinder_db to a prepared AMRFinderPlus database directory.'
    }
    if (!params.vfdb_db || !file("${params.vfdb_db}.dmnd").exists()) {
        error 'Set --vfdb_db to a VFDB DIAMOND database prefix (the .dmnd file must exist).'
    }
    if (!params.eggnog_data || !file(params.eggnog_data).exists()) {
        error 'Set --eggnog_data to an eggNOG-mapper data directory.'
    }

    def required = ['sample', 'participant_id', 'visit', 'mag_id', 'species', 'mag_fasta', 'protein_fasta']
    def manifest_rows = Channel.fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, sep: '\t')
        .map { row ->
            required.each { col ->
                if (!row[col]?.trim()) error "Manifest column '${col}' is empty in row ${row}"
            }
            def fasta = file(row.mag_fasta.trim())
            if (!fasta.exists()) error "MAG FASTA not found for ${row.sample}/${row.mag_id}: ${fasta}"
            def proteins = file(row.protein_fasta.trim())
            if (!proteins.exists()) error "Bakta protein FASTA not found for ${row.sample}/${row.mag_id}: ${proteins}"
            tuple(
                row.sample.trim(), row.participant_id.trim(), row.visit.trim(),
                row.mag_id.trim(), row.species.trim(), fasta, proteins
            )
        }
        .ifEmpty { error "No MAG records found in ${params.input}" }

    // Catch duplicate identifiers without collect(), which flattens tuple
    // fields by default and would make this check index scalar values.
    def manifest = manifest_rows
        .map { row -> tuple([row[0], row[3]], row) }
        .groupTuple()
        .flatMap { key, rows ->
            if (rows.size() > 1) {
                error "Duplicate sample/mag_id in manifest: ${key[0]}/${key[1]}"
            }
            rows
        }

    def all_manifest = Channel.fromPath(params.all_input, checkIfExists: true)
        .splitCsv(header: true, sep: '\t')
        .map { row ->
            required.each { col ->
                if (!row[col]?.trim()) error "Manifest column '${col}' is empty in row ${row}"
            }
            def fasta = file(row.mag_fasta.trim())
            if (!fasta.exists()) error "MAG FASTA not found for ${row.sample}/${row.mag_id}: ${fasta}"
            def proteins = file(row.protein_fasta.trim())
            if (!proteins.exists()) error "Protein FASTA not found for ${row.sample}/${row.mag_id}: ${proteins}"
            tuple(row.sample.trim(), row.participant_id.trim(), row.visit.trim(),
                row.mag_id.trim(), row.species.trim(), fasta, proteins)
        }
        .ifEmpty { error "No MAG records found in ${params.all_input}" }

    def amr_inputs = manifest.map { sample, participant, visit, mag, species, fasta, proteins ->
        tuple(sample, participant, visit, mag, species, fasta)
    }
    def amr = AMRFINDER(amr_inputs, params.amrfinder_db)
    def vfdb = VFDB_SEARCH(manifest, params.vfdb_db,
        params.vfdb_min_identity, params.vfdb_min_query_cover, params.vfdb_evalue)
    // Stage the normalizer as an input so changing it changes the eggNOG task
    // hash and -resume reruns stale normalized outputs.
    def eggnog_normalizer = file("${projectDir}/scripts/normalize_eggnog.py")
    def eggnog = EGGNOG_ANNOTATE(manifest, params.eggnog_data,
        params.eggnog_sensitivity, params.eggnog_options, eggnog_normalizer)
    // Header-only sentinels let collation run when every task in a tool branch
    // fails under errorStrategy 'ignore'. They also keep empty-result tables valid.
    def empty_amr_table = Channel.fromPath("${projectDir}/assets/empty_amr.tsv", checkIfExists: true)
    def empty_vfdb_table = Channel.fromPath("${projectDir}/assets/empty_vfdb.tsv", checkIfExists: true)
    def empty_eggnog_table = Channel.fromPath("${projectDir}/assets/empty_eggnog.tsv", checkIfExists: true)

    // Annotate only pending MAGs. For strain comparison, use all MAGs in the
    // participant/species group but run FastANI only for pairs involving at
    // least one pending MAG. Same-sample pairs are excluded downstream.
    def pending_keys = manifest
        .map { sample, participant, visit, mag, species, fasta, proteins -> "${sample}\t${mag}" }
        .collect()
        .map { keys -> keys as Set }
    def strain_groups = all_manifest
        .filter { sample, participant, visit, mag, species, fasta, proteins -> species && species != 'NA' && species != 's__' }
        .map { sample, participant, visit, mag, species, fasta, proteins ->
            tuple([participant, species], [sample, visit, mag], fasta)
        }
        .groupTuple()
        .map { key, records, genomes ->
            tuple(key[0], key[1], records, genomes)
        }
        .combine(pending_keys)
        // combine() flattens tuple values, so the emitted item is
        // [participant, species, records, genomes, pendingKeys].
        .map { participant, species, records, genomes, pending ->
            def tagged = records.collect { record ->
                [record[0], record[1], record[2], pending.contains("${record[0]}\t${record[2]}")]
            }
            tuple(participant, species, tagged, genomes)
        }
        .filter { participant, species, records, genomes -> records.any { it[3] } }
    def strain = STRAIN_FASTANI(strain_groups)
    def empty_strain_table = Channel.fromPath("${projectDir}/assets/empty_fastani.tsv", checkIfExists: true)

    COLLATE_FEATURES(
        amr.table.concat(empty_amr_table).collect(),
        vfdb.table.concat(empty_vfdb_table).collect(),
        eggnog.table.concat(empty_eggnog_table).collect(),
        strain.table.concat(empty_strain_table).collect()
    )
}
