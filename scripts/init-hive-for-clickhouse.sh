#!/bin/bash
# ============================================================
# Initialize Hive tables for ClickHouse external table access
# Database: hive_db
# Tables: orders (partitioned by dt), user_profiles
# Format: Parquet (ClickHouse Hive engine compatible)
# ============================================================
set -e

JDBC_URI="jdbc:hive2://spark-thrift.hive-net:10000/;principal=spark/spark-thrift.hive-net@EXAMPLE.COM"
BEE="docker exec spark-thrift beeline -u ${JDBC_URI} --silent=true"

echo "============================================================"
echo " Init Hive Tables for ClickHouse Integration"
echo "============================================================"

# Obtain Kerberos ticket
echo "[init] Obtaining Kerberos ticket ..."
docker exec spark-thrift kinit -kt /etc/security/keytabs/spark.keytab \
    spark/spark-thrift.hive-net@EXAMPLE.COM

# Wait for Spark Thrift Server
echo "[init] Waiting for Spark Thrift Server ..."
max_retries=30; retry=0
while ! docker exec spark-thrift beeline -u "${JDBC_URI}" -e "SELECT 1;" >/dev/null 2>&1; do
    retry=$((retry + 1))
    [ "$retry" -ge "$max_retries" ] && { echo "ERROR: Thrift Server not ready"; exit 1; }
    echo "  attempt ${retry}/${max_retries} ..."; sleep 5
done
echo "[init] Spark Thrift Server ready."

# -------------------------------------------------------
# Create database
# -------------------------------------------------------
echo "[init] Creating database hive_db ..."
$BEE -e "CREATE DATABASE IF NOT EXISTS hive_db COMMENT 'E-commerce data lake for ClickHouse integration';"

# -------------------------------------------------------
# Table 1: user_profiles
# -------------------------------------------------------
echo "[init] Creating table hive_db.user_profiles ..."
$BEE -e "
USE hive_db;
DROP TABLE IF EXISTS user_profiles;
CREATE TABLE user_profiles (
    user_id          INT         COMMENT 'Unique user ID',
    username         STRING,
    gender           STRING      COMMENT 'M / F',
    age              INT,
    city             STRING,
    province         STRING,
    register_date    STRING      COMMENT 'YYYY-MM-DD',
    membership_level STRING      COMMENT 'bronze / silver / gold / platinum',
    total_spent      DOUBLE      COMMENT 'Cumulative GMV (CNY)'
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/hive_db.db/user_profiles'
TBLPROPERTIES ('parquet.compression'='SNAPPY');
"

echo "[init] Inserting user_profiles data ..."
$BEE -e "
USE hive_db;
INSERT INTO user_profiles VALUES
  (1,  'zhang_wei',     'M', 32, 'Beijing',   'Beijing',   '2022-03-10', 'gold',     28650.00),
  (2,  'li_na',         'F', 27, 'Shanghai',  'Shanghai',  '2022-05-18', 'silver',   12300.00),
  (3,  'wang_fang',     'F', 35, 'Guangzhou', 'Guangdong', '2021-11-02', 'platinum', 76500.00),
  (4,  'chen_bo',       'M', 29, 'Shenzhen',  'Guangdong', '2023-01-08', 'bronze',    3200.00),
  (5,  'liu_yang',      'M', 41, 'Chengdu',   'Sichuan',   '2021-07-15', 'gold',     42100.00),
  (6,  'zhao_min',      'F', 24, 'Hangzhou',  'Zhejiang',  '2023-06-20', 'bronze',    1850.00),
  (7,  'sun_jie',       'M', 38, 'Wuhan',     'Hubei',     '2021-09-11', 'silver',   18900.00),
  (8,  'zhou_xin',      'F', 31, 'Nanjing',   'Jiangsu',   '2022-08-03', 'gold',     35600.00),
  (9,  'wu_hao',        'M', 26, 'Xian',      'Shaanxi',   '2023-02-14', 'bronze',    2700.00),
  (10, 'zheng_ling',    'F', 44, 'Chongqing', 'Chongqing', '2020-12-25', 'platinum', 98300.00),
  (11, 'huang_tao',     'M', 33, 'Tianjin',   'Tianjin',   '2022-04-07', 'silver',   21400.00),
  (12, 'xu_mei',        'F', 28, 'Suzhou',    'Jiangsu',   '2022-10-19', 'gold',     31800.00),
  (13, 'zhu_gang',      'M', 36, 'Qingdao',   'Shandong',  '2021-06-30', 'silver',   16500.00),
  (14, 'he_shan',       'F', 22, 'Xiamen',    'Fujian',    '2023-08-11', 'bronze',     980.00),
  (15, 'gao_peng',      'M', 45, 'Zhengzhou', 'Henan',     '2020-09-05', 'platinum', 112000.00);
"

# -------------------------------------------------------
# Table 2: orders (partitioned by dt)
# -------------------------------------------------------
echo "[init] Creating table hive_db.orders ..."
$BEE -e "
USE hive_db;
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id        STRING,
    user_id         INT,
    product_id      INT,
    quantity        INT,
    unit_price      DOUBLE,
    discount_amount DOUBLE,
    total_amount    DOUBLE,
    status          STRING   COMMENT 'pending / shipped / completed / cancelled / refunded',
    payment_method  STRING   COMMENT 'alipay / wechat / creditcard / banktransfer',
    city            STRING,
    province        STRING,
    created_at      STRING
)
PARTITIONED BY (dt STRING COMMENT 'Order date YYYY-MM-DD')
STORED AS PARQUET
LOCATION '/user/hive/warehouse/hive_db.db/orders'
TBLPROPERTIES ('parquet.compression'='SNAPPY');
"

