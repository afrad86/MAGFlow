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

    // Catch duplicate identifiers before any tasks publish a file with that name.
    def manifest = manifest_rows.collect().flatMap { rows ->
        def seen = [] as Set
        rows.each { row ->
            def id = [row[0], row[3]]
            if (!seen.add(id)) error "Duplicate sample/mag_id in manifest: ${row[0]}/${row[3]}"
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
    def eggnog = EGGNOG_ANNOTATE(manifest, params.eggnog_data,
        params.eggnog_sensitivity, params.eggnog_options)

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
        .map { pair ->
            def group = pair[0]
            def pending = pair[1]
            def participant = group[0]
            def species = group[1]
            def records = group[2]
            def genomes = group[3]
            def tagged = records.collect { record ->
                [record[0], record[1], record[2], pending.contains("${record[0]}\t${record[2]}")]
            }
            tuple(participant, species, tagged, genomes)
        }
        .filter { participant, species, records, genomes -> records.any { it[3] } }
    def strain = STRAIN_FASTANI(strain_groups)
    def empty_strain_table = Channel.fromPath("${projectDir}/assets/empty_fastani.tsv", checkIfExists: true)

    COLLATE_FEATURES(
        amr.table.collect(), vfdb.table.collect(),
        eggnog.table.collect(), strain.table.concat(empty_strain_table).collect()
    )
}
