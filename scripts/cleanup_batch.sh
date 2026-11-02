#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Batch sample list
###############################################################################

DELETE_MODE=false
LSF_JOB_ID=""

if [[ $# -eq 1 ]]; then
    BATCH_FILE="$1"
elif [[ $# -eq 2 && "$1" == "--delete" ]]; then
    DELETE_MODE=true
    BATCH_FILE="$2"
elif [[ $# -eq 2 ]]; then
    BATCH_FILE="$1"
    LSF_JOB_ID="$2"
elif [[ $# -eq 3 && "$1" == "--delete" ]]; then
    DELETE_MODE=true
    BATCH_FILE="$2"
    LSF_JOB_ID="$3"
else
    echo "Usage:"
    echo "  $0 <batch_sample_list.txt>"
    echo "  $0 <batch_sample_list.txt> <LSF_JOB_ID>"
    echo "  $0 --delete <batch_sample_list.txt>"
    echo "  $0 --delete <batch_sample_list.txt> <LSF_JOB_ID>"
    exit 1
fi

if [[ -n "${LSF_JOB_ID}" && ! "${LSF_JOB_ID}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: LSF job ID must be numeric:"
    echo "  ${LSF_JOB_ID}"
    exit 1
fi

if [[ ! -f "${BATCH_FILE}" ]]; then
    echo "ERROR: Batch sample list not found:"
    echo "  ${BATCH_FILE}"
    exit 1
fi

mapfile -t BATCH_SAMPLES < <(
    sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d' "${BATCH_FILE}"
)

if [[ ${#BATCH_SAMPLES[@]} -eq 0 ]]; then
    echo "ERROR: Batch sample list is empty:"
    echo "  ${BATCH_FILE}"
    exit 1
fi

echo "Batch samples: ${#BATCH_SAMPLES[@]}"

###############################################################################
# MAGFlow batch cleanup
#
# Purpose:
#   Identify files that can be safely removed after a completed batch.
#
# IMPORTANT:
#   This version is DRY-RUN ONLY.
#   It does NOT delete anything.
###############################################################################

PROJECT_DIR="/data/pam/ha7g/scratch/projects/metagenomics/CATI"

FASTQ_DIR="${PROJECT_DIR}/fastq"
RESULTS_DIR="${PROJECT_DIR}/MAGFlow_results"

if [[ "${DELETE_MODE}" == true ]]; then
    echo "MAGFlow Batch Cleanup - DELETE MODE"
else
    echo "MAGFlow Batch Cleanup - DRY RUN"
fi

echo
echo "Project : ${PROJECT_DIR}"
echo "FASTQ   : ${FASTQ_DIR}"
echo "Results : ${RESULTS_DIR}"
echo
if [[ "${DELETE_MODE}" == true ]]; then
    echo "WARNING: ELIGIBLE FILES WILL BE DELETED."
else
    echo "NO FILES WILL BE DELETED."
fi
echo

###############################################################################
# Check directories
###############################################################################

if [[ ! -d "${FASTQ_DIR}" ]]; then
    echo "ERROR: FASTQ directory not found:"
    echo "${FASTQ_DIR}"
    exit 1
fi

if [[ ! -d "${RESULTS_DIR}" ]]; then
    echo "ERROR: MAGFlow results directory not found:"
    echo "${RESULTS_DIR}"
    exit 1
fi

###############################################################################
# Raw FASTQ
#
# Raw FASTQs are removable only when BOTH corresponding trimmed FASTQs exist.
# Only samples listed in the batch file are considered.
###############################################################################

echo "------------------------------------------------------------"
echo "RAW FASTQ"
echo "------------------------------------------------------------"

raw_count=0
raw_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    r1="${FASTQ_DIR}/${sample}_1.fastq.gz"
    r2="${FASTQ_DIR}/${sample}_2.fastq.gz"

    trimmed_r1="${RESULTS_DIR}/01_fastp/${sample}.trimmed_R1.fastq.gz"
    trimmed_r2="${RESULTS_DIR}/01_fastp/${sample}.trimmed_R2.fastq.gz"

    echo
    echo "Sample: ${sample}"

    if [[ ! -s "${r1}" ]]; then
        echo "  R1 raw FASTQ: NOT FOUND"
        continue
    fi

    if [[ ! -s "${r2}" ]]; then
        echo "  R2 raw FASTQ: NOT FOUND"
        continue
    fi

    if [[ ! -s "${trimmed_r1}" ]]; then
        echo "  SAFETY STOP: trimmed R1 not found"
        echo "    ${trimmed_r1}"
        continue
    fi

    if [[ ! -s "${trimmed_r2}" ]]; then
        echo "  SAFETY STOP: trimmed R2 not found"
        echo "    ${trimmed_r2}"
        continue
    fi

    size_r1=$(stat -c '%s' "${r1}")
    size_r2=$(stat -c '%s' "${r2}")

    raw_bytes=$((raw_bytes + size_r1 + size_r2))
    raw_count=$((raw_count + 2))

if [[ "${DELETE_MODE}" == true ]]; then
    if [[ -s "${r1}" && -s "${r2}" && -s "${trimmed_r1}" && -s "${trimmed_r2}" ]]; then
        echo "  DELETING:"
        echo "    ${r1}"
        echo "    ${r2}"

        rm -- "${r1}" "${r2}"
    else
        echo "  SAFETY STOP: deletion conditions changed before deletion"
        echo "    No raw FASTQ files deleted."
    fi
else
    echo "  WOULD DELETE:"
    echo "    ${r1}"
    echo "    ${r2}"
fi

done

echo
echo "Raw FASTQ files eligible for deletion: ${raw_count}"
echo "Space that would be freed: $(numfmt --to=iec "${raw_bytes}")"
echo

###############################################################################
# Kraken2 read-level output
#
# Kraken2 read-level output files are very large and are not required by
# downstream MAGFlow analysis once the Kraken2 report and Bracken outputs
# have been successfully produced.
#
# Keep:
#   - *.kraken2.report.tsv
#   - *.kraken2.version.txt
#   - Bracken outputs
#
# Delete:
#   - *.kraken2.output.tsv
#
# Safety check:
#   Require both Kraken2 report and Bracken outputs before marking the
#   read-level Kraken2 output for deletion.
###############################################################################

echo "------------------------------------------------------------"
echo "KRAKEN2 READ-LEVEL OUTPUT"
echo "------------------------------------------------------------"

KRAKEN2_DIR="${RESULTS_DIR}/12_kraken2"
BRACKEN_DIR="${RESULTS_DIR}/13_bracken"

kraken2_output_count=0
kraken2_output_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    kraken2_output="${KRAKEN2_DIR}/${sample}.kraken2.output.tsv"
    kraken2_report="${KRAKEN2_DIR}/${sample}.kraken2.report.tsv"

    bracken_output="${BRACKEN_DIR}/${sample}.bracken.tsv"
    bracken_report="${BRACKEN_DIR}/${sample}.bracken.report.tsv"

    ###########################################################################
    # Safety check: Kraken2 report
    ###########################################################################

    if [[ ! -s "${kraken2_report}" ]]; then
        echo "  SAFETY STOP: Kraken2 report not found or empty"
        echo "    ${kraken2_report}"
        continue
    fi

    ###########################################################################
    # Safety check: Bracken outputs
    ###########################################################################

    if [[ ! -s "${bracken_output}" ]]; then
        echo "  SAFETY STOP: Bracken output not found or empty"
        echo "    ${bracken_output}"
        continue
    fi

    if [[ ! -s "${bracken_report}" ]]; then
        echo "  SAFETY STOP: Bracken report not found or empty"
        echo "    ${bracken_report}"
        continue
    fi

    ###########################################################################
    # Kraken2 read-level output
    ###########################################################################

    if [[ ! -s "${kraken2_output}" ]]; then
        echo "  Kraken2 read-level output: NOT FOUND"
        continue
    fi

    size=$(stat -c '%s' "${kraken2_output}")

    kraken2_output_bytes=$((kraken2_output_bytes + size))
    kraken2_output_count=$((kraken2_output_count + 1))

    echo "  Kraken2 report: OK"
    echo "  Bracken output: OK"
    echo "  Bracken report: OK"
    if [[ "${DELETE_MODE}" == true ]]; then
        echo "  DELETING:"
        echo "    ${kraken2_output}"
        echo "    Size: $(numfmt --to=iec "${size}")"

        if [[ -s "${kraken2_output}" && -s "${kraken2_report}" && \
            -s "${bracken_output}" && -s "${bracken_report}" ]]; then
            rm -- "${kraken2_output}"
        else
            echo "  SAFETY STOP: deletion conditions changed before deletion"
            echo "    No Kraken2 read-level output deleted."
        fi
    else
        echo "  WOULD DELETE:"
        echo "    ${kraken2_output}"
        echo "    Size: $(numfmt --to=iec "${size}")"
    fi

done

echo
echo "Kraken2 read-level output files eligible for deletion: ${kraken2_output_count}"
echo "Space that would be freed: $(numfmt --to=iec "${kraken2_output_bytes}")"
echo

###############################################################################
# Published host-removed FASTQ
#
# Host-removed reads are safe to remove only after:
#
#   Kraken2
#   Assembly
#   Mapping
#   MaxBin2
#
# have completed for the sample.
#
# The cleanup script is intended to be run only after the batch has finished.
# We therefore verify the downstream outputs before removing these files.
###############################################################################

echo "------------------------------------------------------------"
echo "HOST-REMOVED FASTQ"
echo "------------------------------------------------------------"

HOST_REMOVAL_DIR="${RESULTS_DIR}/02_host_removal/reads"

host_removed_count=0
host_removed_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    r1="${HOST_REMOVAL_DIR}/${sample}.host_removed_R1.fastq.gz"
    r2="${HOST_REMOVAL_DIR}/${sample}.host_removed_R2.fastq.gz"

    if [[ ! -s "${r1}" && ! -s "${r2}" ]]; then
        echo "  Host-removed FASTQs: NOT FOUND"
        continue
    fi

    if [[ ! -s "${r1}" ]]; then
        echo "  SAFETY STOP: host-removed R1 not found"
        continue
    fi

    if [[ ! -s "${r2}" ]]; then
        echo "  SAFETY STOP: host-removed R2 not found"
        continue
    fi

    ###########################################################################
    # Verify downstream outputs
    ###########################################################################

    kraken2_report="${RESULTS_DIR}/12_kraken2/${sample}.kraken2.report.tsv"

    if [[ ! -s "${kraken2_report}" ]]; then
        echo "  SAFETY STOP: Kraken2 report not found or empty"
        echo "    ${kraken2_report}"
        continue
    fi


    assembly_contigs="${RESULTS_DIR}/03_assembly/contigs/${sample}.contigs.fasta"

    if [[ ! -s "${assembly_contigs}" ]]; then
        echo "  SAFETY STOP: assembly contigs not found"
        echo "    ${assembly_contigs}"
        continue
    fi

    maxbin_dir="${RESULTS_DIR}/05_binning/maxbin2/${sample}_maxbin2"

    if [[ ! -d "${maxbin_dir}" ]]; then
        echo "  SAFETY STOP: MaxBin2 output directory not found"
        echo "    ${maxbin_dir}"
        continue
    fi

    maxbin_count=$(find "${maxbin_dir}" -type f \
        \( -name "*.fasta" -o -name "*.fa" \) \
        -size +0c 2>/dev/null | wc -l)

    if [[ "${maxbin_count}" -eq 0 ]]; then
        echo "  SAFETY STOP: no non-empty MaxBin2 bins found"
        echo "    ${maxbin_dir}"
        continue
    fi

    bam="${RESULTS_DIR}/04_mapping/bam/${sample}.sorted.bam"
    bai="${RESULTS_DIR}/04_mapping/bai/${sample}.sorted.bam.bai"

    if [[ ! -s "${bam}" ]]; then
        echo "  SAFETY STOP: BAM not found"
        echo "    ${bam}"
        continue
    fi

    if [[ ! -s "${bai}" ]]; then
        echo "  SAFETY STOP: BAI not found"
        echo "    ${bai}"
        continue
    fi

    size_r1=$(stat -c '%s' "${r1}")
    size_r2=$(stat -c '%s' "${r2}")

    host_removed_bytes=$((host_removed_bytes + size_r1 + size_r2))
    host_removed_count=$((host_removed_count + 2))

    if [[ "${DELETE_MODE}" == true ]]; then
        echo "  DELETING:"
        rm -f -- "${r1}" "${r2}"
    else
        echo "  WOULD DELETE:"
        echo "    ${r1}"
        echo "    ${r2}"
    fi

done

echo
echo "Host-removed FASTQ files eligible for deletion: ${host_removed_count}"
echo "Space that would be freed: $(numfmt --to=iec "${host_removed_bytes}")"
echo

###############################################################################
# Bowtie2 mapping indexes
#
# Bowtie2 indexes are created from the assembly contigs and are used only
# during the mapping step. They are not required by downstream MAG analysis.
#
# Because this script is run only after the batch has finished, the mapping
# result is used as the safety check before marking the index for deletion.
###############################################################################

echo "------------------------------------------------------------"
echo "BOWTIE2 INDEX"
echo "------------------------------------------------------------"

MAPPING_INDEX_DIR="${RESULTS_DIR}/04_mapping/index"

index_count=0
index_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    bam="${RESULTS_DIR}/04_mapping/bam/${sample}.sorted.bam"
    bai="${RESULTS_DIR}/04_mapping/bai/${sample}.sorted.bam.bai"

    if [[ ! -s "${bam}" || ! -s "${bai}" ]]; then
        echo "  SAFETY STOP: mapping BAM/BAI not complete"
        continue
    fi

    found_index=false

    for index_file in \
        "${MAPPING_INDEX_DIR}/${sample}.1.bt2" \
        "${MAPPING_INDEX_DIR}/${sample}.2.bt2" \
        "${MAPPING_INDEX_DIR}/${sample}.3.bt2" \
        "${MAPPING_INDEX_DIR}/${sample}.4.bt2" \
        "${MAPPING_INDEX_DIR}/${sample}.rev.1.bt2" \
        "${MAPPING_INDEX_DIR}/${sample}.rev.2.bt2"
    do

        if [[ -s "${index_file}" ]]; then

            size=$(stat -c '%s' "${index_file}")

            index_bytes=$((index_bytes + size))
            index_count=$((index_count + 1))

            if [[ "${DELETE_MODE}" == true ]]; then
                echo "  DELETING:"
                rm -f -- "${index_file}"
            else
                echo "  WOULD DELETE:"
                echo "    ${index_file}"
            fi

            found_index=true

        fi

    done

    if [[ "${found_index}" == false ]]; then
        echo "  Bowtie2 index files: NOT FOUND"

    fi

done

echo
echo "Bowtie2 index files eligible for deletion: ${index_count}"
echo "Space that would be freed: $(numfmt --to=iec "${index_bytes}")"
echo

###############################################################################
# BAM / BAI
#
# BAM and BAI are required by:
#   - MetaBAT2
#   - CONCOCT
#   - CoverM
#
# CoverM is the final consumer, so its normalized abundance output is used
# as the safety check before marking BAM/BAI for deletion.
###############################################################################

echo "------------------------------------------------------------"
echo "BAM / BAI"
echo "------------------------------------------------------------"

bam_bai_count=0
bam_bai_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    bam="${RESULTS_DIR}/04_mapping/bam/${sample}.sorted.bam"
    bai="${RESULTS_DIR}/04_mapping/bai/${sample}.sorted.bam.bai"

    coverm_output="${RESULTS_DIR}/11_abundance/${sample}/${sample}_coverm/mag_abundance.normalized.tsv"

    ###########################################################################
    # Verify BAM/BAI
    ###########################################################################

    if [[ ! -s "${bam}" ]]; then
        echo "  BAM: NOT FOUND"
        continue
    fi

    if [[ ! -s "${bai}" ]]; then
        echo "  SAFETY STOP: BAI not found"
        echo "    ${bai}"
        continue
    fi

    ###########################################################################
    # Verify CoverM
    ###########################################################################

    if [[ ! -s "${coverm_output}" ]]; then
        echo "  SAFETY STOP: CoverM output not found"
        echo "    ${coverm_output}"
        continue
    fi

    ###########################################################################
    # Calculate space
    ###########################################################################

    size_bam=$(stat -c '%s' "${bam}")
    size_bai=$(stat -c '%s' "${bai}")

    bam_bai_bytes=$((bam_bai_bytes + size_bam + size_bai))
    bam_bai_count=$((bam_bai_count + 2))

    if [[ "${DELETE_MODE}" == true ]]; then
        echo "  DELETING:"
        rm -f -- "${bam}" "${bai}"
    else
        echo "  WOULD DELETE:"
        echo "    ${bam}"
        echo "    ${bai}"
    fi

done

echo
echo "BAM/BAI files eligible for deletion: ${bam_bai_count}"
echo "Space that would be freed: $(numfmt --to=iec "${bam_bai_bytes}")"
echo

###############################################################################
# MetaBAT2 / CONCOCT / MaxBin2
#
# These are intermediate binning results.
#
# They are consumed by DAS Tool.
# Once DAS Tool has produced the final MAG FASTAs, these intermediate
# binning directories are no longer required by downstream MAGFlow steps.
#
# Safety check:
#   Require the DAS Tool final MAG directory to exist and contain at least
#   one non-empty MAG FASTA before marking these directories for deletion.
###############################################################################

echo "------------------------------------------------------------"
echo "MetaBAT2 / CONCOCT / MaxBin2"
echo "------------------------------------------------------------"

BINNING_DIR="${RESULTS_DIR}/05_binning"
DASTOOL_DIR="${RESULTS_DIR}/06_dastool"

binning_dir_count=0
binning_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    dastool_mag_dir="${DASTOOL_DIR}/${sample}_dastool/${sample}_DASTool_bins"

    ###########################################################################
    # Safety check: DAS Tool final MAGs
    ###########################################################################

    if [[ ! -d "${dastool_mag_dir}" ]]; then
        echo "  SAFETY STOP: DAS Tool MAG directory not found"
        echo "    ${dastool_mag_dir}"
        continue
    fi

    mag_count=$(find "${dastool_mag_dir}" -type f \
        \( -name "*.fa" -o -name "*.fasta" \) \
        -size +0c 2>/dev/null | wc -l)

    if [[ "${mag_count}" -eq 0 ]]; then
        echo "  SAFETY STOP: no non-empty DAS Tool MAG FASTA files found"
        echo "    ${dastool_mag_dir}"
        continue
    fi

    echo "  DAS Tool MAGs found: ${mag_count}"

    ###########################################################################
    # MetaBAT2
    ###########################################################################

    metabat2_dir="${BINNING_DIR}/metabat2/${sample}_metabat2"

    if [[ ! -d "${metabat2_dir}" ]]; then
        echo "  MetaBAT2: NOT FOUND"
    else
        metabat2_count=$(find "${metabat2_dir}" -type f \
            -name "*.fa" -size +0c 2>/dev/null | wc -l)

        if [[ "${metabat2_count}" -eq 0 ]]; then
            echo "  MetaBAT2: SAFETY STOP - no non-empty bins found"
        else
            size=$(du -sb "${metabat2_dir}" | awk '{print $1}')

            binning_bytes=$((binning_bytes + size))
            binning_dir_count=$((binning_dir_count + 1))

            echo "  MetaBAT2 bins found: ${metabat2_count}"
            if [[ "${DELETE_MODE}" == true ]]; then
                echo "  DELETING:"
                rm -rf -- "${metabat2_dir}"
            else
                echo "  WOULD DELETE:"
            fi
            echo "    ${metabat2_dir}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi
    fi

    ###########################################################################
    # CONCOCT
    ###########################################################################

    concoct_dir="${BINNING_DIR}/concoct/${sample}_concoct"

    if [[ ! -d "${concoct_dir}" ]]; then
        echo "  CONCOCT: NOT FOUND"
    else
        concoct_count=$(find "${concoct_dir}/bins" -type f \
            -name "*.fa" -size +0c 2>/dev/null | wc -l)

        if [[ "${concoct_count}" -eq 0 ]]; then
            echo "  CONCOCT: SAFETY STOP - no non-empty bins found"
        else
            size=$(du -sb "${concoct_dir}" | awk '{print $1}')

            binning_bytes=$((binning_bytes + size))
            binning_dir_count=$((binning_dir_count + 1))

            echo "  CONCOCT bins found: ${concoct_count}"
            if [[ "${DELETE_MODE}" == true ]]; then
                echo "  DELETING:"
                rm -rf -- "${concoct_dir}"
            else
                echo "  WOULD DELETE:"
            fi
            echo "    ${concoct_dir}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi
    fi

    ###########################################################################
    # MaxBin2
    ###########################################################################

    maxbin2_dir="${BINNING_DIR}/maxbin2/${sample}_maxbin2"

    if [[ ! -d "${maxbin2_dir}" ]]; then
        echo "  MaxBin2: NOT FOUND"
    else
        maxbin2_count=$(find "${maxbin2_dir}" -type f \
            \( -name "*.fasta" -o -name "*.fa" \) \
            -size +0c 2>/dev/null | wc -l)

        if [[ "${maxbin2_count}" -eq 0 ]]; then
            echo "  MaxBin2: SAFETY STOP - no non-empty bins found"
        else
            size=$(du -sb "${maxbin2_dir}" | awk '{print $1}')

            binning_bytes=$((binning_bytes + size))
            binning_dir_count=$((binning_dir_count + 1))

            echo "  MaxBin2 bins found: ${maxbin2_count}"
            if [[ "${DELETE_MODE}" == true ]]; then
                echo "  DELETING:"
                rm -rf -- "${maxbin2_dir}"
            else
                echo "  WOULD DELETE:"
            fi
            echo "    ${maxbin2_dir}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi
    fi

done

echo
echo "Binning directories eligible for deletion: ${binning_dir_count}"
echo "Space that would be freed: $(numfmt --to=iec "${binning_bytes}")"
echo

###############################################################################
# DAS Tool intermediate files
#
# Keep:
#   ${sample}_DASTool_bins/
#
# The MAG FASTAs inside this directory are required by:
#   - CheckM2
#   - GTDB-Tk
#   - Prokka
#   - CoverM
#
# We therefore do NOT delete anything inside the final MAG directory.
#
# Everything else directly under the sample's DAS Tool result directory is
# considered an intermediate/output artifact and is marked for deletion only
# after all downstream analyses have completed successfully.
###############################################################################

echo "------------------------------------------------------------"
echo "DAS Tool intermediate files"
echo "------------------------------------------------------------"

DASTOOL_DIR="${RESULTS_DIR}/06_dastool"

dastool_file_count=0
dastool_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    sample_dastool_dir="${DASTOOL_DIR}/${sample}_dastool"
    mag_dir="${sample_dastool_dir}/${sample}_DASTool_bins"

    ###########################################################################
    # Safety check: final MAG directory
    ###########################################################################

    if [[ ! -d "${mag_dir}" ]]; then
        echo "  SAFETY STOP: final DAS Tool MAG directory not found"
        echo "    ${mag_dir}"
        continue
    fi

    mag_count=$(find "${mag_dir}" -type f \
        \( -name "*.fa" -o -name "*.fasta" \) \
        -size +0c 2>/dev/null | wc -l)

    if [[ "${mag_count}" -eq 0 ]]; then
        echo "  SAFETY STOP: no non-empty final MAG FASTAs found"
        echo "    ${mag_dir}"
        continue
    fi

    ###########################################################################
    # Safety check: downstream MAG analyses
    ###########################################################################

    checkm2_dir="${RESULTS_DIR}/07_checkm2/${sample}"
    gtdbtk_dir="${RESULTS_DIR}/08_gtdbtk/${sample}"
    prokka_dir="${RESULTS_DIR}/10_prokka/${sample}"
    coverm_dir="${RESULTS_DIR}/11_abundance/${sample}"

    checkm2_count=$(find "${checkm2_dir}" -type f \
        -size +0c 2>/dev/null | wc -l)

    if [[ "${checkm2_count}" -eq 0 ]]; then
        echo "  SAFETY STOP: CheckM2 output directory is empty"
        echo "    ${checkm2_dir}"
        continue
    fi

    gtdbtk_count=$(find "${gtdbtk_dir}" -type f \
        -size +0c 2>/dev/null | wc -l)

    if [[ "${gtdbtk_count}" -eq 0 ]]; then
        echo "  SAFETY STOP: GTDB-Tk output directory is empty"
        echo "    ${gtdbtk_dir}"
        continue
    fi

    prokka_count=0
    prokka_missing=false

    while IFS= read -r mag_fasta; do

        mag_name=$(basename "${mag_fasta}")
        mag_name="${mag_name%.*}"

        prokka_mag_dir="${prokka_dir}/${mag_name}_prokka"

        if [[ ! -d "${prokka_mag_dir}" ]]; then
            echo "  SAFETY STOP: Prokka output missing for MAG"
            echo "    MAG: ${mag_name}"
            echo "    Expected: ${prokka_mag_dir}"
            prokka_missing=true
            continue
        fi

        prokka_files=$(find "${prokka_mag_dir}" -type f \
            -size +0c 2>/dev/null | wc -l)

        if [[ "${prokka_files}" -eq 0 ]]; then
            echo "  SAFETY STOP: Prokka directory is empty"
            echo "    ${prokka_mag_dir}"
            prokka_missing=true
            continue
        fi

        prokka_count=$((prokka_count + 1))

    done < <(
        find "${mag_dir}" -type f \
            -name "*.fa" \
            -size +0c \
            | sort
    )

    if [[ "${prokka_missing}" == true ]]; then
        continue
    fi

    if [[ "${prokka_count}" -ne "${mag_count}" ]]; then
        echo "  SAFETY STOP: Prokka MAG count does not match DAS Tool MAG count"
        echo "    DAS Tool MAGs: ${mag_count}"
        echo "    Prokka MAGs:   ${prokka_count}"
        continue
    fi

    coverm_output="${coverm_dir}/${sample}_coverm/mag_abundance.normalized.tsv"

    if [[ ! -s "${coverm_output}" ]]; then
        echo "  SAFETY STOP: CoverM normalized abundance output not found"
        echo "    ${coverm_output}"
        continue
    fi

    echo "  Final MAGs found: ${mag_count}"
    echo "  Downstream MAG analyses found."

    ###########################################################################
    # Mark everything except the final MAG directory for deletion
    ###########################################################################

    if [[ ! -d "${sample_dastool_dir}" ]]; then
        echo "  DAS Tool sample directory: NOT FOUND"
        continue
    fi

    while IFS= read -r item; do

        [[ "${item}" == "${mag_dir}" ]] && continue

        if [[ -d "${item}" ]]; then
            size=$(du -sb "${item}" | awk '{print $1}')
        elif [[ -f "${item}" ]]; then
            size=$(stat -c '%s' "${item}")
        else
            continue
        fi

        dastool_bytes=$((dastool_bytes + size))
        dastool_file_count=$((dastool_file_count + 1))

        if [[ "${DELETE_MODE}" == true ]]; then
            echo "  DELETING:"
            echo "    ${item}"
            echo "    Size: $(numfmt --to=iec "${size}")"

            # Recheck immediately before deletion.
            if [[ -d "${item}" ]]; then
                rm -rf -- "${item}"
            elif [[ -f "${item}" ]]; then
                rm -- "${item}"
            else
                echo "  SAFETY STOP: DAS Tool item changed before deletion"
                echo "    ${item}"
            fi
        else
            echo "  WOULD DELETE:"
            echo "    ${item}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi

    done < <(
        find "${sample_dastool_dir}" -mindepth 1 -maxdepth 1 \
            ! -path "${mag_dir}" \
            -print
    )

done

echo
echo "DAS Tool items eligible for deletion: ${dastool_file_count}"
echo "Space that would be freed: $(numfmt --to=iec "${dastool_bytes}")"
echo

###############################################################################
# Prokka redundant output files
#
# Keep:
#   - .faa
#   - .ffn
#   - .gbk
#   - .gff
#   - .tsv
#   - .txt
#   - .log
#   - .prokka.version.txt
#
# Delete:
#   - .fna
#   - .fsa
#   - .sqn
#   - .tbl
#   - .err
#
# These files are not required for downstream CATI analyses.
###############################################################################

echo "------------------------------------------------------------"
echo "PROKKA REDUNDANT OUTPUT FILES"
echo "------------------------------------------------------------"

PROKKA_CLEANUP_DIR="${RESULTS_DIR}/10_prokka"

prokka_cleanup_count=0
prokka_cleanup_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    prokka_cleanup_sample_dir="${PROKKA_CLEANUP_DIR}/${sample}"

    if [[ ! -d "${prokka_cleanup_sample_dir}" ]]; then
        echo "  Prokka output directory: NOT FOUND"
        continue
    fi

    while IFS= read -r prokka_file; do

        [[ -z "${prokka_file}" ]] && continue

        size=$(stat -c '%s' "${prokka_file}")

        prokka_cleanup_bytes=$((prokka_cleanup_bytes + size))
        prokka_cleanup_count=$((prokka_cleanup_count + 1))

        if [[ "${DELETE_MODE}" == true ]]; then
            echo "  DELETING:"
            echo "    ${prokka_file}"
            echo "    Size: $(numfmt --to=iec "${size}")"

            # Recheck immediately before deletion.
            if [[ -f "${prokka_file}" ]]; then
                rm -f -- "${prokka_file}"
            else
                echo "  SAFETY STOP: Prokka file changed before deletion"
                echo "    ${prokka_file}"
            fi
        else
            echo "  WOULD DELETE:"
            echo "    ${prokka_file}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi

    done < <(
        find "${prokka_cleanup_sample_dir}" -type f \
            \( -name "*.fna" -o \
               -name "*.fsa" -o \
               -name "*.sqn" -o \
               -name "*.tbl" -o \
               -name "*.err" \) \
            -size +0c \
            | sort
    )

done

echo
echo "Prokka redundant files eligible for deletion: ${prokka_cleanup_count}"
echo "Space that would be freed: $(numfmt --to=iec "${prokka_cleanup_bytes}")"
echo

###############################################################################
# GTDB-Tk redundant output files
#
# Delete:
#   - align/gtdbtk.bac120.filtered.tsv
#   - align/gtdbtk.bac120.user_msa.fasta.gz
#   - identify/gtdbtk.ar53.markers_summary.tsv
#   - identify/gtdbtk.bac120.markers_summary.tsv
#   - identify/gtdbtk.failed_genomes.tsv
#   - identify/gtdbtk.translation_table_summary.tsv
#
# These are GTDB-Tk intermediate/identification-stage files and are not
# required for downstream CATI analyses.
###############################################################################

echo "------------------------------------------------------------"
echo "GTDB-Tk REDUNDANT OUTPUT FILES"
echo "------------------------------------------------------------"

GTDBTK_CLEANUP_DIR="${RESULTS_DIR}/08_gtdbtk"

gtdbtk_cleanup_count=0
gtdbtk_cleanup_bytes=0

for sample in "${BATCH_SAMPLES[@]}"; do

    echo
    echo "Sample: ${sample}"

    gtdbtk_cleanup_sample_dir="${GTDBTK_CLEANUP_DIR}/${sample}"

    if [[ ! -d "${gtdbtk_cleanup_sample_dir}" ]]; then
        echo "  GTDB-Tk output directory: NOT FOUND"
        continue
    fi

    while IFS= read -r gtdbtk_file; do

        [[ -z "${gtdbtk_file}" ]] && continue

        size=$(stat -c '%s' "${gtdbtk_file}")

        gtdbtk_cleanup_bytes=$((gtdbtk_cleanup_bytes + size))
        gtdbtk_cleanup_count=$((gtdbtk_cleanup_count + 1))

        if [[ "${DELETE_MODE}" == true ]]; then
            echo "  DELETING:"
            echo "    ${gtdbtk_file}"
            echo "    Size: $(numfmt --to=iec "${size}")"

            # Recheck immediately before deletion.
            if [[ -f "${gtdbtk_file}" ]]; then
                rm -f -- "${gtdbtk_file}"
            else
                echo "  SAFETY STOP: GTDB-Tk file changed before deletion"
                echo "    ${gtdbtk_file}"
            fi
        else
            echo "  WOULD DELETE:"
            echo "    ${gtdbtk_file}"
            echo "    Size: $(numfmt --to=iec "${size}")"
        fi

    done < <(
        find "${gtdbtk_cleanup_sample_dir}" -type f \
            \( -path "*/align/gtdbtk.bac120.filtered.tsv" -o \
               -path "*/align/gtdbtk.bac120.user_msa.fasta.gz" -o \
               -path "*/identify/gtdbtk.ar53.markers_summary.tsv" -o \
               -path "*/identify/gtdbtk.bac120.markers_summary.tsv" -o \
               -path "*/identify/gtdbtk.failed_genomes.tsv" -o \
               -path "*/identify/gtdbtk.translation_table_summary.tsv" \) \
            -size +0c \
            | sort
    )

done

echo
echo "GTDB-Tk redundant files eligible for deletion: ${gtdbtk_cleanup_count}"
echo "Space that would be freed: $(numfmt --to=iec "${gtdbtk_cleanup_bytes}")"
echo

###############################################################################
# Assembly graph files
#
# MetaSPAdes GFA files are not used by downstream MAGFlow processes.
#
# Keep:
#   - contigs
#   - scaffolds
#   - assembly reports
#
# Delete:
#   - assembly graph GFA files
###############################################################################

echo "------------------------------------------------------------"
# LSF .out / .err
#
# LSF job console logs are not required for downstream MAGFlow analysis.
#
# Keep:
#   - Nextflow report
#   - Nextflow trace
#   - Nextflow timeline
#   - Nextflow DAG
#
# Delete:
#   - nextflow.<JOBID>.out
#   - nextflow.<JOBID>.err
#
# Safety:
#   Cleanup requires an explicit LSF job ID.
#   The .out file must contain "Successfully completed."
#   Default mode is dry-run; deletion requires --delete.
###############################################################################

echo "------------------------------------------------------------"
echo "LSF .out / .err"
echo "------------------------------------------------------------"

LOG_DIR="${PROJECT_DIR}/MAGFlow_logs"

lsf_log_count=0
lsf_log_bytes=0

if [[ -z "${LSF_JOB_ID}" ]]; then

    echo "LSF job ID: NOT PROVIDED"
    echo "LSF .out/.err cleanup will be skipped."
    echo "Provide an LSF job ID to enable LSF log cleanup."
    echo

else

    lsf_out="${LOG_DIR}/nextflow.${LSF_JOB_ID}.out"
    lsf_err="${LOG_DIR}/nextflow.${LSF_JOB_ID}.err"

    echo "LSF job ID: ${LSF_JOB_ID}"
    echo

    if [[ ! -s "${lsf_out}" ]]; then
        echo "SAFETY STOP: LSF .out file not found or empty"
        echo "  ${lsf_out}"
    elif ! grep -qF "Successfully completed." "${lsf_out}"; then
        echo "SAFETY STOP: LSF job completion marker not found"
        echo "  ${lsf_out}"
        echo "  Required marker: Successfully completed."
    elif [[ ! -f "${lsf_err}" ]]; then
        echo "SAFETY STOP: LSF .err file not found"
        echo "  ${lsf_err}"
    else

        out_size=$(stat -c '%s' "${lsf_out}")
        err_size=$(stat -c '%s' "${lsf_err}")

        lsf_log_bytes=$((out_size + err_size))
        lsf_log_count=2

        if [[ "${DELETE_MODE}" == true ]]; then

            echo "  DELETING:"
            echo "    ${lsf_out}"
            echo "    ${lsf_err}"

            rm -- "${lsf_out}" "${lsf_err}"

        else

            echo "  WOULD DELETE:"
            echo "    ${lsf_out}"
            echo "    ${lsf_err}"

        fi
    fi
fi

echo
echo "LSF .out/.err files eligible for deletion: ${lsf_log_count}"
echo "Space that would be freed: $(numfmt --to=iec "${lsf_log_bytes}")"
echo

###############################################################################
# Summary
###############################################################################

echo "============================================================"

if [[ "${DELETE_MODE}" == true ]]; then
    echo "CLEANUP COMPLETE - DELETE MODE"
else
    echo "CLEANUP COMPLETE - DRY RUN"
fi

echo "============================================================"
echo

if [[ "${DELETE_MODE}" == true ]]; then
    echo "Eligible files were deleted only after their safety checks passed."
else
    echo "NO FILES WERE DELETED."
fi