echo "[init] Inserting orders (Jan 2024) ..."
$BEE -e "
USE hive_db;
SET hive.exec.dynamic.partition.mode=nonstrict;
INSERT INTO orders PARTITION (dt='2024-01-01') VALUES ('ORD-20240101-001', 3,  2, 1, 5999.00, 300.00,  5699.00, 'completed',  'alipay',       'Guangzhou', 'Guangdong', '2024-01-01 09:12:33');
INSERT INTO orders PARTITION (dt='2024-01-02') VALUES ('ORD-20240102-001', 8,  5, 2,  199.00,   0.00,   398.00, 'completed',  'wechat',       'Nanjing',   'Jiangsu',   '2024-01-02 14:05:20');
INSERT INTO orders PARTITION (dt='2024-01-03') VALUES
  ('ORD-20240103-001', 1,  1, 1, 12999.00, 1000.00, 11999.00, 'completed',  'creditcard',   'Beijing',   'Beijing',   '2024-01-03 10:30:15'),
  ('ORD-20240103-002', 5,  8, 3,    89.00,    0.00,   267.00, 'completed',  'alipay',       'Chengdu',   'Sichuan',   '2024-01-03 16:48:02');
INSERT INTO orders PARTITION (dt='2024-01-04') VALUES ('ORD-20240104-001', 10, 3, 1,  8999.00,  500.00,  8499.00, 'shipped',    'banktransfer', 'Chongqing', 'Chongqing', '2024-01-04 11:22:44');
INSERT INTO orders PARTITION (dt='2024-01-05') VALUES ('ORD-20240105-001', 2,  6, 2,   349.00,   30.00,   668.00, 'completed',  'wechat',       'Shanghai',  'Shanghai',  '2024-01-05 09:55:31');
INSERT INTO orders PARTITION (dt='2024-01-06') VALUES ('ORD-20240106-001', 7,  4, 1,  3299.00,  200.00,  3099.00, 'completed',  'alipay',       'Wuhan',     'Hubei',     '2024-01-06 13:17:08');
INSERT INTO orders PARTITION (dt='2024-01-07') VALUES ('ORD-20240107-001', 4,  9, 5,    59.00,    0.00,   295.00, 'cancelled',  'wechat',       'Shenzhen',  'Guangdong', '2024-01-07 08:40:55');
INSERT INTO orders PARTITION (dt='2024-01-08') VALUES ('ORD-20240108-001', 12, 7, 2,   599.00,   50.00,  1148.00, 'completed',  'creditcard',   'Suzhou',    'Jiangsu',   '2024-01-08 15:33:27');
INSERT INTO orders PARTITION (dt='2024-01-09') VALUES ('ORD-20240109-001', 15, 2, 1,  5999.00,  600.00,  5399.00, 'completed',  'alipay',       'Zhengzhou', 'Henan',     '2024-01-09 10:05:19');
INSERT INTO orders PARTITION (dt='2024-01-10') VALUES
  ('ORD-20240110-001', 6,  10, 1, 2499.00,  100.00,  2399.00, 'completed',  'wechat',       'Hangzhou',  'Zhejiang',  '2024-01-10 18:22:41'),
  ('ORD-20240110-002', 11,  1, 1,12999.00, 1200.00, 11799.00, 'shipped',    'banktransfer', 'Tianjin',   'Tianjin',   '2024-01-10 19:01:58');
