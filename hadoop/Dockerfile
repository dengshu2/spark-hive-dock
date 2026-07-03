# syntax=docker/dockerfile:1
# ============================================================
# Hadoop Base Image
# Based on Eclipse Temurin JDK 17 (Hadoop 3.5+ requires JDK 17 server-side)
# Supports: NameNode + ResourceManager, DataNode + NodeManager
# Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
FROM eclipse-temurin:17-jdk AS hadoop-base

LABEL maintainer="hive-docker"
LABEL description="Hadoop 3.5.0 base image with YARN + Kerberos (JDK 17)"

# Build arguments
ARG HADOOP_VERSION=3.5.0
# huaweicloud mirror: stable (keeps archived releases, unlike dlcdn which only
# serves the current release of each line) and ~140x faster than archive.apache.org.
ARG HADOOP_URL=https://mirrors.huaweicloud.com/apache/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz

# Environment variables
ENV HADOOP_VERSION=${HADOOP_VERSION}
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV PATH=${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}
ENV JAVA_HOME=/opt/java/openjdk
ENV HDFS_NAMENODE_USER=root
ENV HDFS_DATANODE_USER=root
ENV HDFS_SECONDARYNAMENODE_USER=root
ENV YARN_RESOURCEMANAGER_USER=root
ENV YARN_NODEMANAGER_USER=root
# JDK 17 module access: Hadoop daemons reflect into java.base internals (Kerberos
# UGI, NIO, security). Hadoop 3.5's hadoop-env appends to HADOOP_OPTS, so this is
# a safe base set. Without these the daemons throw InaccessibleObjectException on
# JDK 17.
ENV HADOOP_OPTS="--add-opens java.base/java.lang=ALL-UNNAMED \
--add-opens java.base/java.lang.reflect=ALL-UNNAMED \
--add-opens java.base/java.io=ALL-UNNAMED \
--add-opens java.base/java.net=ALL-UNNAMED \
--add-opens java.base/java.nio=ALL-UNNAMED \
--add-opens java.base/java.util=ALL-UNNAMED \
--add-opens java.base/java.util.concurrent=ALL-UNNAMED \
--add-opens java.base/java.util.zip=ALL-UNNAMED \
--add-opens java.base/sun.nio.ch=ALL-UNNAMED \
--add-opens java.base/sun.security.action=ALL-UNNAMED \
--add-opens java.base/sun.security.util=ALL-UNNAMED \
--add-exports java.base/sun.net.dns=ALL-UNNAMED \
--add-exports java.base/sun.net.util=ALL-UNNAMED"
# NOTE: HDFS_DATANODE_SECURE_USER is intentionally NOT set.
# With dfs.data.transfer.protection=authentication (SASL), the DataNode
# uses unprivileged ports and does not need the secure user mechanism.
# NOTE: Spark External Shuffle Service (yarn.nodemanager.aux-services=spark_shuffle)
# is intentionally not configured. Dynamic allocation on the Spark Connect
# Server uses driver-side shuffle tracking instead
# (spark.dynamicAllocation.shuffleTracking.enabled=true in spark-defaults.conf),
# so the NodeManager needs no spark_shuffle aux-service.

# Install dependencies (includes Kerberos client)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    krb5-user \
    netcat-openbsd \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Download and install Hadoop (cached across rebuilds).
# gzip -t treats a truncated cached tarball as missing, and the .part + mv
# dance keeps an interrupted curl from poisoning the cache for later builds.
RUN --mount=type=cache,target=/tmp/downloads \
    if ! gzip -t /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz 2>/dev/null; then \
        curl -fSL --retry 3 "${HADOOP_URL}" -o /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz.part \
        && mv /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz.part /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz; \
    fi \
    && tar -xzf /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz -C /opt/ \
    && mv /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME} \
    && rm -rf ${HADOOP_HOME}/share/doc

# Create data directories
RUN mkdir -p /data/namenode /data/datanode

# Copy configuration files
COPY core-site.xml ${HADOOP_CONF_DIR}/core-site.xml
COPY hdfs-site.xml ${HADOOP_CONF_DIR}/hdfs-site.xml
COPY yarn-site.xml ${HADOOP_CONF_DIR}/yarn-site.xml
COPY mapred-site.xml ${HADOOP_CONF_DIR}/mapred-site.xml

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
