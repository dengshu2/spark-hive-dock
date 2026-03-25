# spark-hive-dock

[English](README.md) | 中文

基于 Docker 的 Spark SQL 集群，集成 Hive Metastore 和 Hadoop HDFS，使用 **MIT Kerberos** 实现安全认证，**YARN** 提供资源管理和 Delegation Token 分发。MySQL 作为 Metastore 后端存储。面向开发和测试环境 — **请勿用于生产**。

## 版本矩阵

| 组件 | 版本 | JDK |
|------|------|-----|
| Hadoop | 3.3.6 | OpenJDK 8 (Temurin) |
| Hive Metastore | 3.1.3 | OpenJDK 8 (Temurin) |
| Spark | 3.5.3 | OpenJDK 11 (Temurin) |
| MySQL | 8.0 | — |
| MIT Kerberos (KDC) | Debian bookworm | — |

## 架构

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

**认证流程**: KDC 分发 principals 和 keytabs → 所有服务通过 GSSAPI/SASL 认证

**数据流**: Beeline → Spark Thrift Server (JDBC :10000) → Hive Metastore (元数据) → HDFS (数据存储)

## 快速开始

```bash
# 1. 复制环境变量模板并修改密码
cp .env.example .env
# 编辑 .env，将 <CHANGE_ME> 替换为实际密码

# 2. 构建并启动集群
make up

# 3. 查看服务状态
make status

# 4. 验证 Kerberos 票据
make kinit

# 5. 连接 Beeline (Kerberos GSSAPI)
bash scripts/beeline-connect.sh

# 6. (可选) 加载测试数据
bash scripts/init-test-data.sh

# 7. 运行冒烟测试
make test
```

## Make 命令

| 命令 | 说明 |
|------|------|
| `make build` | 按正确顺序构建所有镜像 (kdc → hadoop-base → hive + spark) |
| `make up` | 构建 + 启动全部服务 |
| `make down` | 停止并移除容器 |
| `make clean` | 停止并移除容器、卷和本地镜像 |
| `make test` | 通过 Kerberos 运行冒烟测试 (CREATE → INSERT → SELECT → DROP) |
| `make kinit` | 验证所有服务的 Kerberos 票据 |
| `make yarn-status` | 查看 YARN 集群状态和应用列表 |
| `make status` | 查看服务健康状态 |
| `make logs` | 跟踪所有服务日志 |
| `make restart` | 重启所有服务 |

> 为什么需要 Makefile？`hive-metastore` 镜像构建依赖 `hadoop-base` 镜像 (`FROM hadoop-base:3.3.6`)，但 `docker compose build` 不保证构建顺序。Makefile 确保先构建 hadoop-base 再构建 hive-metastore。

## Kerberos 配置

集群使用 MIT Kerberos 实现跨服务认证。KDC 容器自动完成：

1. 创建 Kerberos realm 数据库
2. 为 HDFS、Hive、Spark、YARN 创建服务 principals（同时包含短主机名和 Docker FQDN `.hive-net` 后缀）
3. 导出 keytabs 到共享 Docker 卷
4. 通过标记文件通知依赖服务 KDC 已就绪

### 服务 Principals

| 服务 | Principal 模式 |
|------|----------------|
| HDFS NameNode | `hdfs/namenode.hive-net@EXAMPLE.COM` |
| HDFS DataNode | `hdfs/datanode.hive-net@EXAMPLE.COM` |
| Hive MetaStore | `hive/hive-metastore.hive-net@EXAMPLE.COM` |
| YARN RM (namenode) | `yarn/namenode.hive-net@EXAMPLE.COM` |
| YARN NM (datanode) | `yarn/datanode.hive-net@EXAMPLE.COM` |
| Spark Thrift | `spark/spark-thrift.hive-net@EXAMPLE.COM` |
| HTTP (SPNEGO) | `HTTP/<service>.hive-net@EXAMPLE.COM` |

> 所有服务使用 Docker FQDN（`.hive-net` 后缀）以实现 Kerberos `_HOST` principal 展开的一致性。`docker-compose.yml` 为每个服务设置了 `domainname: hive-net`。

### Kerberos 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `KRB5_REALM` | Kerberos realm 名称 | `EXAMPLE.COM` |
| `KRB5_KDC_PASSWORD` | KDC 数据库主密码 | — |

## Web 界面

| 服务 | 地址 |
|------|------|
| HDFS NameNode | http://localhost:9870 |
| HDFS DataNode | http://localhost:9864 |
| YARN ResourceManager | http://localhost:8088 |
| YARN NodeManager | http://localhost:8042 |
| Spark Application | http://localhost:4040 |

## 项目结构