INSERT INTO orders PARTITION (dt='2024-01-12') VALUES ('ORD-20240112-001', 3,  5, 4,   199.00,    0.00,   796.00, 'completed',  'alipay',       'Guangzhou', 'Guangdong', '2024-01-12 11:44:16');
INSERT INTO orders PARTITION (dt='2024-01-15') VALUES ('ORD-20240115-001', 5,  3, 1,  8999.00,  450.00,  8549.00, 'refunded',   'creditcard',   'Chengdu',   'Sichuan',   '2024-01-15 14:29:03');
INSERT INTO orders PARTITION (dt='2024-01-18') VALUES ('ORD-20240118-001', 9,  6, 1,   349.00,    0.00,   349.00, 'completed',  'wechat',       'Xian',      'Shaanxi',   '2024-01-18 09:18:37');
INSERT INTO orders PARTITION (dt='2024-01-20') VALUES ('ORD-20240120-001', 13, 4, 2,  3299.00,  300.00,  6298.00, 'completed',  'alipay',       'Qingdao',   'Shandong',  '2024-01-20 16:55:21');
INSERT INTO orders PARTITION (dt='2024-01-22') VALUES ('ORD-20240122-001', 1,  8,10,    89.00,   50.00,   840.00, 'completed',  'alipay',       'Beijing',   'Beijing',   '2024-01-22 10:12:44');
INSERT INTO orders PARTITION (dt='2024-01-25') VALUES ('ORD-20240125-001', 8,  2, 1,  5999.00,  300.00,  5699.00, 'pending',    'creditcard',   'Nanjing',   'Jiangsu',   '2024-01-25 17:38:09');
INSERT INTO orders PARTITION (dt='2024-01-28') VALUES ('ORD-20240128-001', 14, 7, 1,   599.00,    0.00,   599.00, 'completed',  'wechat',       'Xiamen',    'Fujian',    '2024-01-28 08:50:22');
INSERT INTO orders PARTITION (dt='2024-01-30') VALUES ('ORD-20240130-001', 10, 1, 1, 12999.00, 1500.00, 11499.00, 'completed',  'banktransfer', 'Chongqing', 'Chongqing', '2024-01-30 13:25:47');
"

