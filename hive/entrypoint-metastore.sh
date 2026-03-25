#!/bin/bash
# ============================================================
# Hive Metastore Entrypoint (Kerberized)
# 1. Wait for KDC
# 2. Inject database credentials
# 3. Wait for MySQL and HDFS NameNode
# 4. Create HDFS directories (using hadoop UserGroupInformation)
# 5. Initialize Metastore schema
# 6. Start Hive Metastore service
# ============================================================
set -e

KEYTAB_DIR="/etc/security/keytabs"

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

wait_for_kdc() {
    local ready_file="${KEYTAB_DIR}/.kdc-ready"
    local max_retries=60
    local retry=0

    echo "[metastore] Waiting for KDC to be ready ..."
    while [ ! -f "$ready_file" ]; do
        retry=$((retry + 1))
        if [ "$retry" -ge "$max_retries" ]; then
            echo "[metastore] ERROR: KDC not ready after ${max_retries} retries"
            exit 1
        fi
        echo "[metastore]   KDC attempt ${retry}/${max_retries} ..."
        sleep 2
    done
    echo "[metastore] KDC is ready"
}

# -------------------------------------------------------
# Step 0: Wait for KDC
# -------------------------------------------------------
echo "============================================================"
echo " Hive Metastore Startup Sequence (Kerberized)"
echo "============================================================"

wait_for_kdc

# -------------------------------------------------------
# Step 1: Inject credentials from environment variables
# -------------------------------------------------------
echo "[metastore] Injecting database credentials ..."
sed -i "s|__MYSQL_DATABASE__|${MYSQL_DATABASE:-hive_metastore}|g" ${HIVE_CONF_DIR}/hive-site.xml
sed -i "s|__MYSQL_USER__|${MYSQL_USER:-hive}|g" ${HIVE_CONF_DIR}/hive-site.xml
sed -i "s|__MYSQL_PASSWORD__|${MYSQL_PASSWORD:-hive2024}|g" ${HIVE_CONF_DIR}/hive-site.xml

# Step 2: Wait for MySQL
wait_for_mysql

# Step 3: Wait for HDFS NameNode
wait_for_port namenode 9000 60

# Step 4: Create HDFS directories
# Use Java keytab login by configuring HADOOP_CLIENT_OPTS for the hdfs CLI
echo "[metastore] Creating HDFS directories ..."
echo "[metastore] FQDN = $(hostname -f)"
export HADOOP_CLIENT_OPTS="-Dhadoop.security.authentication=kerberos"

MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
    # Fresh kinit with the hdfs USER principal (not service principal).
    # We use hdfs@EXAMPLE.COM because the Hive container does not have an
    # hdfs/hive-metastore.hive-net service principal — only NameNode and
    # DataNode hosts have hdfs/<host> principals in the keytab.
    kinit -kt ${KEYTAB_DIR}/hdfs.keytab hdfs@EXAMPLE.COM 2>/dev/null || true

    # Try mkdir with all stderr/stdout captured
    OUTPUT=$(hdfs dfs -mkdir -p /user/hive/warehouse 2>&1) && {
        echo "[metastore] HDFS warehouse directory created."
        hdfs dfs -mkdir -p /tmp 2>/dev/null || true
        hdfs dfs -chmod 777 /tmp 2>/dev/null || true
        hdfs dfs -chown hive:supergroup /user/hive/warehouse 2>/dev/null || true
        hdfs dfs -chmod 1777 /user/hive/warehouse 2>/dev/null || true
        break
    }

    if [ "$i" -ge "$MAX_RETRIES" ]; then
        echo "[metastore] ERROR: Failed to create HDFS directories after ${MAX_RETRIES} retries"
        echo "[metastore] Last error: ${OUTPUT}"
        exit 1
    fi
    echo "[metastore]   HDFS retry ${i}/${MAX_RETRIES} (waiting for safe mode exit) ..."
    # Destroy ticket cache to force clean re-init
    kdestroy 2>/dev/null || true
    sleep 5
done

# Step 5: Obtain hive ticket for Metastore service
FQDN=$(hostname -f)
echo "[metastore] Obtaining Kerberos ticket for hive/${FQDN} ..."
kdestroy 2>/dev/null || true
kinit -kt ${KEYTAB_DIR}/hive.keytab hive/${FQDN}@EXAMPLE.COM
klist

# Step 6: Initialize Metastore schema (idempotent)
echo "[metastore] Checking Metastore schema ..."
if schematool -dbType mysql -info 2>&1 | grep -q "Metastore schema version"; then
    echo "[metastore] Schema already initialized"
else
    echo "[metastore] Initializing Metastore schema ..."
    schematool -dbType mysql -initSchema --verbose
    echo "[metastore] Schema initialization complete"
fi

# Step 7: Start Metastore
echo "[metastore] Starting Hive Metastore on port 9083 ..."
exec hive --service metastore
