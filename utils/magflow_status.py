#!/usr/bin/env python3

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import subprocess

@dataclass
class Task:
    sample: str
    workflow: str
    process: str
    status: str
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
class PipelineState:
    tasks: list

    @property
    def failed_tasks(self):
        return [t for t in self.tasks if t.status == "FAILED"]

    @property
    def completed_tasks(self):
        return [t for t in self.tasks if t.status in ("COMPLETED", "CACHED")]

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
    trace: Path
    report: Path | None = None
    timeline: Path | None = None
    dag: Path | None = None


class RunLocator:

    def __init__(self, logs_dir: Path):
        self.logs_dir = logs_dir

    def latest_run(self) -> RunContext:

        traces = sorted(
            self.logs_dir.glob("trace_*.txt"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

        if not traces:
            raise FileNotFoundError(
                f"No trace_*.txt found in {self.logs_dir}"
            )

        trace = traces[0]

        run_id = trace.stem.removeprefix("trace_")

        return RunContext(
            trace=trace,
            report=self.logs_dir / f"report_{run_id}.html",
            timeline=self.logs_dir / f"timeline_{run_id}.html",
            dag=self.logs_dir / f"dag_{run_id}.html",
        )


@dataclass
class FailureDiagnosis:
    job_id: int
    reason: str = "UNKNOWN"
    details: str = ""
    suggestion: str = ""


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
            "BAKTA"
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


class TraceParser:

    def __init__(self, trace_file: Path):
        self.trace_file = trace_file

    def parse_task_name(self, name: str):

        if ":" in name and "(" in name and name.endswith(")"):

            workflow_process, sample = name.rsplit("(", 1)

            sample = sample.rstrip(")").strip()

            workflow, process = workflow_process.split(":", 1)

            return workflow.strip(), process.strip(), sample

        return "", name.strip(), ""

    def parse(self):

        if not self.trace_file.exists():
            raise FileNotFoundError(
                f"Trace file not found: {self.trace_file}"
            )

        tasks = []

        header = None

        with self.trace_file.open("r") as handle:

            for line in handle:

                line = line.strip()

                if not line:
                    continue

                if line.startswith("task_id"):
                    header = line.split("\t")
                    continue

                columns = line.split("\t")

                if len(columns) != len(header):
                    continue

                record = dict(zip(header, columns))

                workflow, process, sample = self.parse_task_name(record["name"])

                job_id = int(record["native_id"]) if record["native_id"] else None

                exit_code = int(record["exit"]) if record["exit"] else None

                duration = record.get("duration") or None

                workdir = None
                if record.get("workdir"):
                    workdir = Path(record["workdir"])

                tasks.append(
                    Task(
                        sample=sample,
                        workflow=workflow,
                        process=process,
                        status=record["status"],
                        job_id=job_id,
                        exit_code=exit_code,
                        duration=duration,
                        workdir=workdir,
                    )
                )

        return tasks


import subprocess


import re


class LSFParser:

    def diagnose(self, job_id: int) -> FailureDiagnosis:

        try:
            result = subprocess.run(
                ["bacct", "-l", str(job_id)],
                capture_output=True,
                text=True,
                check=False
            )

            text = result.stdout + result.stderr

        except Exception as e:
            return FailureDiagnosis(
                job_id=job_id,
                reason="LSF ERROR",
                details=str(e)
            )

        if "TERM_MEMLIMIT" in text:
            return FailureDiagnosis(
                job_id=job_id,
                reason="MEMORY LIMIT",
                suggestion="Increase process memory."
            )

        if "TERM_RUNLIMIT" in text:
            return FailureDiagnosis(
                job_id=job_id,
                reason="TIME LIMIT",
                suggestion="Increase walltime."
            )

        return FailureDiagnosis(
            job_id=job_id,
            reason="UNKNOWN"
        )


class WorkflowModel:

    def __init__(self, tasks):
        self.tasks = tasks
        self.samples = self.build_sample_index()


    def build_sample_index(self):

        samples = {}

        for task in self.tasks:

            if not task.sample or "#" not in task.sample:
                continue

            samples.setdefault(task.sample, {})

            samples[task.sample][task.process] = task

        return samples


    def get_sample_stage(self, sample):

        tasks = self.samples.get(sample, [])

        if not tasks:
            return "Unknown"

        completed = {
            task.process
            for task in tasks
            if task.status in ("COMPLETED", "CACHED")
        }

        for stage in reversed(WORKFLOW):

            if any(process in completed for process in stage["processes"]):
                return stage["name"]

        return "Not started"


class StatusEngine:

    def __init__(self, model):
        self.model = model


    def stage_progress(self):

        total_samples = len(self.model.samples)

        progress = []

        FINISHED = {"COMPLETED", "CACHED"}

        for stage in WORKFLOW:

            completed = 0

            for sample in self.model.samples.values():

                if any(
                    sample.get(process)
                    and sample[process].status in FINISHED
                    for process in stage["processes"]
                ):
                    completed += 1

            progress.append(
                StageProgress(
                    stage=stage["name"],
                    completed=completed,
                    total=total_samples,
                )
            )

        return progress


class FailureAnalyzer:

    def __init__(self, state):
        self.state = state

    def failed_tasks(self):
        return self.state.failed_tasks


class Dashboard:

    def __init__(self, engine):
        self.engine = engine
    
    def progress_bar(self, completed, total, width=20):

        if total == 0:
            return "░" * width

        fraction = completed / total
        filled = int(fraction * width)

        return "█" * filled + "░" * (width - filled)

    def display(self):

        print("=" * 60)
        print("                 MAGFLOW STATUS")
        print("=" * 60)

        print(f"Samples : {len(self.engine.model.samples)}")
        print(f"Tasks   : {len(self.engine.model.tasks)}")

        print()

        print("Stage Progress")
        print("-" * 60)

        for stage in self.engine.stage_progress():
            
            bar = self.progress_bar(stage.completed, stage.total)

            print(
                f"{stage.stage:<24} "
                f"{bar:<20} "
                f"{stage.completed:>4}/{stage.total:<4}"
            )


if __name__ == "__main__":

    logs = Path("~/pipelines/MAGFlow/logs").expanduser()

    locator = RunLocator(logs)

    run = locator.latest_run()

    parser = TraceParser(run.trace)

    tasks = parser.parse()

    state = PipelineState(tasks)

    model = WorkflowModel(state.tasks)

    engine = StatusEngine(model)

    failure = FailureAnalyzer(state)

    dashboard = Dashboard(engine)

    print(f"Using trace: {run.trace.name}\n")

    dashboard.display()

    parser = LSFParser()

    for task in state.failed_tasks:
        if task.job_id:
            print(parser.diagnose(task.job_id))

    print()
    print("Failed Tasks")

    for task in failure.failed_tasks():
        print(task)