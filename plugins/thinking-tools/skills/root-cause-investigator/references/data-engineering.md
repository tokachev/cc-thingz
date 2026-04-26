# Data Engineering Root Cause Patterns

Patterns specific to ETL/ELT pipelines, data warehouses, streaming systems, and orchestrators. Use alongside `patterns.md` when the issue involves data, jobs, or pipelines rather than application code.

## Data Quality Issues

### Schema Drift
- **Symptoms**: Job fails on parse, silent NULLs in new columns, type cast errors
- **Investigation**: Diff producer schema between runs, check column order/types, inspect raw payload sample
- **Root causes**: Upstream added/renamed/retyped a column without contract; consumer reads by position instead of name; Avro/Protobuf schema registry drift

### Null/Duplicate Spikes
- **Symptoms**: Row counts diverge from baseline, dashboards show gaps or doubled metrics
- **Investigation**: Compare row counts and null ratios per partition vs prior runs; check unique-key violations
- **Root causes**: Source returns partial data on retry; upstream join cardinality changed; non-idempotent merge; missing dedup window

### Late / Out-of-Order Data
- **Symptoms**: Daily totals shift after the fact, "missing" events that arrive next day
- **Investigation**: Check event_time vs ingest_time gap, watermark/lateness config
- **Root causes**: Upstream batching delays, timezone mismatch between producer and consumer, fixed-window aggregation without grace period

### Timezone / Date Boundary Bugs
- **Symptoms**: Counts off by ~1 day boundary, double-counted or missing rows at midnight
- **Investigation**: Check session timezone, `current_date()` vs `current_timestamp()`, partition column type (date vs timestamp vs string)
- **Root causes**: Mixing UTC and local; warehouse session TZ differs from job TZ; DST transitions; string-formatted dates compared lexically

### Silent Type Coercion
- **Symptoms**: Aggregates wrong but no error, IDs collide, decimals truncated
- **Investigation**: `DESCRIBE` / `INFORMATION_SCHEMA.COLUMNS`, sample raw vs typed values
- **Root causes**: int → string → int round-trip loses leading zeros; float aggregation loses precision; implicit cast in JOIN keys

## Orchestration & Pipeline Issues

### Non-Idempotent Retries
- **Symptoms**: Duplicates after a retried task, partial writes, off-by-one on backfill
- **Investigation**: Check whether task uses INSERT vs MERGE/overwrite; inspect partition write mode; look for side effects outside the transaction
- **Root causes**: Append-only logic in a retried task; external API call before DB commit; missing `replace_where` / `overwrite` on partition

### Stuck / Skipped Tasks
- **Symptoms**: Task stays queued, never runs, or marked success with no output
- **Investigation**: Scheduler logs, executor pool/slot saturation, sensor timeout, trigger rule
- **Root causes**: Pool exhausted; sensor `poke_interval` × `timeout` exceeded; `trigger_rule` (e.g. `all_success`) blocked by upstream skip; `depends_on_past` waiting on stuck prior run

### Wrong Logical Date / Backfill
- **Symptoms**: Backfill writes to wrong partition; "today" data lands in yesterday's slot
- **Investigation**: Print `logical_date` / `data_interval_start` inside task; verify partition expression uses interval, not `now()`
- **Root causes**: Code uses wallclock (`datetime.now()`) instead of execution context; partition column derived at write time, not from interval

### DAG Parsing / Import Failures
- **Symptoms**: DAG missing from UI, "broken DAG" banner, scheduler CPU spike
- **Investigation**: Run DAG file directly, check top-level imports, time `import` of heavy modules
- **Root causes**: Network/DB call at import time; circular import; missing dep in scheduler image but present in worker image

## Warehouse & SQL Issues

### Query Plan Regression
- **Symptoms**: Same query suddenly 10× slower, no code change
- **Investigation**: `EXPLAIN` / query profile, compare plan hash, check stats freshness, last `ANALYZE`
- **Root causes**: Stale statistics after large load; data volume crossed optimizer threshold; new index changed plan; clustering keys eroded

