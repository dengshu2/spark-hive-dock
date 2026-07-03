#!/bin/bash
# ============================================================
# Initialize Test Data (Kerberized)
# Creates a sample database, table, and inserts test records.
#
# Requires the cluster to be fully running with Kerberos enabled.
# See scripts/lib.sh for how the cluster is reached.
# ============================================================
set -e
source "$(dirname "$0")/lib.sh"

echo "============================================================"
echo " Initializing Test Data (Kerberos)"
echo "============================================================"
echo ""

spark_kinit
wait_for_metastore
echo ""

# Create database + table, insert data, and verify — all in a
# single spark-sql session to avoid repeated driver/JVM cold starts.
echo "[init] Creating sample_db.employees and inserting records ..."
spark_sql -e "
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
