include { COVERM } from '../../modules/abundance/coverm'

workflow COVERM_WORKFLOW {

    take:

    alignment
    bins

    main:

    alignment_for_join = alignment.map {
        sample,
        participant_id,
        visit,
        bam,
        bai ->

        tuple(
            [sample, participant_id, visit],
            bam,
            bai
        )
    }

    bins_for_join = bins.map {
        sample,
        participant_id,
        visit,
        dastool_dir ->

        tuple(
            [sample, participant_id, visit],
            dastool_dir
        )
    }

    coverm_input = alignment_for_join
        .join(bins_for_join)
        .map { key, bam, bai, dastool_dir ->

            tuple(
                key[0],
                key[1],
                key[2],
                bam,
                bai,
                dastool_dir
            )
        }

    COVERM(coverm_input)

    emit:

    results = COVERM.out.results
    version = COVERM.out.version
}