### Join Cardinality Explosion
- **Symptoms**: Output row count >> expected, memory spill, query timeout
- **Investigation**: Count distinct keys on each side, look for missing dedup before join, check for fanout from 1:N becoming N:M
- **Root causes**: Duplicates in dimension table; wrong join keys; missing `qualify row_number()` filter

### Partition Pruning Not Working
- **Symptoms**: Full-table scan despite WHERE on partition column
- **Investigation**: Query profile / scan bytes, check predicate type matches partition type, look for functions on partition column
- **Root causes**: `WHERE date(ts) = '...'` on `ts`-partitioned table (function disables pruning); type mismatch (string filter on date partition); predicate pushdown blocked by subquery

### dbt Incremental Drift
- **Symptoms**: Incremental model rows don't match full-refresh; duplicates after model change
- **Investigation**: Check `unique_key`, `is_incremental()` branch, `on_schema_change` setting; compare full-refresh vs incremental output
- **Root causes**: `unique_key` not actually unique; logic differs between initial and incremental branch; `merge` columns missing after schema change

## Storage & File Format Issues

### Small-Files Problem
- **Symptoms**: Slow reads, listing-bound queries, metadata service throttled
- **Investigation**: Count files per partition, average file size, check writer parallelism
- **Root causes**: Streaming writer with short trigger; over-partitioned table; no compaction job

### Stale / Corrupt Stats in Parquet/ORC
- **Symptoms**: Predicate pushdown returns wrong rows, min/max filters miss data
- **Investigation**: Inspect file footer (`parquet-tools meta`), check writer version
- **Root causes**: Writer bug (specific Spark/library version); mixed-version writers in same table; stats disabled

### Eventual Consistency / List-After-Write
- **Symptoms**: Just-written file not visible to reader; downstream sees partial partition
- **Investigation**: Check object store guarantees, look for list-then-read patterns, manifest commit logs
- **Root causes**: Direct `LIST` on S3 prefix instead of using table format manifest (Iceberg/Delta/Hudi); cross-region replication lag

### Format Version Mismatch
- **Symptoms**: Reader fails on new files, "unsupported encoding"
- **Investigation**: `parquet-tools` / `orc-tools` to print writer version; check reader library version
- **Root causes**: Writer upgraded (e.g. Parquet v2 / DELTA_BINARY_PACKED) before all readers; Iceberg/Delta protocol bump

## Streaming Issues

### Consumer Lag / Backpressure
- **Symptoms**: Lag growing, end-to-end latency rising, downstream stale
- **Investigation**: `kafka-consumer-groups --describe`, per-partition lag, processing time per batch
- **Root causes**: Skewed partition keys; slow downstream sink; insufficient parallelism; GC pauses

### At-Least-Once Duplicates
- **Symptoms**: Same event processed twice after restart or rebalance
- **Investigation**: Check ordering of sink-write vs offset-commit; inspect rebalance logs around restart; look for in-flight batches at shutdown; check whether sink is idempotent
- **Root causes**: Sink write succeeded but offset commit didn't (process crash, rebalance, or `auto.commit.interval.ms` hadn't fired) → message redelivered on resume; rebalance reassigns partition mid-batch and new owner re-reads from last committed offset; sink not idempotent and no exactly-once / transactional sink connector
- **Note on direction**: Committing offset *before* sink ack causes the *opposite* problem — data loss, not duplicates (offset advances, then crash loses the unwritten record). Duplicates come from committing *after* (or failing to commit) the side effect.

### Watermark Stalled
- **Symptoms**: Windowed aggregations never fire; output frozen
- **Investigation**: Check watermark per source partition; look for idle partitions
- **Root causes**: One idle partition holds back global watermark; event-time extractor returns null/stale; allowed lateness too large

## Spark / Distributed Compute Issues

### Data Skew
- **Symptoms**: One task runs forever while others finish in seconds; one executor OOMs
- **Investigation**: Spark UI stage detail — task duration distribution, shuffle read size per task
- **Root causes**: Hot key in join/groupBy (one value dominates); should use salting, broadcast, or skew-join hint

