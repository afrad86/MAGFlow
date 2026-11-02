include { PROKKA } from '../../modules/annotation/prokka'

workflow PROKKA_WORKFLOW {

    take:
    mags

    main:
    PROKKA(mags)

    prokka_results = PROKKA.out.results
        .map { sample, participant_id, visit, mag, prokka_dir ->

            tuple(
                [sample, participant_id, visit],
                tuple(mag, prokka_dir)
            )
        }
        .groupTuple()
        .map { key, mag_results ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                mag_results
            )
        }

    emit:
    results = prokka_results
    version = PROKKA.out.version
}
