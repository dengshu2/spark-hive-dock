#!/usr/bin/env python3
"""Run an isolated ODS -> DWD -> DWS -> ADS flow through Spark Connect.

The script prints a JSON summary and removes the temporary warehouse objects
after validation. Spark Event Log retains the SQL and physical plans.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from pyspark.sql import SparkSession


def json_default(value: object) -> str:
    if isinstance(value, (datetime, Decimal)):
        return str(value)
    raise TypeError(f"Cannot serialize {type(value).__name__}")


def execute(spark: SparkSession, sql_text: str) -> None:
    spark.sql(sql_text).collect()


def query_clickhouse(sql_text: str, marker: str = "") -> dict[str, Any]:
    command = ["chsql", "query"]
    if marker:
        command.extend(["--param", f"marker={marker}"])
    command.append(sql_text)
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"ClickHouse validation failed ({result.returncode}): "
            f"{result.stderr.strip()}"
        )
    rows = [
        json.loads(line)
        for line in result.stdout.splitlines()
        if line.strip()
    ]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one ClickHouse result row, got {len(rows)}")
    return rows[0]


def wait_for_eventlog(marker: str) -> dict[str, Any]:
    timeout_seconds = float(
        os.environ.get("EVENTLOG_TEST_TIMEOUT_SECONDS", "180")
    )
    poll_seconds = float(os.environ.get("EVENTLOG_TEST_POLL_SECONDS", "5"))
    deadline = time.monotonic() + timeout_seconds
    last_stats: dict[str, Any] = {}
    query = """
        SELECT
            count() AS executions,
            countIf(status = 'RUNNING') AS running,
            countIf(status = 'FAILED') AS failed,
            countIf(physical_plan = '') AS without_plan
        FROM spark_observability.sql_executions
        WHERE position(sql_text, %(marker)s) > 0
    """

    while time.monotonic() < deadline:
        last_stats = query_clickhouse(query, marker)
        if (
            int(last_stats["executions"]) >= 9
            and int(last_stats["running"]) == 0
        ):
            if int(last_stats["failed"]) != 0:
                raise AssertionError(
                    f"Failed SQL executions found in Event Log: {last_stats}"
                )
            if int(last_stats["without_plan"]) != 0:
                raise AssertionError(
                    f"Executions without physical plans found: {last_stats}"
                )

            uniqueness = query_clickhouse(
                """
                SELECT
                    count() AS raw_rows,
                    uniqExact(event_key) AS unique_events
                FROM spark_observability.sql_events
                """
            )
            if int(uniqueness["raw_rows"]) != int(
                uniqueness["unique_events"]
            ):
                raise AssertionError(
                    f"Duplicate Event Log rows found: {uniqueness}"
                )
            return {**last_stats, **uniqueness}
        time.sleep(poll_seconds)

    raise TimeoutError(
        f"Event Log was not complete within {timeout_seconds}s: {last_stats}"
    )


def main() -> None:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    prefix = f"eventlog_e2e_{run_id}"
    namespaces = {
        layer: f"{prefix}_{layer}" for layer in ("ods", "dwd", "dws", "ads")
    }
    tables = {
        "ods": f"{namespaces['ods']}.raw_orders",
        "dwd": f"{namespaces['dwd']}.fact_paid_orders",
        "dws": f"{namespaces['dws']}.user_order_summary",
        "ads": f"{namespaces['ads']}.user_value_report",
    }

    spark = (
        SparkSession.builder.remote("sc://localhost:15002")
        .appName(f"eventlog-warehouse-e2e-{run_id}")
        .getOrCreate()
    )

    try:
        for layer in ("ods", "dwd", "dws", "ads"):
            execute(spark, f"CREATE NAMESPACE {namespaces[layer]}")

        execute(
            spark,
            f"""
            CREATE TABLE {tables['ods']} (
                order_id STRING,
                user_id STRING,
                product_id STRING,
                amount STRING,
                order_status STRING,
                event_time STRING,
                source_system STRING
            )
            USING PARQUET
            """,
        )

        execute(
            spark,
            f"""
            INSERT INTO {tables['ods']} VALUES
                ('1', '101', 'P-001', '99.50',  'paid',      '2026-07-30 10:00:00', 'shop_app'),
                ('2', '101', 'P-002', '20.00',  'cancelled', '2026-07-30 10:05:00', 'shop_app'),
                ('3', '102', 'P-003', '149.00', 'PAID',      '2026-07-30 11:00:00', 'mini_app'),
                ('4', '101', 'P-004', '50.50',  'paid',      '2026-07-30 12:00:00', 'shop_app'),
                ('5', '103', 'P-005', '-1.00',  'paid',      '2026-07-30 13:00:00', 'mini_app')
            """,
        )

        execute(
            spark,
            f"""
            CREATE TABLE {tables['dwd']}
            USING PARQUET
            AS
            SELECT
                CAST(order_id AS BIGINT) AS order_id,
                CAST(user_id AS BIGINT) AS user_id,
                product_id,
                CAST(amount AS DECIMAL(18, 2)) AS paid_amount,
                TO_TIMESTAMP(event_time) AS order_time,
                source_system
            FROM {tables['ods']}
            WHERE UPPER(order_status) = 'PAID'
              AND CAST(amount AS DECIMAL(18, 2)) > 0
            """,
        )

        execute(
            spark,
            f"""
            CREATE TABLE {tables['dws']}
            USING PARQUET
            AS
            SELECT
                user_id,
                COUNT(*) AS paid_order_count,
                SUM(paid_amount) AS total_paid_amount,
                MAX(order_time) AS last_paid_time
            FROM {tables['dwd']}
            GROUP BY user_id
            """,
        )

        execute(
            spark,
            f"""
            CREATE TABLE {tables['ads']}
            USING PARQUET
            AS
            SELECT
                user_id,
                paid_order_count,
                total_paid_amount,
                DENSE_RANK() OVER (ORDER BY total_paid_amount DESC) AS value_rank,
                CASE
                    WHEN total_paid_amount >= 150 THEN 'HIGH'
                    ELSE 'NORMAL'
                END AS user_value_level
            FROM {tables['dws']}
            """,
        )

        result_rows = [
            row.asDict(recursive=True)
            for row in spark.sql(
                f"""
                SELECT
                    user_id,
                    paid_order_count,
                    total_paid_amount,
                    value_rank,
                    user_value_level
                FROM {tables['ads']}
                ORDER BY value_rank, user_id
                """
            ).collect()
        ]

        counts = {
            layer: spark.table(table_name).count()
            for layer, table_name in tables.items()
        }
        expected_counts = {"ods": 5, "dwd": 3, "dws": 2, "ads": 2}
        expected_result = [
            {
                "user_id": 101,
                "paid_order_count": 2,
                "total_paid_amount": Decimal("150.00"),
                "value_rank": 1,
                "user_value_level": "HIGH",
            },
            {
                "user_id": 102,
                "paid_order_count": 1,
                "total_paid_amount": Decimal("149.00"),
                "value_rank": 2,
                "user_value_level": "NORMAL",
            },
        ]
        if counts != expected_counts:
            raise AssertionError(f"Unexpected layer counts: {counts}")
        if result_rows != expected_result:
            raise AssertionError(f"Unexpected ADS result: {result_rows}")

        eventlog_validation = wait_for_eventlog(prefix)
        print(
            json.dumps(
                {
                    "validated": True,
                    "run_id": run_id,
                    "spark_version": spark.version,
                    "spark_application_id": spark.conf.get("spark.app.id"),
                    "namespaces": namespaces,
                    "tables": tables,
                    "row_counts": counts,
                    "ads_result": result_rows,
                    "eventlog_validation": eventlog_validation,
                },
                ensure_ascii=False,
                indent=2,
                default=json_default,
            )
        )
    finally:
        for layer in ("ads", "dws", "dwd", "ods"):
            try:
                execute(spark, f"DROP TABLE IF EXISTS {tables[layer]}")
                execute(spark, f"DROP NAMESPACE IF EXISTS {namespaces[layer]}")
            except Exception as exc:
                print(f"cleanup failed for {layer}: {exc}")
        spark.stop()


if __name__ == "__main__":
    main()
