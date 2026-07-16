#!/usr/bin/env python3

import argparse
import csv
import json
import sys
from pathlib import Path


VERSION = "MAGFlow merge_summary 1.0.0"

SUMMARY_HEADER = [
    "sample",
    "participant_id",
    "visit",
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

    # Bakta
    "bakta_genome_size_bp",
    "bakta_gc_percent",
    "bakta_coding_density_percent",
    "bakta_cds",
    "bakta_trna",
    "bakta_rrna",
    "bakta_ncrna",
    "bakta_ncrna_regions",
    "bakta_crispr_arrays",
    "bakta_sorfs",
    "bakta_oric",
    "bakta_orit"
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


def read_bakta(directory):
    """Read Bakta annotations for all MAGs."""

    directory = Path(directory)

    if not directory.exists():
        die(f"Bakta directory not found: {directory}")

    bakta = {}

    feature_map = {
        "cds": "bakta_cds",
        "tRNA": "bakta_trna",
        "rRNA": "bakta_rrna",
        "ncRNA": "bakta_ncrna",
        "ncRNA-region": "bakta_ncrna_regions",
        "crispr": "bakta_crispr_arrays",
        "sorf": "bakta_sorfs",
        "oriC": "bakta_oric",
        "oriT": "bakta_orit"
    }

    for json_file in sorted(directory.glob("*/**/*.json")):

        mag = json_file.stem

        with open(json_file, encoding="utf-8") as handle:
            data = json.load(handle)

        stats = data.get("stats", {})
        features = data.get("features", [])

        summary = {
            "bakta_genome_size_bp": stats.get("size", "NA"),
            "bakta_gc_percent": round(stats.get("gc", 0.0) * 100, 2),
            "bakta_coding_density_percent": round(
                stats.get("coding_ratio", 0.0) * 100,
                2
            ),
            "bakta_cds": 0,
            "bakta_trna": 0,
            "bakta_rrna": 0,
            "bakta_ncrna": 0,
            "bakta_ncrna_regions": 0,
            "bakta_crispr_arrays": 0,
            "bakta_sorfs": 0,
            "bakta_oric": 0,
            "bakta_orit": 0
        }

        for feature in features:

            feature_type = feature.get("type", "")

            if feature_type in feature_map:
                summary[feature_map[feature_type]] += 1

        bakta[mag] = summary

    if not bakta:
        die(f"No Bakta JSON files found in {directory}")

    return bakta


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
    bakta,
    coverm,
    sample,
    participant,
    visit,
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
            | set(bakta)

        )

        for mag in all_mags:

            quality = checkm2.get(mag, {})
            taxonomy = gtdb.get(mag, {})
            cover = coverm.get(mag, {})
            bakta_summary = bakta.get(mag, {})

            writer.writerow([
                sample,
                participant,
                visit,
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

                bakta_summary.get("bakta_genome_size_bp", "NA"),
                bakta_summary.get("bakta_gc_percent", "NA"),
                bakta_summary.get("bakta_coding_density_percent", "NA"),
                bakta_summary.get("bakta_cds", "NA"),
                bakta_summary.get("bakta_trna", "NA"),
                bakta_summary.get("bakta_rrna", "NA"),
                bakta_summary.get("bakta_ncrna", "NA"),
                bakta_summary.get("bakta_ncrna_regions", "NA"),
                bakta_summary.get("bakta_crispr_arrays", "NA"),
                bakta_summary.get("bakta_sorfs", "NA"),
                bakta_summary.get("bakta_oric", "NA"),
                bakta_summary.get("bakta_orit", "NA")
            ])


def main():

    parser = argparse.ArgumentParser(
        description="Merge CheckM2, GTDB-Tk, CoverM and Bakta results into a MAG summary."
    )

    parser.add_argument("--checkm2", required=True)
    parser.add_argument("--gtdbtk", required=True)
    parser.add_argument("--bakta", required=True)
    parser.add_argument("--coverm", required=True)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--participant", required=True)
    parser.add_argument("--visit", required=True)
    parser.add_argument("--output", required=True)

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}"
    )

    args = parser.parse_args()

    checkm2 = read_checkm2(args.checkm2)
    gtdb = read_gtdbtk(args.gtdbtk)
    bakta = read_bakta(args.bakta)
    coverm = read_coverm(args.coverm)

    write_summary(
        checkm2,
        gtdb,
        bakta,
        coverm,
        args.sample,
        args.participant,
        args.visit,
        args.output
    )


if __name__ == "__main__":
    main()