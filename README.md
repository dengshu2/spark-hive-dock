# spark-hive-dock

English | [中文](README_CN.md)

Dockerized Spark SQL cluster with Hive Metastore on Hadoop HDFS, secured with **MIT Kerberos** authentication and **YARN** resource management with delegation token distribution. MySQL serves as the Metastore backend. Designed for development and testing — **not for production use**.

## Version Matrix

| Component | Version | JDK |
|-----------|---------|-----|
| Hadoop | 3.3.6 | OpenJDK 8 (Temurin) |
| Hive Metastore | 3.1.3 | OpenJDK 8 (Temurin) |
| Spark | 3.5.3 | OpenJDK 11 (Temurin) |
| MySQL | 8.0 | — |
| MIT Kerberos (KDC) | Debian bookworm | — |

## Architecture

```
                     ┌──────────────────────────────────────┐
                     │       Docker Network: hive-net        │
                     │  ┌─────────┐                         │
                     │  │   KDC   │  ← MIT Kerberos         │
                     │  │   :88   │    (principals + keytabs)│
                     │  └────┬────┘                         │
                     │       │ GSSAPI / keytab               │
  ┌───────┐          │  ┌────▼─────┐   ┌──────────┐        │
  │ MySQL │◄─────────┤  │ NameNode │   │ DataNode │        │
  │ :3306 │          │  │  :9870   │   │  :9864   │        │
  └───────┘          │  └────┬─────┘   └─────┬────┘        │
                     │       │  HDFS (Kerberos RPC)          │
                     │  ┌────┴───────────────┴────┐        │
                     │  │    Hive Metastore        │        │
                     │  │    :9083 (SASL/GSSAPI)   │        │
                     │  └────────────┬─────────────┘        │
                     │               │                      │
  ┌──────────────┐   │  ┌────────────▼─────────────┐       │
  │   Beeline    │──►│  │  Spark Master             │       │
  │  (GSSAPI)    │   │  │  :7077 (RPC)              │       │
  └──────────────┘   │  │  :10000 (Thrift / JDBC)   │       │
                     │  │  :18080 (Web UI)          │       │
                     │  └────────────┬─────────────┘       │
                     │               │                      │
                     │  ┌────────────▼─────────────┐       │
                     │  │    Spark Worker           │       │
                     │  └──────────────────────────┘       │
                     └──────────────────────────────────────┘
```

**Authentication flow**: KDC provisions principals and keytabs → all services authenticate via GSSAPI/SASL

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

# 4. Verify Kerberos tickets
make kinit

# 5. Connect via Beeline (Kerberos GSSAPI)
bash scripts/beeline-connect.sh

# 6. (Optional) Load test data
bash scripts/init-test-data.sh

# 7. Run smoke test
make test
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make build` | Build all images in correct dependency order (kdc → hadoop-base → hive + spark) |
| `make up` | Build + start all services |
| `make down` | Stop and remove containers |
| `make clean` | Stop and remove containers, volumes, and local images |
| `make test` | Run smoke test (CREATE → INSERT → SELECT → DROP) via Kerberos |
| `make kinit` | Verify Kerberos tickets on all services |
| `make yarn-status` | Show YARN cluster status and application list |
| `make status` | Show service health status |
| `make logs` | Follow all service logs |
| `make restart` | Restart all services |

> Why a Makefile? The `hive-metastore` image depends on `hadoop-base` (`FROM hadoop-base:3.3.6`), but `docker compose build` doesn't guarantee build ordering. The Makefile ensures hadoop-base is built before hive-metastore.

## Kerberos Configuration

The cluster uses MIT Kerberos for authentication across all services. The KDC container automatically:

1. Creates the Kerberos realm database
2. Provisions service principals for HDFS, Hive, Spark, and YARN (both short hostnames and Docker FQDNs with `.hive-net` suffix)
3. Exports keytabs to a shared Docker volume
4. Signals readiness via a marker file

### Service Principals

| Service | Principal Pattern |
|---------|-------------------|
| HDFS NameNode | `hdfs/namenode.hive-net@EXAMPLE.COM` |
| HDFS DataNode | `hdfs/datanode.hive-net@EXAMPLE.COM` |
| Hive MetaStore | `hive/hive-metastore.hive-net@EXAMPLE.COM` |
| YARN RM (namenode) | `yarn/namenode.hive-net@EXAMPLE.COM` |
| YARN NM (datanode) | `yarn/datanode.hive-net@EXAMPLE.COM` |
| Spark Thrift | `spark/spark-thrift.hive-net@EXAMPLE.COM` |
| HTTP (SPNEGO) | `HTTP/<service>.hive-net@EXAMPLE.COM` |

> All services use Docker FQDN (`.hive-net` suffix) for consistent Kerberos `_HOST` principal expansion. The `docker-compose.yml` sets `domainname: hive-net` on every service.

### Kerberos Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KRB5_REALM` | Kerberos realm name | `EXAMPLE.COM` |
| `KRB5_KDC_PASSWORD` | KDC database master password | — |

