# syntax=docker/dockerfile:1
# ============================================================
# Spark 4.1.2 Image
# - JDK 17 (Spark 4.x requirement)
# - Scala 2.13 (Spark 4.x dropped Scala 2.12)
# - Hadoop + YARN client configs for HDFS/YARN access
# - Hive Metastore integration via Spark SQL
# - Spark Connect Server (gRPC) — BUNDLED in the 4.x distribution
#   (no more --packages / Ivy pre-resolution needed; see entrypoint.sh)
# - Kerberos client for authenticated access
# - Uses BuildKit cache for download layer (avoids re-download)
# ============================================================

# Hive image to source the 4.1.0 metastore client jars from. Declared in global
# scope (before the first FROM) so it can parameterize the hive-libs stage —
# BuildKit does not allow variable expansion directly in `COPY --from=${VAR}`.
ARG HIVE_VERSION=4.1.0
ARG HIVE_METASTORE_IMAGE=hive-metastore:${HIVE_VERSION}
FROM ${HIVE_METASTORE_IMAGE} AS hive-libs

FROM eclipse-temurin:17-jre-jammy

LABEL description="Spark 4.1.2 Connect Server with YARN + Kerberos (JDK 17, Scala 2.13)"

ARG SPARK_VERSION=4.1.2
# mysql-connector-java was renamed to mysql-connector-j (coordinate
# com.mysql:mysql-connector-j) from 8.1 onward; 8.0.x is EOL/deprecated.
ARG MYSQL_CONNECTOR_VERSION=9.1.0
# archive.apache.org caps bandwidth at ~40KB/s; huaweicloud mirror is ~140x faster.
# Spark 4.x bin-hadoop3 tarballs are Scala 2.13 (the only Scala build in 4.x).
ARG SPARK_URL=https://mirrors.huaweicloud.com/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz
ARG MYSQL_CONNECTOR_URL=https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar
# ClickHouse JDBC driver (shaded "all" uber jar) — lets Spark write to ClickHouse
# via JDBC (`com.clickhouse.jdbc.ClickHouseDriver`). Used by spark-connect-cli
# `sync`.
# 0.7.2 "all": verified to be a *complete* uber jar (bundles clickhouse-client +
# clickhouse-http + the com.clickhouse.client.ClickHouseClient SPI and its
# META-INF/services registration), so the driver's static initializer succeeds.
# We moved off 0.4.6: that old client failed batch writes on the JDK 17 / Spark
# 4.1 stack with "BatchUpdateException: Unknown error 1002" (the endpoint itself
# was fine — chsql reached it). 0.7.2 is the version the official ClickHouse
# Spark docs use. NOTE: avoid the 0.6.x "-all" classifier — it ships WITHOUT the
# ClickHouseClient SPI and the driver fails to initialize.
ARG CLICKHOUSE_JDBC_VERSION=0.7.2
ARG CLICKHOUSE_JDBC_URL=https://repo1.maven.org/maven2/com/clickhouse/clickhouse-jdbc/${CLICKHOUSE_JDBC_VERSION}/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar
# Apache Iceberg Spark runtime — table format support (HiveCatalog backed by the
# Hive 4.1.0 HMS). 1.11.0 is the first line with a Spark 4.1 / Scala 2.13 build.
# NOTE: Iceberg's HiveCatalog instantiates its own HiveMetaStoreClient from the
# main classpath (Spark's bundled Hive 2.3.10) and does NOT honor
# spark.sql.hive.metastore.jars — so against the Hive 4.1.0 HMS it would hit
# "Invalid method name: 'get_table'". The fix is in spark-defaults.conf:
# spark.driver.extraClassPath prepends the baked Hive 4.1.0 metastore client jars
# (/opt/hive-metastore-libs) ahead of the 2.3.10 ones. Verified not to disturb
# Spark's own spark_catalog (which uses the isolated 4.1.0 client loader).
ARG ICEBERG_SPARK_RUNTIME_VERSION=1.11.0
ARG ICEBERG_SPARK_RUNTIME_URL=https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/${ICEBERG_SPARK_RUNTIME_VERSION}/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar

