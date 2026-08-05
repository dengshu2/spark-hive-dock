# ============================================================
# spark-hive-dock Makefile (Kerberized + YARN)
#
# Handles build-time dependency: hive-metastore FROM hadoop-base
# Usage:
#   make build   — build all images in correct order
#   make up      — build + start all services
#   make down    — stop and remove containers
#   make clean   — stop, remove containers, volumes, and images
#   make test    — run smoke test via spark-sql (local mode)
#   make test-eventlog — validate ODS -> DWD -> DWS -> ADS log ingestion
#   make kinit   — verify Kerberos tickets on all services
#   make logs    — follow all service logs
#   make status  — show service health status
# ============================================================

# bash (not sh) so recipes can use `set -o pipefail` — without it a pipeline's
# exit code is the last command's, letting docker-exec failures vanish behind
# `| tail`.
SHELL := /bin/bash

.PHONY: build up down clean test test-eventlog eventlog-status kinit logs status restart sync-conf

# -- Config sync -----------------------------------------
# hadoop/ is the single source of truth for the shared HDFS/YARN/MapReduce/core
# configs. spark/ needs verbatim copies so the Spark Connect client agrees with
# the cluster; without this they drift (e.g. RM bind-host added to hadoop/ but
# not spark/). These spark/ files are GENERATED — edit hadoop/ and re-run build,
# don't hand-edit spark/{core,hdfs,yarn,mapred}-site.xml. spark/hive-site.xml is
# Spark-specific and intentionally NOT synced.
SHARED_CONF := core-site.xml hdfs-site.xml yarn-site.xml mapred-site.xml

sync-conf:
	@echo "=== Syncing shared Hadoop conf: hadoop/ -> spark/ ==="
	@for f in $(SHARED_CONF); do \
		cp hadoop/$$f spark/$$f && echo "  synced $$f"; \
	done

# -- Build -----------------------------------------------
# Step 0: sync shared Hadoop conf into spark/ (prevents config drift)
# Step 1: kdc (no dependencies)
# Step 2: hadoop-base (no dependencies, includes YARN)
# Step 3: hive-metastore (FROM hadoop-base)
# Step 4: spark (COPY --from hive-metastore for the 4.1.0 client jars, so it
#         must be built AFTER hive-metastore — not in parallel)
# Step 5: event log collector (small Python layer on top of the Spark image)
build: sync-conf
	@echo "=== [1/5] Building KDC ==="
	docker compose build kdc
	@echo "=== [2/5] Building hadoop-base (HDFS + YARN) ==="
	docker compose build namenode
	@echo "=== [3/5] Building hive-metastore ==="
	docker compose build hive-metastore
	@echo "=== [4/5] Building spark (uses hive-metastore jars) ==="
	docker compose build spark-connect
	@echo "=== [5/5] Building Spark Event Log collector ==="
	docker compose build spark-eventlog-collector

# -- Lifecycle -------------------------------------------
up: build
	docker compose up -d
	@echo "Waiting for services ..."
	@$(MAKE) --no-print-directory _wait

down:
	docker compose down

clean:
	docker compose down -v --rmi local

restart: down up

# -- Observability ---------------------------------------
logs:
	docker compose logs -f

status:
	@docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'

# -- Kerberos Verification --------------------------------
kinit:
	@echo "=== Kerberos Ticket Status ==="
	@echo "--- KDC ---"
	@set -o pipefail; docker exec kdc kadmin.local -q "listprincs" 2>/dev/null | head -20 || echo "No principals (KDC not reachable)"
	@echo ""
	@echo "--- NameNode (HDFS + YARN RM) ---"
	@docker exec namenode klist 2>/dev/null || echo "No ticket"
	@echo ""
	@echo "--- DataNode (HDFS + YARN NM) ---"
	@docker exec datanode klist 2>/dev/null || echo "No ticket"
	@echo ""
	@echo "--- Hive Metastore ---"
	@docker exec hive-metastore klist 2>/dev/null || echo "No ticket"
	@echo ""
	@echo "--- Spark Connect ---"
	@docker exec spark-connect klist 2>/dev/null || echo "No ticket"
	@echo ""
	@echo "--- Spark History Server ---"
	@docker exec spark-history klist 2>/dev/null || echo "No ticket"
	@echo ""
	@echo "--- Spark Event Log Collector ---"
	@docker exec spark-eventlog-collector klist 2>/dev/null || echo "No ticket"