### Wrong Join Strategy
- **Symptoms**: Shuffle of huge table, slow join
- **Investigation**: Spark UI SQL tab — physical plan; check broadcast threshold and table stats
- **Root causes**: Broadcast didn't trigger because stats missing → SortMergeJoin instead of BroadcastHashJoin; `ANALYZE TABLE` never run

### Executor OOM / Spill
- **Symptoms**: Containers killed, "OutOfMemoryError", excessive shuffle spill
- **Investigation**: Spark UI executor metrics, spill bytes, peak execution memory
- **Root causes**: Too few partitions (each too large); `collect()` to driver; UDF holds state; cached DataFrame larger than memory

## Lineage & Contract Issues

### Upstream Semantic Change
- **Symptoms**: Numbers shift but nothing failed; column "means something else now"
- **Investigation**: Lineage graph (dbt docs / OpenLineage / Marquez); check upstream changelog; diff sample values across run boundary
- **Root causes**: Producer changed business definition without versioning; column renamed in ETL but downstream still reads old meaning

### Missing Data Contract
- **Symptoms**: Repeated incidents from same upstream source; "we didn't know they changed it"
- **Investigation**: Check whether source has schema registry / contract test; look at incident history grouped by source
- **Root causes**: No producer-side validation; consumer not subscribed to schema changes; informal coupling via shared table

## Data Engineering Investigation Commands

```bash
# dbt
dbt run --select state:modified+ --defer --state path/to/prod-manifest
dbt test --select <model>
dbt show --inline "select count(*), count(distinct id) from {{ ref('x') }}"
dbt ls --select <model> --output json   # lineage / config

# Airflow
airflow tasks test <dag_id> <task_id> <logical_date>
airflow dags list-import-errors
airflow tasks states-for-dag-run <dag_id> <run_id>

# Kafka
kafka-consumer-groups --bootstrap-server <b> --describe --group <g>
kafka-topics --describe --topic <t>
kafka-console-consumer --topic <t> --from-beginning --max-messages 5

# Spark (after job)
# Spark UI: stages → sort by duration, executors → sort by spill
# History server: /api/v1/applications/<id>/stages

# Parquet / Iceberg / Delta
parquet-tools meta <file>
parquet-tools rowcount <path>
# Iceberg: SELECT * FROM db.tbl.snapshots / .files / .history
# Delta:   DESCRIBE HISTORY db.tbl

# Warehouse meta (BigQuery / Snowflake / Redshift)
# BQ:        INFORMATION_SCHEMA.JOBS_BY_PROJECT, region-*.INFORMATION_SCHEMA.TABLE_STORAGE
# Snowflake: QUERY_HISTORY, TABLE_STORAGE_METRICS, ACCESS_HISTORY
# Redshift:  STL_QUERY, SVL_QUERY_SUMMARY, SVV_TABLE_INFO

# Row count / null sanity per partition
# (run in warehouse SQL)
# SELECT partition_col, COUNT(*), COUNT(DISTINCT key), SUM(CASE WHEN col IS NULL THEN 1 ELSE 0 END)
# FROM tbl WHERE partition_col BETWEEN ... GROUP BY 1 ORDER BY 1;
```

## Multiple Perspective Analysis (DE-specific)

### Data
- Schema, types, nullability, cardinality
- Volume vs baseline, distribution, skew
- Freshness (event_time vs ingest_time vs now)

### Pipeline / Orchestration
- Idempotency of each task
- Trigger rules, retries, SLA
- Logical date vs wallclock usage

### Compute / Query
- Plan regression, stats freshness
- Skew, partition pruning, join strategy
- Resource limits (slots, executors, memory)

### Storage
- File count and size distribution
- Format version, stats validity
- Table format manifest vs raw listing

### Contracts / Lineage
- Producer/consumer schema agreement
- Upstream semantic versioning
- Cross-team ownership boundary
