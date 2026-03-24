#!/bin/bash
# ============================================================
# Hadoop Entrypoint Script
# Routes to the correct startup based on HADOOP_ROLE env var
# ============================================================
set -e

# -------------------------------------------------------
# Wait for a TCP port to become available
# Usage: wait_for_port <host> <port> <max_retries>
# -------------------------------------------------------
wait_for_port() {
    local host=$1
    local port=$2
    local max_retries=${3:-30}
    local retry=0

    echo "[entrypoint] Waiting for ${host}:${port} ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[entrypoint] ERROR: ${host}:${port} not available after ${max_retries} retries"
            exit 1
        fi
        echo "[entrypoint]   attempt ${retry}/${max_retries} ..."
        sleep 2
    done
    echo "[entrypoint] ${host}:${port} is available"
}

# -------------------------------------------------------
# Main routing
# -------------------------------------------------------
case "${HADOOP_ROLE}" in
    namenode)
        echo "[entrypoint] Starting as NameNode ..."

        # Format namenode if not already formatted
        if [ ! -f /data/namenode/current/VERSION ]; then
            echo "[entrypoint] Formatting NameNode ..."
            hdfs namenode -format -force -nonInteractive
        else
            echo "[entrypoint] NameNode already formatted, skipping."
        fi

        echo "[entrypoint] Launching NameNode ..."
        exec hdfs namenode
        ;;

    datanode)
        echo "[entrypoint] Starting as DataNode ..."

        # Wait for NameNode to be available
        wait_for_port namenode 9000 60

        echo "[entrypoint] Launching DataNode ..."
        exec hdfs datanode
        ;;

    resourcemanager)
        echo "[entrypoint] Starting as ResourceManager ..."

        # Wait for NameNode to be available
        wait_for_port namenode 9000 60

        echo "[entrypoint] Launching ResourceManager ..."
        exec yarn resourcemanager
        ;;

    nodemanager)
        echo "[entrypoint] Starting as NodeManager ..."

        # Wait for ResourceManager to be available
        wait_for_port resourcemanager 8088 60

        echo "[entrypoint] Launching NodeManager ..."
        exec yarn nodemanager
        ;;

    *)
        echo "[entrypoint] ERROR: Unknown HADOOP_ROLE '${HADOOP_ROLE}'"
        echo "[entrypoint] Valid roles: namenode, datanode, resourcemanager, nodemanager"
        exit 1
        ;;
esac
