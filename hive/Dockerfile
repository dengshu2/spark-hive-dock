# syntax=docker/dockerfile:1
# ============================================================
# Hive Metastore Image
# Metadata-only service — no execution engine, no HiveServer2
# Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
ARG HADOOP_VERSION=3.3.6
FROM hadoop-base:${HADOOP_VERSION}

LABEL description="Hive 3.1.3 Metastore on Hadoop 3.3.6"

# Build arguments
ARG HIVE_VERSION=3.1.3
ARG MYSQL_CONNECTOR_VERSION=8.0.28
ARG HIVE_URL=https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz
ARG MYSQL_CONNECTOR_URL=https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar

# Environment variables
ENV HIVE_VERSION=${HIVE_VERSION}
ENV HIVE_HOME=/opt/hive
ENV HIVE_CONF_DIR=${HIVE_HOME}/conf
ENV PATH=${HIVE_HOME}/bin:${PATH}

# Install mysql client for health checks + Kerberos client
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-mysql-client \
    krb5-user \
    && rm -rf /var/lib/apt/lists/*

# Download and install Hive (cached across rebuilds)
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/hive-${HIVE_VERSION}.tar.gz ]; then \
        curl -fSL "${HIVE_URL}" -o /tmp/downloads/hive-${HIVE_VERSION}.tar.gz; \
    fi \
    && tar -xzf /tmp/downloads/hive-${HIVE_VERSION}.tar.gz -C /opt/ \
    && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME}

# ============================================================
# Resolve dependency conflicts
# ============================================================

# Guava conflict: Hive ships Guava 19, Hadoop ships 27.0+
RUN rm -f ${HIVE_HOME}/lib/guava-*.jar \
    && cp ${HADOOP_HOME}/share/hadoop/common/lib/guava-*.jar ${HIVE_HOME}/lib/

# SLF4J conflict: remove duplicate binding from Hive
RUN rm -f ${HIVE_HOME}/lib/log4j-slf4j-impl-*.jar

# Add MySQL JDBC driver
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ]; then \
        curl -fSL "${MYSQL_CONNECTOR_URL}" -o /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ${HIVE_HOME}/lib/

# Create Hive directories
RUN mkdir -p /user/hive/warehouse /tmp/hive

# Copy configuration
COPY hive-site.xml ${HIVE_CONF_DIR}/hive-site.xml

# Copy entrypoint
COPY entrypoint-metastore.sh /entrypoint-metastore.sh
RUN chmod +x /entrypoint-metastore.sh

ENTRYPOINT ["/entrypoint-metastore.sh"]
