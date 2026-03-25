#!/bin/bash
# ============================================================
# Beeline Connect Script (Kerberos)
# Connects to Spark Thrift Server with Kerberos authentication
# ============================================================
docker exec -it spark-master /opt/spark/bin/beeline \
    -u "jdbc:hive2://spark-master.hive-net:10000/;principal=spark/spark-master.hive-net@EXAMPLE.COM"
