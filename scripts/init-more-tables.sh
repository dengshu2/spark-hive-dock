#!/bin/bash
# 新增 Hive 测试表：products / user_behavior / dim_category
set -e

SPARK_SUBMIT="/opt/spark/bin/spark-submit"
SPARK_SQL="/opt/spark/bin/spark-sql"

echo "======================================================"
echo " Creating additional Hive test tables"
echo "======================================================"

$SPARK_SQL --master yarn --conf spark.sql.warehouse.dir=hdfs://namenode.hive-net:9000/user/hive/warehouse <<'EOF'

-- ============================================================
-- 1. products（商品表，非分区，~200行）
-- ============================================================
CREATE DATABASE IF NOT EXISTS hive_db;

DROP TABLE IF EXISTS hive_db.products;
CREATE TABLE hive_db.products (
    product_id      INT         COMMENT 'SKU ID',
    name            STRING      COMMENT '商品名称',
    category_id     INT         COMMENT '分类ID',
    brand           STRING      COMMENT '品牌',
    price           DOUBLE      COMMENT '定价',
    cost            DOUBLE      COMMENT '成本价',
    stock           INT         COMMENT '库存量',
    rating          DOUBLE      COMMENT '评分 0-5',
    review_count    INT         COMMENT '评价数',
    is_active       BOOLEAN     COMMENT '是否上架',
    created_date    STRING      COMMENT '上架日期'
)
STORED AS PARQUET
TBLPROPERTIES ('parquet.compression'='SNAPPY');

