# syntax=docker/dockerfile:1
# ============================================================
# Hadoop Base Image
# Based on Eclipse Temurin JDK 8 (production-grade OpenJDK)
# Uses BuildKit cache for download layer (avoids re-download)
# ============================================================
FROM eclipse-temurin:8-jdk AS hadoop-base

LABEL maintainer="hive-docker"
LABEL description="Hadoop 3.3.6 base image with OpenJDK 8"

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


# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
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


# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
