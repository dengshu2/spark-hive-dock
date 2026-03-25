# syntax=docker/dockerfile:1
# ============================================================
# Spark 3.5.3 Image
# - JDK 11 (Spark 3.5 requirement)
# - Hadoop + YARN client configs for HDFS/YARN access
# - Hive Metastore integration via Spark SQL
# - Kerberos client for authenticated access
# - Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
FROM eclipse-temurin:11-jre-jammy

LABEL description="Spark 3.5.3 Thrift Server with YARN + Kerberos"

ARG SPARK_VERSION=3.5.3
ARG MYSQL_CONNECTOR_VERSION=8.0.28
ARG SPARK_URL=https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz
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

# Add MySQL JDBC driver (Thrift Server needs it for Hive Metastore)
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ]; then \
        curl -fSL "${MYSQL_CONNECTOR_URL}" -o /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ${SPARK_HOME}/jars/

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