INSERT INTO hive_db.products VALUES
(1001, '华为 Mate 60 Pro', 1, '华为', 6999.00, 5200.00, 850, 4.8, 12580, true, '2023-09-01'),
(1002, '苹果 iPhone 15 Pro', 1, '苹果', 8999.00, 6100.00, 640, 4.7, 9870, true, '2023-09-22'),
(1003, '小米 14', 1, '小米', 3999.00, 2800.00, 1200, 4.6, 7620, true, '2023-10-26'),
(1004, 'OPPO Find X7', 1, 'OPPO', 4499.00, 3100.00, 560, 4.5, 4230, true, '2023-12-12'),
(1005, 'vivo X100 Pro', 1, 'vivo', 4999.00, 3400.00, 480, 4.6, 3890, true, '2023-11-13'),
(1006, '三星 Galaxy S24', 1, '三星', 5999.00, 4100.00, 320, 4.4, 2760, true, '2024-01-17'),
(1007, '一加 12', 1, '一加', 3999.00, 2700.00, 290, 4.5, 2180, true, '2024-01-23'),
(1008, '荣耀 Magic6 Pro', 1, '荣耀', 4999.00, 3300.00, 410, 4.5, 3150, true, '2024-01-10'),
(1009, '红米 Note 13 Pro', 1, '小米', 1799.00, 1100.00, 3200, 4.4, 15600, true, '2023-09-21'),
(1010, '真我 GT5 Pro', 1, '真我', 2999.00, 2000.00, 680, 4.3, 2890, true, '2023-12-07'),
(2001, '联想小新 Pro 16', 2, '联想', 5999.00, 4200.00, 420, 4.5, 6780, true, '2023-08-15'),
(2002, '苹果 MacBook Air M2', 2, '苹果', 8999.00, 6500.00, 280, 4.9, 8920, true, '2022-06-10'),
(2003, '华为 MateBook X Pro', 2, '华为', 9999.00, 7100.00, 160, 4.7, 4560, true, '2023-09-28'),
(2004, '戴尔 XPS 15', 2, '戴尔', 10999.00, 7800.00, 120, 4.6, 3240, true, '2023-10-05'),
(2005, '惠普 ENVY 16', 2, '惠普', 7999.00, 5600.00, 200, 4.4, 2780, true, '2023-11-20'),
(2006, '华硕 ROG 幻 16', 2, '华硕', 11999.00, 8500.00, 150, 4.7, 3560, true, '2023-09-10'),
(2007, '雷蛇 灵刃 16', 2, '雷蛇', 14999.00, 10800.00, 80, 4.6, 1890, true, '2023-10-18'),
(2008, '微软 Surface Pro 9', 2, '微软', 9999.00, 7200.00, 110, 4.5, 2340, true, '2022-10-12'),
(3001, '索尼 WH-1000XM5 耳机', 3, '索尼', 2299.00, 1400.00, 780, 4.8, 18920, true, '2022-05-20'),
(3002, '苹果 AirPods Pro 2', 3, '苹果', 1799.00, 1100.00, 1200, 4.7, 24680, true, '2022-09-07'),
(3003, '华为 FreeBuds Pro 3', 3, '华为', 999.00, 580.00, 2100, 4.6, 12340, true, '2023-09-25'),
(3004, '小米 Buds 4 Pro', 3, '小米', 599.00, 320.00, 3400, 4.4, 18760, true, '2022-10-11'),
(3005, 'Bose QuietComfort 45', 3, 'Bose', 2699.00, 1800.00, 320, 4.7, 8920, true, '2021-09-23'),
(3006, 'JBL Charge 5 音箱', 3, 'JBL', 899.00, 520.00, 980, 4.5, 14230, true, '2021-07-15'),
(3007, '森海塞尔 Momentum 4', 3, '森海塞尔', 2499.00, 1650.00, 210, 4.8, 5670, true, '2022-09-29'),
(4001, '戴森 V15 吸尘器', 4, '戴森', 4490.00, 2900.00, 560, 4.8, 32480, true, '2021-03-25'),
(4002, '追觅 X30 扫地机器人', 4, '追觅', 3999.00, 2600.00, 420, 4.6, 18920, true, '2023-08-03'),
(4003, '石头 G20 扫地机器人', 4, '石头科技', 3499.00, 2200.00, 380, 4.5, 15670, true, '2023-10-12'),
(4004, '美的 空气净化器 KJ600', 4, '美的', 1999.00, 1200.00, 890, 4.4, 9870, true, '2023-05-15'),
(4005, '飞利浦 空气净化器', 4, '飞利浦', 2499.00, 1600.00, 340, 4.5, 7650, true, '2022-11-08'),
(4006, '海尔 冰箱 BCD-603', 4, '海尔', 5999.00, 3800.00, 180, 4.6, 5430, true, '2023-04-20'),
(4007, '格力 空调 3匹', 4, '格力', 4999.00, 3100.00, 260, 4.7, 8920, true, '2023-02-28'),
(5001, '耐克 Air Max 270', 5, '耐克', 899.00, 450.00, 1800, 4.5, 24680, true, '2023-01-15'),
(5002, '阿迪达斯 Ultra Boost 23', 5, '阿迪达斯', 1099.00, 560.00, 1400, 4.6, 19870, true, '2023-02-20'),
(5003, '李宁 驭帅 TD', 5, '李宁', 699.00, 320.00, 2200, 4.4, 32560, true, '2023-09-01'),
(5004, '安踏 KT9 篮球鞋', 5, '安踏', 599.00, 280.00, 2800, 4.3, 28940, true, '2023-10-10'),
(5005, 'New Balance 574', 5, 'New Balance', 599.00, 290.00, 1900, 4.5, 18760, true, '2023-03-15');

-- ============================================================
-- 2. dim_category（商品分类维表，非分区，小表）
-- ============================================================
DROP TABLE IF EXISTS hive_db.dim_category;
CREATE TABLE hive_db.dim_category (
    category_id     INT     COMMENT '分类ID',
    name            STRING  COMMENT '分类名称',
    parent_id       INT     COMMENT '父分类ID（0为顶级）',
    level           INT     COMMENT '层级',
    sort_order      INT     COMMENT '排序'
)
STORED AS PARQUET
TBLPROPERTIES ('parquet.compression'='SNAPPY');

INSERT INTO hive_db.dim_category VALUES
(1, '手机', 0, 1, 1),
(2, '笔记本电脑', 0, 1, 2),
(3, '音频设备', 0, 1, 3),
(4, '家用电器', 0, 1, 4),
(5, '运动鞋', 0, 1, 5);

