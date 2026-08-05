# Kerberos 集成问题清单

> **项目**: `spark-hive-dock` — Spark + Hive Metastore + HDFS Docker 集群 + MIT Kerberos + YARN
> **日期**: 2026-03-26（2026-08-05 依赖维护至 Spark 4.1.3，Hive 4.1.0 / Hadoop 3.5.0 保持不变）
> **当前状态**: ✅ Spark on YARN 模式稳定运行；✅ 依赖升级、校验和固定及端到端验证完成

---

## 依赖维护（2026-08-05）

本轮只处理有明确收益且已完成回归的升级，避免为追新而改动整套兼容矩阵：

| 依赖 | 处理 | 原因 |
|---|---|---|
| Spark | 4.1.2 → **4.1.3** | 同一 4.1 维护线的安全性、正确性与稳定性修复 |
| MySQL Connector/J | 9.1.0 → **9.7.0** | 仅 Hive Metastore 需要；Spark 通过 Thrift 访问 HMS，不需要直连 MySQL |
| ClickHouse JDBC | 0.7.2 → **0.9.8** | 升级当前驱动并完成真实 Hive→ClickHouse 同步回归 |
| Iceberg | 保持 **1.11.0** | 已是当前 Spark 4.1 / Scala 2.13 适配版本，升级无收益 |
| Hive / Hadoop | 保持 **4.1.0 / 3.5.0** | 当前兼容组合稳定，本轮没有必要扩大升级面 |

同时为 Spark 发布包、ClickHouse JDBC、Iceberg runtime 和 Connector/J 固定并验证
SHA-512/SHA-256；缓存文件同样必须通过校验，避免旧缓存或损坏下载被误用。
Spark 镜像中已移除 Connector/J，包括复制进来的 Hive 客户端隔离目录，仅 Hive
Metastore 镜像保留该驱动。

### 验证（全部通过）

- `make test`：Kerberos SASL、Hive 4.1 HMS、建表/插入/查询/删除。
- Spark Connect 4.1.3：版本、SQL 与数据库枚举。
- Iceberg 1.11.0：建表、写入、聚合、snapshot 元数据和清理。
- ClickHouse JDBC 0.9.8：异步同步 3 行，`BIGINT`、`DECIMAL`、`STRING` 核对一致。
- `make test-eventlog`：ODS/DWD/DWS/ADS 为 5/3/2/2 行；13 个执行、350 条去重事件，
  `failed=0`、`without_plan=0`。

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
**修复**: 移除 `yarn.nodemanager.aux-services=spark_shuffle` 配置及对应 Dockerfile 下载步骤。集群迁移到 Spark Connect 后启用了动态分配，但采用 driver 端的 `spark.dynamicAllocation.shuffleTracking.enabled=true`（而非外部 Shuffle Service），因此 NodeManager 仍无需 `spark_shuffle` aux-service。

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

## ✅ 遗留问题 3（已解决）：`spark/` 下的 Hadoop 配置文件是手动静态副本

### 现状（历史）
`spark/{core,hdfs,yarn,mapred}-site.xml` 均是从 `hadoop/` 手动复制的静态副本。修改 Hadoop 侧配置后 Spark 侧不会自动同步，曾造成漂移（`hadoop/yarn-site.xml` 加了 `yarn.resourcemanager.bind-host=0.0.0.0` 但 `spark/` 侧漏了）。

### 修复（2026-06-26，采用方案 A）
`hadoop/` 定为唯一权威源。Makefile 新增 `sync-conf` target，在 `build` 前用 `cp hadoop/* → spark/*` 同步 `SHARED_CONF`（core/hdfs/yarn/mapred-site.xml），把 `spark/` 这四个文件钉成**生成物**——只改 `hadoop/` 侧、重新 build 即可，勿手改 `spark/`。`spark/hive-site.xml` 为 Spark 专属、不在同步范围。已执行一次 `make sync-conf`，四个文件现与 `hadoop/` 字节一致。

> 未采用方案 B（多阶段构建）/ 方案 C（共享 volume）：方案 A 改动最小、零运行期依赖，且 `spark/` 仍保留在 git 中作为快照与漂移告警信号。

---

