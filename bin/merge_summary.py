#!/usr/bin/env python3

import argparse
import csv
import json
import sys
from pathlib import Path


VERSION = "MAGFlow merge_summary 1.1.0"

SUMMARY_HEADER = [
    "sample",
    "participant_id",
    "visit",
    "intervention_arm",
    "mag_id",

    # CheckM2
    "completeness",
    "contamination",
    "quality_score",
    "mimag_quality",
    "passes_quality_filter",

    # GTDB-Tk
    "domain",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species",
    "closest_reference",

    # CoverM
    "coverm_relative_abundance",
    "coverm_mean_coverage",
    "coverm_covered_fraction",

    # Prokka
    "prokka_genome_size_bp",
    "prokka_contigs",
    "prokka_gc_percent",
    "prokka_cds",
    "prokka_trna",
    "prokka_tmrna",
    "prokka_crispr"
]


def die(message):
    """Exit with a clear error message."""
    print(f"\nERROR: {message}\n", file=sys.stderr)
    sys.exit(1)


def require_columns(reader, required, filename):
    """Ensure all required columns exist."""

    if reader.fieldnames is None:
        die(f"{filename} is empty or does not contain a valid header.")

    missing = [c for c in required if c not in reader.fieldnames]

    if missing:
        die(
            f"{filename} is missing required column(s): "
            f"{', '.join(missing)}\n\n"
            f"Available columns:\n"
            + "\n".join(reader.fieldnames)
        )


def calculate_quality(completeness, contamination):
    """Calculate MAG quality metrics."""

    quality_score = round(completeness - (5 * contamination), 2)

    if completeness >= 90 and contamination < 5:
        mimag_quality = "High"
    elif completeness >= 50 and contamination < 10:
        mimag_quality = "Medium"
    else:
        mimag_quality = "Low"

    passes = (
        completeness >= 50
        and contamination < 10
    )

    passes_quality_filter = "YES" if passes else "NO"

    return quality_score, mimag_quality, passes_quality_filter


def parse_taxonomy(classification):
    """Split GTDB taxonomy into ranks."""

    taxonomy = {
        "domain": "NA",
        "phylum": "NA",
        "class": "NA",
        "order": "NA",
        "family": "NA",
        "genus": "NA",
        "species": "NA"
    }

    if not classification:
        return taxonomy

    rank_map = {
        "d": "domain",
        "p": "phylum",
        "c": "class",
        "o": "order",
        "f": "family",
        "g": "genus",
        "s": "species"
    }

    for item in classification.split(";"):

        if "__" not in item:
            continue

        prefix, value = item.split("__", 1)

        if prefix in rank_map and value:
            taxonomy[rank_map[prefix]] = value

    return taxonomy


def read_checkm2(filename):
    """Read CheckM2 quality report."""

    mags = {}

    with open(filename, encoding="utf-8") as handle:

        reader = csv.DictReader(handle, delimiter="\t")

        require_columns(
            reader,
            [
                "Name",
                "Completeness",
                "Contamination"
            ],
            filename
        )

        for row in reader:

            mag = row["Name"]

            completeness = float(row["Completeness"])
            contamination = float(row["Contamination"])

            score, mimag_quality, passes_quality_filter = calculate_quality(
                completeness,
                contamination
            )

            mags[mag] = {
                "completeness": round(completeness, 2),
                "contamination": round(contamination, 2),
                "quality_score": score,
                "mimag_quality": mimag_quality,
                "passes_quality_filter": passes_quality_filter
            }

    return mags


def read_gtdbtk(filename):
    """Read GTDB-Tk taxonomy summary."""

    mags = {}

    with open(filename, encoding="utf-8") as handle:

        reader = csv.DictReader(handle, delimiter="\t")

        require_columns(
            reader,
            [
                "user_genome",
                "classification"
            ],
            filename
        )

        for row in reader:

            mag = row["user_genome"]

            taxonomy = parse_taxonomy(row["classification"])

            taxonomy["closest_reference"] = (
                row.get("closest_genome_reference") or "NA"
            )

            mags[mag] = taxonomy

    return mags


def calculate_gc_percent(fasta):
    """Calculate GC percentage from a FASTA file."""

    total_bases = 0
    gc_bases = 0

    try:
        with open(fasta, encoding="utf-8") as handle:

            for line in handle:

                line = line.strip()

                if not line or line.startswith(">"):
                    continue

                sequence = line.upper()

                total_bases += len(sequence)
                gc_bases += sequence.count("G") + sequence.count("C")

    except OSError as exc:
        die(f"Could not read Prokka FASTA {fasta}: {exc}")

    if total_bases == 0:
        return "NA"

    return round((gc_bases / total_bases) * 100, 2)


