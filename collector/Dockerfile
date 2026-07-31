ARG SPARK_IMAGE=spark-hive-custom:4.1.2
FROM ${SPARK_IMAGE}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip \
    && pip3 install --no-cache-dir zstandard==0.25.0 \
    && rm -rf /var/lib/apt/lists/ /root/.cache

COPY scripts/spark-eventlog-collector.py /opt/spark-eventlog-collector/collector.py
COPY collector/entrypoint.sh /entrypoint-collector.sh

RUN chmod 755 /entrypoint-collector.sh \
    /opt/spark-eventlog-collector/collector.py

ENTRYPOINT ["/entrypoint-collector.sh"]
