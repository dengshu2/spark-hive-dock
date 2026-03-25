# Kerberos 集成问题清单

> **项目**: `spark-hive-dock` — Spark + Hive Metastore + HDFS Docker 集群 + MIT Kerberos + YARN
> **日期**: 2026-03-26
> **当前状态**: ✅ Spark on YARN 模式稳定运行，全部启动问题已解决

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

## YARN 集成启动问题（本次会话）

### ✅ 问题 6：kinit 报 "Password incorrect"（KDC ready marker 竞态）
**根因**: `keytabs` volume 中残留上一轮容器的 `.kdc-ready` 标记。KDC 容器重建后，Docker healthcheck 立即通过（旧标记仍在），namenode 在 `init-kdc.sh` 还未重新生成 keytab 之前就执行 `kinit`，读到的是过期 keytab。
**修复**: `kdc/init-kdc.sh` 启动时首先执行 `rm -f "${READY_FILE}"`，强制依赖方等待本次初始化完成。

### ✅ 问题 7：NameNode healthcheck 失败（ResourceManager 绑定 FQDN）
**根因**: `yarn-site.xml` 中 `yarn.resourcemanager.address=namenode.hive-net:8032`，RM 监听在 FQDN 对应的 IP 而非 `0.0.0.0`，healthcheck 的 `nc -z localhost 8032` 无法连通。
**修复**: `hadoop/yarn-site.xml` 增加 `yarn.resourcemanager.bind-host=0.0.0.0`，与 NameNode 的 `dfs.namenode.rpc-bind-host` 做法一致。

### ✅ 问题 8：NodeManager 启动崩溃（Spark shuffle JAR 缺失）
**根因**: Hadoop Dockerfile 使用 `tar --wildcards` 提取 Spark shuffle JAR，因 glob 匹配问题静默失败（无报错退出），导致 `/opt/spark-yarn/` 为空目录。NodeManager 尝试加载 `YarnShuffleService` 时抛 `ClassNotFoundException`。
**修复**: 移除 `yarn.nodemanager.aux-services=spark_shuffle` 配置及对应 Dockerfile 下载步骤。本集群使用固定 executor 数量（`spark.executor.instances=1`）且不启用动态分配，无需外部 Shuffle Service。

### ✅ 问题 9：YARN 虚拟内存检查误杀容器
**根因**: `yarn.nodemanager.vmem-check-enabled` 默认为 `true`，虚拟内存上限比率 2.1x。JVM 进程的虚拟内存远高于物理内存，在 Docker 环境下触发 YARN 将刚分配的 executor 容器立即 Kill，报 "exceeded virtual memory limits"。
**修复**: `hadoop/yarn-site.xml` 和 `spark/yarn-site.xml` 均添加 `yarn.nodemanager.vmem-check-enabled=false` 和 `yarn.nodemanager.pmem-check-enabled=false`。

### ✅ 问题 10：datanode 内存上限不足，executor 无法分配
**根因**: `yarn.nodemanager.resource.memory-mb=2048` 但 datanode 容器上限仅 1536M。DataNode JVM + NodeManager JVM 已占用约 768MB，剩余不足以容纳 executor 容器（1g + 384MB overhead = 1408MB）。
**修复**: `docker-compose.yml` 将 datanode 内存上限从 `1536M` 提升至 `3g`。

### ✅ 问题 11：YARN 无法分配 executor（AM + executor 超出 NM 容量）
**根因**: 单个 NodeManager 容量 2048MB，AM 容器占用 1024MB，剩余 1024MB 无法放下 executor（1g heap + 384MB overhead → 实际申请 1408MB，调度最小粒度 512MB 对齐后为 1536MB）。
**修复**: `spark/spark-defaults.conf` 将 `spark.executor.memory` 从 `1g` 降至 `512m`，使 AM（1024MB）+ executor（1024MB）= 2048MB 恰好填满 NM 容量。

### ✅ 问题 12：Spark staging 目录权限拒绝
**根因**: Spark on YARN 提交时需在 HDFS 创建 `/user/spark/.sparkStaging`，但 `/user` 目录权限为 `drwxr-xr-x`（755，属主 `hdfs`），`spark` 用户无写权限。
**修复**: `spark/spark-defaults.conf` 设置 `spark.yarn.stagingDir=hdfs://namenode.hive-net:9000/tmp/spark-staging`，`/tmp` 目录已由 hive-metastore entrypoint 设为 `1777`。

---

## 🟡 遗留问题 3：`spark/` 下的 Hadoop 配置文件是手动静态副本

### 现状
`spark/{hdfs-site,yarn-site,mapred-site}.xml` 均是从 `hadoop/` 手动复制的静态副本。修改 Hadoop 侧配置后 Spark 侧不会自动同步，容易造成两侧配置漂移。

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