-- ============================================================
-- 3. user_behavior（用户行为日志，按 dt 分区，较大数据量）
-- ============================================================
DROP TABLE IF EXISTS hive_db.user_behavior;
CREATE TABLE hive_db.user_behavior (
    event_id        STRING  COMMENT '事件ID',
    user_id         INT     COMMENT '用户ID',
    product_id      INT     COMMENT '商品ID',
    event_type      STRING  COMMENT 'view/cart/wishlist/purchase',
    session_id      STRING  COMMENT '会话ID',
    duration_sec    INT     COMMENT '停留秒数',
    source          STRING  COMMENT '来源：search/recommend/ad/direct',
    device          STRING  COMMENT '设备：mobile/pc/tablet',
    ts              STRING  COMMENT '事件时间'
)
PARTITIONED BY (dt STRING COMMENT '日期 YYYY-MM-DD')
STORED AS PARQUET
TBLPROPERTIES ('parquet.compression'='SNAPPY');

-- 2024-01-15 行为数据
INSERT INTO hive_db.user_behavior PARTITION (dt='2024-01-15') VALUES
('ev_0001',1,1001,'view','s001',45,'search','mobile','2024-01-15 08:12:30'),
('ev_0002',1,1001,'cart','s001',12,'search','mobile','2024-01-15 08:13:10'),
('ev_0003',2,2001,'view','s002',120,'recommend','pc','2024-01-15 09:05:22'),
('ev_0004',3,3001,'view','s003',89,'search','mobile','2024-01-15 09:30:15'),
('ev_0005',3,3001,'wishlist','s003',5,'search','mobile','2024-01-15 09:31:00'),
('ev_0006',4,1002,'view','s004',200,'ad','mobile','2024-01-15 10:00:45'),
('ev_0007',4,1002,'purchase','s004',30,'ad','mobile','2024-01-15 10:04:00'),
('ev_0008',5,4001,'view','s005',340,'recommend','pc','2024-01-15 10:30:00'),
('ev_0009',6,5001,'view','s006',55,'search','mobile','2024-01-15 11:00:10'),
('ev_0010',6,5002,'view','s006',40,'search','mobile','2024-01-15 11:01:00'),
('ev_0011',6,5001,'cart','s006',8,'search','mobile','2024-01-15 11:01:50'),
('ev_0012',7,1003,'view','s007',180,'direct','mobile','2024-01-15 12:05:00'),
('ev_0013',8,2002,'view','s008',250,'recommend','pc','2024-01-15 13:20:00'),
('ev_0014',9,3002,'view','s009',95,'ad','mobile','2024-01-15 14:00:00'),
('ev_0015',10,4002,'view','s010',400,'recommend','pc','2024-01-15 15:30:00');

-- 2024-01-16 行为数据
INSERT INTO hive_db.user_behavior PARTITION (dt='2024-01-16') VALUES
('ev_0016',1,1001,'purchase','s011',20,'search','mobile','2024-01-16 08:30:00'),
('ev_0017',2,2001,'cart','s012',15,'recommend','pc','2024-01-16 09:10:00'),
('ev_0018',3,3001,'purchase','s013',25,'search','mobile','2024-01-16 09:45:00'),
('ev_0019',4,1005,'view','s014',130,'ad','mobile','2024-01-16 10:20:00'),
('ev_0020',5,4001,'cart','s015',10,'recommend','pc','2024-01-16 11:00:00'),
('ev_0021',11,1009,'view','s016',60,'search','mobile','2024-01-16 11:30:00'),
('ev_0022',12,2003,'view','s017',200,'direct','pc','2024-01-16 12:00:00'),
('ev_0023',13,5003,'view','s018',75,'search','mobile','2024-01-16 12:30:00'),
('ev_0024',13,5003,'purchase','s018',20,'search','mobile','2024-01-16 12:31:00'),
('ev_0025',14,3004,'view','s019',50,'recommend','tablet','2024-01-16 13:00:00'),
('ev_0026',15,1006,'view','s020',220,'ad','pc','2024-01-16 14:00:00'),
('ev_0027',15,1006,'cart','s020',12,'ad','pc','2024-01-16 14:04:00'),
('ev_0028',16,4003,'view','s021',300,'recommend','mobile','2024-01-16 15:00:00'),
('ev_0029',17,2004,'view','s022',180,'search','pc','2024-01-16 16:00:00'),
('ev_0030',18,5001,'purchase','s023',25,'ad','mobile','2024-01-16 17:00:00');

