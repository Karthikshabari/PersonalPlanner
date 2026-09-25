import { spawnSync } from "node:child_process";
import { describe, expect, it } from "vitest";
import { SCHEMA_VERIFICATION_SQL } from "../src/migrations";

const container = process.env.PP_LOCAL_POSTGRES_CONTAINER;
const sql = SCHEMA_VERIFICATION_SQL.trim().replace(/;$/u, "");

function inspect(database: string): Record<string, boolean> {
  const query = `begin read only;
select pg_catalog.row_to_json(result) from (${sql}) result;
rollback;`;
  const result = spawnSync("podman", [
    "exec", "-i", container!, "psql", "-h", "127.0.0.1",
    "-U", "supabase_read_only_user", "-d", database,
    "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
  ], { input: query, encoding: "utf8" });
  expect(result.status, result.stderr).toBe(0);
  const row = result.stdout.split("\n").find(line => line.startsWith("{"));
  expect(row, result.stdout).toBeDefined();
  return JSON.parse(row!) as Record<string, boolean>;
}

describe.skipIf(!container)("real PostgreSQL read-only metadata verification", () => {
  it("matches apply_sync_operation by the exact catalog argument types", () => {
    const query = `select pg_catalog.array_to_json(pg_catalog.array_agg(t.typname::pg_catalog.text order by a.ordinality))
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
cross join lateral pg_catalog.unnest(p.proargtypes::pg_catalog.oid[]) with ordinality as a(type_oid, ordinality)
join pg_catalog.pg_type t on t.oid = a.type_oid
where n.nspname = 'public' and p.proname = 'apply_sync_operation'`;
    const result = spawnSync("podman", [
      "exec", container!, "psql", "-h", "127.0.0.1", "-U", "supabase_read_only_user",
      "-d", "postgres", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", query,
    ], { encoding: "utf8" });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout.trim())).toEqual([
      "uuid", "text", "text", "text", "int8", "jsonb",
    ]);
    expect(SCHEMA_VERIFICATION_SQL).toContain(
      "('apply_sync_operation', array['uuid','text','text','text','int8','jsonb'])",
    );
  });

  it("inspects all six canonical migrations without EXECUTE on Planner RPCs", () => {
    const result = spawnSync("podman", [
      "exec", container!, "psql", "-U", "postgres", "-d", "postgres", "-X", "-A", "-t",
      "-v", "ON_ERROR_STOP=1", "-c",
      "select pg_catalog.has_function_privilege('supabase_read_only_user', p.oid, 'EXECUTE') from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'planner_sync_capabilities'",
    ], { encoding: "utf8" });
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe("f");
    const row = inspect("postgres");
    expect(Object.values(row).every(value => value === true), JSON.stringify(row)).toBe(true);
  });

  it("classifies an unrelated database with missing Planner objects as incompatible", () => {
    const row = inspect("template1");
    expect(row.required_tables_exist).toBe(false);
    expect(row.required_rpcs_exist).toBe(false);
    expect(row.capability_payload_current).toBe(false);
  });
});