echo "[init] Inserting orders (Feb 2024) ..."
$BEE -e "
USE hive_db;
SET hive.exec.dynamic.partition.mode=nonstrict;
INSERT INTO orders PARTITION (dt='2024-02-01') VALUES ('ORD-20240201-001', 2,  9, 2,    59.00,    0.00,   118.00, 'completed',  'wechat',       'Shanghai',  'Shanghai',  '2024-02-01 10:00:00');
INSERT INTO orders PARTITION (dt='2024-02-03') VALUES ('ORD-20240203-001', 5,  3, 1,  8999.00,  450.00,  8549.00, 'completed',  'alipay',       'Chengdu',   'Sichuan',   '2024-02-03 14:22:11');
INSERT INTO orders PARTITION (dt='2024-02-04') VALUES ('ORD-20240204-001', 7,  6, 3,   349.00,   30.00,  1017.00, 'shipped',    'creditcard',   'Wuhan',     'Hubei',     '2024-02-04 09:15:38');
INSERT INTO orders PARTITION (dt='2024-02-05') VALUES ('ORD-20240205-001', 12, 1, 1, 12999.00, 1200.00, 11799.00, 'completed',  'banktransfer', 'Suzhou',    'Jiangsu',   '2024-02-05 11:40:27');
INSERT INTO orders PARTITION (dt='2024-02-07') VALUES ('ORD-20240207-001', 3,  5, 5,   199.00,    0.00,   995.00, 'completed',  'wechat',       'Guangzhou', 'Guangdong', '2024-02-07 16:08:53');
INSERT INTO orders PARTITION (dt='2024-02-09') VALUES ('ORD-20240209-001', 1,  4, 1,  3299.00,  200.00,  3099.00, 'completed',  'alipay',       'Beijing',   'Beijing',   '2024-02-09 10:35:14');
INSERT INTO orders PARTITION (dt='2024-02-10') VALUES ('ORD-20240210-001', 15, 2, 2,  5999.00,  600.00, 11398.00, 'completed',  'creditcard',   'Zhengzhou', 'Henan',     '2024-02-10 14:51:06');
INSERT INTO orders PARTITION (dt='2024-02-12') VALUES ('ORD-20240212-001', 6,  8, 3,    89.00,    0.00,   267.00, 'cancelled',  'alipay',       'Hangzhou',  'Zhejiang',  '2024-02-12 08:22:39');
INSERT INTO orders PARTITION (dt='2024-02-14') VALUES ('ORD-20240214-001', 8,  10,1,  2499.00,  100.00,  2399.00, 'completed',  'wechat',       'Nanjing',   'Jiangsu',   '2024-02-14 18:00:05');
INSERT INTO orders PARTITION (dt='2024-02-15') VALUES ('ORD-20240215-001', 11, 7, 2,   599.00,   50.00,  1148.00, 'completed',  'alipay',       'Tianjin',   'Tianjin',   '2024-02-15 12:17:43');
INSERT INTO orders PARTITION (dt='2024-02-18') VALUES ('ORD-20240218-001', 4,  3, 1,  8999.00,    0.00,  8999.00, 'pending',    'banktransfer', 'Shenzhen',  'Guangdong', '2024-02-18 09:45:21');
INSERT INTO orders PARTITION (dt='2024-02-20') VALUES ('ORD-20240220-001', 9,  6, 2,   349.00,   30.00,   668.00, 'completed',  'wechat',       'Xian',      'Shaanxi',   '2024-02-20 15:33:08');
INSERT INTO orders PARTITION (dt='2024-02-22') VALUES ('ORD-20240222-001', 13, 5, 3,   199.00,    0.00,   597.00, 'completed',  'creditcard',   'Qingdao',   'Shandong',  '2024-02-22 11:28:34');
INSERT INTO orders PARTITION (dt='2024-02-25') VALUES ('ORD-20240225-001', 10, 1, 1, 12999.00, 1500.00, 11499.00, 'completed',  'alipay',       'Chongqing', 'Chongqing', '2024-02-25 16:44:17');
INSERT INTO orders PARTITION (dt='2024-02-28') VALUES ('ORD-20240228-001', 2,  4, 1,  3299.00,  200.00,  3099.00, 'refunded',   'wechat',       'Shanghai',  'Shanghai',  '2024-02-28 10:05:59');
"