## 🟡 遗留问题 4：`hive.server2.enable.doAs=false` 的安全影响

### 现状
关闭 `doAs` 后，所有通过 Thrift Server 执行的查询都以 `spark` 服务用户身份运行，不区分 beeline 连接用户。这在开发环境中是可接受的，但生产环境需要用户级隔离。

### 如需启用 `doAs`
1. 需要为每个 beeline 用户创建 Kerberos principal 并分发 keytab
2. 或使用 Kerberos Proxy User 机制：确保 `spark` 用户可以 impersonate 其他用户
3. 对应 `core-site.xml` 中已有 `hadoop.proxyuser.spark.{hosts,groups}=*` 配置，但可能需要额外的 MetaStore 端配置

---

## 版本升级（2026-06-30）：Spark 4.1.2 + Hive 4.1.0 + Hadoop 3.5.0（全栈 JDK 17）

> 从 Spark 3.5.3 / Hive 3.1.3 / Hadoop 3.4.1（JDK 8/11 混合）升级到全栈 JDK 17。
> 通过 `down -v` 全新重建（测试数据已授权清空），端到端验证通过。

### 升级矩阵
| 组件 | 旧 | 新 | 关键变化 |
|---|---|---|---|
| Hadoop | 3.4.1 (JDK8) | 3.5.0 (JDK17) | 3.5 起服务端强制 JDK 17 |
| Hive MS | 3.1.3 (JDK8) | 4.1.0 (JDK17) | 4.1 起强制 JDK 17 |
| Spark | 3.5.3 (JDK11, Scala2.12) | 4.1.2 (JDK17, Scala2.13) | Connect **内置**，不再 `--packages`/Ivy |
| mysql 驱动 | mysql-connector-java 8.0.28 | mysql-connector-j 9.1.0 | 旧坐标已废弃 |
| ClickHouse JDBC | 0.4.6 | 0.4.6（保留） | uber-jar JDK8 字节码在 JDK17 运行正常；升级 0.8.x 为后续 TODO |

### ✅ 升级问题 1：JDK 17 + Hadoop 守护进程 InaccessibleObjectException
**根因**: JDK 17 模块系统封装 `java.base` 内部包，Hadoop UGI/NIO/security 反射访问被拒。
**修复**: `hadoop/Dockerfile` 设 `ENV HADOOP_OPTS` 注入一组 `--add-opens`/`--add-exports`（java.lang/io/net/nio/util/sun.nio.ch/sun.security.* 等）。Hadoop 3.5 的 hadoop-env 是 append 模式，安全。Spark 侧由 launcher 的 `JavaModuleOptions` 自动注入，无需手加。

### ✅ 升级问题 2（核心坑）：Spark 内置 Hive 2.3.10 客户端无法连 Hive 4.1.0 HMS
**现象**: `org.apache.thrift.TApplicationException: Invalid method name: 'get_table'`。
**根因**: Spark 4.1 内置 metastore 客户端是 Hive **2.3.10**，调用 Thrift 方法 `get_table`；Hive 4.x 已移除该方法（改用 `get_table_req`）。旧客户端打新 HMS 直接失败。
**修复**: 把 Hive 4.1.0 的客户端 jar 烤进 Spark 镜像，用隔离类加载器加载——
- `spark/Dockerfile`: 全局 ARG + `FROM ${HIVE_METASTORE_IMAGE} AS hive-libs`，`COPY --from=hive-libs /opt/hive/lib /opt/hive-metastore-libs`（复用已构建的 hive 镜像，零二次下载；BuildKit 不支持 `COPY --from=${VAR}`，必须用具名 stage）。
- `spark/spark-defaults.conf`: `spark.sql.hive.metastore.version=4.1.0` + `jars=path` + `jars.path=file:///opt/hive-metastore-libs/*.jar`（无运行期 Maven/Ivy 下载）。Spark 4.x 经 SPARK-45265 支持 4.x metastore 版本。
- 构建顺序：spark 依赖 hive 镜像，Makefile 改为先 hive-metastore 再 spark-connect（不再并行）。

