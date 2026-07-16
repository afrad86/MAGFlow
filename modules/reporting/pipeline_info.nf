process PIPELINE_INFO {

    publishDir "${params.outdir}/00_pipeline_info",
        mode: 'copy',
        overwrite: true

    output:

    path("pipeline_info.txt"), emit: info

    script:
    """
    set -euo pipefail

    {
        echo "========================================================="
        echo "MAGFlow Pipeline Information"
        echo "========================================================="
        echo
        echo "Pipeline Name    : ${workflow.manifest.name}"
        echo "Pipeline Version : ${workflow.manifest.version}"
        echo
        echo "Run Name         : ${workflow.runName}"
        echo "Session ID       : ${workflow.sessionId}"
        echo
        echo "Start Time       : ${workflow.start}"
        echo "Profile          : ${workflow.profile}"
        echo
        echo "Metadata         : ${params.metadata}"
        echo "FASTQ Directory  : ${params.fastq_dir}"
        echo "Output Directory : ${params.outdir}"
        echo "Work Directory   : ${workflow.workDir}"
        echo
        echo "========================================================="
    } > pipeline_info.txt
    """
}