echo "[init] Inserting orders (Mar 2024) ..."
$BEE -e "
USE hive_db;
SET hive.exec.dynamic.partition.mode=nonstrict;
INSERT INTO orders PARTITION (dt='2024-03-01') VALUES ('ORD-20240301-001', 5,  2, 1,  5999.00,  300.00,  5699.00, 'completed',  'alipay',       'Chengdu',   'Sichuan',   '2024-03-01 09:30:00');
INSERT INTO orders PARTITION (dt='2024-03-03') VALUES ('ORD-20240303-001', 1,  8, 5,    89.00,    0.00,   445.00, 'completed',  'wechat',       'Beijing',   'Beijing',   '2024-03-03 14:18:22');
INSERT INTO orders PARTITION (dt='2024-03-05') VALUES ('ORD-20240305-001', 3,  1, 1, 12999.00, 1000.00, 11999.00, 'shipped',    'creditcard',   'Guangzhou', 'Guangdong', '2024-03-05 11:55:41');
INSERT INTO orders PARTITION (dt='2024-03-08') VALUES ('ORD-20240308-001', 12, 3, 1,  8999.00,  450.00,  8549.00, 'completed',  'banktransfer', 'Suzhou',    'Jiangsu',   '2024-03-08 16:37:09');
INSERT INTO orders PARTITION (dt='2024-03-10') VALUES ('ORD-20240310-001', 7,  9, 8,    59.00,    0.00,   472.00, 'completed',  'alipay',       'Wuhan',     'Hubei',     '2024-03-10 08:44:55');
INSERT INTO orders PARTITION (dt='2024-03-12') VALUES ('ORD-20240312-001', 15, 4, 2,  3299.00,  300.00,  6298.00, 'completed',  'wechat',       'Zhengzhou', 'Henan',     '2024-03-12 13:22:30');
INSERT INTO orders PARTITION (dt='2024-03-15') VALUES ('ORD-20240315-001', 8,  6, 1,   349.00,    0.00,   349.00, 'completed',  'creditcard',   'Nanjing',   'Jiangsu',   '2024-03-15 10:09:17');
INSERT INTO orders PARTITION (dt='2024-03-18') VALUES ('ORD-20240318-001', 10, 5, 6,   199.00,   50.00,  1144.00, 'completed',  'alipay',       'Chongqing', 'Chongqing', '2024-03-18 15:50:48');
INSERT INTO orders PARTITION (dt='2024-03-20') VALUES ('ORD-20240320-001', 4,  7, 2,   599.00,   50.00,  1148.00, 'cancelled',  'wechat',       'Shenzhen',  'Guangdong', '2024-03-20 17:15:03');
INSERT INTO orders PARTITION (dt='2024-03-22') VALUES ('ORD-20240322-001', 11, 2, 1,  5999.00,  300.00,  5699.00, 'completed',  'banktransfer', 'Tianjin',   'Tianjin',   '2024-03-22 09:58:34');
INSERT INTO orders PARTITION (dt='2024-03-25') VALUES ('ORD-20240325-001', 6,  10,2,  2499.00,  200.00,  4598.00, 'completed',  'alipay',       'Hangzhou',  'Zhejiang',  '2024-03-25 14:31:21');
INSERT INTO orders PARTITION (dt='2024-03-28') VALUES ('ORD-20240328-001', 9,  3, 1,  8999.00,    0.00,  8999.00, 'pending',    'creditcard',   'Xian',      'Shaanxi',   '2024-03-28 11:47:09');
INSERT INTO orders PARTITION (dt='2024-03-30') VALUES ('ORD-20240330-001', 13, 1, 1, 12999.00, 1200.00, 11799.00, 'completed',  'wechat',       'Qingdao',   'Shandong',  '2024-03-30 16:22:55');
INSERT INTO orders PARTITION (dt='2024-03-31') VALUES
  ('ORD-20240331-001', 2,  4, 3,  3299.00,  450.00,  9447.00, 'shipped',    'alipay',       'Shanghai',  'Shanghai',  '2024-03-31 08:33:40'),
  ('ORD-20240331-002', 14, 5, 2,   199.00,    0.00,   398.00, 'completed',  'wechat',       'Xiamen',    'Fujian',    '2024-03-31 19:10:28');
"

# -------------------------------------------------------
# Verify
# -------------------------------------------------------
echo ""
echo "[init] Verifying ..."
$BEE -e "
SHOW DATABASES;
USE hive_db;
SHOW TABLES;
SELECT COUNT(*) AS user_count FROM user_profiles;
SELECT dt, COUNT(*) AS orders, ROUND(SUM(total_amount),2) AS gmv FROM orders GROUP BY dt ORDER BY dt LIMIT 10;
"

echo ""
echo "============================================================"
echo " Hive tables for ClickHouse ready:"
echo "   hive_db.user_profiles  — 15 users"
echo "   hive_db.orders         — 50 orders (Jan-Mar 2024)"
echo "============================================================"
