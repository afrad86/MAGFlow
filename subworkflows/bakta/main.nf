include { BAKTA } from '../../modules/annotation/bakta'

workflow BAKTA_WORKFLOW {

    take:
    mags

    main:

    BAKTA(mags)

    bakta_results = BAKTA.out.results
        .map { sample, participant_id, visit, mag, bakta_dir ->

            tuple(
                [sample, participant_id, visit],
                tuple(mag, bakta_dir)
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

    results = bakta_results

    version = BAKTA.out.version
}