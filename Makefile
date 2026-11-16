# =====================================================================
# BookMyShow DBMS Project - Developer Automation Makefile
# Authors: Team T0132
# =====================================================================

DB_NAME ?= bms
RUNS ?= 3

.PHONY: help setup init-db load-data test apply-indexes benchmark-baseline benchmark-optimized benchmark-large visualize partition monitor clean

help:
	@echo "====================================================================="
	@echo "BookMyShow DBMS Project - Developer CLI"
	@echo "====================================================================="
	@echo "  make setup                Unpack seed dataset into seed_data/"
	@echo "  make init-db              Execute schema DDL (sql/01_schema.sql)"
	@echo "  make load-data            Ingest seed data (sql/02_load_data.sql)"
	@echo "  make test                 Run 10-point relational integrity test suite"
	@echo "  make apply-indexes        Deploy Phase 4 indexing strategy (sql/05_indexes.sql)"
	@echo "  make benchmark-baseline   Execute 30-query baseline benchmark"
	@echo "  make benchmark-optimized  Execute 30-query optimized benchmark"
	@echo "  make visualize            Display comparative terminal latency report"
	@echo "  make partition            Deploy declarative table partitioning (sql/08_partitioning.sql)"
	@echo "  make monitor              Inspect buffer cache, table bloat, and index usage"
	@echo "====================================================================="

setup:
	@echo "==> Unpacking seed dataset..."
	unzip -q seed_data.zip
	@echo "==> Setup complete."

init-db:
	@echo "==> Initializing schema bms on database $(DB_NAME)..."
	psql -d $(DB_NAME) -f sql/01_schema.sql

load-data:
	@echo "==> Ingesting seed data and running initial integrity checks..."
	psql -d $(DB_NAME) -f sql/02_load_data.sql

test:
	@echo "==> Executing automated relational integrity harness..."
	psql -d $(DB_NAME) -f tests/test_integrity.sql

apply-indexes:
	@echo "==> Deploying Phase 4 indexing strategy..."
	psql -d $(DB_NAME) -f sql/05_indexes.sql

benchmark-baseline:
	@echo "==> Running baseline benchmark (3 runs per query)..."
	./benchmarks/run_benchmark.sh $(DB_NAME) baseline $(RUNS)

benchmark-optimized:
	@echo "==> Running optimized benchmark (3 runs per query)..."
	./benchmarks/run_benchmark.sh $(DB_NAME) optimized $(RUNS) sql/06_optimized_queries.sql

visualize:
	@python3 benchmarks/benchmark_visualizer.py

partition:
	@echo "==> Deploying table partitioning architecture..."
	psql -d $(DB_NAME) -f sql/08_partitioning.sql

monitor:
	@echo "==> Buffer Cache Hit Ratio:"
	@psql -d $(DB_NAME) -c "SELECT * FROM bms.v_cache_hit_ratio LIMIT 10;"
	@echo "==> Table Bloat & Dead Tuples:"
	@psql -d $(DB_NAME) -c "SELECT * FROM bms.v_table_bloat LIMIT 10;"
	@echo "==> Index Utilization:"
	@psql -d $(DB_NAME) -c "SELECT * FROM bms.v_index_usage LIMIT 10;"

clean:
	@echo "==> Cleaning temporary benchmark artifacts..."
	rm -rf /tmp/bms_bench*
