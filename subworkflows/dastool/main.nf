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

    mags = dastool.bins.flatMap { sample, participant_id, visit, dastool_dir ->

        def binsDir = dastool_dir.resolve("${sample}_DASTool_bins")

        if (!binsDir.exists()) {
            throw new IllegalStateException("DAS Tool bins directory not found: ${binsDir}")
        }

        def fastaFiles = binsDir
            .listFiles()
            ?.findAll { it.isFile() && it.name.endsWith('.fa') }
            ?.sort { it.name } ?: []

        if (fastaFiles.isEmpty()) {
            throw new IllegalStateException("No MAG FASTA files found in ${binsDir}")
        }

        fastaFiles.collect { fasta ->
            tuple(
                sample,
                participant_id,
                visit,
                fasta.baseName,
                fasta
            )
        }
    }

    emit:

    bins = dastool.bins

    mags = mags

    version = dastool.version
}