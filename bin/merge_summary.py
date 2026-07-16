#!/usr/bin/env python3

import argparse
import csv
import sys


VERSION = "MAGFlow merge_summary 1.0.0"

SUMMARY_HEADER = [
    "sample",
    "participant_id",
    "visit",
    "mag_id",
    "completeness",
    "contamination",
    "quality_score",
    "mimag_quality",
    "recommended_pass",
    "domain",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species",
    "closest_reference"
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

    recommended_pass = "YES" if passes else "NO"

    return quality_score, mimag_quality, recommended_pass


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

            score, mimag_quality, recommended_pass = calculate_quality(
                completeness,
                contamination
            )

            mags[mag] = {
                "completeness": completeness,
                "contamination": contamination,
                "quality_score": score,
                "mimag_quality": mimag_quality,
                "recommended_pass": recommended_pass
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

            taxonomy["closest_reference"] = row.get(
                "closest_genome_reference",
                "NA"
            )

            mags[mag] = taxonomy

    return mags


def write_summary(
    checkm2,
    gtdb,
    sample,
    participant,
    visit,
    output
):
    """Write the merged MAG summary table."""

    with open(output, "w", newline="", encoding="utf-8") as handle:

        writer = csv.writer(handle, delimiter="\t")

        writer.writerow(SUMMARY_HEADER)

        for mag in sorted(checkm2):

            taxonomy = gtdb.get(mag, {})

            writer.writerow([
                sample,
                participant,
                visit,
                mag,
                checkm2[mag]["completeness"],
                checkm2[mag]["contamination"],
                checkm2[mag]["quality_score"],
                checkm2[mag]["mimag_quality"],
                checkm2[mag]["recommended_pass"],
                taxonomy.get("domain", "NA"),
                taxonomy.get("phylum", "NA"),
                taxonomy.get("class", "NA"),
                taxonomy.get("order", "NA"),
                taxonomy.get("family", "NA"),
                taxonomy.get("genus", "NA"),
                taxonomy.get("species", "NA"),
                taxonomy.get("closest_reference", "NA")
            ])


def main():

    parser = argparse.ArgumentParser(
        description="Merge CheckM2 and GTDB-Tk results into a MAG summary."
    )

    parser.add_argument("--checkm2", required=True)
    parser.add_argument("--gtdbtk", required=True)
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

    write_summary(
        checkm2,
        gtdb,
        args.sample,
        args.participant,
        args.visit,
        args.output
    )


if __name__ == "__main__":
    main()