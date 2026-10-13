#!/usr/bin/env python3
"""Show live progress for the most recent CATI downstream Nextflow run."""

import argparse
import csv
import os
import re
import sys
import textwrap
import time
from collections import Counter
from pathlib import Path


DEFAULT_ROOT = Path("/data/pam/ha7g/scratch/projects/metagenomics/CATI")
PROCESS_ORDER = [
    "AMRFINDER", "VFDB_SEARCH", "EGGNOG_ANNOTATE", "STRAIN_FASTANI",
]
FINISHED = {"COMPLETED", "CACHED"}
LIVE_STATUSES = {"NEW", "SUBMITTED", "RUNNING"}
TASK_HANDLER = re.compile(
    r"TaskHandler\[jobId:\s*(?P<job>[^;]+);\s*id:\s*(?P<id>\d+);\s*"
    r"name:\s*(?P<name>.*?);\s*status:\s*(?P<status>[A-Z_]+);"
)


def read_trace(path):
    with path.open(newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames or not {"name", "status"}.issubset(reader.fieldnames):
            raise ValueError(f"Not a Nextflow trace file: {path}")
        return list(reader)


def read_live_tasks(path):
    """Read the latest task states logged by Nextflow's live TaskHandler output."""
    if not path or not path.is_file():
        return []

    latest = {}
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = TASK_HANDLER.search(line)
            if not match:
                continue
            task_id = match.group("id")
            job_id = match.group("job").strip()
            latest[task_id] = {
                "task_id": task_id,
                "native_id": "" if job_id.lower() in {"null", "-", ""} else job_id,
                "name": match.group("name").strip(),
                "status": match.group("status").upper(),
                "attempt": "1",
            }

    return [row for row in latest.values() if row["status"] in LIVE_STATUSES]


def latest_trace(log_dir):
    traces = list(log_dir.glob("trace_CATI_downstream_*.txt"))
    return max(traces, key=lambda p: p.stat().st_mtime) if traces else None


def trace_job_id(trace_path):
    # Farm22 run IDs are LSF job IDs; timestamp-based IDs are also supported.
    match = re.fullmatch(r"trace_CATI_downstream_(?:smoke_)?(\d+)\.txt", trace_path.name)
    return match.group(1) if match else None


def engine_log_for_trace(log_dir, trace_path):
    job_id = trace_job_id(trace_path)
    if not job_id:
        return None
    kind = "smoke_" if "_smoke_" in trace_path.name else ""
    filename = f"CATI_downstream_{kind}nextflow_{job_id}.log"
    return log_dir / filename


def read_manifest(path):
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle, delimiter="\t"))
    except OSError:
        return []


def process_name(row):
    return row.get("name", "").split("(", 1)[0].strip().split(":")[-1].strip()


def task_sample(row):
    """Extract the sample part from Nextflow's sample:MAG task tag."""
    if process_name(row) not in {"AMRFINDER", "VFDB_SEARCH", "EGGNOG_ANNOTATE"}:
        return None
    name = row.get("name", "")
    match = re.search(r"\(([^()]*)\)", name)
    if not match:
        return None
    tag = match.group(1).strip()
    if ":" not in tag:
        return None
    sample = tag.split(":", 1)[0].strip()
    return sample or None


def task_tag(row):
    match = re.search(r"\(([^()]*)\)", row.get("name", ""))
    return match.group(1).strip() if match else ""


def attempt_number(row):
    try:
        return int(row.get("attempt") or 1)
    except (TypeError, ValueError):
        return 1


