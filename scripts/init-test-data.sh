#!/bin/bash
# ============================================================
# Initialize Test Data (Kerberized)
# Creates a sample database, table, and inserts test records.
#
# Runs via spark-sql in local mode (--master local[*]): the driver
# talks directly to the Hive Metastore over Kerberos SASL and writes
# to HDFS with its TGT — no YARN app and no Spark Connect client needed.
# Requires the cluster to be fully running with Kerberos enabled.
# ============================================================
set -e

CONTAINER=spark-connect
PRINCIPAL="spark/spark-connect.hive-net@EXAMPLE.COM"

echo "============================================================"
echo " Initializing Test Data (Kerberos)"
echo "============================================================"
echo ""

# Step 0: Obtain Kerberos ticket inside the container
echo "[init] Obtaining Kerberos ticket ..."
docker exec ${CONTAINER} kinit -kt /etc/security/keytabs/spark.keytab ${PRINCIPAL}

# Step 1: Wait for the Hive Metastore to be reachable
echo "[init] Waiting for Hive Metastore (9083) ..."
max_retries=30
retry=0
while ! docker exec ${CONTAINER} nc -z hive-metastore 9083 2>/dev/null; do
    retry=$((retry + 1))
    if [ "$retry" -ge "$max_retries" ]; then
        echo "[init] ERROR: Hive Metastore not reachable after ${max_retries} attempts"
        exit 1
    fi
    echo "[init]   attempt ${retry}/${max_retries} ..."
    sleep 5
done
echo "[init] Hive Metastore is reachable"
echo ""

# Step 2: Create database + table, insert data, and verify — all in a
# single spark-sql session to avoid repeated driver/JVM cold starts.
echo "[init] Creating sample_db.employees and inserting records ..."
docker exec ${CONTAINER} /opt/spark/bin/spark-sql --master 'local[*]' -e "
CREATE DATABASE IF NOT EXISTS sample_db;
USE sample_db;
CREATE TABLE IF NOT EXISTS employees (
    id        INT,
    name      STRING,
    dept      STRING,
    salary    DOUBLE,
    hire_date STRING
)
STORED AS ORC;
INSERT INTO employees VALUES
    (1, 'Takeshi Yamamoto',   'Engineering',  92500.00, '2021-03-15'),
    (2, 'Priya Sharma',       'Data Science', 88000.00, '2020-07-22'),
    (3, 'Marcus Weber',       'Engineering',  95800.00, '2019-11-08'),
    (4, 'Liu Mei',            'Analytics',    76300.00, '2022-01-14'),
    (5, 'Sofia Rodriguez',    'Engineering',  101200.00,'2018-06-30'),
    (6, 'Andrei Volkov',      'Data Science', 83700.00, '2021-09-02'),
    (7, 'Fatima Al-Hassan',   'Analytics',    79500.00, '2020-04-18'),
    (8, 'Chen Wei',           'Engineering',  97100.00, '2019-02-25');
SELECT COUNT(*) AS total_employees FROM employees;
SELECT dept, COUNT(*) AS headcount, ROUND(AVG(salary), 2) AS avg_salary FROM employees GROUP BY dept ORDER BY avg_salary DESC;
"

echo ""
echo "============================================================"
echo " Test data initialized successfully"
echo " Database: sample_db"
echo " Table:    employees (8 records)"
echo "============================================================"
