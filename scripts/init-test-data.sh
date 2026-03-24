#!/bin/bash
# ============================================================
# Initialize Test Data
# Creates a sample database, table, and inserts test records
# Requires the cluster to be fully running
# ============================================================
set -e

BEELINE_CMD="docker exec spark-master beeline -u jdbc:hive2://localhost:10000 -n root --silent=true"

echo "============================================================"
echo " Initializing Test Data"
echo "============================================================"
echo ""

# Wait for Spark Thrift Server to accept connections
echo "[init] Checking Spark Thrift Server connectivity ..."
max_retries=30
retry=0
while ! docker exec spark-master beeline -u "jdbc:hive2://localhost:10000" -n root -e "SELECT 1;" >/dev/null 2>&1; do
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

# Create sample database
echo "[init] Creating database 'sample_db' ..."
$BEELINE_CMD -e "CREATE DATABASE IF NOT EXISTS sample_db;"

# Create sample table
echo "[init] Creating table 'sample_db.employees' ..."
$BEELINE_CMD -e "
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

# Insert sample data
echo "[init] Inserting test records ..."
$BEELINE_CMD -e "
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

# Verify insertion
echo ""
echo "[init] Verifying data ..."
$BEELINE_CMD -e "
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