## Web UIs

| Service | URL |
|---------|-----|
| HDFS NameNode | http://localhost:9870 |
| HDFS DataNode | http://localhost:9864 |
| YARN ResourceManager | http://localhost:8088 |
| YARN NodeManager | http://localhost:8042 |
| Spark Application | http://localhost:4040 |

## Project Structure

```
spark-hive-dock/
├── Makefile                  # Build, start, and test entry point
├── docker-compose.yml        # Service orchestration (6 containers)
├── .env.example              # Environment template
├── .dockerignore             # Build context exclusions
├── kdc/
│   ├── Dockerfile            # MIT Kerberos KDC image
│   ├── krb5.conf             # Kerberos client configuration
│   └── init-kdc.sh           # Principal provisioning + keytab export
├── hadoop/
│   ├── Dockerfile            # Hadoop 3.3.6 + YARN + Spark Shuffle + Kerberos
│   ├── core-site.xml         # HDFS + Kerberos authentication
│   ├── hdfs-site.xml         # HDFS replication, storage, Kerberos principals
│   ├── yarn-site.xml         # YARN resource management + Kerberos
│   ├── mapred-site.xml       # MapReduce framework config
│   └── entrypoint.sh         # Multi-role startup (NN+RM / DN+NM) with kinit
├── hive/
│   ├── Dockerfile            # Hive 3.1.3 Metastore + krb5-user
│   ├── hive-site.xml         # Metastore SASL/GSSAPI authentication
│   └── entrypoint-metastore.sh  # Kerberized startup sequence
├── spark/
│   ├── Dockerfile            # Spark 3.5.3 + Thrift Server + krb5-user
│   ├── core-site.xml         # HDFS + Kerberos + proxy user config
│   ├── hdfs-site.xml         # HDFS Kerberos principals (synced from hadoop/)
│   ├── yarn-site.xml         # YARN client config (synced from hadoop/)
│   ├── mapred-site.xml       # MapReduce config (synced from hadoop/)
│   ├── hive-site.xml         # MetaStore SASL client config
│   ├── spark-defaults.conf   # YARN mode + Kerberos delegation token
│   └── entrypoint.sh         # Thrift Server (YARN client) + kinit
├── mysql/
│   └── init.sql              # Metastore DB charset config
└── scripts/
    ├── beeline-connect.sh    # Quick Beeline connection (Kerberos)
    └── init-test-data.sh     # Sample database + table (Kerberized)
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
| `KRB5_REALM` | Kerberos realm | kdc, hadoop, hive, spark |
| `KRB5_KDC_PASSWORD` | KDC database master password | kdc |
| `TZ` | Timezone for all containers | all |

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
| Filesystem closed IOException | `fs.hdfs.impl.disable.cache=true` in `core-site.xml` prevents shared DFSClient closure |
| Docker DNS `_HOST` mismatch | All service URIs use FQDN (`.hive-net`); `domainname: hive-net` set in compose |
| SASL fallback to DIGEST-MD5 | `hive.server2.enable.doAs=false` keeps Spark's Kerberos Subject on MetaStore calls |
| Executor Kerberos auth | Solved via YARN mode — YARN auto-distributes delegation tokens to Executors |

> **Note**: `spark/` directory contains copies of `core-site.xml`, `hdfs-site.xml`, `yarn-site.xml`, and `mapred-site.xml` from `hadoop/`. If you modify Hadoop config, update both locations.

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

# Verify Kerberos
make kinit
```

## ⚠️ Development Use Only

This deployment is intended for local development and testing:

- All services run as root inside containers
- Kerberos realm uses a test domain (`EXAMPLE.COM`)
- `ignore.secure.ports.for.testing=true` allows unprivileged HDFS ports
- `hive.server2.enable.doAs=false` — no per-user impersonation
- Proxy user restrictions are fully open (`hadoop.proxyuser.*.hosts=*`)
- Spark Thrift Server runs in YARN client mode with Executors managed by NodeManager

Do **not** use this configuration in production.

## License

MIT
