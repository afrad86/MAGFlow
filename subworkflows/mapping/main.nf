include { BOWTIE2_BUILD_INDEX } from '../../modules/mapping/bowtie2_build_index'
include { BOWTIE2_MAP }         from '../../modules/mapping/bowtie2_map'

workflow MAPPING {

    take:
    contigs
    reads

    main:

    bowtie2_index = BOWTIE2_BUILD_INDEX(contigs)

    index_for_join = bowtie2_index.index.map { sample, participant_id, visit, index_files ->
        tuple([sample, participant_id, visit], index_files)
    }

    reads_for_join = reads.map { sample, participant_id, visit, reads_r1, reads_r2 ->
        tuple([sample, participant_id, visit], reads_r1, reads_r2)
    }

    mapping_input = index_for_join.join(reads_for_join)
        .map { key, index_files, reads_r1, reads_r2 ->

            def sample = key[0]
            def participant_id = key[1]
            def visit = key[2]

            tuple(
                sample,
                participant_id,
                visit,
                index_files,
                reads_r1,
                reads_r2
            )
        }

    bowtie2_map = BOWTIE2_MAP(mapping_input)

    emit:
    alignment    = bowtie2_map.alignment
    bam          = bowtie2_map.bam
    bai          = bowtie2_map.bai
    bowtie2_log  = bowtie2_map.log
    version      = bowtie2_map.version
}