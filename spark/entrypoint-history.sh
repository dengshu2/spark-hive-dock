#!/bin/bash
# ============================================================
# Spark History Server Entrypoint — Kerberized HDFS
# ============================================================
set -e

wait_for_port() {
    local host=$1
    local port=$2
    local label=$3
    local max_retries=${4:-60}
    local retry=0

    echo "[history] Waiting for ${label} (${host}:${port}) ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[history] ERROR: ${label} not available after ${max_retries} attempts"
            exit 1
        fi
        sleep 3
    done
    echo "[history] ${label} is available"
}

wait_for_kdc() {
    local ready_file="/etc/security/keytabs/.kdc-ready"
    local max_retries=60
    local retry=0

    echo "[history] Waiting for KDC to be ready ..."
    while [ ! -f "$ready_file" ]; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[history] ERROR: KDC not ready after ${max_retries} retries"
            exit 1
        fi
        sleep 2
    done
    echo "[history] KDC is ready"
}

echo "============================================================"
echo " Spark History Server Startup (HDFS + Kerberos)"
echo "============================================================"

wait_for_kdc
wait_for_port namenode 9000 "HDFS NameNode" 60

PRINCIPAL="spark/spark-history.hive-net@EXAMPLE.COM"
echo "[history] Obtaining Kerberos ticket for ${PRINCIPAL} ..."
kinit -kt /etc/security/keytabs/spark-history.keytab "${PRINCIPAL}"
klist

# This is normally created by the Connect entrypoint. Keeping the operation
# idempotent also makes the History Server safe to start independently.
"${SPARK_HOME}/bin/spark-class" org.apache.hadoop.fs.FsShell \
    -mkdir -p /tmp/spark-events
"${SPARK_HOME}/bin/spark-class" org.apache.hadoop.fs.FsShell \
    -chmod 1777 /tmp/spark-events

echo "[history] Starting Spark History Server on port 18080 ..."
exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.deploy.history.HistoryServer
