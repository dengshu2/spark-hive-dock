#!/bin/bash
# ============================================================
# Hadoop Entrypoint Script
# Routes to the correct startup based on HADOOP_ROLE env var
# Includes Kerberos initialization (kinit) before service start
#
# Roles:
#   namenode  - HDFS NameNode + YARN ResourceManager
#   datanode  - HDFS DataNode + YARN NodeManager
# ============================================================
set -e

# -------------------------------------------------------
# Wait for a TCP port to become available
# Usage: wait_for_port <host> <port> <label> <max_retries>
# -------------------------------------------------------
wait_for_port() {
    local host=$1
    local port=$2
    local label=$3
    local max_retries=${4:-30}
    local retry=0

    echo "[entrypoint] Waiting for ${label} (${host}:${port}) ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[entrypoint] ERROR: ${label} not available after ${max_retries} retries"
            exit 1
        fi
        echo "[entrypoint]   attempt ${retry}/${max_retries} ..."
        sleep 2
    done
    echo "[entrypoint] ${label} is available"
}

# -------------------------------------------------------
# Wait for KDC to be ready (keytab volume populated)
# -------------------------------------------------------
wait_for_kdc() {
    local ready_file="/etc/security/keytabs/.kdc-ready"
    local max_retries=60
    local retry=0

    echo "[entrypoint] Waiting for KDC to be ready ..."
    while [ ! -f "$ready_file" ]; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[entrypoint] ERROR: KDC not ready after ${max_retries} retries"
            exit 1
        fi
        echo "[entrypoint]   KDC attempt ${retry}/${max_retries} ..."
        sleep 2
    done
    echo "[entrypoint] KDC is ready"
}

# -------------------------------------------------------
# Main routing
# -------------------------------------------------------
case "${HADOOP_ROLE}" in
    namenode)
        echo "============================================================"
        echo " NameNode + ResourceManager Startup (Kerberized)"
        echo "============================================================"

        # Wait for KDC and obtain Kerberos tickets
        wait_for_kdc
        FQDN=$(hostname -f)
        echo "[entrypoint] FQDN = ${FQDN} (hostname = $(hostname))"

        echo "[entrypoint] Obtaining Kerberos ticket for hdfs/${FQDN} ..."
        kinit -kt /etc/security/keytabs/hdfs.keytab hdfs/${FQDN}@EXAMPLE.COM
        klist

        # Format namenode if not already formatted
        if [ ! -f /data/namenode/current/VERSION ]; then
            echo "[entrypoint] Formatting NameNode ..."
            hdfs namenode -format -force -nonInteractive
        else
            echo "[entrypoint] NameNode already formatted, skipping."
        fi

        # Start YARN ResourceManager in background
        echo "[entrypoint] Starting YARN ResourceManager (background) ..."
        yarn --daemon start resourcemanager

        # Give RM time to initialize
        sleep 5

        echo "[entrypoint] Launching NameNode (foreground) ..."
        exec hdfs namenode
        ;;

    datanode)
        echo "============================================================"
        echo " DataNode + NodeManager Startup (Kerberized)"
        echo "============================================================"

        # Wait for KDC and obtain Kerberos tickets
        wait_for_kdc
        FQDN=$(hostname -f)
        echo "[entrypoint] FQDN = ${FQDN} (hostname = $(hostname))"

        echo "[entrypoint] Obtaining Kerberos ticket for hdfs/${FQDN} ..."
        kinit -kt /etc/security/keytabs/hdfs.keytab hdfs/${FQDN}@EXAMPLE.COM
        klist

        # Wait for NameNode (HDFS) to be available
        wait_for_port namenode 9000 "HDFS NameNode" 60

        # Wait for ResourceManager to be available
        wait_for_port namenode 8032 "YARN ResourceManager" 60

        # Start YARN NodeManager in background
        echo "[entrypoint] Starting YARN NodeManager (background) ..."
        yarn --daemon start nodemanager

        # Give NM time to initialize
        sleep 5

        echo "[entrypoint] Launching DataNode (foreground) ..."
        exec hdfs datanode
        ;;

    *)
        echo "[entrypoint] ERROR: Unknown HADOOP_ROLE '${HADOOP_ROLE}'"
        echo "[entrypoint] Valid roles: namenode, datanode"
        exit 1
        ;;
esac
