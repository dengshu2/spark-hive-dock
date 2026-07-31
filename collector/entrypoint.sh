#!/bin/bash
set -euo pipefail

KEYTAB="/etc/security/keytabs/spark-eventlog-collector.keytab"
PRINCIPAL="spark/spark-eventlog-collector.hive-net@EXAMPLE.COM"
READY_FILE="/etc/security/keytabs/.kdc-ready"

wait_for_file() {
    local path=$1
    local label=$2
    local attempts=${3:-60}
    for _ in $(seq 1 "${attempts}"); do
        if [ -f "${path}" ]; then
            return 0
        fi
        sleep 2
    done
    echo "[collector] ERROR: ${label} not ready: ${path}" >&2
    return 1
}

wait_for_port() {
    local host=$1
    local port=$2
    local label=$3
    local attempts=${4:-60}
    for _ in $(seq 1 "${attempts}"); do
        if nc -z "${host}" "${port}" 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo "[collector] ERROR: ${label} not ready: ${host}:${port}" >&2
    return 1
}

renew_ticket() {
    while sleep 3600; do
        if ! kinit -kt "${KEYTAB}" "${PRINCIPAL}"; then
            echo "[collector] WARN: Kerberos ticket renewal failed" >&2
        fi
    done
}

echo "[collector] Waiting for Kerberos, HDFS, and Vector ..."
wait_for_file "${READY_FILE}" "KDC marker"
wait_for_file "${KEYTAB}" "collector keytab"
wait_for_port namenode 9000 "HDFS NameNode"
wait_for_port vector 8687 "Vector HTTP source"

echo "[collector] Obtaining Kerberos ticket for ${PRINCIPAL} ..."
kinit -kt "${KEYTAB}" "${PRINCIPAL}"

renew_ticket &
renew_pid=$!
trap 'kill "${renew_pid}" 2>/dev/null || true' EXIT INT TERM

echo "[collector] Starting Spark Event Log collector ..."
python3 /opt/spark-eventlog-collector/collector.py \
    --hdfs-command-mode direct \
    --sink-mode vector \
    --watch