def sample_progress(rows, process, sample_ids, pending_rows):
    """Count sample visits by task state, collapsing MAG tasks by sample."""
    sample_statuses = {}
    expected_counts = Counter()
    selected = [row for row in rows if process_name(row) == process]
    if process in {"AMRFINDER", "VFDB_SEARCH", "EGGNOG_ANNOTATE"}:
        expected_counts.update(row.get("sample", "") for row in pending_rows if row.get("sample"))
        mag_statuses = {}
        for row in selected:
            tag = task_tag(row)
            sample, sep, mag = tag.partition(":")
            if sep:
                current = mag_statuses.setdefault(sample.strip(), {}).get(mag.strip())
                if current is None or attempt_number(row) >= current[0]:
                    mag_statuses[sample.strip()][mag.strip()] = (
                        attempt_number(row), row.get("status", "UNKNOWN").upper())
        for sample, mags in mag_statuses.items():
            sample_statuses[sample] = [status for _, status in mags.values()]
    elif process == "STRAIN_FASTANI":
        group_samples = {}
        for row in pending_rows:
            group = (row.get("participant_id", ""), row.get("species", ""))
            if row.get("sample") and row.get("species") not in {"", "NA", "s__"}:
                group_samples.setdefault(group, set()).add(row["sample"])
        expected_groups = {sample: set() for sample in sample_ids}
        for group, samples in group_samples.items():
            for sample in samples:
                expected_groups.setdefault(sample, set()).add(group)
        expected_counts.update({sample: len(groups) for sample, groups in expected_groups.items()})
        group_statuses = {}
        for row in selected:
            tag = task_tag(row)
            participant, sep, species = tag.partition(":")
            if sep:
                group = (participant.strip(), species.strip())
                current = group_statuses.get(group)
                if current is None or attempt_number(row) >= current[0]:
                    group_statuses[group] = (attempt_number(row), row.get("status", "UNKNOWN").upper())
        for group, (_, status) in group_statuses.items():
            for sample in group_samples.get(group, set()):
                sample_statuses.setdefault(sample, []).append(status)
    elif process == "COLLATE_FEATURES":
        expected_counts.update({sample: 1 for sample in sample_ids})
        for sample in sample_ids:
            sample_statuses[sample] = [row.get("status", "UNKNOWN").upper() for row in selected]

    finished, running, queued, failed, aborted = set(), set(), set(), set(), set()
    for sample in sample_ids:
        sample_states = sample_statuses.get(sample, [])
        expected = expected_counts.get(sample, len(sample_states))
        if process == "STRAIN_FASTANI" and expected == 0:
            # MAGs without an assigned species are intentionally skipped by ANI.
            finished.add(sample)
        if sample in finished:
            continue
        if any(state == "FAILED" for state in sample_states):
            finished.discard(sample)
            failed.add(sample)
        elif any(state in {"ABORTED", "CANCELLED"} for state in sample_states):
            finished.discard(sample)
            aborted.add(sample)
        elif expected > 0 and len(sample_states) >= expected and all(state in FINISHED for state in sample_states):
            finished.add(sample)
        elif any(state == "RUNNING" for state in sample_states):
            running.add(sample)
        else:
            # SUBMITTED tasks are waiting for an executor slot; NEW tasks have
            # not been submitted yet. Samples with no trace row are also queued.
            queued.add(sample)
    return {
        "finished": finished,
        "running": running,
        "pending": queued,
        "failed": failed,
        "aborted": aborted,
        "total": len(sample_ids),
    }