# -- YARN Status ------------------------------------------
yarn-status:
	@echo "=== YARN Cluster Status ==="
	@docker exec namenode yarn node -list 2>/dev/null || echo "ResourceManager not ready"
	@echo ""
	@docker exec namenode yarn application -list 2>/dev/null || echo "No applications"

# -- Smoke Test ------------------------------------------
# Uses spark-sql in local mode (talks directly to the Hive Metastore over
# Kerberos SASL — no YARN app, no Connect client needed).
test:
	@echo "=== Smoke Test: spark-sql local mode (Kerberos) ==="
	@set -o pipefail; docker exec spark-connect bash -lc "\
		kinit -kt /etc/security/keytabs/spark.keytab spark/spark-connect.hive-net@EXAMPLE.COM && \
		/opt/spark/bin/spark-sql --master 'local[*]' \
		-e \"CREATE DATABASE IF NOT EXISTS smoke_test; \
		    USE smoke_test; \
		    CREATE TABLE IF NOT EXISTS t1 (id INT, name STRING); \
		    INSERT INTO t1 VALUES (1, 'hello'), (2, 'world'); \
		    SELECT * FROM t1; \
		    DROP TABLE t1; \
		    DROP DATABASE smoke_test;\"" \
		2>&1 | tail -20 \
		|| { echo "=== Smoke test FAILED ==="; exit 1; }
	@echo "=== Smoke test passed ==="

# Runs an isolated ODS -> DWD -> DWS -> ADS workload through Spark Connect,
# then waits for the Collector and validates SQL/plan completeness and
# event-key uniqueness in ClickHouse.
test-eventlog:
	@command -v uv >/dev/null || { echo "ERROR: uv is required"; exit 1; }
	@command -v chsql >/dev/null || { echo "ERROR: chsql login is required"; exit 1; }
	uv run --with "pyspark[connect]==4.1.3" scripts/test-eventlog-warehouse.py

eventlog-status:
	@docker compose ps spark-history spark-eventlog-collector
	@chsql query --format table "\
		SELECT count() AS raw_rows, uniqExact(event_key) AS unique_events, \
		       max(collected_at) AS last_collected_at \
		FROM spark_observability.sql_events"
	@chsql query --format table "\
		SELECT count() AS executions, countIf(status = 'RUNNING') AS running, \
		       countIf(status = 'FAILED') AS failed \
		FROM spark_observability.sql_executions"

# -- Internal helpers ------------------------------------
# Waits until every service defined in docker-compose.yml reports (healthy).
# EXPECTED comes from `docker compose config --services` (not `ps`, which
# omits crashed containers and would shrink the target). Fails loudly on
# timeout instead of letting `make up` pretend everything came up.
_wait:
	@EXPECTED=$$(docker compose config --services | wc -l); \
	if [ "$$EXPECTED" -eq 0 ]; then \
		echo "ERROR: docker compose config failed — cannot determine expected service count"; \
		exit 1; \
	fi; \
	for i in $$(seq 1 40); do \
		HEALTHY=$$(docker compose ps --format '{{.Status}}' 2>/dev/null | grep -c "(healthy)"); \
		printf "\r  Healthy: %s/%s" "$$HEALTHY" "$$EXPECTED"; \
		if [ "$$HEALTHY" -ge "$$EXPECTED" ]; then \
			printf "\n"; $(MAKE) --no-print-directory status; exit 0; \
		fi; \
		sleep 10; \
	done; \
	printf "\n"; \
	echo "ERROR: not all services became healthy within the wait window:"; \
	$(MAKE) --no-print-directory status; \
	exit 1
