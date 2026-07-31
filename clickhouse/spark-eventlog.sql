CREATE DATABASE IF NOT EXISTS spark_observability;

CREATE TABLE IF NOT EXISTS spark_observability.sql_events
(
    event_key String,
    app_id String,
    app_attempt_id String,
    source_file String,
    source_file_index UInt64,
    source_line UInt64,
    event_type LowCardinality(String),
    execution_id UInt64,
    root_execution_id Nullable(UInt64),
    event_time DateTime64(3, 'UTC'),
    event_time_ms UInt64,
    event_version UInt64,
    user_id String,
    session_id String,
    operation_id String,
    sql_text String,
    description String,
    details String,
    physical_plan String,
    error_message String,
    raw_json String,
    collected_at DateTime64(3, 'UTC')
)
ENGINE = ReplacingMergeTree(event_version)
PARTITION BY toYYYYMM(event_time)
ORDER BY (app_id, app_attempt_id, execution_id, event_type)
TTL event_time + INTERVAL 180 DAY DELETE;

ALTER TABLE spark_observability.sql_events
    MODIFY TTL event_time + INTERVAL 180 DAY DELETE;

CREATE VIEW IF NOT EXISTS spark_observability.sql_executions AS
SELECT
    *,
    if(end_time_ms = 0, NULL, end_time_ms - start_time_ms) AS duration_ms,
    multiIf(
        end_time_ms = 0, 'RUNNING',
        error_message = '', 'SUCCEEDED',
        'FAILED'
    ) AS status
FROM
(
    SELECT
        app_id,
        app_attempt_id,
        execution_id,
        argMaxIf(root_execution_id, event_version, event_type = 'start')
            AS root_execution_id,
        maxIf(event_time_ms, event_type = 'start') AS start_time_ms,
        maxIf(event_time_ms, event_type = 'end') AS end_time_ms,
        argMaxIf(user_id, event_version, event_type = 'start') AS user_id,
        argMaxIf(session_id, event_version, event_type = 'start') AS session_id,
        argMaxIf(operation_id, event_version, event_type = 'start')
            AS operation_id,
        argMaxIf(sql_text, event_version, event_type = 'start') AS sql_text,
        argMaxIf(description, event_version, event_type = 'start')
            AS description,
        argMaxIf(physical_plan, event_version, event_type = 'start')
            AS physical_plan,
        argMaxIf(error_message, event_version, event_type = 'end')
            AS error_message
    FROM spark_observability.sql_events
    GROUP BY
        app_id,
        app_attempt_id,
        execution_id
)
WHERE start_time_ms > 0;
