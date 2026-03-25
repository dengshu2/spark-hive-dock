# syntax=docker/dockerfile:1
# ============================================================
# Hadoop Base Image
# Based on Eclipse Temurin JDK 8 (production-grade OpenJDK)
# Supports: NameNode + ResourceManager, DataNode + NodeManager
# Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
FROM eclipse-temurin:8-jdk AS hadoop-base

LABEL maintainer="hive-docker"
LABEL description="Hadoop 3.3.6 base image with YARN + Kerberos"

# Build arguments
ARG HADOOP_VERSION=3.3.6
ARG HADOOP_URL=https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz

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
# NOTE: HDFS_DATANODE_SECURE_USER is intentionally NOT set.
# With dfs.data.transfer.protection=authentication (SASL), the DataNode
# uses unprivileged ports and does not need the secure user mechanism.
# NOTE: Spark External Shuffle Service (yarn.nodemanager.aux-services=spark_shuffle)
# is intentionally not configured. This cluster uses fixed executor count
# (spark.executor.instances=1) with no dynamic allocation, so the external
# shuffle service is not required.

# Install dependencies (includes Kerberos client)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    krb5-user \
    netcat-openbsd \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Download and install Hadoop (cached across rebuilds)
RUN --mount=type=cache,target=/tmp/downloads \
    if [ ! -f /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz ]; then \
        curl -fSL "${HADOOP_URL}" -o /tmp/downloads/hadoop-${HADOOP_VERSION}.tar.gz; \
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