def read_prokka(directory):
    """Read Prokka annotations for all MAGs."""

    directory = Path(directory)

    if not directory.exists():
        die(f"Prokka directory not found: {directory}")

    prokka = {}

    for txt_file in sorted(directory.glob("*/**/*.txt")):

        mag = txt_file.stem

        values = {}

        try:
            with open(txt_file, encoding="utf-8") as handle:

                for line in handle:

                    line = line.strip()

                    if not line or ":" not in line:
                        continue

                    key, value = line.split(":", 1)

                    values[key.strip()] = value.strip()

        except OSError as exc:
            die(f"Could not read Prokka summary {txt_file}: {exc}")

        if "bases" not in values:
            continue

        genome_size = values.get("bases", "NA")
        contigs = values.get("contigs", "NA")
        cds = values.get("CDS", "NA")
        crispr = values.get("CRISPR", "NA")
        trna = values.get("tRNA", "NA")
        tmrna = values.get("tmRNA", "NA")

        fna_file = txt_file.with_suffix(".fna")

        if fna_file.exists():
            gc_percent = calculate_gc_percent(fna_file)
        else:
            gc_percent = "NA"

        prokka[mag] = {
            "prokka_genome_size_bp": genome_size,
            "prokka_contigs": contigs,
            "prokka_gc_percent": gc_percent,
            "prokka_cds": cds,
            "prokka_trna": trna,
            "prokka_tmrna": tmrna,
            "prokka_crispr": crispr
        }

    if not prokka:
        die(f"No valid Prokka annotation summaries found in {directory}")

    return prokka


def parse_float(value):
    """Safely convert a value to float."""

    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def round_or_na(value, digits=2):
    """Round numeric values while preserving NA."""

    if value is None:
        return "NA"

    return round(value, digits)


def read_coverm(filename):
    """Read CoverM normalized abundance table."""

    if not Path(filename).exists():
        die(f"CoverM file not found: {filename}")

    mags = {}

    with open(filename, encoding="utf-8") as handle:

        reader = csv.DictReader(handle, delimiter="\t")

        require_columns(
            reader,
            [
                "Genome",
                "coverm_relative_abundance",
                "coverm_mean_coverage",
                "coverm_covered_fraction"
            ],
            filename
        )

        for row in reader:

            mag = row["Genome"].strip()

            if mag == "unmapped":
                continue

            mags[mag] = {
                "coverm_relative_abundance": round_or_na(
                    parse_float(row["coverm_relative_abundance"]),
                    3
                ),
                "coverm_mean_coverage": round_or_na(
                    parse_float(row["coverm_mean_coverage"]),
                    2
                ),
                "coverm_covered_fraction": round_or_na(
                    parse_float(row["coverm_covered_fraction"]),
                    3
                )
            }

        if not mags:
            die(f"No MAGs found in CoverM file: {filename}")

    return mags


def write_summary(
    checkm2,
    gtdb,
    prokka,
    coverm,
    sample,
    participant,
    visit,
    intervention_arm,
    output
):

    """Write the merged MAG summary table."""

    with open(output, "w", newline="", encoding="utf-8") as handle:

        writer = csv.writer(
            handle,
            delimiter="\t",
            lineterminator="\n"
        )

        writer.writerow(SUMMARY_HEADER)

        all_mags = sorted(
            set(checkm2)
            | set(gtdb)
            | set(coverm)
            | set(prokka)
        )

        for mag in all_mags:

            quality = checkm2.get(mag, {})
            taxonomy = gtdb.get(mag, {})
            cover = coverm.get(mag, {})
            prokka_summary = prokka.get(mag, {})

            writer.writerow([
                sample,
                participant,
                visit,
                intervention_arm,
                mag,

                quality.get("completeness", "NA"),
                quality.get("contamination", "NA"),
                quality.get("quality_score", "NA"),
                quality.get("mimag_quality", "NA"),
                quality.get("passes_quality_filter", "NA"),

                taxonomy.get("domain", "NA"),
                taxonomy.get("phylum", "NA"),
                taxonomy.get("class", "NA"),
                taxonomy.get("order", "NA"),
                taxonomy.get("family", "NA"),
                taxonomy.get("genus", "NA"),
                taxonomy.get("species", "NA"),
                taxonomy.get("closest_reference", "NA"),

                cover.get("coverm_relative_abundance", "NA"),
                cover.get("coverm_mean_coverage", "NA"),
                cover.get("coverm_covered_fraction", "NA"),

                prokka_summary.get("prokka_genome_size_bp", "NA"),
                prokka_summary.get("prokka_contigs", "NA"),
                prokka_summary.get("prokka_gc_percent", "NA"),
                prokka_summary.get("prokka_cds", "NA"),
                prokka_summary.get("prokka_trna", "NA"),
                prokka_summary.get("prokka_tmrna", "NA"),
                prokka_summary.get("prokka_crispr", "NA")
            ])


def main():

    parser = argparse.ArgumentParser(
        description=(
            "Merge CheckM2, GTDB-Tk, CoverM and Prokka "
            "results into a MAG summary."
        )
    )

    parser.add_argument("--checkm2", required=True)
    parser.add_argument("--gtdbtk", required=True)
    parser.add_argument("--prokka", required=True)
    parser.add_argument("--coverm", required=True)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--participant", required=True)
    parser.add_argument("--visit", required=True)
    parser.add_argument("--intervention-arm", default="NA")
    parser.add_argument("--output", required=True)

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}"
    )

    args = parser.parse_args()

    checkm2 = read_checkm2(args.checkm2)
    gtdb = read_gtdbtk(args.gtdbtk)
    prokka = read_prokka(args.prokka)
    coverm = read_coverm(args.coverm)

    write_summary(
        checkm2,
        gtdb,
        prokka,
        coverm,
        args.sample,
        args.participant,
        args.visit,
        args.intervention_arm,
        args.output
    )


if __name__ == "__main__":
    main()