### ✅ 升级问题 3：Spark 4.x ANSI SQL 默认开启
**影响**: 溢出/除零/非法 cast 由返回 NULL 变为抛错，可能改变 `scq` 既有查询结果。
**处理**: 升级期间先设 `spark.sql.ansi.enabled=false` 保持 3.5 语义，避免把 SQL 语义变更和基础设施升级耦合在一起。**2026-06-30 验证后已切回 Spark 4 默认 `true`**：实测良构查询行为不变，仅坏操作 fail-loud（`DIVIDE_BY_ZERO` / `CAST_INVALID_INPUT`，如 `CAST('abc' AS INT)` / `ARITHMETIC_OVERFLOW`）。需要宽松语义的查询可用 `try_cast`/`try_divide`，或按会话 `SET spark.sql.ansi.enabled=false`（已验证 per-session 仍可覆盖）。

### 镜像与下载源
- Hadoop URL 由 dlcdn 改 huaweicloud（dlcdn 只留各线最新版，会 404）。
- 环境只能访问 huaweicloud 镜像，**不能直连 pypi.org**：pip 需 `-i https://mirrors.huaweicloud.com/repository/pypi/simple/`。
- PyPI 无 `pyspark-client`/`pyspark==4.1.2`（直连失败误导），实际用 `pyspark[connect]==4.1.2` 经 huaweicloud 镜像可装。

### 验证（全部通过）
- 6 服务全 healthy，0 僵尸进程（tini）。
- Kerberos delegation token 在 JDK17 下正常签发（HDFS_DELEGATION_TOKEN）。
- `make test`（local 模式）：Hive 4.1.0 HMS 建库建表插查删，Kerberos SASL 通。
- Spark Connect gRPC 端到端（pyspark 4.1.2 客户端 → sc://15002 → YARN executor → HDFS → HMS）：SHOW DATABASES / INSERT / 聚合 / range filter 全部正确。

### 客户端侧后续（未做，本次只升 spark-hive-dock 服务端）
`scq`（spark-connect-cli）的 pyspark 3.5.8 与 4.1.2 服务端协议不匹配，需升到 4.1.x 并重建 mcp-chat。详见 memory [[spark-connect-cli]]。

---

## Iceberg 表格式验证（2026-06-30）：基础读写往返 + HiveCatalog

> 目标：在新栈（Spark 4.1.2 / Hive 4.1.0 HMS）上验证 Iceberg 基础建表/插入/查询，catalog 用 HiveCatalog（复用现有 HMS）。**结论：✅ 通，但需绕过一个 Iceberg↔Hive4 的已知坑。**

### ⚠️ 坑：Iceberg HiveCatalog 不认 `spark.sql.hive.metastore.jars`，撞同样的 `get_table`
**现象**: `CREATE TABLE ... USING iceberg` 报 `TApplicationException: Invalid method name: 'get_table'`。
**根因**: 与升级问题 2 同源，但**修复方式不同**。Spark 自己的 `spark_catalog` 用 IsolatedClientLoader 读 `metastore.jars=path`（4.1.0），所以没事；但 Iceberg 的 `HiveCatalog` 是直接 `new HiveMetaStoreClient()`，从**主 classpath** 取类——主 classpath 上是 Spark 自带的 Hive **2.3.10**（`$SPARK_HOME/jars/hive-metastore-2.3.10.jar`），它调已被 Hive 4.x 删除的 `get_table`。Iceberg **不读** `spark.sql.hive.metastore.jars`。这是上游已知问题（apache/iceberg #13572 / #13628）。
**修复**: `spark-defaults.conf` 用 `spark.driver.extraClassPath` 把已烤进镜像的 Hive 4.1.0 metastore client jar 预置到主 classpath 之前——
```
spark.driver.extraClassPath /opt/hive-metastore-libs/hive-metastore-4.1.0.jar:/opt/hive-metastore-libs/hive-standalone-metastore-common-4.1.0.jar
```
这样 Iceberg 解析到 4.1.0 的 HiveMetaStoreClient（走 `get_table_req`）。**已验证不影响 `spark_catalog`**（它走隔离 4.1.0 loader，与主 classpath 无关；常规 Hive 表 + scq 查询路径回归通过）。

