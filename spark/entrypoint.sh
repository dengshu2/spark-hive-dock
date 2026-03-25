#!/bin/bash
# ============================================================
# Spark Entrypoint
# Routes to the correct service based on SPARK_ROLE:
#   master  - Spark Master + Thrift Server (Kerberized)
#   worker  - Spark Worker
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

case "${SPARK_ROLE}" in
    master)
        echo "============================================================"
        echo " Spark Master + Thrift Server Startup (Kerberized)"
        echo "============================================================"

        # Wait for KDC and obtain Kerberos ticket
        wait_for_kdc
        FQDN=$(hostname -f)
        echo "[spark] Obtaining Kerberos ticket for spark/${FQDN} ..."
        kinit -kt /etc/security/keytabs/spark.keytab spark/${FQDN}@EXAMPLE.COM
        klist

        # Start Spark Master in background
        echo "[spark] Starting Spark Master ..."
        ${SPARK_HOME}/sbin/start-master.sh

        # Give daemon time to initialize JVM
        sleep 10

        # Wait for Master to be ready
        wait_for_port spark-master 7077 "Spark Master" 60

        # Wait for Hive Metastore
        wait_for_port hive-metastore 9083 "Hive Metastore" 60

        # Wait for HDFS
        wait_for_port namenode 9000 "HDFS NameNode" 60

        # Start Spark Thrift Server (foreground, keeps container alive)
        # Kerberos auth is configured via hive-site.xml (hive.server2.authentication=KERBEROS)
        echo "[spark] Starting Spark Thrift Server on port 10000 (Kerberos) ..."
        FQDN=$(hostname -f)
        exec ${SPARK_HOME}/bin/spark-submit \
            --class org.apache.spark.sql.hive.thriftserver.HiveThriftServer2 \
            --name "Spark Thrift Server" \
            --master local[*] \
            --principal spark/${FQDN}@EXAMPLE.COM \
            --keytab /etc/security/keytabs/spark.keytab \
            --conf spark.sql.warehouse.dir=hdfs://namenode.hive-net:9000/user/hive/warehouse \
            --conf spark.hadoop.hive.metastore.uris=thrift://hive-metastore.hive-net:9083 \
            --conf spark.sql.catalogImplementation=hive \
            spark-internal
        ;;

    worker)
        echo "============================================================"
        echo " Spark Worker Startup (Kerberized)"
        echo "============================================================"

        # Wait for KDC and obtain Kerberos ticket
        wait_for_kdc
        FQDN=$(hostname -f)
        echo "[spark] Obtaining Kerberos ticket for spark/${FQDN} ..."
        kinit -kt /etc/security/keytabs/spark.keytab spark/${FQDN}@EXAMPLE.COM
        klist

        wait_for_port spark-master 7077 "Spark Master" 60

        echo "[spark] Starting Spark Worker ..."
        exec ${SPARK_HOME}/bin/spark-class org.apache.spark.deploy.worker.Worker \
            spark://spark-master:7077
        ;;

    *)
        echo "[spark] ERROR: Unknown SPARK_ROLE '${SPARK_ROLE}'"
        echo "[spark] Valid roles: master, worker"
        exit 1
        ;;
esac
