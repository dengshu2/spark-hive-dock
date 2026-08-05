# syntax=docker/dockerfile:1
# ============================================================
# Hive Metastore Image
# Metadata-only service — no execution engine, no HiveServer2
# Hive 4.1 requires JDK 17 (inherited from hadoop-base:3.5.0)
# Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
ARG HADOOP_VERSION=3.5.0
FROM hadoop-base:${HADOOP_VERSION}

LABEL description="Hive 4.1.0 Metastore on Hadoop 3.5.0 (JDK 17)"

# Build arguments
ARG HIVE_VERSION=4.1.0
# mysql-connector-java was renamed to mysql-connector-j (coordinate
# com.mysql:mysql-connector-j) from 8.1 onward; 8.0.x is EOL/deprecated.
ARG MYSQL_CONNECTOR_VERSION=9.7.0
ARG MYSQL_CONNECTOR_SHA256=0353648eaa1c91e0f4020c959abf756bc866ffd583df22ae6b6f6e0cbd43eb44
# archive.apache.org caps bandwidth at ~40KB/s; huaweicloud mirror is ~140x faster
ARG HIVE_URL=https://mirrors.huaweicloud.com/apache/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz
ARG MYSQL_CONNECTOR_URL=https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar

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
    if ! gzip -t /tmp/downloads/hive-${HIVE_VERSION}.tar.gz 2>/dev/null; then \
        curl -fSL --retry 3 "${HIVE_URL}" -o /tmp/downloads/hive-${HIVE_VERSION}.tar.gz.part \
        && mv /tmp/downloads/hive-${HIVE_VERSION}.tar.gz.part /tmp/downloads/hive-${HIVE_VERSION}.tar.gz; \
    fi \
    && tar -xzf /tmp/downloads/hive-${HIVE_VERSION}.tar.gz -C /opt/ \
    && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME}

# ============================================================
# Resolve dependency conflicts
# ============================================================

# Guava conflict: align Hive's Guava with Hadoop's (Hadoop is authoritative on
# the classpath for HDFS access). Removes any Hive-shipped guava and copies in
# Hadoop's, avoiding NoSuchMethodError across the Hive↔Hadoop boundary.
RUN rm -f ${HIVE_HOME}/lib/guava-*.jar \
    && cp ${HADOOP_HOME}/share/hadoop/common/lib/guava-*.jar ${HIVE_HOME}/lib/

# SLF4J conflict: remove Hive's log4j→slf4j binding so only one binding is on the
# classpath. Glob covers both slf4j 1.x (log4j-slf4j-impl) and slf4j 2.x
# (log4j-slf4j2-impl) artifact names.
RUN rm -f ${HIVE_HOME}/lib/log4j-slf4j-impl-*.jar ${HIVE_HOME}/lib/log4j-slf4j2-impl-*.jar

# Add the MySQL JDBC driver used by the metastore's JDO backend.
RUN --mount=type=cache,target=/tmp/downloads \
    if ! echo "${MYSQL_CONNECTOR_SHA256}  /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar" | sha256sum -c - >/dev/null 2>&1; then \
        curl -fSL --retry 3 "${MYSQL_CONNECTOR_URL}" -o /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar.part \
        && echo "${MYSQL_CONNECTOR_SHA256}  /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar.part" | sha256sum -c - \
        && mv /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar.part /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar; \
    fi \
    && cp /tmp/downloads/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar ${HIVE_HOME}/lib/

# Create Hive directories
RUN mkdir -p /user/hive/warehouse /tmp/hive

# Copy configuration
COPY hive-site.xml ${HIVE_CONF_DIR}/hive-site.xml

# Copy entrypoint
COPY entrypoint-metastore.sh /entrypoint-metastore.sh
RUN chmod +x /entrypoint-metastore.sh

ENTRYPOINT ["/entrypoint-metastore.sh"]
