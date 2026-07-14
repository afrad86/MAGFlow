include { METABAT2 } from '../../modules/binning/metabat2'

include { CONCOCT } from '../../modules/binning/concoct'

include { MAXBIN2 } from '../../modules/binning/maxbin2'

workflow BINNING {

    take:
    contigs
    alignment
    reads

    main:

    contigs_for_join = contigs.map { sample, participant_id, visit, contigs_file ->
        tuple([sample, participant_id, visit], contigs_file)
    }

    alignment_for_join = alignment.map { sample, participant_id, visit, bam, bai ->
        tuple([sample, participant_id, visit], bam, bai)
    }

    reads_for_join = reads.map { sample, participant_id, visit, reads_r1, reads_r2 ->
        tuple([sample, participant_id, visit], reads_r1, reads_r2)
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

    maxbin2_input = contigs_for_join
        .join(reads_for_join)
        .map { key, contigs_file, reads_r1, reads_r2 ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                contigs_file,
                reads_r1,
                reads_r2
            )
        }

    metabat2 = METABAT2(metabat2_input)

    concoct = CONCOCT(metabat2_input)

    maxbin2 = MAXBIN2(maxbin2_input)

    emit:

    metabat2_bins    = metabat2.bins
    metabat2_version = metabat2.version

    concoct_bins     = concoct.bins
    concoct_version  = concoct.version

    maxbin2_bins      = maxbin2.bins
    maxbin2_version   = maxbin2.version

}