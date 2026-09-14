#!/usr/bin/env bash
set -Eeuo pipefail

# Static regression coverage for the staging assertions in release_gate.sh.
# Live Supabase behavior is intentionally covered only by the opt-in staging
# gate; this test prevents the known composite-key and ownership regressions.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${REPO_ROOT}/tool/release_gate.sh"
TAGS_TABLE="${REPO_ROOT}/lib/core/database/tables/tags_table.dart"

expected_tables=(
  tasks
  categories
  subtasks
  tags
  task_tags
  recurring_rules
  task_templates
  daily_reviews
  weekly_reviews
  timer_sessions
  day_contexts
)

table_loop="$(sed -n '/for table in /,/done/p' "$GATE")"
for table in "${expected_tables[@]}"; do
  rg -q "(^|[[:space:]])${table}([[:space:];]|$)" <<<"$table_loop" || {
    printf 'Missing staging table in RLS loop: %s\n' "$table" >&2
    exit 1
  }
done

rg -q "task_tags\) printf 'task_id,tag_id'" "$GATE" || {
  printf 'task_tags must use its composite task_id,tag_id projection\n' >&2
  exit 1
}
rg -q 'select_columns="\$\(staging_select_columns "\$table"\)"' "$GATE" || {
  printf 'The staging RLS loop must resolve a projection for each table\n' >&2
  exit 1
}
rg -q 'select=\$\{select_columns\}' "$GATE" || {
  printf 'The staging RLS request must use the resolved table projection\n' >&2
  exit 1
}

if rg -q 'rest/v1/\$table\?user_id=eq\.\$alpha_id&select=id&limit=1' "$GATE"; then
  printf 'The staging RLS loop still uses the invalid universal id projection\n' >&2
  exit 1
fi

rg -q 'alpha_direct_payload=' "$GATE" || {
  printf 'The direct cross-account insert must include an explicit ownership payload\n' >&2
  exit 1
}

rg -q '1b22bd8eb9eb9a52a2d9405ba30093d8125816bb7107f11fed6f404230f4369b' "$GATE" || {
  printf 'The deployed sync-v1 migration checksum is not pinned\n' >&2
  exit 1
}
rg -q 'b38c4617cfbf0ccb49db0f5c0a0a32a6b8cafab6147af2a0e20f85073b2b1083' "$GATE" || {
  printf 'The deployed sync-v1-hardening migration checksum is not pinned\n' >&2
  exit 1
}
rg -q '\$payload \+ \{user_id:\$user\}' "$GATE" || {
  printf 'The direct cross-account insert must identify Alpha as the attempted owner\n' >&2
  exit 1
}
rg -q -- '--data "\$alpha_direct_payload"' "$GATE" || {
  printf 'The direct cross-account insert is not using its ownership payload\n' >&2
  exit 1
}

rg -q 'run_check prereq_android_device_state|run_check prereq_adb_device_state' "$GATE" || {
  printf 'Android infrastructure probes must be classified as prerequisites\n' >&2
  exit 1
}
rg -q 'blocked_check android_native_behavior_manual' "$GATE" || {
  printf 'The device gate must remain blocked until native behavior is manually verified\n' >&2
  exit 1
}

rg -q 'Set<Column> get primaryKey => \{taskId, tagId\}' "$TAGS_TABLE" || {
  printf 'The regression fixture no longer matches the task_tags composite key\n' >&2
  exit 1
}

printf 'release_gate staging regression: PASS (11 tables, composite task_tags projection, owned direct DML)\n'
