#!/bin/bash
# ============================================================
# Beeline Connect Script (Kerberos + YARN)
# Connects to Spark Thrift Server with Kerberos authentication
# ============================================================
docker exec -it spark-thrift /opt/spark/bin/beeline \
    -u "jdbc:hive2://spark-thrift.hive-net:10000/;principal=spark/spark-thrift.hive-net@EXAMPLE.COM"
