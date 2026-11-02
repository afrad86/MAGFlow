nextflow.enable.dsl=2

include { PIPELINE_INFO_WORKFLOW } from './subworkflows/pipeline_info/main'
include { PREPROCESSING } from './subworkflows/preprocessing/main'
include { KRAKEN2_WORKFLOW } from './subworkflows/kraken2/main'
include { BRACKEN_WORKFLOW } from './subworkflows/bracken/main'
include { ASSEMBLY }      from './subworkflows/assembly/main'
include { MAPPING }       from './subworkflows/mapping/main'
include { BINNING }       from './subworkflows/binning/main'
include { DASTOOL_WORKFLOW } from './subworkflows/dastool/main'
include { CHECKM2_WORKFLOW } from './subworkflows/checkm2/main'
include { GTDBTK_WORKFLOW }  from './subworkflows/gtdbtk/main'
include { PROKKA_WORKFLOW } from './subworkflows/prokka/main'
include { COVERM_WORKFLOW } from './subworkflows/coverm/main'
include { MAG_SUMMARY_WORKFLOW } from './subworkflows/mag_summary/main'


workflow {

    /*
     * =========================================================================
     * Pipeline information
     * =========================================================================
     */
    PIPELINE_INFO_WORKFLOW()

    /*
     * =========================================================================
     * Allowed longitudinal visits
     * =========================================================================
     */
    def VALID_VISITS = params.valid_visits.collect { it.toString().trim().toUpperCase() }

    /*
     * =========================================================================
     * Allowed intervention arms
     * =========================================================================
     */
    def VALID_INTERVENTION_ARMS = [
        '1_dose',
        '2_dose',
        'control'
    ]

    /*
     * =========================================================================
     * Supported assemblers
     * =========================================================================
     */
    def VALID_ASSEMBLERS = [
        'metaspades'
    ]

    /*
     * =========================================================================
     * Validate Bowtie2 reference index
     * =========================================================================
     */
    def host_reference_files = [
        "${params.reference_host}.1.bt2",
        "${params.reference_host}.2.bt2",
        "${params.reference_host}.3.bt2",
        "${params.reference_host}.4.bt2",
        "${params.reference_host}.rev.1.bt2",
        "${params.reference_host}.rev.2.bt2"
    ]

    host_reference_files.each { reference_file ->

        if (!file(reference_file).exists()) {

            error """
Bowtie2 reference index not found.

Missing file:

${reference_file}

Please verify:

- conf/references.config
- params.reference_host
- All six Bowtie2 index files are present
"""

        }

    }


    /*
     * =========================================================================
     * Validate assembler
     * =========================================================================
     */
    if (!(params.assembler in VALID_ASSEMBLERS)) {

        error """
Unsupported assembler:

    ${params.assembler}

Supported assemblers:

${VALID_ASSEMBLERS.collect { "    - ${it}" }.join('\n')}

Please update:

    - nextflow.config
"""

    }


    /*
     * =========================================================================
     * Read and validate metadata
     * =========================================================================
     */
    samples_ch = Channel
        .fromPath(params.metadata)
        .splitCsv(header: true)
        .map { row ->

            /*
             * -----------------------------------------------------------------
             * Clean metadata
             * -----------------------------------------------------------------
             */
            row.sample = row.sample?.trim()

            row.participant_id = row.participant_id?.trim()

            row.visit = row.visit?.trim()?.toUpperCase()

            row.intervention_arm =
                row.intervention_arm?.trim()?.toLowerCase() ?: "NA"


            /*
             * -----------------------------------------------------------------
             * Validate required metadata
             * -----------------------------------------------------------------
             */
            assert row.sample :
                "Metadata error: 'sample' is empty."


            /*
             * -----------------------------------------------------------------
             * Optional metadata defaults
             * -----------------------------------------------------------------
             */
            if (!row.participant_id) {
                row.participant_id = row.sample
            }

            if (!row.visit) {
                row.visit = ""
            }


            /*
             * -----------------------------------------------------------------
             * Validate visit only if supplied
             * -----------------------------------------------------------------
             */
            if (row.visit && !(row.visit in VALID_VISITS)) {

                error "Invalid visit '${row.visit}' for sample '${row.sample}'. Allowed visit values are: ${VALID_VISITS.join(', ')} (set params.valid_visits to change)."
            }

            /*
             * -----------------------------------------------------------------
             * Validate intervention arm only if supplied
             *
             * Missing/empty intervention_arm is represented as NA and is
             * allowed for backward compatibility.
             * -----------------------------------------------------------------
             */
            if (
                row.intervention_arm &&
                row.intervention_arm != "NA" &&
                !(row.intervention_arm in VALID_INTERVENTION_ARMS)
            ) {

                error """
Invalid intervention_arm '${row.intervention_arm}' for sample '${row.sample}'.

Allowed intervention_arm values are:

    1_dose
    2_dose
    control

The intervention_arm column is optional.
"""
            }

            /*
             * -----------------------------------------------------------------
             * Locate FASTQ files
             *
             * Supported metadata formats:
             *
             * Required:
             *   sample,r1,r2
             *
             * Optional:
             *   participant_id
             *   visit
             *   intervention_arm
             *
             * FASTQs are resolved from params.fastq_dir.
             * -----------------------------------------------------------------
             */
        def reads_r1
        def reads_r2

        if (params.use_trimmed_reads) {

            reads_r1 =
                file("${params.outdir}/01_fastp/${row.sample}.trimmed_R1.fastq.gz")

            reads_r2 =
                file("${params.outdir}/01_fastp/${row.sample}.trimmed_R2.fastq.gz")

        }
        else {

            if (row.r1 && row.r2) {

                def r1 = row.r1.trim()
                def r2 = row.r2.trim()

                if (r1.startsWith("/")) {
                    reads_r1 = file(r1)
                }
                else {
                    reads_r1 = file("${params.fastq_dir}/${r1}")
                }

                if (r2.startsWith("/")) {
                    reads_r2 = file(r2)
                }
                else {
                    reads_r2 = file("${params.fastq_dir}/${r2}")
                }

            }
            else {

                reads_r1 =
                    file("${params.fastq_dir}/${row.sample}_1.fastq.gz")

                reads_r2 =
                    file("${params.fastq_dir}/${row.sample}_2.fastq.gz")

            }

        }

            /*
             * -----------------------------------------------------------------
             * Validate FASTQ files
             * -----------------------------------------------------------------
             */
            if (!reads_r1.exists()) {

                error """

Missing FASTQ file:

${reads_r1}

Please verify:

- sample ID in input/metadata.csv
- FASTQ filename
- params.fastq_dir in nextflow.config
"""

            }

            if (!reads_r2.exists()) {

                error """
Missing FASTQ file:

${reads_r2}

Please verify:

- sample ID in input/metadata.csv
- FASTQ filename
- params.fastq_dir in nextflow.config
"""

            }

            /*
             * -----------------------------------------------------------------
             * Standard MAGFlow sample tuple
             *
             * IMPORTANT:
             * intervention_arm is NOT added to this tuple yet.
             *
             * This preserves the existing interfaces used throughout the
             * pipeline.
             * -----------------------------------------------------------------
             */
            tuple(
                row.sample,
                row.participant_id,
                row.visit,
                reads_r1,
                reads_r2
            )

        }

    /*
     * =========================================================================
     * Metadata for reporting
     *
     * This channel is separate from samples_ch so that the existing pipeline
     * data flow remains unchanged.
     * =========================================================================
     */
    reporting_metadata_ch = Channel
        .fromPath(params.metadata)
        .splitCsv(header: true)
        .map { row ->

            def sample = row.sample?.trim()

            def participant_id = row.participant_id?.trim()

            if (!participant_id) {
                participant_id = sample
            }

            def visit = row.visit?.trim()?.toUpperCase()

            if (!visit) {
                visit = ""
            }

            def intervention_arm =
                row.intervention_arm?.trim()?.toLowerCase()

            if (!intervention_arm) {
                intervention_arm = "NA"
            }

            tuple(
                sample,
                participant_id,
                visit,
                intervention_arm
            )
        }

    /*
     * =========================================================================
     * Run preprocessing workflow
     * =========================================================================
     */
    preprocessing_out = PREPROCESSING(samples_ch)

    
    /*
     * =========================================================================
     * Kraken2 read-level taxonomic classification
     * =========================================================================
     */
    kraken2_out = KRAKEN2_WORKFLOW(
        preprocessing_out.reads
    )

    bracken_out = BRACKEN_WORKFLOW(
        kraken2_out.report
    )

    /*
     * =========================================================================
     * Assembly
     * =========================================================================
     */
    assembly_out = ASSEMBLY(
        preprocessing_out.reads
    )

    /*
     * =========================================================================
     * Read mapping
     * =========================================================================
     */
    mapping_out = MAPPING(
        assembly_out.contigs,
        preprocessing_out.reads
    )

    /*
     * =========================================================================
     * Binning
     * =========================================================================
     */
    binning_out = BINNING(
        assembly_out.contigs,
        mapping_out.alignment,
        preprocessing_out.reads
    )

    /*
     * =========================================================================
     * DAS Tool
     * =========================================================================
     */
    dastool_out = DASTOOL_WORKFLOW(
        assembly_out.contigs,
        binning_out.metabat2_bins,
        binning_out.concoct_bins,
        binning_out.maxbin2_bins
    )

    /*
     * =========================================================================
     * CheckM2
     * =========================================================================
     */
    checkm2_out = CHECKM2_WORKFLOW(
        dastool_out.bins
    )

    /*
     * =========================================================================
     * GTDB-Tk
     * =========================================================================
     */
    gtdbtk_out = GTDBTK_WORKFLOW(
        dastool_out.bins
    )

    /*
     * =========================================================================
     * Prokka
     * =========================================================================
     */
    prokka_out = PROKKA_WORKFLOW(
        dastool_out.mags
    )

    /*
     * =========================================================================
     * CoverM
     * =========================================================================
     */
    coverm_out = COVERM_WORKFLOW(
        mapping_out.alignment,
        dastool_out.bins
    )

    /*
     * =========================================================================
     * MAG Summary
     * =========================================================================
     */
    summary_out = MAG_SUMMARY_WORKFLOW(
        checkm2_out.results,
        gtdbtk_out.results,
        prokka_out.results,
        coverm_out.results,
        reporting_metadata_ch
    )
}