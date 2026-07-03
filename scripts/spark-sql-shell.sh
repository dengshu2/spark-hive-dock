#!/bin/bash
# ============================================================
# Spark SQL Shell (Kerberos)
# Opens an interactive spark-sql session inside the spark-connect
# container, in local mode — direct Hive Metastore access, no YARN
# app spin-up. Replaces the old beeline/Thrift JDBC shell.
#
# For a programmatic Spark Connect client instead:
#   pip install "pyspark[connect]==4.1.2"
#   from pyspark.sql import SparkSession
#   spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
#   spark.sql("SHOW DATABASES").show()
# ============================================================
set -e
source "$(dirname "$0")/lib.sh"

spark_kinit
# Interactive session needs a TTY, so this one doesn't go through spark_sql.
docker exec -it "${CONTAINER}" /opt/spark/bin/spark-sql --master 'local[*]'
