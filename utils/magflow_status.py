#!/usr/bin/env python3

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import subprocess
import re


# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class Task:
    sample: str
    workflow: str
    process: str
    status: str
    name: str = ""
    job_id: Optional[int] = None
    exit_code: Optional[int] = None
    duration: Optional[str] = None
    workdir: Optional[Path] = None


@dataclass
class StageProgress:
    stage: str
    completed: int
    total: int


@dataclass
class ProcessProgress:
    workflow: str
    process: str
    completed: int
    running: int
    pending: int
    failed: int
    total: int


@dataclass
class PipelineState:
    tasks: list

    @property
    def failed_tasks(self):
        return [t for t in self.tasks if t.status == "FAILED"]

    @property
    def completed_tasks(self):
        return [
            t for t in self.tasks
            if t.status in ("COMPLETED", "CACHED")
        ]

    @property
    def running_tasks(self):
        return [
            t for t in self.tasks
            if t.status in ("RUNNING", "SUBMITTED")
        ]

    @property
    def samples(self):
        return sorted({
            t.sample
            for t in self.tasks
            if t.sample
            and "#" in t.sample
        })


@dataclass
class RunContext:
    trace: Optional[Path]
    report: Optional[Path] = None
    timeline: Optional[Path] = None
    dag: Optional[Path] = None
    run_name: str = "Unknown"
    lineage: str = "Unknown"
    active: bool = False


@dataclass
class FailureDiagnosis:
    job_id: int
    reason: str = "UNKNOWN"
    details: str = ""
    suggestion: str = ""


@dataclass
class LSFTask:
    job_id: int
    status: str
    process: str
    sample: str = ""
    job_name: str = ""


# ============================================================================
# WORKFLOW
# ============================================================================

WORKFLOW = [
    {
        "name": "Pipeline information",
        "processes": ["PIPELINE_INFO"]
    },
    {
        "name": "Preprocessing",
        "processes": [
            "FASTP",
            "BOWTIE2_HOST_REMOVAL"
        ]
    },
    {
        "name": "Read-level taxonomy",
        "processes": [
            "KRAKEN2",
            "BRACKEN"
        ]
    },
    {
        "name": "Assembly",
        "processes": [
            "METASPADES"
        ]
    },
    {
        "name": "Read mapping",
        "processes": [
            "BOWTIE2_BUILD_INDEX",
            "BOWTIE2_MAP"
        ]
    },
    {
        "name": "Binning",
        "processes": [
            "METABAT2",
            "CONCOCT",
            "MAXBIN2"
        ]
    },
    {
        "name": "DAS Tool",
        "processes": [
            "DASTOOL"
        ]
    },
    {
        "name": "Quality assessment",
        "processes": [
            "CHECKM2"
        ]
    },
    {
        "name": "Taxonomy",
        "processes": [
            "GTDBTK"
        ]
    },
    {
        "name": "Annotation",
        "processes": [
            "PROKKA"
        ]
    },
    {
        "name": "Abundance",
        "processes": [
            "COVERM"
        ]
    },
    {
        "name": "Summary",
        "processes": [
            "MAG_SUMMARY"
        ]
    }
]


PROCESS_TO_STAGE = {
    process: stage["name"]
    for stage in WORKFLOW
    for process in stage["processes"]
}


# ============================================================================
# RUN LOCATOR
# ============================================================================

