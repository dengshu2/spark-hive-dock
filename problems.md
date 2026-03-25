# Kerberos 集成问题清单

> **项目**: `spark-hive-dock` — Spark + Hive Metastore + HDFS Docker 集群 + MIT Kerberos + YARN
> **日期**: 2026-03-26
> **当前状态**: ✅ 已迁移到 Spark on YARN 模式，所有遗留问题均已处理

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

### ✅ 遗留问题 1（已解决）：Spark Thrift Server 使用 `local[*]` 模式
**根因**: Standalone 模式下 Spark 不支持 Delegation Token 自动分发给 Executor。
**修复**: 迁移到 Spark on YARN 模式。ResourceManager 与 NameNode 同容器，NodeManager 与 DataNode 同容器。YARN 原生支持 Delegation Token 分发和续签。

### ✅ 遗留问题 2（已解决）：`beeline-connect.sh` 脚本使用旧 principal
**修复**: 更新为 `spark/spark-thrift.hive-net@EXAMPLE.COM`。

---

## 🟡 遗留问题 3：`spark/hdfs-site.xml` 是 `hadoop/hdfs-site.xml` 的手动复制

### 现状
`spark/hdfs-site.xml` 是从 `hadoop/hdfs-site.xml` 手动 `cp` 过来的静态副本。如果未来修改 Hadoop 侧的 `hdfs-site.xml`，Spark 侧不会自动同步。同样适用于 `yarn-site.xml` 和 `mapred-site.xml`。

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
  → Spark Thrift Server (:10000, principal=spark/_HOST, YARN client mode)
    → YARN ResourceManager (:8032, on namenode container)
      → YARN NodeManager (on datanode container, runs Spark Executors)
    → Hive MetaStore (:9083, SASL GSSAPI, principal=hive/_HOST)
      → HDFS NameNode (:9000, Kerberos RPC, principal=hdfs/_HOST)
        → HDFS DataNode (SASL auth, principal=hdfs/_HOST)
```

所有 `_HOST` 均从各自 URI 中提取 FQDN（`.hive-net` 后缀）进行展开。
