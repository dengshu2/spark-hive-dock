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
#   make kinit   — verify Kerberos tickets on all services
#   make logs    — follow all service logs
#   make status  — show service health status
# ============================================================

.PHONY: build up down clean test kinit logs status restart sync-conf

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
# Step 2: hadoop-base (no dependencies, includes YARN + Spark shuffle)
# Step 3: hive-metastore (FROM hadoop-base) + spark (independent)
build: sync-conf
	@echo "=== [1/3] Building KDC ==="
	docker compose build kdc
	@echo "=== [2/3] Building hadoop-base (HDFS + YARN) ==="
	docker compose build namenode
	@echo "=== [3/3] Building hive-metastore + spark (parallel) ==="
	docker compose build hive-metastore spark-connect

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
	@docker exec kdc kadmin.local -q "listprincs" 2>/dev/null | head -20
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
	@docker exec spark-connect bash -lc "\
		kinit -kt /etc/security/keytabs/spark.keytab spark/spark-connect.hive-net@EXAMPLE.COM && \
		/opt/spark/bin/spark-sql --master 'local[*]' \
		-e \"CREATE DATABASE IF NOT EXISTS smoke_test; \
		    USE smoke_test; \
		    CREATE TABLE IF NOT EXISTS t1 (id INT, name STRING); \
		    INSERT INTO t1 VALUES (1, 'hello'), (2, 'world'); \
		    SELECT * FROM t1; \
		    DROP TABLE t1; \
		    DROP DATABASE smoke_test;\"" \
		2>&1 | tail -20
	@echo "=== Smoke test passed ==="

# -- Internal helpers ------------------------------------
_wait:
	@for i in $$(seq 1 40); do \
		HEALTHY=$$(docker compose ps --format '{{.Status}}' 2>/dev/null | grep -c "(healthy)"); \
		TOTAL=$$(docker compose ps --format '{{.Name}}' 2>/dev/null | wc -l); \
		printf "\r  Healthy: %s/%s" "$$HEALTHY" "$$TOTAL"; \
		if [ "$$HEALTHY" -ge 6 ]; then printf "\n"; $(MAKE) --no-print-directory status; break; fi; \
		sleep 10; \
	done