### 镜像改动
- `spark/Dockerfile`: 下载 `iceberg-spark-runtime-4.1_2.13:1.11.0`（首个支持 Spark 4.1/Scala2.13 的 Iceberg 线）进 `$SPARK_HOME/jars/`（随 YARN 分发到 executor）。
- `spark-defaults.conf`: 注册 `iceberg` catalog（`SparkCatalog` + `type=hive` + HMS uri/warehouse）+ `IcebergSparkSessionExtensions` + 上面的 extraClassPath 预置。

### 验证（通过）
- 本地模式：`spark_catalog` 常规表（2 行/和 30）与 `iceberg` 表（建库建表插查删）同会话并存，均正确。
- Spark Connect gRPC 端到端：`iceberg.icedb.orders` 建表/插 3 行/聚合（count=3, sumqty=16）/`ORDER BY` 读出/读 `.snapshots` 元数据表（1 个快照，证明确为 Iceberg 格式）/删表删库；常规 `spark_catalog` 路径无回归。

### 未覆盖（本次只验证「基础读写往返」）
time travel / schema evolution / hidden partitioning / row-level MERGE·DELETE（MoR）均未测；复杂操作可能需要预置更多 4.1.0 client 类（当前只预置了 2 个 jar，够基础读写）。Hive 4 自带的 Iceberg **REST Catalog**（`hive-standalone-metastore-rest-catalog-4.1.0.jar`）是另一条可选路径，可绕开 Thrift 老客户端问题，未采用。

---

## ClickHouse JDBC 驱动升级（2026-06-30）：0.4.6 → 0.7.2（sync 在新栈上修复）

> 升级后实测 `scq sync`（Hive→ClickHouse）失败，定位到老驱动在 JDK17/Spark4.1 上挂了。

### 现象与定位
- 旧 0.4.6：JDBC 批量写报 `BatchUpdateException: Unknown error 1002`（catch-all，无可用嵌套 cause）。
- **不是端点/网络问题**：`chsql`（另一 CH 客户端）打同一个公网端点 `clickhouse.dengshu.ovh:443`（Cloudflare 前置 HTTPS，非内网 host；集群从 datanode/spark-connect 可达）正常返回。是 **clickhouse-jdbc 0.4.6 在 JDK17/Spark4.1 上的问题**。

### 修复
`spark/Dockerfile` 把 `CLICKHOUSE_JDBC_VERSION` 0.4.6 → **0.7.2**（`-all` 经校验是完整 uber jar：含 `com.clickhouse.client.ClickHouseClient` SPI 类 + 其 `META-INF/services` 注册 + driver；ClickHouse 官方 Spark 文档用的就是 0.7.2）。换驱动后写入直接拿到结构化 CH 响应（`Code: 60 UNKNOWN_TABLE`），证明驱动通了。⚠️ 勿用 0.6.x `-all`（缺 SPI）。

### sync 正确用法（已验证）
Spark 的通用 JDBC dialect **不会**可靠地给你 auto-create 一个像样的 MergeTree（`--order-by` 的 createTableOptions 不一定生效；sync.py docstring 本就警告这点）。正确路径 = **先在 CH 建好目标表，再 `scq sync ... append`**。实测：预建 `MergeTree ORDER BY id` 后 sync 5 行 → CH 校验 `count=5, sum(amt)=17.5` ✓。

### 客户端版本
[mcp-chat](mcp-chat) 已重建为 `spark-connect-cli==0.3.0`（pyspark 4.1.2），sync 经其异步 job 子系统跑通。详见 memory [[spark-connect-cli]]。

---

## 当前配置架构

```
Spark Connect client (sc://:15002)
  → Spark Connect Server (principal=spark/_HOST, YARN client mode, dynamic allocation 0–3 executors)
    → YARN ResourceManager (:8032, on namenode container)
      → YARN NodeManager (on datanode container, runs Spark Executors)
    → Hive MetaStore (:9083, SASL GSSAPI, principal=hive/_HOST)
      → HDFS NameNode (:9000, Kerberos RPC, principal=hdfs/_HOST)
        → HDFS DataNode (SASL auth, principal=hdfs/_HOST)
```

所有 `_HOST` 均从各自 URI 中提取 FQDN（`.hive-net` 后缀）进行展开。
