#!/bin/bash
# ============================================================
# Shared helpers for the host-side scripts in this directory.
#
# Source it (source "$(dirname "$0")/lib.sh"), then call:
#   spark_kinit          — obtain a Kerberos ticket inside ${CONTAINER}
#   wait_for_metastore   — block until the Hive Metastore accepts TCP
#   spark_sql [args...]  — run spark-sql in local mode inside ${CONTAINER};
#                          pass -e "..." or pipe SQL on stdin
#
# All scripts talk to the cluster the same way: spark-sql in local mode
# (--master local[*]) inside the spark-connect container — direct Hive
# Metastore access over Kerberos SASL, no YARN app, no Connect client.
#
# CONTAINER / PRINCIPAL / KEYTAB are overridable via the environment.
# ============================================================

CONTAINER="${CONTAINER:-spark-connect}"
PRINCIPAL="${PRINCIPAL:-spark/spark-connect.hive-net@EXAMPLE.COM}"
KEYTAB="${KEYTAB:-/etc/security/keytabs/spark.keytab}"

spark_kinit() {
    echo "[init] Obtaining Kerberos ticket ..."
    docker exec "${CONTAINER}" kinit -kt "${KEYTAB}" "${PRINCIPAL}"
}

wait_for_metastore() {
    local max_retries=${1:-30} retry=0
    echo "[init] Waiting for Hive Metastore (9083) ..."
    while ! docker exec "${CONTAINER}" nc -z hive-metastore 9083 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[init] ERROR: Hive Metastore not reachable after ${max_retries} attempts"
            exit 1
        fi
        echo "[init]   attempt ${retry}/${max_retries} ..."
        sleep 5
    done
    echo "[init] Hive Metastore is reachable"
}

spark_sql() {
    docker exec -i "${CONTAINER}" /opt/spark/bin/spark-sql --master 'local[*]' "$@"
}
