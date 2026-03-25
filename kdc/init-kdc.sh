#!/bin/bash
# ============================================================
# KDC Initialization Script
# 1. Create Kerberos realm database
# 2. Create service principals for all cluster components
#    (both short hostnames AND Docker FQDN with .hive-net suffix)
# 3. Export keytabs to shared volume
# 4. Write ready marker for dependent services
# 5. Start KDC daemon (foreground)
# ============================================================
set -e

REALM="${KRB5_REALM:-EXAMPLE.COM}"
KDC_PASSWORD="${KRB5_KDC_PASSWORD:-kdc_admin_2024}"
KEYTAB_DIR="/etc/security/keytabs"
READY_FILE="${KEYTAB_DIR}/.kdc-ready"

# Docker Compose appends the network name as a domain suffix
# e.g. "namenode" becomes "namenode.hive-net" in DNS
DOCKER_DOMAIN="hive-net"

echo "============================================================"
echo " KDC Initialization — Realm: ${REALM}"
echo "============================================================"

# -------------------------------------------------------
# Step 1: Configure KDC
# -------------------------------------------------------
mkdir -p /var/lib/krb5kdc /etc/krb5kdc

cat > /etc/krb5kdc/kdc.conf <<EOF
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    ${REALM} = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = FILE:/etc/krb5kdc/kadm5.keytab
        acl_file = /etc/krb5kdc/kadm5.acl
        key_stash_file = /etc/krb5kdc/stash
        max_life = 24h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        default_principal_flags = +renewable, +forwardable
    }
EOF

cat > /etc/krb5kdc/kadm5.acl <<EOF
*/admin@${REALM} *
EOF

# -------------------------------------------------------
# Step 2: Create realm database (if not already created)
# -------------------------------------------------------
if [ ! -f /var/lib/krb5kdc/principal ]; then
    echo "[kdc] Creating realm database ..."
    kdb5_util create -r "${REALM}" -s -P "${KDC_PASSWORD}"
else
    echo "[kdc] Realm database already exists, skipping creation."
fi

# -------------------------------------------------------
# Step 3: Create service principals
# Each service gets both short hostname and Docker FQDN versions
# to handle Docker DNS resolution quirks.
# -------------------------------------------------------
echo "[kdc] Creating service principals ..."

create_principal() {
    local princ=$1
    kadmin.local -q "addprinc -randkey ${princ}" 2>/dev/null || true
}

# HDFS
create_principal "hdfs/namenode@${REALM}"
create_principal "hdfs/namenode.${DOCKER_DOMAIN}@${REALM}"
create_principal "hdfs/datanode@${REALM}"
create_principal "hdfs/datanode.${DOCKER_DOMAIN}@${REALM}"
create_principal "hdfs@${REALM}"
create_principal "HTTP/namenode@${REALM}"
create_principal "HTTP/namenode.${DOCKER_DOMAIN}@${REALM}"
create_principal "HTTP/datanode@${REALM}"
create_principal "HTTP/datanode.${DOCKER_DOMAIN}@${REALM}"

# Hive
create_principal "hive/hive-metastore@${REALM}"
create_principal "hive/hive-metastore.${DOCKER_DOMAIN}@${REALM}"

# Spark
create_principal "spark/spark-master@${REALM}"
create_principal "spark/spark-master.${DOCKER_DOMAIN}@${REALM}"
create_principal "spark/spark-worker@${REALM}"
create_principal "spark/spark-worker.${DOCKER_DOMAIN}@${REALM}"
create_principal "HTTP/spark-master@${REALM}"
create_principal "HTTP/spark-master.${DOCKER_DOMAIN}@${REALM}"

# Client (for testing / beeline)
create_principal "client@${REALM}"

echo "[kdc] All principals created."

# -------------------------------------------------------
# Step 4: Export keytabs
# -------------------------------------------------------
echo "[kdc] Exporting keytabs to ${KEYTAB_DIR} ..."
mkdir -p "${KEYTAB_DIR}"

# HDFS keytab (all HDFS-related principals)
kadmin.local -q "ktadd -k ${KEYTAB_DIR}/hdfs.keytab \
    hdfs/namenode@${REALM} \
    hdfs/namenode.${DOCKER_DOMAIN}@${REALM} \
    hdfs/datanode@${REALM} \
    hdfs/datanode.${DOCKER_DOMAIN}@${REALM} \
    hdfs@${REALM} \
    HTTP/namenode@${REALM} \
    HTTP/namenode.${DOCKER_DOMAIN}@${REALM} \
    HTTP/datanode@${REALM} \
    HTTP/datanode.${DOCKER_DOMAIN}@${REALM}"

# Hive keytab
kadmin.local -q "ktadd -k ${KEYTAB_DIR}/hive.keytab \
    hive/hive-metastore@${REALM} \
    hive/hive-metastore.${DOCKER_DOMAIN}@${REALM}"

# Spark keytab (master + worker)
kadmin.local -q "ktadd -k ${KEYTAB_DIR}/spark.keytab \
    spark/spark-master@${REALM} \
    spark/spark-master.${DOCKER_DOMAIN}@${REALM} \
    spark/spark-worker@${REALM} \
    spark/spark-worker.${DOCKER_DOMAIN}@${REALM} \
    HTTP/spark-master@${REALM} \
    HTTP/spark-master.${DOCKER_DOMAIN}@${REALM}"

# Client keytab (for testing)
kadmin.local -q "ktadd -k ${KEYTAB_DIR}/client.keytab \
    client@${REALM}"

# Make keytabs readable by all containers
chmod 444 "${KEYTAB_DIR}"/*.keytab

echo "[kdc] Keytabs exported."

# -------------------------------------------------------
# Step 5: Write ready marker
# -------------------------------------------------------
echo "[kdc] Writing ready marker: ${READY_FILE}"
date > "${READY_FILE}"

# -------------------------------------------------------
# Step 6: Start KDC (foreground)
# -------------------------------------------------------
echo "[kdc] Starting KDC daemon ..."
krb5kdc -n
