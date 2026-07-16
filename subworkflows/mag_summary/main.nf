nextflow.enable.dsl=2

include { MAG_SUMMARY } from '../../modules/reporting/mag_summary'

workflow MAG_SUMMARY_WORKFLOW {

    take:
    checkm2_results
    gtdbtk_results
    bakta_results
    coverm_results

    main:

 checkm2_join = checkm2_results
        .map { sample, participant_id, visit, checkm2_dir ->
            tuple([sample, participant_id, visit], checkm2_dir)
        }

    gtdbtk_join = gtdbtk_results
        .map { sample, participant_id, visit, gtdbtk_dir ->
            tuple([sample, participant_id, visit], gtdbtk_dir)
        }

    bakta_join = bakta_results
        .map { sample, participant_id, visit, bakta_dir ->
            tuple([sample, participant_id, visit], bakta_dir)
        }

    coverm_join = coverm_results
        .map { sample, participant_id, visit, coverm_dir ->
            tuple([sample, participant_id, visit], coverm_dir)
        }

    joined = checkm2_join
        .join(gtdbtk_join)
        .join(bakta_join)
        .join(coverm_join)
        .map { key, checkm2_dir, gtdbtk_dir, bakta_dir, coverm_dir ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                checkm2_dir,
                gtdbtk_dir,
                bakta_dir,
                coverm_dir
            )
        }

    MAG_SUMMARY(joined)

    emit:

    results = MAG_SUMMARY.out.results
    version = MAG_SUMMARY.out.version
}