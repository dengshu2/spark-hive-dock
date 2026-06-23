# syntax=docker/dockerfile:1
# ============================================================
# Spark 3.5.3 Image
# - JDK 11 (Spark 3.5 requirement)
# - Hadoop + YARN client configs for HDFS/YARN access
# - Hive Metastore integration via Spark SQL
# - Spark Connect Server (gRPC) — Spark 3.5+ feature
# - Kerberos client for authenticated access
# - Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
FROM eclipse-temurin:11-jre-jammy

LABEL description="Spark 3.5.3 Connect Server with YARN + Kerberos"

ARG SPARK_VERSION=3.5.3
ARG MYSQL_CONNECTOR_VERSION=8.0.28
# Spark Connect server module + its transitive deps (gRPC/protobuf/guava).
# Not bundled in the binary distribution's jars/, so it is resolved via Ivy.
ARG SPARK_CONNECT_PACKAGE=org.apache.spark:spark-connect_2.12:${SPARK_VERSION}
# Maven mirror for fast Ivy resolution (proxies Maven Central)
ARG MAVEN_MIRROR=https://mirrors.huaweicloud.com/repository/maven/
# archive.apache.org caps bandwidth at ~40KB/s; huaweicloud mirror is ~140x faster
ARG SPARK_URL=https://mirrors.huaweicloud.com/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz
ARG MYSQL_CONNECTOR_URL=https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar

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
    if [ ! -f /tmp/downloads/spark-${SPARK_VERSION}.tgz ]; then \
        curl -fSL "${SPARK_URL}" -o /tmp/downloads/spark-${SPARK_VERSION}.tgz; \
    fi \
    && tar -xzf /tmp/downloads/spark-${SPARK_VERSION}.tgz -C /opt/ \
    && mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}

# Add MySQL JDBC driver (Spark needs it for Hive Metastore access)
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ]; then \
        curl -fSL "${MYSQL_CONNECTOR_URL}" -o /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ${SPARK_HOME}/jars/

# Pre-resolve the Spark Connect server package (+ transitive gRPC/protobuf
# deps) into the image's Ivy cache (/root/.ivy2), so the runtime entrypoint's
# --packages flag is an offline cache hit and the container never needs to
# reach Maven at startup. A throwaway local[1] "SELECT 1" triggers resolution
# without requiring HDFS/metastore/YARN. Runs before any Hive/Hadoop config is
# copied in, so it uses an in-memory catalog (no Kerberos/metastore needed).
RUN echo "SELECT 1;" | ${SPARK_HOME}/bin/spark-sql \
        --packages ${SPARK_CONNECT_PACKAGE} \
        --repositories ${MAVEN_MIRROR} \
        --master "local[1]" \
        --conf spark.sql.catalogImplementation=in-memory \
        --conf spark.ui.enabled=false \
    && echo "[build] Spark Connect package resolved into Ivy cache"

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
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
