process COVERM {

    tag "${sample}"

    publishDir "${params.outdir}/11_abundance",
        mode: 'copy',
        overwrite: true,
        saveAs: { filename ->

            if (filename == "${sample}_coverm") {
                return "${sample}/${filename}"
            }

            if (filename == "${sample}.coverm.version.txt") {
                return "${sample}/${filename}"
            }

            return null
        }

    input:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path(bam),
        path(bai),
        path(dastool_dir)
    )

    output:

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}_coverm"),
        emit: results
    )

    tuple(
        val(sample),
        val(participant_id),
        val(visit),
        path("${sample}.coverm.version.txt"),
        emit: version
    )


    script:
    """
    set -euo pipefail

    mkdir -p ${sample}_coverm

    ###########################################################################
    # Version
    ###########################################################################

    {
        echo "========================================"
        echo "MAGFlow CoverM"
        echo "========================================"
        echo "Date      : \$(date)"
        echo "Host      : \$(hostname)"
        echo "Sample    : ${sample}"
        echo "CPUs      : ${task.cpus}"
        echo "Memory    : ${task.memory.toGiga()} GB"
        echo

        echo "CoverM:"
        which coverm
        coverm --version
        echo

    } > ${sample}.coverm.version.txt 2>&1

    [[ -f ${sample}.coverm.version.txt ]] || {
    echo "ERROR: Failed to create version file."
    exit 1
    }

    ###########################################################################
    # MAG abundance
    ###########################################################################

    [[ -f "${bam}" ]] || {
        echo "ERROR: BAM file not found."
        exit 1
    }

    [[ -d "${dastool_dir}/${sample}_DASTool_bins" ]] || {
        echo "ERROR: DASTool bins directory not found."
        exit 1
    }

    compgen -G "${dastool_dir}/${sample}_DASTool_bins/*.fa" > /dev/null || {
        echo "ERROR: No MAG (*.fa) files found in ${dastool_dir}/${sample}_DASTool_bins."
        exit 1
    }

    coverm genome \
        --bam-files "${bam}" \
        --genome-fasta-files "${dastool_dir}/${sample}_DASTool_bins"/*.fa \
        --methods ${params.coverm_methods.join(' ')} \
        --min-covered-fraction ${params.coverm_min_covered_fraction} \
        --threads ${task.cpus} \
        --output-file "${sample}_coverm/mag_abundance.tsv" \
        2> "${sample}_coverm/coverm.log"
    

    python3 - <<'EOF'
    import csv

    with open("${sample}_coverm/mag_abundance.tsv") as fin, \
        open("${sample}_coverm/mag_abundance.normalized.tsv", "w", newline="") as fout:

        reader = csv.reader(fin, delimiter="\t")
        writer = csv.writer(fout, delimiter="\t")

        header = next(reader)

        new_header = ["Genome"]

        for col in header[1:]:
            if col.endswith("Relative Abundance (%)"):
                new_header.append("coverm_relative_abundance")
            elif col.endswith("Mean"):
                new_header.append("coverm_mean_coverage")
            elif col.endswith("Covered Fraction"):
                new_header.append("coverm_covered_fraction")
            else:
                new_header.append(col)

        writer.writerow(new_header)

        rows = []

        for row in reader:
            if row[0] == "unmapped":
                continue

            rows.append(row)

        rows.sort(
            key=lambda x: float(x[1]),
            reverse=True
        )

        writer.writerows(rows)
    
    EOF


    [[ -f "${sample}_coverm/mag_abundance.tsv" ]] || {
        echo "ERROR: CoverM output file not found."
        exit 1
    }

    [[ -f "${sample}_coverm/mag_abundance.normalized.tsv" ]] || {
        echo "ERROR: Normalized CoverM output file not found."
        exit 1
    }

    [[ -f "${sample}_coverm/coverm.log" ]] || {
        echo "ERROR: CoverM log file not found."
        exit 1
    }
    
    """

}