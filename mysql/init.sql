-- ============================================================
-- Hive Metastore MySQL Initialization
--
-- Note: The database, user, and privileges are automatically
-- created by MySQL's official Docker image via MYSQL_DATABASE,
-- MYSQL_USER, and MYSQL_PASSWORD environment variables.
--
-- This script only ensures the correct character set.
-- ============================================================

ALTER DATABASE hive_metastore
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
