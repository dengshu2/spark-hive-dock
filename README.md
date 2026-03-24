# spark-hive-dock

Dockerized Spark SQL cluster with Hive Metastore on Hadoop HDFS. MySQL serves as the Metastore backend. Designed for development and testing — **not for production use**.

## Version Matrix

| Component | Version | JDK |
|-----------|---------|-----|
| Hadoop | 3.3.6 | OpenJDK 8 (Temurin) |
| Hive Metastore | 3.1.3 | OpenJDK 8 (Temurin) |
| Spark | 3.5.3 | OpenJDK 11 (Temurin) |
| MySQL | 8.0 | — |

## Architecture

```
                     ┌──────────────────────────────────┐
                     │     Docker Network: hive-net      │
                     │                                  │
  ┌───────┐          │  ┌──────────┐   ┌──────────┐    │
  │ MySQL │◄─────────┤  │ NameNode │   │ DataNode │    │
  │ :3306 │          │  │  :9870   │   │  :9864   │    │
  └───────┘          │  └────┬─────┘   └─────┬────┘    │
                     │       │               │         │
                     │  ┌────┴───────────────┴────┐    │
                     │  │    Hive Metastore        │    │
                     │  │       :9083              │    │
                     │  └────────────┬─────────────┘    │
                     │               │                  │
  ┌──────────────┐   │  ┌────────────▼─────────────┐   │
  │   Beeline    │──►│  │  Spark Master             │   │
  │  (client)    │   │  │  :7077 (RPC)              │   │
  └──────────────┘   │  │  :10000 (Thrift / JDBC)   │   │
                     │  │  :18080 (Web UI)          │   │
                     │  └────────────┬─────────────┘   │
                     │               │                  │
                     │  ┌────────────▼─────────────┐   │
                     │  │    Spark Worker           │   │
                     │  └──────────────────────────┘   │
                     └──────────────────────────────────┘
```

**Data flow**: Beeline → Spark Thrift Server (JDBC :10000) → Hive Metastore (schema) → HDFS (data storage)

## Quick Start

```bash
# 1. Copy environment template and adjust passwords
cp .env.example .env

# 2. Build and start the cluster
docker compose up -d --build

# 3. Monitor startup (first run takes a few minutes)
docker compose logs -f hive-metastore spark-master

# 4. Connect via Beeline
bash scripts/beeline-connect.sh

# 5. (Optional) Load test data
bash scripts/init-test-data.sh
```

## Web UIs

| Service | URL |
|---------|-----|
| HDFS NameNode | http://localhost:9870 |
| HDFS DataNode | http://localhost:9864 |
| Spark Master | http://localhost:18080 |
| Spark Application | http://localhost:4040 |

## Project Structure

```
spark-hive-dock/
├── docker-compose.yml        # Service orchestration (6 containers)
├── .env.example              # Environment template
├── hadoop/
│   ├── Dockerfile            # Hadoop 3.3.6 + JDK 8 base image
│   ├── core-site.xml         # HDFS default filesystem
│   ├── hdfs-site.xml         # HDFS replication & storage
│   ├── yarn-site.xml         # YARN config (reserved for expansion)
│   ├── mapred-site.xml       # MapReduce framework config (reserved)
│   └── entrypoint.sh         # Multi-role startup script
├── hive/
│   ├── Dockerfile            # Hive 3.1.3 Metastore image
│   ├── hive-site.xml         # Metastore connection (templated)
│   └── entrypoint-metastore.sh
├── spark/
│   ├── Dockerfile            # Spark 3.5.3 + Thrift Server
│   ├── core-site.xml         # HDFS connection
│   ├── hive-site.xml         # Metastore client config
│   ├── spark-defaults.conf   # Spark defaults
│   └── entrypoint.sh         # Master / Worker role switch
├── mysql/
│   └── init.sql              # Metastore DB charset config
└── scripts/
    ├── beeline-connect.sh    # Quick Beeline connection
    └── init-test-data.sh     # Sample database + table
```

## Environment Variables

All configurable via `.env`. Secrets are injected at runtime — no credentials are stored in committed config files.

| Variable | Default | Used By |
|----------|---------|---------|
| `HADOOP_VERSION` | 3.3.6 | hadoop, hive |
| `HIVE_VERSION` | 3.1.3 | hive |
| `SPARK_VERSION` | 3.5.3 | spark |
| `MYSQL_VERSION` | 8.0 | mysql |
| `MYSQL_ROOT_PASSWORD` | rootpass2024 | mysql, hive |
| `MYSQL_DATABASE` | hive_metastore | mysql, hive |
| `MYSQL_USER` | hive | mysql, hive |
| `MYSQL_PASSWORD` | hive2024 | mysql, hive |
| `HDFS_REPLICATION` | 1 | hadoop |

## Known Issues & Solutions

| Issue | Solution |
|-------|----------|
| Guava version conflict | Dockerfile replaces Hive's Guava 19 with Hadoop's Guava 27+ |
| SLF4J duplicate binding | Dockerfile removes `log4j-slf4j-impl` from Hive lib |
| JDBC driver class mismatch | `hive-site.xml` uses `com.mysql.cj.jdbc.Driver` (Connector/J 8.0) |
| MySQL timezone error | JDBC URL includes `serverTimezone=UTC` |
| Metastore not initialized | Entrypoint runs `schematool -initSchema` idempotently |
| Container startup order | `healthcheck` + `depends_on: condition` enforces sequencing |
| First-run failure residue | Run `docker compose down -v` to clear volumes before retrying |

> **Note**: `hadoop/yarn-site.xml` and `hadoop/mapred-site.xml` are included in the base image for forward compatibility. The current deployment uses Spark standalone mode — YARN services are not started.

> **Note**: `spark/core-site.xml` is a copy of `hadoop/core-site.xml`. If you modify HDFS settings, update both files.

## Lifecycle

```bash
# Start
docker compose up -d

# Stop (keep data)
docker compose down

# Stop and destroy all data
docker compose down -v

# Rebuild after config changes
docker compose up -d --build

# View logs
docker compose logs -f <service-name>
```

## ⚠️ Development Use Only

This deployment is intended for local development and testing:

- HDFS permissions are disabled (`dfs.permissions.enabled=false`)
- All services run as root
- Proxy user restrictions are fully open
- Resource limits are set for single-machine use

Do **not** use this configuration in production.

## License

MIT
