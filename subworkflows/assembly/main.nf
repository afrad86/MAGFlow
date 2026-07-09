include { METASPADES } from '../../modules/assembly/metaspades'

workflow ASSEMBLY {

    take:
    reads

    main:
    METASPADES(reads)

    emit:
    contigs = METASPADES.out.contigs
}