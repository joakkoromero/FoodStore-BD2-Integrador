"""Reproducible verification of U4 on the cumulative TP1--TP5 Food Store copy.

Python standard library + psql only. Run after restoring the inherited DB,
adding today's workload, and installing the U4 SQL. Functional tests roll back.
The concurrency test commits real changes, audits, then restores exact prices.
No SQL is executed when the module is imported.
"""

from __future__ import annotations

from decimal import Decimal
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time
import traceback


WORK = Path(__file__).resolve().parent
METRICS = WORK / "metrics.json"
PSQL = r"C:\Program Files\PostgreSQL\17\bin\psql.exe"
ARGS = [PSQL, "-h", "127.0.0.1", "-p", "55439", "-U", "tp_admin",
        "-d", "foodstore_u4_arancibia_romero", "-X", "-v", "ON_ERROR_STOP=1",
        "-q", "-A", "-t"]
ENV = os.environ.copy()
ENV.update(PGCLIENTENCODING="UTF8", PGCONNECT_TIMEOUT="10")
PREFIX = (
    "SET max_parallel_workers_per_gather=0; SET jit=off; "
    "SET default_transaction_isolation='read committed'; "
    "SET timezone='America/Argentina/Buenos_Aires'; "
)
LOCK_SQL = "DO $$ BEGIN PERFORM pg_advisory_xact_lock(204620,4); END $$;"
FROM_SOURCE = """
FROM public.detalle_pedido dp
JOIN public.producto pr ON pr.id=dp.producto_id
JOIN public.categoria c ON c.id=pr.categoria_id
JOIN public.pedido ped ON ped.id=dp.pedido_id
""".strip()
DAY_FILTER = """
ped.fecha >= CURRENT_DATE::timestamptz
AND ped.fecha < (CURRENT_DATE+1)::timestamptz AND ped.eliminado=FALSE
""".strip()
LOCAL_DAY = "(ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date"
ORIGINAL = f"""
SELECT c.nombre AS categoria,SUM(dp.subtotal) AS total_vendido
{FROM_SOURCE}
WHERE {DAY_FILTER}
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
""".strip()
MATERIALIZED = """
SELECT categoria,total_vendido
FROM public.mv_u4_ventas_categoria_dia
WHERE fecha=CURRENT_DATE
ORDER BY total_vendido DESC
LIMIT 5
""".strip()

AUDIT_CTE = f"""
WITH fuente AS (
    SELECT {LOCAL_DAY} AS fecha,c.nombre AS categoria,
           SUM(dp.subtotal) AS total_vendido
    {FROM_SOURCE}
    WHERE ped.eliminado=FALSE
    GROUP BY {LOCAL_DAY},c.nombre
), diferencias AS (
    SELECT 'fuente-mv' AS sentido,d.* FROM (
        SELECT * FROM fuente
        EXCEPT ALL
        SELECT fecha,categoria,total_vendido FROM public.mv_u4_ventas_categoria_dia
    ) d
    UNION ALL
    SELECT 'mv-fuente',d.* FROM (
        SELECT fecha,categoria,total_vendido FROM public.mv_u4_ventas_categoria_dia
        EXCEPT ALL SELECT * FROM fuente
    ) d
), totales AS (
    SELECT pedido_id,SUM(subtotal) AS total
    FROM public.detalle_pedido GROUP BY pedido_id
), totales_incorrectos AS (
    SELECT p.id,p.total AS almacenado,COALESCE(t.total,0) AS calculado
    FROM public.pedido p LEFT JOIN totales t ON t.pedido_id=p.id
    WHERE p.total IS DISTINCT FROM COALESCE(t.total,0::numeric)
), diario_fuente AS (
    SELECT c.nombre AS categoria,SUM(dp.subtotal) AS total_vendido
    {FROM_SOURCE} WHERE {DAY_FILTER}
    GROUP BY c.nombre
), diario_mv AS (
    SELECT categoria,total_vendido FROM public.mv_u4_ventas_categoria_dia
    WHERE fecha=CURRENT_DATE
), diario_diferencias AS (
    (SELECT * FROM diario_fuente EXCEPT ALL SELECT * FROM diario_mv)
    UNION ALL
    (SELECT * FROM diario_mv EXCEPT ALL SELECT * FROM diario_fuente)
)
SELECT json_build_object(
 'difference_count',(SELECT count(*) FROM diferencias),
 'source_groups',(SELECT count(*) FROM fuente),
 'materialized_groups',(SELECT count(*) FROM public.mv_u4_ventas_categoria_dia),
 'daily_difference_count',(SELECT count(*) FROM diario_diferencias),
 'incorrect_order_total_count',(SELECT count(*) FROM totales_incorrectos),
 'differences',COALESCE((SELECT json_agg(d) FROM diferencias d),'[]'::json),
 'incorrect_order_totals',COALESCE((SELECT json_agg(t) FROM totales_incorrectos t),'[]'::json)
)
""".strip()


