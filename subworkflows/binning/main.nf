include { METABAT2 } from '../../modules/binning/metabat2'

workflow BINNING {

    take:
    contigs
    alignment

    main:

    contigs_for_join = contigs.map { sample, participant_id, visit, contigs_file ->
        tuple([sample, participant_id, visit], contigs_file)
    }

    alignment_for_join = alignment.map { sample, participant_id, visit, bam, bai ->
        tuple([sample, participant_id, visit], bam, bai)
    }

    metabat2_input = contigs_for_join
        .join(alignment_for_join)
        .map { key, contigs_file, bam, bai ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                contigs_file,
                bam,
                bai
            )
        }

    metabat2 = METABAT2(metabat2_input)

    emit:
    bins    = metabat2.bins
    version = metabat2.version
}