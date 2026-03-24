# spark-hive-dock

[English](README.md) | 中文

基于 Docker 的 Spark SQL 集群，集成 Hive Metastore 和 Hadoop HDFS。MySQL 作为 Metastore 后端存储。面向开发和测试环境 — **请勿用于生产**。

## 版本矩阵

| 组件 | 版本 | JDK |
|------|------|-----|
| Hadoop | 3.3.6 | OpenJDK 8 (Temurin) |
| Hive Metastore | 3.1.3 | OpenJDK 8 (Temurin) |
| Spark | 3.5.3 | OpenJDK 11 (Temurin) |
| MySQL | 8.0 | — |

## 架构

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
  │  (客户端)    │   │  │  :7077 (RPC)              │   │
  └──────────────┘   │  │  :10000 (Thrift / JDBC)   │   │
                     │  │  :18080 (Web UI)          │   │
                     │  └────────────┬─────────────┘   │
                     │               │                  │
                     │  ┌────────────▼─────────────┐   │
                     │  │    Spark Worker           │   │
                     │  └──────────────────────────┘   │
                     └──────────────────────────────────┘
```

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

# 4. 连接 Beeline
bash scripts/beeline-connect.sh

# 5. (可选) 加载测试数据
bash scripts/init-test-data.sh

# 6. 运行冒烟测试
make test
```

### 中国用户加速构建

在 `.env` 中配置国内镜像源（推荐清华源）：

```bash
APACHE_MIRROR_HADOOP=https://mirrors.tuna.tsinghua.edu.cn/apache
# Spark 3.5.3 和 Hive 3.1.3 为归档版本，清华源不提供，需使用 Apache 官方源
APACHE_MIRROR_SPARK=https://archive.apache.org/dist
APACHE_MIRROR_HIVE=https://archive.apache.org/dist
```

## Make 命令

| 命令 | 说明 |
|------|------|
| `make build` | 按正确顺序构建所有镜像 (hadoop-base → hive + spark) |
| `make up` | 构建 + 启动全部服务 |
| `make down` | 停止并移除容器 |
| `make clean` | 停止并移除容器、卷和本地镜像 |
| `make test` | 运行冒烟测试 (CREATE → INSERT → SELECT → DROP) |
| `make status` | 查看服务健康状态 |
| `make logs` | 跟踪所有服务日志 |
| `make restart` | 重启所有服务 |

> 为什么需要 Makefile？`hive-metastore` 镜像构建依赖 `hadoop-base` 镜像 (`FROM hadoop-base:3.3.6`)，但 `docker compose build` 不保证构建顺序。Makefile 确保先构建 hadoop-base 再构建 hive-metastore。

## Web 界面

| 服务 | 地址 |
|------|------|
| HDFS NameNode | http://localhost:9870 |
| HDFS DataNode | http://localhost:9864 |
| Spark Master | http://localhost:18080 |
| Spark Application | http://localhost:4040 |

## 项目结构

```
spark-hive-dock/
├── Makefile                  # 构建、启动、测试的统一入口
├── docker-compose.yml        # 服务编排 (6 个容器)
├── .env.example              # 环境变量模板
├── .dockerignore             # 构建上下文排除规则
├── hadoop/
│   ├── Dockerfile            # Hadoop 3.3.6 + JDK 8 基础镜像
│   ├── core-site.xml         # HDFS 默认文件系统配置
│   ├── hdfs-site.xml         # HDFS 副本数与存储路径
│   └── entrypoint.sh         # 多角色启动脚本 (namenode / datanode)
├── hive/
│   ├── Dockerfile            # Hive 3.1.3 Metastore 镜像
│   ├── hive-site.xml         # Metastore 连接配置 (模板化)
│   └── entrypoint-metastore.sh
├── spark/
│   ├── Dockerfile            # Spark 3.5.3 + Thrift Server
│   ├── core-site.xml         # HDFS 连接配置
│   ├── hive-site.xml         # Metastore 客户端配置
│   ├── spark-defaults.conf   # Spark 默认参数
│   └── entrypoint.sh         # Master / Worker 角色切换
├── mysql/
│   └── init.sql              # Metastore 数据库字符集配置
└── scripts/
    ├── beeline-connect.sh    # 快速连接 Beeline
    └── init-test-data.sh     # 示例数据库和表
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
| `APACHE_MIRROR_HADOOP` | Hadoop 下载镜像源 | hadoop |
| `APACHE_MIRROR_SPARK` | Spark 下载镜像源 | spark |
| `APACHE_MIRROR_HIVE` | Hive 下载镜像源 | hive |

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

> **注意**: `spark/core-site.xml` 是 `hadoop/core-site.xml` 的副本。如果修改了 HDFS 配置，请同时更新两份文件。

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
```

## ⚠️ 仅限开发环境

本部署面向本地开发和测试：

- HDFS 权限检查已关闭 (`dfs.permissions.enabled=false`)
- 所有服务以 root 用户运行
- 代理用户限制完全开放
- 资源限制为单机使用量

**请勿将此配置用于生产环境。**

## 许可证

MIT
