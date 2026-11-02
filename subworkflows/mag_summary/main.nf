nextflow.enable.dsl=2

include { MAG_SUMMARY } from '../../modules/reporting/mag_summary'

workflow MAG_SUMMARY_WORKFLOW {

    take:
    checkm2_results
    gtdbtk_results
    prokka_results
    coverm_results
    reporting_metadata

    main:
    checkm2_join = checkm2_results
        .map { sample, participant_id, visit, checkm2_dir ->
            tuple([sample, participant_id, visit], checkm2_dir)
        }

    gtdbtk_join = gtdbtk_results
        .map { sample, participant_id, visit, gtdbtk_dir ->
            tuple([sample, participant_id, visit], gtdbtk_dir)
        }

    prokka_join = prokka_results
        .map { sample, participant_id, visit, mag_results ->
            tuple([sample, participant_id, visit], mag_results)
        }

    coverm_join = coverm_results
        .map { sample, participant_id, visit, coverm_dir ->
            tuple([sample, participant_id, visit], coverm_dir)
        }
    
        /*
     * -------------------------------------------------------------------------
     * Metadata for reporting
     * -------------------------------------------------------------------------
     */
    metadata_join = reporting_metadata
        .map { sample, participant_id, visit, intervention_arm ->
            tuple(
                [sample, participant_id, visit],
                intervention_arm
            )
        }

    joined = checkm2_join
        .join(gtdbtk_join)
        .join(prokka_join)
        .join(coverm_join)
        .join(metadata_join)
        .map {
            key,
            checkm2_dir,
            gtdbtk_dir,
            mag_results,
            coverm_dir,
            intervention_arm ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                intervention_arm,
                checkm2_dir,
                gtdbtk_dir,
                mag_results,
                coverm_dir
            )
        }

    MAG_SUMMARY(joined)

    emit:
    results = MAG_SUMMARY.out.results
    version = MAG_SUMMARY.out.version
}