ENV SPARK_VERSION=${SPARK_VERSION}
ENV SPARK_HOME=/opt/spark
ENV HADOOP_CONF_DIR=/opt/spark/conf/hadoop
ENV YARN_CONF_DIR=/opt/spark/conf/hadoop
ENV PATH=${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}

# Install utilities (includes Kerberos client)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl netcat-openbsd krb5-user procps tini \
    && rm -rf /var/lib/apt/lists/*

# Download and install Spark (cached across rebuilds)
RUN --mount=type=cache,target=/tmp/downloads \
    if ! gzip -t /tmp/downloads/spark-${SPARK_VERSION}.tgz 2>/dev/null; then \
        curl -fSL --retry 3 "${SPARK_URL}" -o /tmp/downloads/spark-${SPARK_VERSION}.tgz.part \
        && mv /tmp/downloads/spark-${SPARK_VERSION}.tgz.part /tmp/downloads/spark-${SPARK_VERSION}.tgz; \
    fi \
    && tar -xzf /tmp/downloads/spark-${SPARK_VERSION}.tgz -C /opt/ \
    && mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}

# Add MySQL JDBC driver (Spark needs it for Hive Metastore access)
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar ]; then \
        curl -fSL --retry 3 "${MYSQL_CONNECTOR_URL}" -o /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar.part \
        && mv /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar.part /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar ${SPARK_HOME}/jars/

# Add ClickHouse JDBC driver (for Spark -> ClickHouse writes via `scq sync`).
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar ]; then \
        curl -fSL --retry 3 "${CLICKHOUSE_JDBC_URL}" -o /tmp/downloads/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar.part \
        && mv /tmp/downloads/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar.part /tmp/downloads/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar; \
    fi \
    && cp /tmp/downloads/clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar ${SPARK_HOME}/jars/

# Add the Iceberg Spark runtime (table-format support; see ARG comment above).
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar ]; then \
        curl -fSL --retry 3 "${ICEBERG_SPARK_RUNTIME_URL}" -o /tmp/downloads/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar.part \
        && mv /tmp/downloads/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar.part /tmp/downloads/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/iceberg-spark-runtime-4.1_2.13-${ICEBERG_SPARK_RUNTIME_VERSION}.jar ${SPARK_HOME}/jars/

# Bake Hive 4.1.0 metastore client jars so Spark's IsolatedClientLoader can talk
# to the Hive 4.1.0 HMS. The builtin Hive 2.3.10 client uses the Thrift method
# get_table, which Hive 4.x removed (it uses get_table_req) — so the builtin
# client fails with "Invalid method name: 'get_table'". Copied from the
# already-built hive image (no second Hive download); wired up via
# spark.sql.hive.metastore.jars=path in spark-defaults.conf.
COPY --from=hive-libs /opt/hive/lib /opt/hive-metastore-libs

# Hadoop + YARN configuration (HDFS and YARN access)
RUN mkdir -p ${HADOOP_CONF_DIR}
COPY core-site.xml ${HADOOP_CONF_DIR}/core-site.xml
COPY hdfs-site.xml ${HADOOP_CONF_DIR}/hdfs-site.xml
COPY yarn-site.xml ${HADOOP_CONF_DIR}/yarn-site.xml
COPY mapred-site.xml ${HADOOP_CONF_DIR}/mapred-site.xml

# Spark configuration
COPY spark-defaults.conf ${SPARK_HOME}/conf/spark-defaults.conf

# Hive Metastore client config
COPY hive-site.xml ${SPARK_HOME}/conf/hive-site.xml

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
COPY entrypoint-history.sh /entrypoint-history.sh
RUN chmod +x /entrypoint.sh /entrypoint-history.sh

ENTRYPOINT ["/entrypoint.sh"]
