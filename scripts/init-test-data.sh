#!/bin/bash
# ============================================================
# Initialize Test Data (Kerberized)
# Creates a sample database, table, and inserts test records
# Requires the cluster to be fully running with Kerberos enabled
# ============================================================
set -e

# Kerberos-enabled JDBC URI
JDBC_URI="jdbc:hive2://spark-thrift.hive-net:10000/;principal=spark/spark-thrift.hive-net@EXAMPLE.COM"
BEELINE_CMD="docker exec spark-thrift beeline -u '${JDBC_URI}' --silent=true --outputformat=table2"

echo "============================================================"
echo " Initializing Test Data (Kerberos)"
echo "============================================================"
echo ""

# Step 0: Obtain Kerberos ticket inside the container
echo "[init] Obtaining Kerberos ticket ..."
docker exec spark-thrift kinit -kt /etc/security/keytabs/spark.keytab spark/spark-thrift.hive-net@EXAMPLE.COM

# Step 1: Check Spark Thrift Server connectivity
echo "[init] Checking Spark Thrift Server connectivity ..."
max_retries=30
retry=0
while ! docker exec spark-thrift beeline -u "${JDBC_URI}" -e "SELECT 1;" >/dev/null 2>&1; do
    retry=$((retry + 1))
    if [ "$retry" -ge "$max_retries" ]; then
        echo "[init] ERROR: Spark Thrift Server not ready after ${max_retries} attempts"
        exit 1
    fi
    echo "[init]   attempt ${retry}/${max_retries} ..."
    sleep 5
done
echo "[init] Spark Thrift Server is ready"
echo ""

# Step 2: Create sample database
echo "[init] Creating database 'sample_db' ..."
docker exec spark-thrift beeline -u "${JDBC_URI}" --silent=true -e "CREATE DATABASE IF NOT EXISTS sample_db;"

# Step 3: Create sample table
echo "[init] Creating table 'sample_db.employees' ..."
docker exec spark-thrift beeline -u "${JDBC_URI}" --silent=true -e "
USE sample_db;
CREATE TABLE IF NOT EXISTS employees (
    id        INT,
    name      STRING,
    dept      STRING,
    salary    DOUBLE,
    hire_date STRING
)
STORED AS ORC;
"

# Step 4: Insert sample data
echo "[init] Inserting test records ..."
docker exec spark-thrift beeline -u "${JDBC_URI}" --silent=true -e "
USE sample_db;
INSERT INTO employees VALUES
    (1, 'Takeshi Yamamoto',   'Engineering',  92500.00, '2021-03-15'),
    (2, 'Priya Sharma',       'Data Science', 88000.00, '2020-07-22'),
    (3, 'Marcus Weber',       'Engineering',  95800.00, '2019-11-08'),
    (4, 'Liu Mei',            'Analytics',    76300.00, '2022-01-14'),
    (5, 'Sofia Rodriguez',    'Engineering',  101200.00,'2018-06-30'),
    (6, 'Andrei Volkov',      'Data Science', 83700.00, '2021-09-02'),
    (7, 'Fatima Al-Hassan',   'Analytics',    79500.00, '2020-04-18'),
    (8, 'Chen Wei',           'Engineering',  97100.00, '2019-02-25');
"

# Step 5: Verify insertion
echo ""
echo "[init] Verifying data ..."
docker exec spark-thrift beeline -u "${JDBC_URI}" --silent=true -e "
USE sample_db;
SELECT COUNT(*) AS total_employees FROM employees;
SELECT dept, COUNT(*) AS headcount, ROUND(AVG(salary), 2) AS avg_salary FROM employees GROUP BY dept ORDER BY avg_salary DESC;
"

echo ""
echo "============================================================"
echo " Test data initialized successfully"
echo " Database: sample_db"
echo " Table:    employees (8 records)"
echo "============================================================"
