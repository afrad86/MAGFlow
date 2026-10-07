nextflow.enable.dsl=2

include { AMRFINDER } from './modules/amrfinder'
include { VFDB_SEARCH } from './modules/vfdb'
include { EGGNOG_ANNOTATE } from './modules/eggnog'
include { STRAIN_FASTANI } from './modules/fastani'
include { COLLATE_FEATURES } from './modules/collate'

workflow {
    if (!params.input) error 'Set --input to a tab-delimited MAG manifest.'
    if (!params.outdir) error 'Set --outdir to a new downstream-results directory.'
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
        def hasSpecies = rows.any { row -> row[4] && row[4] != 'NA' && row[4] != 's__' }
        if (!hasSpecies) error 'No MAG has a GTDB species assignment; the strain-comparison table cannot be generated.'
        rows.each { row ->
            def id = [row[0], row[3]]
            if (!seen.add(id)) error "Duplicate sample/mag_id in manifest: ${row[0]}/${row[3]}"
        }
        rows
    }

    def amr_inputs = manifest.map { sample, participant, visit, mag, species, fasta, proteins ->
        tuple(sample, participant, visit, mag, species, fasta)
    }
    def amr = AMRFINDER(amr_inputs, params.amrfinder_db)
    def vfdb = VFDB_SEARCH(manifest, params.vfdb_db,
        params.vfdb_min_identity, params.vfdb_min_query_cover, params.vfdb_evalue)
    def eggnog = EGGNOG_ANNOTATE(manifest, params.eggnog_data,
        params.eggnog_sensitivity, params.eggnog_options)

    // Compare MAGs only within the same participant and supplied GTDB species.
    // Same-sample pairs are excluded; fastANI is a genome comparison, not read-based profiling.
    def strain_groups = manifest
        .filter { sample, participant, visit, mag, species, fasta, proteins -> species && species != 'NA' && species != 's__' }
        .map { sample, participant, visit, mag, species, fasta, proteins ->
            tuple([participant, species], [sample, visit, mag], fasta)
        }
        .groupTuple()
        .map { key, records, genomes ->
            tuple(key[0], key[1], records, genomes)
        }
    def strain = STRAIN_FASTANI(strain_groups)

    COLLATE_FEATURES(
        amr.table.collect(), vfdb.table.collect(),
        eggnog.table.collect(), strain.table.collect()
    )
}