def print_dashboard(root, state_dir, trace, rows, live_rows, manifest_override=None):
    job_id = trace_job_id(trace)
    batch_file = state_dir / "active_batch.tsv"
    batch_id = "not recorded (job may have finalized)"
    if batch_file.exists():
        try:
            with batch_file.open(encoding="utf-8") as handle:
                fields = handle.readline().rstrip("\n").split("\t")
                if len(fields) > 1:
                    batch_id = fields[1]
        except OSError:
            pass
    if job_id:
        lineage_file = state_dir / f"run_lineage_{job_id}.tsv"
        if lineage_file.exists():
            try:
                with lineage_file.open(encoding="utf-8") as handle:
                    fields = handle.readline().rstrip("\n").split("\t")
                    if len(fields) > 1:
                        batch_id = fields[1]
            except OSError:
                pass

    snapshot_dir = state_dir / "batches" / batch_id
    pending_rows = read_manifest(manifest_override) if manifest_override else []
    if not manifest_override:
        pending_rows = read_manifest(snapshot_dir / "pending_manifest.tsv")
        if not pending_rows:
            pending_rows = read_manifest(root / "CATI_downstream_manifest.tsv")
    sample_ids = {row.get("sample", "") for row in pending_rows if row.get("sample")}
    if not sample_ids:
        sample_ids = {task_sample(row) for row in rows if task_sample(row)}
    sample_ids.discard("")

    # Trace files can already contain a task row with status SUBMITTED while
    # the engine log has since advanced it to RUNNING. Keep the newest live
    # state for that task instead of dropping it just because its ID is also
    # present in the trace. Otherwise LSF RUN/PEND totals and sample progress
    # undercount active jobs.
    live_task_ids = {str(row.get("task_id", "")) for row in live_rows
                     if row.get("task_id")}
    all_rows = [row for row in rows
                if str(row.get("task_id", "")) not in live_task_ids] + live_rows

    progress = {
        process: sample_progress(all_rows, process, sample_ids, pending_rows)
        for process in PROCESS_ORDER
    }

    print("=" * 60)
    print("                 CATI DOWNSTREAM STATUS")
    print("=" * 60)
    print(f"Run lineage : {batch_id}")
    print(f"Samples     : {len(sample_ids)}")
    print(f"Tasks       : {len(rows)} trace records; {len(live_rows)} active/queued")
    print()
    print("Completed")
    print("-" * 60)
    any_completed = False
    for process in PROCESS_ORDER:
        completed = len(progress[process]["finished"])
        if completed:
            any_completed = True
            print(f"✔ {process:<25} {completed}/{len(sample_ids)}")
    if not any_completed:
        print("None")

    for section, key, icon in (("Running", "running", "◷"), ("Pending", "pending", "⌛")):
        print("\n" + "-" * 60)
        print(section)
        print("-" * 60)
        any_state = False
        for process in PROCESS_ORDER:
            count = len(progress[process][key])
            if count:
                any_state = True
                print(f"{icon} {process:<25} {count}/{len(sample_ids)}")
        if not any_state:
            print("None")

    for section, key in (("Failed", "failed"), ("Aborted", "aborted")):
        print("\n" + "-" * 60)
        print(section)
        print("-" * 60)
        any_state = False
        for process in PROCESS_ORDER:
            affected = sorted(progress[process][key])
            if affected:
                any_state = True
                print(f"{process}:")
                print(textwrap.fill(", ".join(affected), width=58,
                                    initial_indent="  ", subsequent_indent="  "))
        if not any_state:
            print("None")

    running_job_ids = {row.get("native_id") for row in live_rows
                       if row.get("native_id") and row.get("status", "").upper() == "RUNNING"}
    pending_job_ids = {row.get("native_id") for row in live_rows
                       if row.get("native_id") and row.get("status", "").upper() == "SUBMITTED"}
    print("\n" + "-" * 60)
    print("LSF Jobs")
    print("-" * 60)
    print(f"RUN  : {len(running_job_ids)}")
    print(f"PEND : {len(pending_job_ids)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(os.environ.get("CATI_ROOT", DEFAULT_ROOT)))
    parser.add_argument("--logs-dir", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--watch", type=int, metavar="SECONDS", help="refresh repeatedly at this interval")
    parser.add_argument("--trace", type=Path, help="inspect a specific Nextflow trace file")
    parser.add_argument("--nextflow-log", type=Path,
                        help="live Nextflow engine log corresponding to the trace")
    parser.add_argument("--manifest", type=Path,
                        help="pending manifest for this run (useful for smoke-test runs)")
    args = parser.parse_args()
    if args.watch is not None and args.watch < 1:
        parser.error("--watch must be at least 1 second")

    logs_dir = args.logs_dir or args.root / "MAGFlow_logs"
    state_dir = args.state_dir or args.root / "CATI_downstream_state"
    try:
        while True:
            trace = args.trace or latest_trace(logs_dir)
            if trace is None:
                if args.watch:
                    print("\033[2J\033[H", end="")
                    print(f"Waiting for a downstream Nextflow trace in {logs_dir}...")
                    time.sleep(args.watch)
                    continue
                print(f"No downstream trace found in {logs_dir}.")
                print("Submit the downstream job first; its trace will appear while Nextflow runs.")
                return 1
            rows = read_trace(trace)
            engine_log = args.nextflow_log or engine_log_for_trace(logs_dir, trace)
            live_rows = read_live_tasks(engine_log)
            if args.watch:
                print("\033[2J\033[H", end="")
            print_dashboard(args.root, state_dir, trace, rows, live_rows, args.manifest)
            if not args.watch:
                break
            time.sleep(args.watch)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