class RunLocator:

    def __init__(self, logs_dir: Path):
        self.logs_dir = logs_dir

    def get_history_entries(self):

        history = Path(".nextflow/history")

        if not history.exists():
            return []

        try:
            return history.read_text().splitlines()
        except Exception:
            return []

    def get_latest_history_entry(self):

        entries = self.get_history_entries()

        if not entries:
            return None

        return entries[-1]

    def get_current_master_job(self):

        try:
            result = subprocess.run(
                [
                    "bjobs",
                    "-noheader",
                    "-o",
                    "jobid stat job_name"
                ],
                capture_output=True,
                text=True,
                check=False
            )

        except Exception:
            return None

        for line in result.stdout.splitlines():

            parts = line.split(maxsplit=2)

            if len(parts) != 3:
                continue

            job_id, status, job_name = parts

            if job_name == "MAGFlow":

                return {
                    "job_id": int(job_id),
                    "status": status
                }

        return None

    def get_run_name(self):

        entry = self.get_latest_history_entry()

        if not entry:
            return "Unknown"

        fields = entry.split()

        if len(fields) >= 4:
            return fields[3]

        return "Unknown"

    def get_latest_trace(self):

        traces = sorted(
            self.logs_dir.glob("trace_*.txt"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

        if not traces:
            return None

        return traces[0]

    def get_lineage(self):

        entry = self.get_latest_history_entry()

        if not entry:
            return "Unknown"

        fields = entry.split()

        # Nextflow history:
        #
        # date time duration run_name status revision session_id command
        #
        # Session UUID is field 6 in the whitespace representation.
        if len(fields) >= 6:
            return fields[5]

        return "Unknown"

    def latest_run(self):

        trace = self.get_latest_trace()
        master = self.get_current_master_job()

        active = (
            master is not None
            and master["status"] in ("RUN", "PEND")
        )

        run_id = None

        if trace:
            run_id = trace.stem.removeprefix("trace_")

        return RunContext(
            trace=trace,
            report=(
                self.logs_dir / f"report_{run_id}.html"
                if run_id else None
            ),
            timeline=(
                self.logs_dir / f"timeline_{run_id}.html"
                if run_id else None
            ),
            dag=(
                self.logs_dir / f"dag_{run_id}.html"
                if run_id else None
            ),
            run_name=self.get_run_name(),
            lineage=self.get_lineage(),
            active=active,
        )


# ============================================================================
# LSF TASK PARSER
# ============================================================================

class LSFTaskParser:

    def normalize_process(self, name):

        if "_WORKFLOW_" in name:
            return name.rsplit("_WORKFLOW_", 1)[1]

        if "_" in name:
            return name.split("_", 1)[1]

        return name

    def parse_job_name(self, job_name):

        if not job_name.startswith("nf-"):
            return "", ""

        name = job_name.removeprefix("nf-")

        match = re.match(
            r"(.+?)_\((.+)\)$",
            name
        )

        if not match:
            return self.normalize_process(name), ""

        process_name = match.group(1)
        identifier = match.group(2)

        process = self.normalize_process(process_name)

        sample = identifier

        return process, sample

    def parse(self):

        try:

            result = subprocess.run(
                [
                    "bjobs",
                    "-noheader",
                    "-o",
                    "jobid stat job_name"
                ],
                capture_output=True,
                text=True,
                check=False
            )

        except Exception:
            return []

        tasks = []

        for line in result.stdout.splitlines():

            parts = line.split(maxsplit=2)

            if len(parts) != 3:
                continue

            job_id, status, job_name = parts

            if not job_name.startswith("nf-"):
                continue

            process, sample = self.parse_job_name(job_name)

            if not process:
                continue

            try:
                numeric_job_id = int(job_id)
            except ValueError:
                continue

            tasks.append(
                LSFTask(
                    job_id=numeric_job_id,
                    status=status,
                    process=process,
                    sample=sample,
                    job_name=job_name,
                )
            )

        return tasks


# ============================================================================
# TRACE PARSER
# ============================================================================

class TraceParser:

    def __init__(
        self,
        trace_file: Path,
        metadata_file: Optional[Path] = None
    ):
        self.trace_file = trace_file
        self.sample_aliases = {}

        if metadata_file and metadata_file.exists():

            import csv

            with metadata_file.open(encoding="utf-8") as handle:

                reader = csv.DictReader(handle)

                for row in reader:

                    sample = row.get(
                        "sample",
                        ""
                    ).strip()

                    participant_id = row.get(
                        "participant_id",
                        ""
                    ).strip()

                    visit = row.get(
                        "visit",
                        ""
                    ).strip()

                    if sample and participant_id and visit:

                        alias = (
                            f"{participant_id}_{visit}"
                        )

                        self.sample_aliases[
                            alias
                        ] = sample

    def parse_task_name(self, name):

        if ":" in name and "(" in name and name.endswith(")"):

            workflow_process, sample = name.rsplit(
                "(",
                1
            )

            sample = sample.rstrip(
                ")"
            ).strip()

            sample = self.sample_aliases.get(
                sample,
                sample
            )

            workflow, process = workflow_process.split(
                ":",
                1
            )

            return (
                workflow.strip(),
                process.strip(),
                sample
            )

        if ":" in name:

            workflow, process = name.rsplit(
                ":",
                1
            )

            return (
                workflow.strip(),
                process.strip(),
                ""
            )

        return "", name.strip(), ""

    def parse(self):

        if not self.trace_file:
            return []

        if not self.trace_file.exists():
            return []

        tasks = []

        header = None

        with self.trace_file.open(
            "r",
            errors="replace"
        ) as handle:

            for line in handle:

                line = line.strip()

                if not line:
                    continue

                if line.startswith("task_id"):

                    header = line.split("\t")

                    continue

                if header is None:
                    continue

                columns = line.split("\t")

                if len(columns) != len(header):
                    continue

                record = dict(
                    zip(
                        header,
                        columns
                    )
                )

                task_name = record.get(
                    "name",
                    ""
                )

                workflow, process, sample = \
                    self.parse_task_name(
                        task_name
                    )

                if process == "BAKTA":
                    continue

                native_id = record.get(
                    "native_id",
                    ""
                ).strip()

                try:
                    job_id = (
                        int(native_id)
                        if native_id not in ("", "-")
                        else None
                    )
                except ValueError:
                    job_id = None

                exit_value = record.get(
                    "exit",
                    ""
                ).strip()

                try:
                    exit_code = (
                        int(exit_value)
                        if exit_value not in ("", "-")
                        else None
                    )
                except ValueError:
                    exit_code = None

                duration = (
                    record.get("duration")
                    or None
                )

                workdir = None

                if record.get("workdir"):

                    workdir = Path(
                        record["workdir"]
                    )

                tasks.append(
                    Task(
                        sample=sample,
                        workflow=workflow,
                        process=process,
                        status=record.get(
                            "status",
                            ""
                        ),
                        name=task_name,
                        job_id=job_id,
                        exit_code=exit_code,
                        duration=duration,
                        workdir=workdir,
                    )
                )

        return tasks


# ============================================================================
# LIVE NEXTFLOW LOG PARSER
#
# This is the critical part of the fix.
#
# The trace belongs to the previous completed run in your current situation.
# The live .nextflow.log contains the current resume session.
#
# We use the live log to override the state of tasks from the old trace.
# ============================================================================

class LiveNextflowParser:

    SUBMITTED_RE = re.compile(
        r"\[LSF\] submitted process "
        r"(.+?) > jobId:\s*(\d+);\s*"
        r"workDir:\s*(.+)$"
    )

    COMPLETED_RE = re.compile(
        r"Task completed > TaskHandler\["
        r"jobId:\s*(\d+);.*?"
        r"name:\s*(.+?);\s*"
        r"status:\s*COMPLETED;\s*"
        r"exit:\s*(\d+);.*?"
        r"workDir:\s*(.+?)\s+"
    )

    RUNNING_RE = re.compile(
        r"TaskHandler\["
        r"jobId:\s*(\d+);.*?"
        r"name:\s*(.+?);\s*"
        r"status:\s*RUNNING;"
    )

    SUBMITTED_TASK_RE = re.compile(
        r"TaskHandler\["
        r"jobId:\s*(\d+);.*?"
        r"name:\s*(.+?);\s*"
        r"status:\s*SUBMITTED;"
    )

    def __init__(
        self,
        log_file: Path,
        metadata_file: Optional[Path] = None
    ):

        self.log_file = log_file
        self.sample_aliases = {}

        if metadata_file and metadata_file.exists():

            import csv

            try:

                with metadata_file.open(
                    encoding="utf-8"
                ) as handle:

                    reader = csv.DictReader(handle)

                    for row in reader:

                        sample = row.get(
                            "sample",
                            ""
                        ).strip()

                        participant_id = row.get(
                            "participant_id",
                            ""
                        ).strip()

                        visit = row.get(
                            "visit",
                            ""
                        ).strip()

                        if sample and participant_id and visit:

                            alias = (
                                f"{participant_id}_{visit}"
                            )

                            self.sample_aliases[
                                alias
                            ] = sample

            except Exception:
                pass

    def parse_task_name(self, name):

        if ":" in name and "(" in name and name.endswith(")"):

            workflow_process, sample = name.rsplit(
                "(",
                1
            )

            sample = sample.rstrip(
                ")"
            ).strip()

            sample = self.sample_aliases.get(
                sample,
                sample
            )

            workflow, process = workflow_process.split(
                ":",
                1
            )

            return (
                workflow.strip(),
                process.strip(),
                sample
            )

        if ":" in name:

            workflow, process = name.rsplit(
                ":",
                1
            )

            return (
                workflow.strip(),
                process.strip(),
                ""
            )

        return "", name.strip(), ""

    def parse(self):

        if not self.log_file.exists():
            return []

        tasks = {}

        try:

            lines = self.log_file.read_text(
                errors="replace"
            ).splitlines()

        except Exception:
            return []

        for line in lines:

            # --------------------------------------------------------
            # Submitted process
            # --------------------------------------------------------

            match = self.SUBMITTED_RE.search(
                line
            )

            if match:

                name = match.group(1).strip()
                job_id = int(match.group(2))
                workdir = Path(
                    match.group(3).strip()
                )

                workflow, process, sample = \
                    self.parse_task_name(
                        name
                    )

                if process == "BAKTA":
                    continue

                tasks[name] = Task(
                    sample=sample,
                    workflow=workflow,
                    process=process,
                    status="SUBMITTED",
                    name=name,
                    job_id=job_id,
                    workdir=workdir,
                )

                continue

            # --------------------------------------------------------
            # Completed process
            # --------------------------------------------------------

            match = self.COMPLETED_RE.search(
                line
            )

            if match:

                job_id = int(match.group(1))
                name = match.group(2).strip()
                exit_code = int(match.group(3))

                workdir = Path(
                    match.group(4).strip()
                )

                workflow, process, sample = \
                    self.parse_task_name(
                        name
                    )

                if process == "BAKTA":
                    continue

                tasks[name] = Task(
                    sample=sample,
                    workflow=workflow,
                    process=process,
                    status="COMPLETED",
                    name=name,
                    job_id=job_id,
                    exit_code=exit_code,
                    workdir=workdir,
                )

                continue

            # --------------------------------------------------------
            # Explicit running state
            # --------------------------------------------------------

            match = self.RUNNING_RE.search(
                line
            )

            if match:

                job_id = int(match.group(1))
                name = match.group(2).strip()

                workflow, process, sample = \
                    self.parse_task_name(
                        name
                    )

                if process == "BAKTA":
                    continue

                existing = tasks.get(name)

                if existing and existing.status == "COMPLETED":
                    continue

                tasks[name] = Task(
                    sample=sample,
                    workflow=workflow,
                    process=process,
                    status="RUNNING",
                    name=name,
                    job_id=job_id,
                )

                continue

            # --------------------------------------------------------
            # Explicit submitted state
            # --------------------------------------------------------

            match = self.SUBMITTED_TASK_RE.search(
                line
            )

            if match:

                job_id = int(match.group(1))
                name = match.group(2).strip()

                workflow, process, sample = \
                    self.parse_task_name(
                        name
                    )

                if process == "BAKTA":
                    continue

                existing = tasks.get(name)

                if existing and existing.status == "COMPLETED":
                    continue

                tasks[name] = Task(
                    sample=sample,
                    workflow=workflow,
                    process=process,
                    status="SUBMITTED",
                    name=name,
                    job_id=job_id,
                )

        return list(tasks.values())


# ============================================================================
# MERGE OLD TRACE + CURRENT RESUME
# ============================================================================

def merge_tasks(
    trace_tasks,
    live_tasks,
    lsf_tasks
):

    merged = {}

    # ------------------------------------------------------------------------
    # First load the completed/failed state from the previous trace.
    # ------------------------------------------------------------------------

    for task in trace_tasks:

        if not task.name:
            continue

        merged[task.name] = task

    # ------------------------------------------------------------------------
    # Overlay the live current resume session.
    #
    # A current task ALWAYS supersedes the old trace.
    # This is what removes stale failures.
    # ------------------------------------------------------------------------

    for task in live_tasks:

        if not task.name:
            continue

        merged[task.name] = task

    # ------------------------------------------------------------------------
    # Overlay current LSF state.
    #
    # If Nextflow has submitted a task and LSF says it is RUNNING,
    # display it as RUNNING.
    # ------------------------------------------------------------------------

    for lsf in lsf_tasks:

        if not lsf.sample:
            continue

        candidates = [
            task
            for task in merged.values()
            if task.process == lsf.process
            and task.sample == lsf.sample
        ]

        if not candidates:
            continue

        for task in candidates:

            if lsf.status == "RUN":

                if task.status not in (
                    "COMPLETED",
                    "CACHED"
                ):

                    task.status = "RUNNING"
                    task.job_id = lsf.job_id

            elif lsf.status == "PEND":

                if task.status not in (
                    "COMPLETED",
                    "CACHED",
                    "RUNNING"
                ):

                    task.status = "SUBMITTED"
                    task.job_id = lsf.job_id

    return list(merged.values())


# ============================================================================
# WORKFLOW MODEL
# ============================================================================

class WorkflowModel:

    def __init__(self, tasks):

        self.tasks = tasks
        self.samples = self.build_sample_index()

    def build_sample_index(self):

        samples = {}

        for task in self.tasks:

            if not task.sample:
                continue

            if "#" not in task.sample:
                continue

            samples.setdefault(
                task.sample,
                {}
            )

            samples[
                task.sample
            ][task.process] = task

        return samples


# ============================================================================
# STATUS ENGINE
# ============================================================================

class StatusEngine:

    def __init__(self, model):
        self.model = model

    def process_progress(self):

        processes = {}

        for task in self.model.tasks:

            key = (
                task.workflow,
                task.process
            )

            if key not in processes:

                processes[key] = {
                    "completed": 0,
                    "running": 0,
                    "pending": 0,
                    "failed": 0,
                    "total": 0,
                }

            processes[key]["total"] += 1

            if task.status in (
                "COMPLETED",
                "CACHED"
            ):

                processes[key]["completed"] += 1

            elif task.status in (
                "RUNNING",
                "SUBMITTED"
            ):

                processes[key]["running"] += 1

            elif task.status == "FAILED":

                processes[key]["failed"] += 1

        return processes


# ============================================================================
# FAILURE DIAGNOSIS
# ============================================================================

class LSFParser:

    def diagnose(self, job_id: int):

        try:

            result = subprocess.run(
                [
                    "bacct",
                    "-l",
                    str(job_id)
                ],
                capture_output=True,
                text=True,
                check=False
            )

            text = (
                result.stdout
                + result.stderr
            )

        except Exception as e:

            return FailureDiagnosis(
                job_id=job_id,
                reason="LSF ERROR",
                details=str(e)
            )

        if "TERM_MEMLIMIT" in text:

            max_mem = ""

            match = re.search(
                r"MAX MEM:\s*([0-9.]+\s*Gbytes)",
                text
            )

            if match:
                max_mem = match.group(1)

            return FailureDiagnosis(
                job_id=job_id,
                reason="MEMORY LIMIT",
                details=(
                    f"MAX MEM: {max_mem}"
                    if max_mem
                    else ""
                ),
                suggestion="Increase process memory."
            )

        if "TERM_RUNLIMIT" in text:

            return FailureDiagnosis(
                job_id=job_id,
                reason="TIME LIMIT",
                suggestion="Increase walltime."
            )

        match = re.search(
            r"Exited with exit code\s+(\d+)",
            text
        )

        if match:

            return FailureDiagnosis(
                job_id=job_id,
                reason=f"EXIT CODE {match.group(1)}"
            )

        return FailureDiagnosis(
            job_id=job_id,
            reason="UNKNOWN"
        )


# ============================================================================
# EXPECTED SAMPLE COUNT
# ============================================================================

def get_expected_sample_count(
    metadata_file="input/metadata.csv"
):

    path = Path(metadata_file)

    if not path.exists():
        return None

    try:
        import csv

        with path.open(
            newline="",
            encoding="utf-8-sig"
        ) as handle:

            reader = csv.DictReader(handle)

            sample_ids = {
                row["sample"].strip()
                for row in reader
                if row.get("sample", "").strip()
            }

        return len(sample_ids)

    except Exception:
        return None


# ============================================================================
# DASHBOARD
# ============================================================================

class Dashboard:

    def __init__(
        self,
        engine,
        lsf_tasks=None,
        expected_samples=None
    ):

        self.engine = engine
        self.lsf_tasks = lsf_tasks or []
        self.expected_samples = expected_samples

    def sample_state(
        self,
        process
    ):

        # ------------------------------------------------------------
        # Build process tasks by sample.
        #
        # IMPORTANT:
        # This dashboard reports PROKKA at SAMPLE level.
        # Individual MAGs are NOT displayed here.
        # ------------------------------------------------------------

        sample_tasks = {}

        for task in self.engine.model.tasks:

            if task.process != process:
                continue

            if not task.sample:
                continue

            # PROKKA tasks operate on individual MAGs, but the
            # dashboard reports PROKKA at sample level.
            sample_key = task.sample

            if process == "PROKKA" and ":" in sample_key:
                sample_key = sample_key.split(":", 1)[0]

            sample_tasks.setdefault(
                sample_key,
                []
            ).append(task)

        # ------------------------------------------------------------
        # Overlay live LSF state.
        # ------------------------------------------------------------

        running_samples = {
            task.sample
            for task in self.lsf_tasks
            if task.process == process
            and task.sample
            and task.status == "RUN"
        }

        pending_samples = {
            task.sample
            for task in self.lsf_tasks
            if task.process == process
            and task.sample
            and task.status == "PEND"
        }

        completed = set()
        running = set()
        failed = set()

        for sample, tasks in sample_tasks.items():

            states = [
                task.status
                for task in tasks
            ]

            # Current LSF state wins.

            if sample in running_samples:

                running.add(sample)
                continue

            if sample in pending_samples:

                running.add(sample)
                continue

            # If any task from the current merged state is running.

            if any(
                state in (
                    "RUNNING",
                    "SUBMITTED"
                )
                for state in states
            ):

                running.add(sample)
                continue

            # Prokka is a MAG-level process but is displayed at
            # sample level. A sample is complete only when ALL of
            # its MAG-level Prokka tasks completed successfully.

            if states and all(
                state in (
                    "COMPLETED",
                    "CACHED"
                )
                for state in states
            ):

                completed.add(sample)
                continue

            # A sample with any failed MAG is failed/partial once
            # there are no active tasks.

            if any(
                state == "FAILED"
                for state in states
            ):

                failed.add(sample)

        # ------------------------------------------------------------
        # Metadata defines the denominator.
        # ------------------------------------------------------------

        expected = (
            self.expected_samples
            if self.expected_samples is not None
            else len(sample_tasks)
        )

        pending = max(
            0,
            expected
            - len(completed)
            - len(running)
            - len(failed)
        )

        return (
            len(completed),
            len(running),
            pending,
            len(failed)
        )

    def process_counts(
        self,
        process
    ):

        # PROKKA is displayed at SAMPLE level.

        if process == "PROKKA":

            return self.sample_state(
                process
            )

        # ------------------------------------------------------------
        # Other sample-level processes.
        # ------------------------------------------------------------

        sample_tasks = {}

        for task in self.engine.model.tasks:

            if task.process != process:
                continue

            if not task.sample:
                continue

            sample_tasks.setdefault(
                task.sample,
                []
            ).append(task)

        completed_samples = set()
        running_samples = set()
        failed_samples = set()

        for sample, tasks in sample_tasks.items():

            if any(
                task.status in (
                    "RUNNING",
                    "SUBMITTED"
                )
                for task in tasks
            ):

                running_samples.add(sample)
                continue

            if any(
                task.status == "FAILED"
                for task in tasks
            ):

                failed_samples.add(sample)
                continue

            if tasks and all(
                task.status in (
                    "COMPLETED",
                    "CACHED"
                )
                for task in tasks
            ):

                completed_samples.add(sample)

        # Current LSF state.

        running_samples.update({
            task.sample
            for task in self.lsf_tasks
            if task.process == process
            and task.sample
            and task.status == "RUN"
        })

        completed = len(
            completed_samples
            - running_samples
        )

        running = len(
            running_samples
        )

        failed = len(
            failed_samples
            - running_samples
        )

        if self.expected_samples is not None:

            pending = max(
                0,
                self.expected_samples
                - completed
                - running
                - failed
            )

        else:

            pending = 0

        return (
            completed,
            running,
            pending,
            failed
        )

    def display(
        self,
        run
    ):

        print("=" * 60)
        print(
            "                 MAGFLOW STATUS"
        )
        print("=" * 60)

        print(
            f"Run lineage : {run.lineage}"
        )

        print(
            f"Samples     : {self.expected_samples}"
        )

        print(
            f"Tasks       : {len(self.engine.model.tasks)}"
        )

        print()

        completed_items = []
        running_items = []
        failed_items = []

        for stage in WORKFLOW:

            for process in stage["processes"]:

                completed, running, pending, failed = \
                    self.process_counts(
                        process
                    )

                if (
                    self.expected_samples is not None
                    and process != "PIPELINE_INFO"
                ):

                    total = self.expected_samples

                else:

                    total = (
                        completed
                        + running
                        + pending
                        + failed
                    )

                if completed > 0:

                    completed_items.append(
                        (
                            stage["name"],
                            process,
                            completed,
                            total
                        )
                    )

                if running > 0:

                    running_items.append(
                        (
                            stage["name"],
                            process,
                            running,
                            total
                        )
                    )

                if failed > 0:

                    failed_items.append(
                        (
                            stage["name"],
                            process,
                            failed,
                            total
                        )
                    )

        # ============================================================
        # COMPLETED
        # ============================================================

        print(
            "Completed"
        )

        print(
            "-" * 60
        )

        if completed_items:

            current_stage = None

            for (
                stage,
                process,
                completed,
                total
            ) in completed_items:

                if stage != current_stage:

                    print()
                    print(stage)

                    current_stage = stage

                print(
                    f"  ✔ {process:<25} "
                    f"{completed}/{total}"
                )

        else:

            print("None")

        # ============================================================
        # RUNNING
        # ============================================================

        print()
        print("-" * 60)
        print("Running")
        print("-" * 60)

        if running_items:

            current_stage = None

            for (
                stage,
                process,
                running,
                total
            ) in running_items:

                if stage != current_stage:

                    print()
                    print(stage)

                    current_stage = stage

                print(
                    f"  ◐ {process:<25} "
                    f"{running}/{total}"
                )

        else:

            print("None")

        # ============================================================
        # FAILED
        # ============================================================

        print()
        print("-" * 60)
        print("Failed")
        print("-" * 60)

        if failed_items:

            current_stage = None

            for (
                stage,
                process,
                failed,
                total
            ) in failed_items:

                if stage != current_stage:

                    print()
                    print(stage)

                    current_stage = stage

                print(
                    f"  ✖ {process:<25} "
                    f"{failed}/{total}"
                )

        else:

            print("None")

        # ============================================================
        # ABORTED
        # ============================================================

        print()
        print("-" * 60)
        print("Aborted")
        print("-" * 60)

        aborted_tasks = [
            task
            for task in self.engine.model.tasks
            if task.status == "ABORTED"
        ]

        unique_aborted = {}

        for task in aborted_tasks:

            key = (
                task.process,
                task.sample
            )

            unique_aborted[key] = task

        if unique_aborted:

            current_stage = None

            for task in unique_aborted.values():

                stage = PROCESS_TO_STAGE.get(
                    task.process,
                    "Other"
                )

                if stage != current_stage:

                    print()
                    print(stage)

                    current_stage = stage

                sample = (
                    task.sample
                    or "pipeline"
                )

                print(
                    f"  ⚠ {task.process:<25} "
                    f"{sample} — Nextflow session aborted"
                )

        else:

            print("None")

        # ============================================================
        # LSF
        # ============================================================

        run_count = sum(
            1
            for task in self.lsf_tasks
            if task.status == "RUN"
        )

        pend_count = sum(
            1
            for task in self.lsf_tasks
            if task.status == "PEND"
        )

        print()
        print("-" * 60)
        print("LSF Jobs")
        print("-" * 60)

        print(
            f"RUN  : {run_count}"
        )

        print(
            f"PEND : {pend_count}"
        )


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":

    logs = Path(
        "/lustre/scratch124/pam/teams/team216/ha7/"
        "projects/metagenomics/CATI/MAGFlow_logs"
    )

    metadata = Path(
        "input/metadata.csv"
    )

    locator = RunLocator(
        logs
    )

    run = locator.latest_run()

    # ------------------------------------------------------------------------
    # Previous/latest completed trace.
    # ------------------------------------------------------------------------

    trace_tasks = []

    if run.trace:

        trace_parser = TraceParser(
            run.trace,
            metadata
        )

        trace_tasks = trace_parser.parse()

    # ------------------------------------------------------------------------
    # Current live Nextflow session.
    # ------------------------------------------------------------------------

    live_log = Path(
        ".nextflow.log"
    )

    # Only use .nextflow.log while the current Nextflow run is active.
    # After the run ends, .nextflow.log may contain stale submissions
    # from the ended session and must not override the completed trace.

    if run.active:

        live_parser = LiveNextflowParser(
            live_log,
            metadata
        )

        live_tasks = live_parser.parse()

    else:

        live_tasks = []

    # ------------------------------------------------------------------------
    # Current LSF tasks.
    # ------------------------------------------------------------------------

    lsf_parser = LSFTaskParser()

    lsf_tasks = lsf_parser.parse()

    # ------------------------------------------------------------------------
    # Merge old completed trace with current resume state.
    # ------------------------------------------------------------------------

    tasks = merge_tasks(
        trace_tasks,
        live_tasks,
        lsf_tasks
    )

    state = PipelineState(
        tasks
    )

    model = WorkflowModel(
        state.tasks
    )

    engine = StatusEngine(
        model
    )

    expected_samples = get_expected_sample_count(
        metadata
    )

    dashboard = Dashboard(
        engine,
        lsf_tasks,
        expected_samples
    )

    if run.active:

        print(
            "Nextflow status: ACTIVE"
        )

        print(
            "Using previous trace + live .nextflow.log"
        )

    else:

        print(
            "Nextflow status: NOT ACTIVE"
        )

        if run.trace:

            print(
                f"Using latest trace: "
                f"{run.trace.name}"
            )

    print()

    dashboard.display(
        run
    )
