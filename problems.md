# Kerberos 集成问题清单

> **项目**: `spark-hive-dock` — Spark + Hive Metastore + HDFS Docker 集群 + MIT Kerberos
> **日期**: 2026-03-25
> **当前状态**: ✅ 端到端测试已通过（CREATE DB → CREATE TABLE → INSERT → SELECT），但有两个遗留问题需处理

---

## 已解决的问题

### ✅ 问题 1：DataNode 安全启动报错
SASL 模式 + 非特权端口 + 不设置 `HDFS_DATANODE_SECURE_USER`。

### ✅ 问题 2：Docker DNS FQDN 导致 `_HOST` 展开不匹配
**根因**: `fs.defaultFS=hdfs://namenode:9000` — Hadoop NameNode 从此 URI 提取主机名做 `_HOST` 展开，得到 `namenode`（短名）而非 `namenode.hive-net`（FQDN）。
**修复**: 所有配置文件中的 service URI 统一改为 FQDN (`.hive-net`)，`docker-compose.yml` 所有服务添加 `domainname: hive-net`。

### ✅ 问题 3：Hive MetaStore SASL 降级到 DIGEST-MD5
**根因**: `hive.server2.enable.doAs=true`（默认）→ Thrift Server 用 beeline 用户身份连接 MetaStore → 该用户没有 Kerberos TGT → SASL fallback 到 DIGEST-MD5 → 失败。
**修复**: `spark/hive-site.xml` 中设 `hive.server2.enable.doAs=false`，spark-submit 添加 `--principal`/`--keytab`。

### ✅ 问题 4：Spark 缺少 `hdfs-site.xml`
**根因**: `spark/Dockerfile` 只 COPY 了 `core-site.xml` 到 `HADOOP_CONF_DIR`，没有 `hdfs-site.xml` → Spark 不知道 `dfs.namenode.kerberos.principal=hdfs/_HOST@EXAMPLE.COM`。
**修复**: Dockerfile 添加 `COPY hdfs-site.xml`，新建 `spark/hdfs-site.xml`（从 `hadoop/hdfs-site.xml` 复制）。

### ✅ 问题 5：HDFS warehouse 目录权限
**根因**: `spark` 用户不在 `supergroup` 组，775 权限不足。
**修复**: `entrypoint-metastore.sh` 中 chmod `1777`。

---

## 🔴 遗留问题 1：Spark Thrift Server 使用 `local[*]` 模式（非分布式）

### 现状
Thrift Server 当前使用 `--master local[*]` 运行，所有 SQL 计算都在 Driver JVM 中完成。Spark Worker 容器虽然运行但实际上没有被使用。

### 根因
在 Standalone 模式（`spark://spark-master:7077`）下，Executor 运行在 Worker 容器的 JVM 中。Driver 通过 `--principal`/`--keytab` 拥有 Kerberos Subject，但 Executor JVM 没有相应的 Kerberos 凭据。当 Executor 尝试写 ORC 文件到 HDFS 时，报错：
```
Client cannot authenticate via:[TOKEN, KERBEROS]
```

### 预期行为
Spark 的 `--principal`/`--keytab` 应在 Driver 启动时获取 HDFS Delegation Token，并通过 Spark 内部机制分发给 Executor。但在长时间运行的 Thrift Server 中，每个 beeline session 触发的查询不一定能获取到初始的 Delegation Token。

### 需要研究的方向
1. **Delegation Token 分发**: `spark.kerberos.access.hadoopFileSystems` 配置是否能解决
2. **Executor keytab login**: `spark.executorEnv.HADOOP_JAAS_DEBUG=true` + 让 Executor 也执行 keytab login
3. **Token renewal**: Thrift Server 是否支持自动续签 Delegation Token
4. **Spark 3.5 standalone Kerberos**: 查阅是否有官方的 standalone + Kerberos + HDFS 最佳实践

### 相关文件
- `spark/entrypoint.sh` (line 83): `--master local[*]` ← 需要改回 `spark://spark-master:7077`
- `spark/spark-defaults.conf`: `spark.kerberos.principal` / `spark.kerberos.keytab`
- keytab 共享卷: Worker 容器已挂载相同的 keytab 文件

### 验证方法
```bash
# 1. 改回 standalone 模式
# spark/entrypoint.sh: --master spark://spark-master:7077

# 2. 重建测试
docker compose down -v && make build && docker compose up -d

# 3. 运行测试 (INSERT 操作会触发 Executor 写 HDFS)
bash scripts/init-test-data.sh

# 4. 如果失败，检查 Worker 日志
docker compose logs spark-worker | grep -i "kerberos\|auth\|token"
```

---

## 🟡 遗留问题 2：`beeline-connect.sh` 脚本使用旧 principal

### 现状
`scripts/beeline-connect.sh` 中的 JDBC URI 仍使用短主机名 principal：
```bash
-u "jdbc:hive2://localhost:10000/;principal=spark/spark-master@EXAMPLE.COM"
```

### 修复建议
```bash
-u "jdbc:hive2://spark-master.hive-net:10000/;principal=spark/spark-master.hive-net@EXAMPLE.COM"
```

相关：`scripts/init-test-data.sh` 已更新为 Kerberos 版本，可参考其中的 JDBC URI 格式。

---

## 🟡 遗留问题 3：`spark/hdfs-site.xml` 是 `hadoop/hdfs-site.xml` 的手动复制

### 现状
`spark/hdfs-site.xml` 是从 `hadoop/hdfs-site.xml` 手动 `cp` 过来的静态副本。如果未来修改 Hadoop 侧的 `hdfs-site.xml`，Spark 侧不会自动同步。

### 修复建议
- 方案 A: 在 Makefile 的 `build` target 中添加自动同步步骤
- 方案 B: 在 `spark/Dockerfile` 中使用多阶段构建，从 hadoop image 复制
- 方案 C: 使用 Docker Compose 的 `configs` 或共享 volume 挂载同一份文件

---

## 🟡 遗留问题 4：`hive.server2.enable.doAs=false` 的安全影响

### 现状
关闭 `doAs` 后，所有通过 Thrift Server 执行的查询都以 `spark` 服务用户身份运行，不区分 beeline 连接用户。这在开发环境中是可接受的，但生产环境需要用户级隔离。

### 如需启用 `doAs`
1. 需要为每个 beeline 用户创建 Kerberos principal 并分发 keytab
2. 或使用 Kerberos Proxy User 机制：确保 `spark` 用户可以 impersonate 其他用户
3. 对应 `core-site.xml` 中已有 `hadoop.proxyuser.spark.{hosts,groups}=*` 配置，但可能需要额外的 MetaStore 端配置

---

## 当前配置架构

```
beeline (GSSAPI)
  → Spark Thrift Server (:10000, principal=spark/_HOST, local[*] mode)
    → Hive MetaStore (:9083, SASL GSSAPI, principal=hive/_HOST)
      → HDFS NameNode (:9000, Kerberos RPC, principal=hdfs/_HOST)
        → HDFS DataNode (SASL auth, principal=hdfs/_HOST)
```

所有 `_HOST` 均从各自 URI 中提取 FQDN（`.hive-net` 后缀）进行展开。
