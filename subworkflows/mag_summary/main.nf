nextflow.enable.dsl=2

include { MAG_SUMMARY } from '../../modules/reporting/mag_summary'

workflow MAG_SUMMARY_WORKFLOW {

    take:
    checkm2_results
    gtdbtk_results

    main:

 joined = checkm2_results
    .join(gtdbtk_results)
    .map { sample,
           participant_id,
           visit,
           checkm2_dir,
           participant_id2,
           visit2,
           gtdbtk_dir ->

        assert participant_id == participant_id2
        assert visit == visit2

        tuple(
            sample,
            participant_id,
            visit,
            checkm2_dir,
            gtdbtk_dir
        )
    }

    MAG_SUMMARY(joined)

    emit:

    results = MAG_SUMMARY.out.results
    version = MAG_SUMMARY.out.version
}