-- 2024-01-17 行为数据
INSERT INTO hive_db.user_behavior PARTITION (dt='2024-01-17') VALUES
('ev_0031',1,3001,'view','s024',100,'recommend','mobile','2024-01-17 08:00:00'),
('ev_0032',2,2001,'purchase','s025',40,'recommend','pc','2024-01-17 09:00:00'),
('ev_0033',19,1004,'view','s026',160,'search','mobile','2024-01-17 10:00:00'),
('ev_0034',20,4004,'view','s027',210,'direct','pc','2024-01-17 10:30:00'),
('ev_0035',20,4004,'cart','s027',8,'direct','pc','2024-01-17 10:32:00'),
('ev_0036',21,3005,'view','s028',280,'recommend','pc','2024-01-17 11:00:00'),
('ev_0037',22,5004,'view','s029',65,'search','mobile','2024-01-17 11:30:00'),
('ev_0038',22,5004,'purchase','s029',18,'search','mobile','2024-01-17 11:32:00'),
('ev_0039',23,1008,'view','s030',190,'ad','mobile','2024-01-17 12:00:00'),
('ev_0040',24,2005,'view','s031',240,'direct','pc','2024-01-17 13:00:00'),
('ev_0041',25,3006,'view','s032',70,'search','mobile','2024-01-17 14:00:00'),
('ev_0042',26,4005,'view','s033',330,'recommend','pc','2024-01-17 15:00:00'),
('ev_0043',27,1010,'view','s034',80,'ad','mobile','2024-01-17 16:00:00'),
('ev_0044',28,5005,'view','s035',90,'search','mobile','2024-01-17 16:30:00'),
('ev_0045',29,2006,'view','s036',200,'direct','pc','2024-01-17 17:00:00');

-- 2024-02-01 行为数据
INSERT INTO hive_db.user_behavior PARTITION (dt='2024-02-01') VALUES
('ev_0046',1,1001,'view','s037',30,'search','mobile','2024-02-01 09:00:00'),
('ev_0047',5,4001,'purchase','s038',35,'recommend','pc','2024-02-01 09:30:00'),
('ev_0048',10,4002,'purchase','s039',28,'recommend','pc','2024-02-01 10:00:00'),
('ev_0049',15,1006,'purchase','s040',22,'ad','pc','2024-02-01 10:30:00'),
('ev_0050',30,3007,'view','s041',120,'search','mobile','2024-02-01 11:00:00'),
('ev_0051',30,3007,'cart','s041',10,'search','mobile','2024-02-01 11:02:00'),
('ev_0052',30,3007,'purchase','s041',25,'search','mobile','2024-02-01 11:05:00');

-- 2024-03-01 行为数据（最新月份）
INSERT INTO hive_db.user_behavior PARTITION (dt='2024-03-01') VALUES
('ev_0053',1,2002,'view','s042',400,'recommend','pc','2024-03-01 10:00:00'),
('ev_0054',1,2002,'cart','s042',15,'recommend','pc','2024-03-01 10:07:00'),
('ev_0055',2,3001,'view','s043',90,'search','mobile','2024-03-01 11:00:00'),
('ev_0056',3,1002,'view','s044',250,'ad','mobile','2024-03-01 12:00:00'),
('ev_0057',3,1002,'purchase','s044',30,'ad','mobile','2024-03-01 12:05:00'),
('ev_0058',7,4006,'view','s045',600,'direct','pc','2024-03-01 13:00:00'),
('ev_0059',8,4007,'view','s046',500,'recommend','pc','2024-03-01 14:00:00'),
('ev_0060',9,5002,'purchase','s047',20,'search','mobile','2024-03-01 15:00:00');

-- 验证
SELECT 'products' AS tbl, count(*) AS cnt FROM hive_db.products
UNION ALL SELECT 'dim_category', count(*) FROM hive_db.dim_category
UNION ALL SELECT 'user_behavior', count(*) FROM hive_db.user_behavior;

SHOW PARTITIONS hive_db.user_behavior;

EOF

echo "======================================================"
echo " Done"
echo "======================================================"
