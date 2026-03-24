# ============================================================
# spark-hive-dock Makefile
#
# Handles build-time dependency: hive-metastore FROM hadoop-base
# Usage:
#   make build   — build all images in correct order
#   make up      — build + start all services
#   make down    — stop and remove containers
#   make clean   — stop, remove containers, volumes, and images
#   make test    — run smoke test against Spark Thrift Server
#   make logs    — follow all service logs
#   make status  — show service health status
# ============================================================

.PHONY: build up down clean test logs status restart

# -- Build -----------------------------------------------
# Step 1: hadoop-base (no dependencies)
# Step 2: hive-metastore (FROM hadoop-base) + spark (independent)
build:
	@echo "=== [1/2] Building hadoop-base ==="
	docker compose build namenode
	@echo "=== [2/2] Building hive-metastore + spark (parallel) ==="
	docker compose build hive-metastore spark-master

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

# -- Smoke Test ------------------------------------------
test:
	@echo "=== Smoke Test: Spark SQL via Thrift ==="
	@docker exec spark-master /opt/spark/bin/beeline \
		-u "jdbc:hive2://localhost:10000" -n spark \
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
