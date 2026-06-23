#!/bin/bash
# ============================================================
# Spark Entrypoint — Connect Server (YARN client mode)
#
# Runs the Spark Connect Server (gRPC, port 15002) as a YARN
# client application. The Driver runs in this container;
# Executors are launched by YARN NodeManagers, which handle
# Kerberos delegation token distribution automatically.
#
# Clients connect with: spark.remote("sc://<host>:15002")
# ============================================================
set -e

wait_for_port() {
    local host=$1
    local port=$2
    local label=$3
    local max_retries=${4:-60}
    local retry=0

    echo "[spark] Waiting for ${label} (${host}:${port}) ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[spark] ERROR: ${label} not available after ${max_retries} attempts"
            exit 1
        fi
        sleep 3
    done
    echo "[spark] ${label} is available"
}

wait_for_kdc() {
    local ready_file="/etc/security/keytabs/.kdc-ready"
    local max_retries=60
    local retry=0

    echo "[spark] Waiting for KDC to be ready ..."
    while [ ! -f "$ready_file" ]; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[spark] ERROR: KDC not ready after ${max_retries} retries"
            exit 1
        fi
        echo "[spark]   KDC attempt ${retry}/${max_retries} ..."
        sleep 2
    done
    echo "[spark] KDC is ready"
}

echo "============================================================"
echo " Spark Connect Server Startup (YARN + Kerberos)"
echo "============================================================"

# Wait for KDC and obtain Kerberos ticket
wait_for_kdc
FQDN=$(hostname -f)
echo "[spark] Obtaining Kerberos ticket for spark/${FQDN} ..."
kinit -kt /etc/security/keytabs/spark.keytab spark/${FQDN}@EXAMPLE.COM
klist

# Wait for dependencies
wait_for_port namenode 9000 "HDFS NameNode" 60
wait_for_port namenode 8032 "YARN ResourceManager" 60
wait_for_port hive-metastore 9083 "Hive Metastore" 60

# Start Spark Connect Server (foreground, keeps container alive)
# YARN mode: Executors get delegation tokens automatically.
# --packages resolves from the Ivy cache baked into the image at build time
# (see Dockerfile), so this does not need to reach Maven at startup.
SPARK_CONNECT_PACKAGE="${SPARK_CONNECT_PACKAGE:-org.apache.spark:spark-connect_2.12:${SPARK_VERSION}}"
echo "[spark] Starting Spark Connect Server on port 15002 (YARN + Kerberos) ..."
exec ${SPARK_HOME}/bin/spark-submit \
    --class org.apache.spark.sql.connect.service.SparkConnectServer \
    --name "Spark Connect Server" \
    --packages "${SPARK_CONNECT_PACKAGE}" \
    --master yarn \
    --deploy-mode client \
    --principal spark/${FQDN}@EXAMPLE.COM \
    --keytab /etc/security/keytabs/spark.keytab \
    --conf spark.connect.grpc.binding.port=15002 \
    spark-internal
