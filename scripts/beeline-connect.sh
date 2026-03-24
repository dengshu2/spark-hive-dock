#!/bin/bash
# ============================================================
# Connect to Spark Thrift Server via Beeline
# ============================================================
echo "Connecting to Spark Thrift Server ..."
echo "  JDBC URL: jdbc:hive2://localhost:10000"
echo ""
docker exec -it spark-master beeline -u "jdbc:hive2://localhost:10000" -n root
