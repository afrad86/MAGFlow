include { DASTOOL } from '../../modules/binning/dastool'

workflow DASTOOL_WORKFLOW {

    take:
    contigs
    metabat2_bins
    concoct_bins
    maxbin2_bins

    main:

    contigs_for_join = contigs.map { sample, participant_id, visit, contigs_file ->
        tuple([sample, participant_id, visit], contigs_file)
    }

    metabat2_for_join = metabat2_bins.map { sample, participant_id, visit, bins ->
        tuple([sample, participant_id, visit], bins)
    }

    concoct_for_join = concoct_bins.map { sample, participant_id, visit, bins ->
        tuple([sample, participant_id, visit], bins)
    }

    maxbin2_for_join = maxbin2_bins.map { sample, participant_id, visit, bins ->
        tuple([sample, participant_id, visit], bins)
    }

    dastool_input = contigs_for_join
        .join(metabat2_for_join)
        .join(concoct_for_join)
        .join(maxbin2_for_join)
        .map { key, contigs_file, metabat2_dir, concoct_dir, maxbin2_dir ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                contigs_file,
                metabat2_dir,
                concoct_dir,
                maxbin2_dir
            )
        }

    dastool = DASTOOL(dastool_input)

    emit:

    bins = dastool.bins

    version = dastool.version
}