```
spark-hive-dock/
├── Makefile                  # 构建、启动、测试的统一入口
├── docker-compose.yml        # 服务编排 (6 个容器)
├── .env.example              # 环境变量模板
├── .dockerignore             # 构建上下文排除规则
├── kdc/
│   ├── Dockerfile            # MIT Kerberos KDC 镜像
│   ├── krb5.conf             # Kerberos 客户端配置
│   └── init-kdc.sh           # Principal 创建 + keytab 导出
├── hadoop/
│   ├── Dockerfile            # Hadoop 3.3.6 + YARN + Spark Shuffle + Kerberos
│   ├── core-site.xml         # HDFS + Kerberos 认证
│   ├── hdfs-site.xml         # HDFS 副本数、存储、Kerberos principals
│   ├── yarn-site.xml         # YARN 资源管理 + Kerberos
│   ├── mapred-site.xml       # MapReduce 框架配置
│   └── entrypoint.sh         # 多角色启动 (NN+RM / DN+NM) + kinit
├── hive/
│   ├── Dockerfile            # Hive 3.1.3 Metastore + krb5-user
│   ├── hive-site.xml         # Metastore SASL/GSSAPI 认证
│   └── entrypoint-metastore.sh  # Kerberos 化启动流程
├── spark/
│   ├── Dockerfile            # Spark 3.5.3 + Thrift Server + krb5-user
│   ├── core-site.xml         # HDFS + Kerberos + 代理用户配置
│   ├── hdfs-site.xml         # HDFS Kerberos principals (与 hadoop/ 同步)
│   ├── yarn-site.xml         # YARN 客户端配置 (与 hadoop/ 同步)
│   ├── mapred-site.xml       # MapReduce 配置 (与 hadoop/ 同步)
│   ├── hive-site.xml         # MetaStore SASL 客户端配置
│   ├── spark-defaults.conf   # YARN 模式 + Kerberos delegation token
│   └── entrypoint.sh         # Thrift Server (YARN client) + kinit
├── mysql/
│   └── init.sql              # Metastore 数据库字符集配置
└── scripts/
    ├── beeline-connect.sh    # 快速连接 Beeline (Kerberos)
    └── init-test-data.sh     # 示例数据库和表 (Kerberos 版)
```

## 环境变量

所有配置通过 `.env` 文件管理。敏感信息在运行时注入，不会存储在已提交的配置文件中。

| 变量 | 说明 | 使用方 |
|------|------|--------|
| `HADOOP_VERSION` | Hadoop 版本 | hadoop, hive |
| `HIVE_VERSION` | Hive 版本 | hive |
| `SPARK_VERSION` | Spark 版本 | spark |
| `MYSQL_VERSION` | MySQL 版本 | mysql |
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码 | mysql, hive |
| `MYSQL_DATABASE` | Metastore 数据库名 | mysql, hive |
| `MYSQL_USER` | Metastore 数据库用户 | mysql, hive |
| `MYSQL_PASSWORD` | Metastore 数据库密码 | mysql, hive |
| `HDFS_REPLICATION` | HDFS 副本数 | hadoop |
| `KRB5_REALM` | Kerberos realm | kdc, hadoop, hive, spark |
| `KRB5_KDC_PASSWORD` | KDC 数据库主密码 | kdc |
| `TZ` | 容器时区 | all |

## 已知问题与解决方案

| 问题 | 解决方案 |
|------|----------|
| Guava 版本冲突 | Dockerfile 将 Hive 的 Guava 19 替换为 Hadoop 的 Guava 27+ |
| SLF4J 重复绑定 | Dockerfile 从 Hive lib 中移除 `log4j-slf4j-impl` |
| JDBC 驱动类名不匹配 | `hive-site.xml` 使用 `com.mysql.cj.jdbc.Driver` (Connector/J 8.0) |
| MySQL 时区错误 | JDBC URL 包含 `serverTimezone=UTC` |
| Metastore 未初始化 | 入口脚本幂等执行 `schematool -initSchema` |
| 容器启动顺序 | `healthcheck` + `depends_on: condition` 保证依赖链 |
| 构建顺序 | Makefile 保证 hadoop-base 先于 hive-metastore 构建 |
| 首次运行失败残留 | 执行 `make clean` 清除卷后重试 |
| Filesystem closed 异常 | `core-site.xml` 设置 `fs.hdfs.impl.disable.cache=true`，避免共享 DFSClient 被关闭 |
| Docker DNS `_HOST` 展开不匹配 | 所有服务 URI 使用 FQDN (`.hive-net`)；compose 中设置 `domainname: hive-net` |
| SASL 降级到 DIGEST-MD5 | `hive.server2.enable.doAs=false` 保持 Spark 的 Kerberos Subject 连接 MetaStore |
| Executor Kerberos 认证 | 已通过 YARN 模式解决 — YARN 自动分发 Delegation Token 给 Executor |

> **注意**: `spark/` 目录中的 `core-site.xml`、`hdfs-site.xml`、`yarn-site.xml`、`mapred-site.xml` 是 `hadoop/` 目录下对应文件的副本。如果修改了 Hadoop 配置，请同时更新两处。

## 生命周期

```bash
# 启动
make up

# 停止 (保留数据)
make down

# 停止并销毁所有数据
make clean

# 配置变更后重建
make restart

# 查看日志
make logs

# 验证 Kerberos
make kinit
```

## ⚠️ 仅限开发环境

本部署面向本地开发和测试：

- 所有服务在容器内以 root 用户运行
- Kerberos realm 使用测试域名 (`EXAMPLE.COM`)
- `ignore.secure.ports.for.testing=true` 允许非特权 HDFS 端口
- `hive.server2.enable.doAs=false` — 不进行用户级模拟
- 代理用户限制完全开放 (`hadoop.proxyuser.*.hosts=*`)
- Spark Thrift Server 使用 YARN client 模式，Executor 由 NodeManager 管理

**请勿将此配置用于生产环境。**

## 许可证

MIT