def progress(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def run_raw(sql: str, timeout: float = 240) -> subprocess.CompletedProcess:
    completed = subprocess.run(
        ARGS+["-c", PREFIX+sql], env=ENV, capture_output=True, text=True,
        encoding="utf-8", errors="strict", timeout=timeout, check=False,
    )
    if completed.returncode:
        raise RuntimeError(f"psql failed ({completed.returncode})\n{completed.stderr}\nSQL:\n{sql}")
    return completed


def run_sql(sql: str) -> str:
    return run_raw(sql).stdout.strip()


def sql_json(sql: str):
    return json.loads(run_sql(sql))


def explain_json(query: str) -> dict:
    return sql_json(f"EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) {query};")[0]


def node_summary(node: dict, path: str = "root") -> list[dict]:
    loops = node.get("Actual Loops", 1)
    inclusive = node.get("Actual Total Time", 0)*loops
    children = node.get("Plans", [])
    own_time = inclusive-sum(c.get("Actual Total Time", 0)*c.get("Actual Loops", 1) for c in children)
    cost = node.get("Total Cost", 0)
    own_cost = cost-sum(c.get("Total Cost", 0) for c in children)
    rows = [{
        "path": path, "node_type": node["Node Type"],
        "relation": node.get("Relation Name"), "index": node.get("Index Name"),
        "estimated_total_cost": cost,
        "approximate_estimated_own_cost": round(max(0, own_cost), 6),
        "inclusive_time_ms": round(inclusive, 6),
        "approximate_exclusive_time_ms": round(max(0, own_time), 6),
        "actual_rows": node.get("Actual Rows"), "actual_loops": loops,
        "shared_hit_blocks": node.get("Shared Hit Blocks", 0),
        "shared_read_blocks": node.get("Shared Read Blocks", 0),
    }]
    for number, child in enumerate(children):
        rows.extend(node_summary(child, f"{path}/{number}"))
    return rows


def text_time(plan: str, label: str):
    match = re.search(re.escape(label)+r": ([0-9.]+) ms", plan)
    return float(match.group(1)) if match else None


def benchmark(label: str, query: str) -> dict:
    progress(f"Benchmark {label}: 1 warmup + 5 JSON repetitions")
    warmup = explain_json(query)
    plans = [explain_json(query) for _ in range(5)]
    times = [p["Execution Time"] for p in plans]
    median = statistics.median(times)
    chosen = min(range(5), key=lambda i: abs(times[i]-median))
    nodes = node_summary(plans[chosen]["Plan"])
    text_plan = run_sql(f"EXPLAIN (ANALYZE,BUFFERS,FORMAT TEXT) {query};")
    return {
        "query": query, "warmup_execution_time_ms": warmup["Execution Time"],
        "execution_times_ms": times, "median_execution_time_ms": median,
        "min_execution_time_ms": min(times), "max_execution_time_ms": max(times),
        "representative_run_index": chosen, "plan_json": plans[chosen],
        "plans_json": plans, "plan_text": text_plan,
        "plan_text_is_additional_evidence_execution": True,
        "plan_text_execution_time_ms": text_time(text_plan, "Execution Time"),
        "plan_text_planning_time_ms": text_time(text_plan, "Planning Time"),
        "nodes": nodes,
        "dominant_node_by_approximate_exclusive_time": max(nodes, key=lambda r: r["approximate_exclusive_time_ms"]),
        "dominant_node_by_approximate_estimated_own_cost": max(nodes, key=lambda r: r["approximate_estimated_own_cost"]),
        "dominance_method": "Approximate own time = inclusive time*loops minus children times*loops; own cost = total cost minus children total costs. Parallel execution disabled.",
    }


def top_five(query: str):
    return sql_json("SELECT COALESCE(json_agg(r),'[]'::json) FROM ("+query+") r;")


def audit(mutation: str = "") -> dict:
    return sql_json("BEGIN ISOLATION LEVEL READ COMMITTED; "+LOCK_SQL+" "+mutation+" "+AUDIT_CTE+"; ROLLBACK;")


def assert_clean(result: dict, label: str) -> None:
    assert result["difference_count"] == 0, (label, result)
    assert result["daily_difference_count"] == 0, (label, result)
    assert result["incorrect_order_total_count"] == 0, (label, result)
    assert result["source_groups"] == result["materialized_groups"], (label, result)


def frozen_hashes() -> dict:
    specs = [
        ("categoria", "id<=2", "id"),
        ("producto", "id<=50000", "id"),
        ("usuario", "id<=20000", "id"),
        ("pedido", "id<=200000", "id"),
        ("detalle_pedido", "pedido_id<=200000", "pedido_id,producto_id"),
    ]
    fields = []
    for table, where, ordering in specs:
        fields.append(
            f"'{table}',(SELECT json_build_object('count',count(*),'md5',"
            f"md5(string_agg(md5(row_to_json(t)::text),'' ORDER BY {ordering}))) "
            f"FROM public.{table} t WHERE {where})"
        )
    return sql_json("SELECT json_build_object("+",".join(fields)+");")


def test_lines() -> list[dict]:
    lines = sql_json("""
SELECT json_agg(r ORDER BY pedido_id) FROM (
 SELECT DISTINCT ON (d.pedido_id) d.pedido_id,d.producto_id,d.cantidad,
        d.precio_unitario::text AS precio_unitario,d.subtotal::text AS subtotal,
        p.estado::text AS estado,p.eliminado,
        (p.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date=CURRENT_DATE AS is_today
 FROM public.detalle_pedido d JOIN public.pedido p ON p.id=d.pedido_id
 WHERE d.pedido_id IN (200001,200002) AND d.cantidad=1
 ORDER BY d.pedido_id,d.producto_id
) r;
""")
    assert lines and [r["pedido_id"] for r in lines] == [200001, 200002], lines
    assert all(r["cantidad"] == 1 and r["estado"] == "PENDIENTE" and not r["eliminado"] and r["is_today"] for r in lines), lines
    return lines


def line_where(line: dict) -> str:
    return f"pedido_id={int(line['pedido_id'])} AND producto_id={int(line['producto_id'])}"


def measure_refresh(line: dict) -> dict:
    update = f"UPDATE public.detalle_pedido SET precio_unitario=precio_unitario WHERE {line_where(line)}"
    plan = sql_json("BEGIN ISOLATION LEVEL READ COMMITTED; "+f"EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) {update}; ROLLBACK;")[0]
    text_plan = run_sql("BEGIN ISOLATION LEVEL READ COMMITTED; "+f"EXPLAIN (ANALYZE,BUFFERS,FORMAT TEXT) {update}; ROLLBACK;")
    refresh = [t for t in plan.get("Triggers", []) if t.get("Trigger Name") == "ventas_refresco"]
    assert len(refresh) == 1 and refresh[0]["Calls"] == 1, plan
    return {
        "query": update,
        "execution_time_including_triggers_ms": plan["Execution Time"],
        "refresh_trigger_time_ms": refresh[0]["Time"],
        "refresh_trigger_calls": refresh[0]["Calls"],
        "plan_json": plan, "plan_text": text_plan,
        "plan_text_execution_time_ms": text_time(text_plan, "Execution Time"),
        "scope": "No-op unit-price UPDATE, rolled back; includes inherited total recalculation and one external full refresh. Nested pedido refresh is skipped.",
    }


def mutation_tests(line: dict) -> list[dict]:
    where = line_where(line)
    order_id = int(line["pedido_id"])
    product_id = int(line["producto_id"])
    cases = [
        ("unit_price", f"UPDATE public.detalle_pedido SET precio_unitario=precio_unitario+17.35 WHERE {where};", None),
        ("quantity", f"UPDATE public.detalle_pedido SET cantidad=cantidad+1 WHERE {where};", None),
        ("move_line_between_pending_orders", f"""DO $test$ DECLARE target_id bigint; BEGIN
 INSERT INTO public.pedido(usuario_id,fecha,forma_pago)
 SELECT usuario_id,fecha,forma_pago FROM public.pedido WHERE id={order_id}
 RETURNING id INTO target_id;
 UPDATE public.detalle_pedido SET pedido_id=target_id WHERE {where};
END $test$;""", None),
        ("soft_delete_order", f"UPDATE public.pedido SET eliminado=TRUE WHERE id={order_id};", None),
        ("restore_order", f"UPDATE public.pedido SET eliminado=TRUE WHERE id={order_id}; UPDATE public.pedido SET eliminado=FALSE WHERE id={order_id};", None),
        ("order_previous_day", f"UPDATE public.pedido SET fecha=fecha-interval '1 day' WHERE id={order_id};", None),
        ("order_midday_included", f"UPDATE public.pedido SET fecha=CURRENT_DATE::timestamptz+interval '12 hours 34 minutes 56 seconds' WHERE id={order_id};", None),
        ("order_next_midnight_excluded", f"UPDATE public.pedido SET fecha=(CURRENT_DATE+1)::timestamptz WHERE id={order_id};", None),
        ("product_category", f"UPDATE public.producto SET categoria_id=(SELECT id FROM public.categoria WHERE id<>public.producto.categoria_id ORDER BY id LIMIT 1) WHERE id={product_id};", None),
        ("rename_category_free_name", "UPDATE public.categoria SET nombre='U4_categoria_auditoria_temporal' WHERE id=1;", None),
        ("delete_pending_detail", f"DELETE FROM public.detalle_pedido WHERE {where};", None),
        ("insert_pending_detail", f"""INSERT INTO public.detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario)
 SELECT {order_id},p.id,1,123.45 FROM public.producto p
 WHERE NOT EXISTS (SELECT 1 FROM public.detalle_pedido d WHERE d.pedido_id={order_id} AND d.producto_id=p.id)
 ORDER BY p.id LIMIT 1;""", None),
        ("reject_duplicate_category_name", "UPDATE public.categoria SET nombre=(SELECT nombre FROM public.categoria WHERE id=2) WHERE id=1;", "23505"),
        ("reject_confirmed_detail_edit", "UPDATE public.detalle_pedido SET cantidad=cantidad+1 WHERE pedido_id=5 AND producto_id=1;", "23514"),
        ("reject_backwards_state_transition", "UPDATE public.pedido SET estado='PENDIENTE' WHERE id=1;", "23514"),
        ("reject_generated_subtotal_write", f"UPDATE public.detalle_pedido SET subtotal=0 WHERE {where};", "428C9"),
        ("reject_truncate_details", "TRUNCATE public.detalle_pedido;", "23514"),
        ("reject_truncate_orders_cascade", "TRUNCATE public.pedido CASCADE;", "23514"),
        ("reject_truncate_products_cascade", "TRUNCATE public.producto CASCADE;", "23514"),
        ("reject_truncate_categories_cascade", "TRUNCATE public.categoria CASCADE;", "23514"),
    ]
    results = []
    for label, sql, expected in cases:
        progress(f"Functional check: {label}")
        mutation = sql
        if expected:
            mutation = f"""DO $negative$ BEGIN
 BEGIN
  {sql}
  RAISE EXCEPTION 'Expected SQLSTATE {expected} was not raised' USING ERRCODE='P0001';
 EXCEPTION WHEN SQLSTATE '{expected}' THEN
  RAISE NOTICE 'U4_EXPECTED_SQLSTATE={expected} test={label}';
 END;
END $negative$;"""
        started = time.perf_counter()
        completed = run_raw("BEGIN ISOLATION LEVEL READ COMMITTED; "+LOCK_SQL+" "+mutation+" "+AUDIT_CTE+"; ROLLBACK;")
        result = json.loads(completed.stdout.strip())
        assert_clean(result, label)
        if expected:
            assert f"U4_EXPECTED_SQLSTATE={expected}" in completed.stderr, completed.stderr
        results.append({
            "name": label, "sql": sql, "audit": result,
            "expected_sqlstate": expected, "expected_rejection_observed": bool(expected),
            "notices": [s for s in completed.stderr.splitlines() if "U4_EXPECTED_SQLSTATE" in s],
            "rolled_back": True, "wall_time_ms": round((time.perf_counter()-started)*1000, 3),
        })
    return results


def recursion_check(order_id: int) -> dict:
    progress("Checking inherited nested-trigger refresh suppression")
    expected_lines = sql_json(f"SELECT to_json(count(*)) FROM public.detalle_pedido WHERE pedido_id={order_id};")
    sql = f"UPDATE public.detalle_pedido SET precio_unitario=precio_unitario+0.01 WHERE pedido_id={order_id};"
    completed = run_raw("SET client_min_messages=debug1; BEGIN ISOLATION LEVEL READ COMMITTED; "+LOCK_SQL+" "+sql+" "+AUDIT_CTE+"; ROLLBACK;")
    result = json.loads(completed.stdout.strip())
    assert_clean(result, "nested refresh suppression")
    messages = [s for s in completed.stderr.splitlines() if "U4_REFRESH_" in s]
    skipped = [s for s in messages if "U4_REFRESH_SKIPPED table=pedido depth=2" in s]
    executed = [s for s in messages if "U4_REFRESH_EXECUTED table=detalle_pedido depth=1" in s]
    assert len(skipped) == expected_lines, (expected_lines, messages)
    assert len(executed) == 1 and len(messages) == expected_lines+1, messages
    return {"sql": sql, "modified_lines": expected_lines, "nested_refreshes_skipped": len(skipped),
            "external_refreshes_executed": len(executed), "debug_messages": messages,
            "audit": result, "rolled_back": True}


def activity(application: str):
    assert application in {"tp_verify_writer_a", "tp_verify_writer_b"}
    return sql_json("SELECT COALESCE(json_agg(r),'[]'::json) FROM (SELECT pid,state,wait_event_type,wait_event FROM pg_stat_activity WHERE application_name='"+application+"') r;")


def writer(application: str, line: dict, delta: Decimal, pause: bool):
    sql = PREFIX+f"SET application_name='{application}'; BEGIN ISOLATION LEVEL READ COMMITTED; "
    sql += f"UPDATE public.detalle_pedido SET precio_unitario=precio_unitario+{delta} WHERE {line_where(line)}; "
    sql += ("SELECT pg_sleep(2); " if pause else "")+"COMMIT;"
    return subprocess.Popen(ARGS+["-c", sql], env=ENV, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="strict")


def concurrency_state(lines: list[dict]) -> dict:
    predicates = " OR ".join("("+line_where(line)+")" for line in lines)
    return sql_json(f"""
SELECT json_build_object(
 'details',(SELECT json_agg(r ORDER BY pedido_id,producto_id) FROM (
   SELECT pedido_id,producto_id,cantidad,precio_unitario::text AS precio_unitario,subtotal::text AS subtotal
   FROM public.detalle_pedido WHERE {predicates}) r),
 'materialized_total_today',(SELECT COALESCE(SUM(total_vendido),0)::text FROM public.mv_u4_ventas_categoria_dia WHERE fecha=CURRENT_DATE),
 'source_total_today',(SELECT COALESCE(SUM(dp.subtotal),0)::text {FROM_SOURCE} WHERE {DAY_FILTER})
);
""")


def concurrency_test(lines: list[dict]) -> dict:
    progress("Concurrency: real +11.11/+22.22 prices, audit before exact restoration")
    assert len(lines) == 2 and all(line["cantidad"] == 1 for line in lines), lines
    baseline = concurrency_state(lines)
    baseline_total = Decimal(baseline["materialized_total_today"])
    assert baseline_total == Decimal(baseline["source_total_today"]), baseline
    prices = {r["pedido_id"]: Decimal(r["precio_unitario"]) for r in baseline["details"]}
    subtotals = {r["pedido_id"]: Decimal(r["subtotal"]) for r in baseline["details"]}
    deltas = {200001: Decimal("11.11"), 200002: Decimal("22.22")}
    expected_delta = Decimal("33.33")
    result = {"baseline": baseline, "changes": [
        {"pedido_id": line["pedido_id"], "producto_id": line["producto_id"],
         "cantidad": 1, "precio_unitario_delta": str(deltas[line["pedido_id"]])}
        for line in lines], "expected_total_today_delta": str(expected_delta)}
    first = second = None
    try:
        first = writer("tp_verify_writer_a", lines[0], deltas[200001], True)
        observed_a = []
        deadline = time.monotonic()+25
        while time.monotonic() < deadline:
            observed_a = activity("tp_verify_writer_a")
            if any(r.get("wait_event") == "PgSleep" for r in observed_a):
                break
            if first.poll() is not None:
                out, err = first.communicate()
                raise AssertionError(("Writer A ended before PgSleep", out, err))
            time.sleep(0.03)
        else:
            raise AssertionError("Writer A PgSleep not observed")
        started_b = time.perf_counter()
        second = writer("tp_verify_writer_b", lines[1], deltas[200002], False)
        observed_b = []
        deadline = time.monotonic()+1.5
        while time.monotonic() < deadline:
            observed_b = activity("tp_verify_writer_b")
            if any(r.get("wait_event_type") == "Lock" and r.get("wait_event") == "advisory" for r in observed_b):
                break
            if second.poll() is not None:
                break
            time.sleep(0.03)
        assert any(r.get("wait_event_type") == "Lock" and r.get("wait_event") == "advisory" for r in observed_b), observed_b
        out_a, err_a = first.communicate(timeout=180)
        out_b, err_b = second.communicate(timeout=180)
        elapsed_b = (time.perf_counter()-started_b)*1000
        assert first.returncode == 0, (out_a, err_a)
        assert second.returncode == 0, (out_b, err_b)
        before_restore = audit()
        assert_clean(before_restore, "real concurrency before restoration")
        committed = concurrency_state(lines)
        observed_delta = Decimal(committed["materialized_total_today"])-baseline_total
        source_delta = Decimal(committed["source_total_today"])-baseline_total
        assert observed_delta == expected_delta and source_delta == expected_delta, committed
        for row in committed["details"]:
            pid = row["pedido_id"]
            assert Decimal(row["precio_unitario"]) == prices[pid]+deltas[pid], row
            assert Decimal(row["subtotal"]) == subtotals[pid]+deltas[pid], row
        result.update({
            "writer_a_observed_during_sleep": observed_a,
            "writer_b_observed_waiting": observed_b,
            "writer_b_wall_time_ms": round(elapsed_b, 3),
            "writer_a_returncode": first.returncode, "writer_b_returncode": second.returncode,
            "audit_before_restore": before_restore, "audit_after_both_commits": before_restore,
            "committed_state_before_restore": committed,
            "observed_materialized_total_today_delta": str(observed_delta),
            "observed_source_total_today_delta": str(source_delta), "combined_delta_verified": True,
        })
    finally:
        for process in (first, second):
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate(timeout=10)
        restore = (
            "UPDATE public.detalle_pedido SET precio_unitario=CASE pedido_id "
            f"WHEN 200001 THEN {prices[200001]}::numeric WHEN 200002 THEN {prices[200002]}::numeric END "
            "WHERE "+" OR ".join("("+line_where(line)+")" for line in lines)+";"
        )
        restoration_audit = sql_json("BEGIN ISOLATION LEVEL READ COMMITTED; "+LOCK_SQL+" "+restore+" "+AUDIT_CTE+"; COMMIT;")
        assert_clean(restoration_audit, "concurrency restoration")
        restored = concurrency_state(lines)
        assert restored["details"] == baseline["details"], (baseline, restored)
        assert Decimal(restored["materialized_total_today"]) == baseline_total, restored
        assert Decimal(restored["source_total_today"]) == baseline_total, restored
        result["restoration"] = {"sql": restore, "audit": restoration_audit,
                                 "restored_state": restored, "baseline_restored": True, "committed": True}
    return result


def collect_metadata() -> dict:
    return sql_json("""
SELECT json_build_object(
 'version',version(),'server_version',current_setting('server_version'),
 'database',current_database(),'measurement_time',clock_timestamp(),
 'current_date',CURRENT_DATE,'timezone',current_setting('TimeZone'),
 'settings',json_build_object('max_parallel_workers_per_gather',current_setting('max_parallel_workers_per_gather'),
   'jit',current_setting('jit'),'work_mem',current_setting('work_mem'),'shared_buffers',current_setting('shared_buffers'),
   'transaction_isolation',current_setting('transaction_isolation')),
 'counts',json_build_object(
   'categoria',(SELECT count(*) FROM public.categoria),'producto',(SELECT count(*) FROM public.producto),
   'usuario',(SELECT count(*) FROM public.usuario),'pedido',(SELECT count(*) FROM public.pedido),
   'detalle_pedido',(SELECT count(*) FROM public.detalle_pedido),
   'legacy_pedido',(SELECT count(*) FROM public.pedido WHERE id<=200000),
   'legacy_detalle',(SELECT count(*) FROM public.detalle_pedido WHERE pedido_id<=200000),
   'new_pedido',(SELECT count(*) FROM public.pedido WHERE id>200000),
   'new_detalle',(SELECT count(*) FROM public.detalle_pedido WHERE pedido_id>200000),
   'materialized_groups',(SELECT count(*) FROM public.mv_u4_ventas_categoria_dia),
   'today_active_orders',(SELECT count(*) FROM public.pedido WHERE fecha>=CURRENT_DATE::timestamptz AND fecha<(CURRENT_DATE+1)::timestamptz AND NOT eliminado),
   'today_active_details',(SELECT count(*) FROM public.detalle_pedido d JOIN public.pedido p ON p.id=d.pedido_id WHERE p.fecha>=CURRENT_DATE::timestamptz AND p.fecha<(CURRENT_DATE+1)::timestamptz AND NOT p.eliminado)),
 'date_range',(SELECT json_build_object('min',min(fecha),'max',max(fecha),'distinct_local_days',count(DISTINCT (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)) FROM public.pedido),
 'sizes',(SELECT json_agg(r) FROM (SELECT relname,pg_relation_size(oid) AS heap_bytes,pg_total_relation_size(oid) AS total_bytes FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind IN ('r','m') ORDER BY relname) r),
 'legacy_indices',(SELECT json_agg(r) FROM (SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' AND indexname NOT LIKE '%u4%' ORDER BY indexname) r),
 'all_indices',(SELECT json_agg(r) FROM (SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY indexname) r),
 'source_triggers',(SELECT json_agg(r) FROM (SELECT c.relname AS table_name,t.tgname AS trigger_name,pg_get_triggerdef(t.oid) AS definition,t.tgenabled AS enabled FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace='public'::regnamespace AND NOT t.tgisinternal ORDER BY c.relname,t.tgname) r),
 'views',(SELECT json_agg(r) FROM (SELECT viewname,definition FROM pg_views WHERE schemaname='public' ORDER BY viewname) r),
 'materialized_views',(SELECT json_agg(r) FROM (SELECT matviewname,definition FROM pg_matviews WHERE schemaname='public' ORDER BY matviewname) r),
 'columns',(SELECT json_agg(r) FROM (SELECT table_name,column_name,data_type,is_nullable,is_generated,generation_expression FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('categoria','producto','usuario','pedido','detalle_pedido') ORDER BY table_name,ordinal_position) r),
 'u4_refresh_function',pg_get_functiondef('public.u4_refrescar_ventas()'::regprocedure)
);
""")


def main() -> None:
    metrics = {"status": "running", "method": {
        "engine": "PostgreSQL 17, psql subprocess, Python standard library",
        "data": "TP4 supplied dump + cumulative TP4/TP5 additions; prior rows retained; 25000 synthetic current-day orders and 100000 details added separately",
        "repetitions": 5, "warmups_per_query": 1,
        "cache": "Warm database cache, no cache flushing",
        "session_prefix_sql": PREFIX,
        "text_plan_capture": "One additional real EXPLAIN TEXT execution per query, outside the five measured JSON runs",
        "compatibility": "Inherited TIMESTAMPTZ uses local-day range; detail has generated subtotal, composite key and no soft-delete column; no state filter is added",
    }}
    try:
        progress("Capturing cumulative schema metadata and inherited frozen-row hashes")
        metrics["metadata"] = collect_metadata()
        assert metrics["metadata"]["database"] == "foodstore_u4_arancibia_romero"
        counts = metrics["metadata"]["counts"]
        assert counts["legacy_pedido"] == 200000 and counts["legacy_detalle"] == 399997, counts
        metrics["baseline_frozen_hashes"] = frozen_hashes()
        metrics["test_lines"] = lines = test_lines()
        metrics["initial_audit"] = audit()
        assert_clean(metrics["initial_audit"], "initial")
        metrics["before"] = benchmark("normalized daily query", ORIGINAL)
        metrics["after"] = benchmark("daily materialized query", MATERIALIZED)
        metrics["top5_original"] = top_five(ORIGINAL)
        metrics["top5_materialized"] = top_five(MATERIALIZED)
        assert metrics["top5_original"] == metrics["top5_materialized"], "Top 5 mismatch"
        metrics["top5_equal"] = True
        before = metrics["before"]["median_execution_time_ms"]
        after = metrics["after"]["median_execution_time_ms"]
        metrics["speedup_ratio_of_medians"] = before/after
        metrics["latency_reduction_percent"] = 100*(1-after/before)
        metrics["refresh_cost"] = measure_refresh(lines[0])
        metrics["mutation_tests"] = mutation_tests(lines[0])
        metrics["recursion_check"] = recursion_check(200001)
        metrics["concurrency_test"] = concurrency_test(lines)
        metrics["final_audit"] = audit()
        assert_clean(metrics["final_audit"], "final")
        metrics["top5_after_all_tests"] = top_five(ORIGINAL)
        assert metrics["top5_after_all_tests"] == metrics["top5_original"], "Fixture baseline changed"
        metrics["final_frozen_hashes"] = frozen_hashes()
        assert metrics["final_frozen_hashes"] == metrics["baseline_frozen_hashes"], "Inherited historical rows changed"
        metrics["historical_rows_preserved"] = True
        metrics["status"] = "passed"
    except BaseException as exc:
        metrics.update(status="failed", error=str(exc), traceback=traceback.format_exc())
        raise
    finally:
        METRICS.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
        progress(f"Saved {METRICS}; status={metrics['status']}")
    print(json.dumps({
        "status": metrics["status"],"median_before_ms": before,"median_after_ms": after,
        "speedup": metrics["speedup_ratio_of_medians"],
        "refresh_trigger_ms": metrics["refresh_cost"]["refresh_trigger_time_ms"],
        "functional_cases": len(metrics["mutation_tests"]),"recursion_check": metrics["recursion_check"],
        "concurrency_delta": metrics["concurrency_test"]["observed_materialized_total_today_delta"],
        "historical_rows_preserved": metrics["historical_rows_preserved"],"metrics_path": str(METRICS),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
