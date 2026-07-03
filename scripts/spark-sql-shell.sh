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
docker exec -it spark-connect bash -lc "\
    kinit -kt /etc/security/keytabs/spark.keytab spark/spark-connect.hive-net@EXAMPLE.COM && \
    /opt/spark/bin/spark-sql --master 'local[*]'"
