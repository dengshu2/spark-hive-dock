#!/bin/bash
# ============================================================
# Hive Metastore Entrypoint
# 1. Inject database credentials from environment variables
# 2. Wait for MySQL to be ready
# 3. Wait for HDFS (NameNode) to be ready and leave safe mode
# 4. Create HDFS directories for Hive warehouse
# 5. Initialize Metastore schema (first run only)
# 6. Start Hive Metastore service
# ============================================================
set -e

wait_for_port() {
    local host=$1
    local port=$2
    local max_retries=${3:-60}
    local retry=0

    echo "[metastore] Waiting for ${host}:${port} ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[metastore] ERROR: ${host}:${port} not available after ${max_retries} attempts"
            exit 1
        fi
        echo "[metastore]   attempt ${retry}/${max_retries} ..."
        sleep 3
    done
    echo "[metastore] ${host}:${port} is available"
}

wait_for_mysql() {
    local max_retries=60
    local retry=0

    echo "[metastore] Waiting for MySQL to be ready ..."
    while ! mysqladmin ping -h mysql -u root -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[metastore] ERROR: MySQL not ready after ${max_retries} attempts"
            exit 1
        fi
        echo "[metastore]   MySQL attempt ${retry}/${max_retries} ..."
        sleep 3
    done
    echo "[metastore] MySQL is ready"
}

wait_for_hdfs() {
    local max_retries=60
    local retry=0

    echo "[metastore] Waiting for HDFS to leave safe mode ..."
    while true; do
        safe_mode=$(hdfs dfsadmin -safemode get 2>/dev/null || echo "UNKNOWN")
        if echo "$safe_mode" | grep -q "OFF"; then
            echo "[metastore] HDFS safe mode is OFF"
            break
        fi
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[metastore] ERROR: HDFS did not leave safe mode after ${max_retries} attempts"
            exit 1
        fi
        echo "[metastore]   HDFS safe mode: ${safe_mode} (attempt ${retry}/${max_retries})"
        sleep 3
    done
}

# -------------------------------------------------------
# Step 0: Inject credentials from environment variables
# -------------------------------------------------------
echo "============================================================"
echo " Hive Metastore Startup Sequence"
echo "============================================================"

echo "[metastore] Injecting database credentials ..."
sed -i "s|__MYSQL_DATABASE__|${MYSQL_DATABASE:-hive_metastore}|g" ${HIVE_CONF_DIR}/hive-site.xml
sed -i "s|__MYSQL_USER__|${MYSQL_USER:-hive}|g" ${HIVE_CONF_DIR}/hive-site.xml
sed -i "s|__MYSQL_PASSWORD__|${MYSQL_PASSWORD:-hive2024}|g" ${HIVE_CONF_DIR}/hive-site.xml

# Step 1: Wait for MySQL
wait_for_mysql

# Step 2: Wait for HDFS
wait_for_port namenode 9000 60
wait_for_hdfs

# Step 3: Create HDFS directories
echo "[metastore] Creating HDFS directories ..."
hdfs dfs -mkdir -p /user/hive/warehouse
hdfs dfs -mkdir -p /tmp
hdfs dfs -chmod 777 /tmp
hdfs dfs -chmod 755 /user/hive/warehouse

# Step 4: Initialize Metastore schema (idempotent)
echo "[metastore] Checking Metastore schema ..."
if schematool -dbType mysql -info 2>&1 | grep -q "Metastore schema version"; then
    echo "[metastore] Schema already initialized"
else
    echo "[metastore] Initializing Metastore schema ..."
    schematool -dbType mysql -initSchema --verbose
    echo "[metastore] Schema initialization complete"
fi

# Step 5: Start Metastore
echo "[metastore] Starting Hive Metastore on port 9083 ..."
exec hive --service metastore
