# ============================================================
# spark-hive-dock Makefile (Kerberized + YARN)
#
# Handles build-time dependency: hive-metastore FROM hadoop-base
# Usage:
#   make build   — build all images in correct order
#   make up      — build + start all services
#   make down    — stop and remove containers
#   make clean   — stop, remove containers, volumes, and images
#   make test    — run smoke test against Spark Thrift Server
#   make kinit   — verify Kerberos tickets on all services
#   make logs    — follow all service logs
#   make status  — show service health status
# ============================================================

.PHONY: build up down clean test kinit logs status restart

# -- Build -----------------------------------------------
# Step 1: kdc (no dependencies)
# Step 2: hadoop-base (no dependencies, includes YARN + Spark shuffle)
# Step 3: hive-metastore (FROM hadoop-base) + spark (independent)
build:
	@echo "=== [1/3] Building KDC ==="
	docker compose build kdc
	@echo "=== [2/3] Building hadoop-base (HDFS + YARN) ==="
	docker compose build namenode
	@echo "=== [3/3] Building hive-metastore + spark (parallel) ==="
	docker compose build hive-metastore spark-thrift

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
	@echo "--- Spark Thrift ---"
	@docker exec spark-thrift klist 2>/dev/null || echo "No ticket"

# -- YARN Status ------------------------------------------
yarn-status:
	@echo "=== YARN Cluster Status ==="
	@docker exec namenode yarn node -list 2>/dev/null || echo "ResourceManager not ready"
	@echo ""
	@docker exec namenode yarn application -list 2>/dev/null || echo "No applications"

# -- Smoke Test ------------------------------------------
test:
	@echo "=== Smoke Test: Spark SQL via Thrift (YARN + Kerberos) ==="
	@docker exec spark-thrift /opt/spark/bin/beeline \
		-u "jdbc:hive2://spark-thrift.hive-net:10000/;principal=spark/spark-thrift.hive-net@EXAMPLE.COM" \
		-e "CREATE DATABASE IF NOT EXISTS smoke_test; \
		    USE smoke_test; \
		    CREATE TABLE IF NOT EXISTS t1 (id INT, name STRING); \
		    INSERT INTO t1 VALUES (1, 'hello'), (2, 'world'); \
		    SELECT * FROM t1; \
		    DROP TABLE t1; \
		    DROP DATABASE smoke_test;" \
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
