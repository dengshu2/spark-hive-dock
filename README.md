# spark-hive-dock

English | [中文](README_CN.md)

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
# 1. Copy environment template and set your own passwords
cp .env.example .env
# Edit .env and replace <CHANGE_ME> with actual passwords

# 2. Build and start the cluster
make up

# 3. Check service status
make status

# 4. Connect via Beeline
bash scripts/beeline-connect.sh

# 5. (Optional) Load test data
bash scripts/init-test-data.sh

# 6. Run smoke test
make test
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make build` | Build all images in correct dependency order (hadoop-base → hive + spark) |
| `make up` | Build + start all services |
| `make down` | Stop and remove containers |
| `make clean` | Stop and remove containers, volumes, and local images |
| `make test` | Run smoke test (CREATE → INSERT → SELECT → DROP) |
| `make status` | Show service health status |
| `make logs` | Follow all service logs |
| `make restart` | Restart all services |

> Why a Makefile? The `hive-metastore` image depends on `hadoop-base` (`FROM hadoop-base:3.3.6`), but `docker compose build` doesn't guarantee build ordering. The Makefile ensures hadoop-base is built before hive-metastore.

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
├── Makefile                  # Build, start, and test entry point
├── docker-compose.yml        # Service orchestration (6 containers)
├── .env.example              # Environment template
├── .dockerignore             # Build context exclusions
├── hadoop/
│   ├── Dockerfile            # Hadoop 3.3.6 + JDK 8 base image
│   ├── core-site.xml         # HDFS default filesystem
│   ├── hdfs-site.xml         # HDFS replication & storage
│   └── entrypoint.sh         # Multi-role startup (namenode / datanode)
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

| Variable | Description | Used By |
|----------|-------------|---------|
| `HADOOP_VERSION` | Hadoop version | hadoop, hive |
| `HIVE_VERSION` | Hive version | hive |
| `SPARK_VERSION` | Spark version | spark |
| `MYSQL_VERSION` | MySQL version | mysql |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | mysql, hive |
| `MYSQL_DATABASE` | Metastore database name | mysql, hive |
| `MYSQL_USER` | Metastore database user | mysql, hive |
| `MYSQL_PASSWORD` | Metastore database password | mysql, hive |
| `HDFS_REPLICATION` | HDFS replication factor | hadoop |

## Known Issues & Solutions

| Issue | Solution |
|-------|----------|
| Guava version conflict | Dockerfile replaces Hive's Guava 19 with Hadoop's Guava 27+ |
| SLF4J duplicate binding | Dockerfile removes `log4j-slf4j-impl` from Hive lib |
| JDBC driver class mismatch | `hive-site.xml` uses `com.mysql.cj.jdbc.Driver` (Connector/J 8.0) |
| MySQL timezone error | JDBC URL includes `serverTimezone=UTC` |
| Metastore not initialized | Entrypoint runs `schematool -initSchema` idempotently |
| Container startup order | `healthcheck` + `depends_on: condition` enforces sequencing |
| Build dependency order | Makefile ensures hadoop-base is built before hive-metastore |
| First-run failure residue | Run `make clean` to clear volumes before retrying |

> **Note**: `spark/core-site.xml` is a copy of `hadoop/core-site.xml`. If you modify HDFS settings, update both files.

## Lifecycle

```bash
# Start
make up

# Stop (keep data)
make down

# Stop and destroy all data
make clean

# Rebuild after config changes
make restart

# View logs
make logs
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
