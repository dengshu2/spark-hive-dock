#!/usr/bin/env python3
"""Collect Spark SQL execution events from rolling HDFS Event Logs.

The collector deliberately re-opens the active compressed file, skips JSON
records covered by its durable checkpoint, and emits deterministic event keys.
Completed rolling files are skipped once their final checkpoint is stored.

In production it runs inside a Kerberos-enabled container, reads HDFS through
the bundled Hadoop client, and sends NDJSON to Vector. Vector acknowledges the
HTTP request after ClickHouse delivery or durable disk buffering, so the local
checkpoint only advances after the batch is safe.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import zstandard


SQL_START = (
    "org.apache.spark.sql.execution.ui.SparkListenerSQLExecutionStart"
)
SQL_END = "org.apache.spark.sql.execution.ui.SparkListenerSQLExecutionEnd"
EVENT_FILE_RE = re.compile(r"/events_(\d+)_")
QUOTED_FIELD_CACHE: dict[str, re.Pattern[str]] = {}


def run(
    command: list[str],
    *,
    input_text: str | None = None,
    binary: bool = False,
) -> subprocess.CompletedProcess[Any]:
    result = subprocess.run(
        command,
        input=input_text if not binary else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
        check=False,
    )
    if result.returncode != 0:
        stderr = (
            result.stderr.decode("utf-8", errors="replace")
            if binary
            else result.stderr
        )
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{stderr}"
        )
    return result


def fs_base_command(mode: str, container: str) -> list[str]:
    spark_class = str(
        Path(os.environ.get("SPARK_HOME", "/opt/spark")) / "bin/spark-class"
    )
    command = [
        spark_class,
        "org.apache.hadoop.fs.FsShell",
    ]
    if mode == "docker":
        return ["docker", "exec", container, *command]
    if mode == "direct":
        return command
    if Path(spark_class).exists():
        return command
    return ["docker", "exec", container, *command]


def fs_command(
    mode: str,
    container: str,
    *arguments: str,
    binary: bool = False,
) -> Any:
    command = [*fs_base_command(mode, container), *arguments]
    return run(command, binary=binary).stdout


def list_event_log_files(
    mode: str,
    container: str,
    log_dir: str,
) -> dict[str, dict[str, Any]]:
    output = fs_command(mode, container, "-ls", "-R", log_dir)
    applications: dict[str, dict[str, Any]] = {}
    for line in output.splitlines():
        fields = line.split(maxsplit=7)
        if len(fields) != 8:
            continue
        permissions, _, _, _, size, _, _, path = fields
        if permissions.startswith("d"):
            if "/eventlog_v2_" in path:
                applications.setdefault(
                    path,
                    {"completed": False, "files": [], "listed_size": 0},
                )
            continue

        parent = path.rsplit("/", 1)[0]
        if "/eventlog_v2_" not in parent:
            continue
        app = applications.setdefault(
            parent,
            {"completed": False, "files": [], "listed_size": 0},
        )
        name = path.rsplit("/", 1)[-1]
        if name.startswith("appstatus_"):
            app["completed"] = not name.endswith(".inprogress")
        match = EVENT_FILE_RE.search(path)
        if match:
            app["files"].append(
                {
                    "path": path,
                    "name": name,
                    "index": int(match.group(1)),
                    "listed_size": int(size),
                }
            )
            app["listed_size"] += int(size)

    for app in applications.values():
        app["files"].sort(key=lambda item: item["index"])
    return applications


class CountingReader:
    """Minimal file wrapper that counts compressed bytes consumed by zstd."""

    def __init__(self, stream: Any):
        self.stream = stream
        self.bytes_read = 0

    def read(self, size: int = -1) -> bytes:
        data = self.stream.read(size)
        self.bytes_read += len(data)
        return data


def extract_quoted_field(text: str, field: str) -> str:
    pattern = QUOTED_FIELD_CACHE.get(field)
    if pattern is None:
        pattern = re.compile(
            rf"(?:^|\n)\s*{re.escape(field)}:\s*\"((?:\\.|[^\"\\])*)\"",
            re.DOTALL,
        )
        QUOTED_FIELD_CACHE[field] = pattern
    match = pattern.search(text)
    if not match:
        return ""
    try:
        return json.loads(f'"{match.group(1)}"')
    except json.JSONDecodeError:
        return match.group(1)


def app_identity(directory: str) -> tuple[str, str]:
    name = directory.rsplit("/", 1)[-1]
    identity = name.removeprefix("eventlog_v2_")
    # YARN client mode and local mode in this stack do not have attempt IDs.
    return identity, ""


def event_row(
    event: dict[str, Any],
    *,
    app_id: str,
    attempt_id: str,
    source_file: str,
    source_file_index: int,
    source_line: int,
    collected_at: str,
) -> dict[str, Any] | None:
    spark_event_type = event.get("Event", "")
    if spark_event_type == SQL_START:
        event_type = "start"
    elif spark_event_type == SQL_END:
        event_type = "end"
    else:
        return None

    execution_id = int(event["executionId"])
    event_time_ms = int(event.get("time", 0))
    details = event.get("details", "")
    event_key_text = (
        f"{app_id}\x1f{attempt_id}\x1f{execution_id}\x1f{event_type}"
    )
    event_key = hashlib.sha256(event_key_text.encode("utf-8")).hexdigest()
    event_time = datetime.fromtimestamp(
        event_time_ms / 1000, tz=timezone.utc
    ).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

    return {
        "event_key": event_key,
        "app_id": app_id,
        "app_attempt_id": attempt_id,
        "source_file": source_file,
        "source_file_index": source_file_index,
        "source_line": source_line,
        "event_type": event_type,
        "execution_id": execution_id,
        "root_execution_id": event.get("rootExecutionId"),
        "event_time": event_time,
        "event_time_ms": event_time_ms,
        "event_version": event_time_ms,
        "user_id": extract_quoted_field(details, "user_id"),
        "session_id": extract_quoted_field(details, "session_id"),
        "operation_id": extract_quoted_field(details, "operation_id"),
        "sql_text": extract_quoted_field(details, "query"),
        "description": event.get("description", ""),
        "details": details,
        "physical_plan": event.get("physicalPlanDescription", ""),
        "error_message": event.get("errorMessage", ""),
        "raw_json": json.dumps(event, ensure_ascii=False, separators=(",", ":")),
        "collected_at": collected_at,
    }


def read_new_rows(
    args: argparse.Namespace,
    *,
    path: str,
    processed_lines: int,
    app_id: str,
    attempt_id: str,
    source_file_index: int,
    collected_at: str,
) -> tuple[int, int, list[dict[str, Any]]]:
    command = [
        *fs_base_command(args.hdfs_command_mode, args.hdfs_container),
        "-cat",
        path,
    ]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.stdout is None or process.stderr is None:
        process.kill()
        raise RuntimeError(f"failed to open HDFS reader: {' '.join(command)}")

    compressed = CountingReader(process.stdout)
    rows: list[dict[str, Any]] = []
    valid_lines = 0
    try:
        with zstandard.ZstdDecompressor().stream_reader(
            compressed,
            read_across_frames=True,
        ) as decompressed:
            with io.TextIOWrapper(decompressed, encoding="utf-8") as text:
                while True:
                    line = text.readline()
                    if line == "":
                        break
                    if not line.strip():
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        # An active HDFS file can expose a trailing partial
                        # record. Do not advance the checkpoint past it.
                        break
                    valid_lines += 1
                    if valid_lines <= processed_lines:
                        continue
                    row = event_row(
                        event,
                        app_id=app_id,
                        attempt_id=attempt_id,
                        source_file=path,
                        source_file_index=source_file_index,
                        source_line=valid_lines,
                        collected_at=collected_at,
                    )
                    if row is not None:
                        rows.append(row)
    finally:
        process.stdout.close()

    stderr = process.stderr.read().decode("utf-8", errors="replace")
    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(
            f"HDFS reader failed ({return_code}): {' '.join(command)}\n{stderr}"
        )
    return valid_lines, compressed.bytes_read, rows


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "files": {}}
    with path.open(encoding="utf-8") as stream:
        state = json.load(stream)
    if state.get("version") != 1 or not isinstance(state.get("files"), dict):
        raise ValueError(f"unsupported checkpoint format: {path}")
    return state


def save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(state, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")
    temporary.replace(path)


def initialize_clickhouse(schema_path: Path) -> None:
    statements = [
        statement.strip()
        for statement in schema_path.read_text(encoding="utf-8").split(";")
        if statement.strip()
    ]
    for statement in statements:
        run(
            [
                "chsql",
                "query",
                "--allow-ddl",
                "--write",
                statement,
            ]
        )


def insert_rows_with_chsql(table: str, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    payload = "\n".join(
        json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows
    )
    sql = f"INSERT INTO {table} FORMAT JSONEachRow\n{payload}\n"
    run(["chsql", "query", "--write"], input_text=sql)


def post_rows_to_vector(
    url: str,
    rows: list[dict[str, Any]],
    timeout: float,
) -> None:
    if not rows:
        return
    payload = (
        "\n".join(
            json.dumps(row, ensure_ascii=False, separators=(",", ":"))
            for row in rows
        )
        + "\n"
    ).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={"Content-Type": "application/x-ndjson"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if not 200 <= response.status < 300:
                raise RuntimeError(
                    f"Vector returned HTTP {response.status}: "
                    f"{response.read().decode('utf-8', errors='replace')}"
                )
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Vector returned HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Vector request failed: {exc.reason}") from exc


def emit_rows(args: argparse.Namespace, rows: list[dict[str, Any]]) -> None:
    for start in range(0, len(rows), args.batch_size):
        batch = rows[start : start + args.batch_size]
        if args.sink_mode == "chsql":
            insert_rows_with_chsql(args.table, batch)
        else:
            post_rows_to_vector(args.vector_url, batch, args.http_timeout)


def collect(args: argparse.Namespace) -> dict[str, Any]:
    state_path = Path(args.state).resolve()
    state = load_state(state_path)
    applications = list_event_log_files(
        args.hdfs_command_mode,
        args.hdfs_container,
        args.log_dir,
    )
    collected_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[
        :-3
    ]

    if args.initialize_schema:
        initialize_clickhouse(Path(args.schema).resolve())

    scanned_files = 0
    skipped_completed_files = 0
    inserted_events = 0
    start_events = 0
    end_events = 0

    for directory, application in sorted(applications.items()):
        app_id, attempt_id = app_identity(directory)
        files = application["files"]
        for position, event_file in enumerate(files):
            path = event_file["path"]
            checkpoint = state["files"].get(path, {})
            is_last_file = position == len(files) - 1
            is_immutable = application["completed"] or not is_last_file
            if checkpoint.get("complete") and is_immutable:
                skipped_completed_files += 1
                continue

            processed_lines = int(checkpoint.get("processed_lines", 0))
            valid_lines, actual_compressed_size, rows = read_new_rows(
                args,
                path=path,
                processed_lines=processed_lines,
                app_id=app_id,
                attempt_id=attempt_id,
                source_file_index=event_file["index"],
                collected_at=collected_at,
            )
            scanned_files += 1
            if processed_lines > valid_lines:
                # Defensive recovery for replaced or compacted source files.
                valid_lines, actual_compressed_size, rows = read_new_rows(
                    args,
                    path=path,
                    processed_lines=0,
                    app_id=app_id,
                    attempt_id=attempt_id,
                    source_file_index=event_file["index"],
                    collected_at=collected_at,
                )

            # Vector only returns success after ClickHouse delivery or durable
            # disk buffering. Advancing state after this call provides
            # at-least-once delivery; deterministic keys absorb any replay.
            emit_rows(args, rows)
            state["files"][path] = {
                "processed_lines": valid_lines,
                "listed_size": event_file["listed_size"],
                "actual_compressed_size": actual_compressed_size,
                "complete": is_immutable,
                "updated_at": collected_at,
            }
            save_state(state_path, state)
            inserted_events += len(rows)
            start_events += sum(row["event_type"] == "start" for row in rows)
            end_events += sum(row["event_type"] == "end" for row in rows)

    return {
        "applications_seen": len(applications),
        "files_scanned": scanned_files,
        "completed_files_skipped": skipped_completed_files,
        "sql_events_inserted": inserted_events,
        "start_events": start_events,
        "end_events": end_events,
        "checkpoint": str(state_path),
        "sink": args.table if args.sink_mode == "chsql" else args.vector_url,
    }


def write_health(
    path: str,
    *,
    ok: bool,
    summary: dict[str, Any] | None = None,
    error: str = "",
) -> None:
    if not path:
        return
    health_path = Path(path)
    health_path.parent.mkdir(parents=True, exist_ok=True)
    payload: dict[str, Any] = {
        "ok": ok,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }
    if summary is not None:
        payload["summary"] = summary
    if error:
        payload["error"] = error
    temporary = health_path.with_suffix(health_path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, ensure_ascii=False)
        stream.write("\n")
    temporary.replace(health_path)


def parse_args() -> argparse.Namespace:
    repository = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--hdfs-command-mode",
        choices=("auto", "direct", "docker"),
        default=os.environ.get("EVENTLOG_HDFS_COMMAND_MODE", "auto"),
    )
    parser.add_argument(
        "--hdfs-container",
        default=os.environ.get("EVENTLOG_HDFS_CONTAINER", "spark-history"),
    )
    parser.add_argument(
        "--log-dir",
        default=os.environ.get(
            "EVENTLOG_HDFS_LOG_DIR",
            "hdfs://namenode.hive-net:9000/tmp/spark-events",
        ),
    )
    parser.add_argument(
        "--state",
        default=os.environ.get(
            "EVENTLOG_STATE_PATH",
            str(repository / "var/spark-eventlog-collector/state.json"),
        ),
    )
    parser.add_argument(
        "--schema",
        default=os.environ.get(
            "EVENTLOG_SCHEMA_PATH",
            str(repository / "clickhouse/spark-eventlog.sql"),
        ),
    )
    parser.add_argument(
        "--initialize-schema",
        action="store_true",
        default=os.environ.get("EVENTLOG_INITIALIZE_SCHEMA", "false").lower()
        == "true",
    )
    parser.add_argument(
        "--schema-only",
        action="store_true",
        help="create ClickHouse schema with chsql, then exit",
    )
    parser.add_argument(
        "--sink-mode",
        choices=("vector", "chsql"),
        default=os.environ.get("EVENTLOG_SINK_MODE", "chsql"),
    )
    parser.add_argument(
        "--vector-url",
        default=os.environ.get(
            "EVENTLOG_VECTOR_URL",
            "http://vector:8687/spark-eventlog",
        ),
    )
    parser.add_argument(
        "--table",
        default=os.environ.get(
            "EVENTLOG_CLICKHOUSE_TABLE",
            "spark_observability.sql_events",
        ),
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=int(os.environ.get("EVENTLOG_BATCH_SIZE", "250")),
    )
    parser.add_argument(
        "--http-timeout",
        type=float,
        default=float(os.environ.get("EVENTLOG_HTTP_TIMEOUT", "120")),
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        default=os.environ.get("EVENTLOG_WATCH", "false").lower() == "true",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=float(os.environ.get("EVENTLOG_INTERVAL_SECONDS", "30")),
    )
    parser.add_argument(
        "--health-file",
        default=os.environ.get("EVENTLOG_HEALTH_FILE", ""),
    )
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size must be at least 1")
    if args.interval <= 0:
        parser.error("--interval must be positive")
    return args


def main() -> None:
    args = parse_args()
    if args.schema_only:
        initialize_clickhouse(Path(args.schema).resolve())
        print(
            json.dumps(
                {"ok": True, "schema_initialized": str(Path(args.schema).resolve())}
            )
        )
        return
    # The health file lives in a persistent volume. Reset it on every process
    # start so a freshly restarted container cannot inherit a stale "ok".
    write_health(args.health_file, ok=False, error="collector starting")
    while True:
        try:
            summary = collect(args)
            write_health(args.health_file, ok=True, summary=summary)
            print(
                json.dumps({"ok": True, **summary}, ensure_ascii=False),
                flush=True,
            )
        except Exception as exc:
            write_health(args.health_file, ok=False, error=str(exc))
            print(
                json.dumps(
                    {"ok": False, "error": str(exc)},
                    ensure_ascii=False,
                ),
                flush=True,
            )
            if not args.watch:
                raise
        if not args.watch:
            break
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
