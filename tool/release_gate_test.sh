#!/usr/bin/env bash
set -Eeuo pipefail

# Regression coverage for release_gate.sh and its shared checks.
# Live Supabase behavior is intentionally covered only by the opt-in staging
# gate; this test prevents the known composite-key, ownership, migration-order,
# and secret-scan regressions.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${REPO_ROOT}/tool/release_gate.sh"
CHECKS="${REPO_ROOT}/tool/release_gate_checks.sh"
WORKER_MANIFEST="${REPO_ROOT}/provisioning_poc/src/index.ts"
TAGS_TABLE="${REPO_ROOT}/lib/core/database/tables/tags_table.dart"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

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

rg -q 'release_gate_checks\.sh" secret-scan' "$GATE" ||
  fail 'The gate must run the shared secret scan'
rg -q 'release_gate_checks\.sh" migration-order' "$GATE" ||
  fail 'The gate must run the shared migration check'
if rg -q -- '--scope --wait' "$GATE"; then
  fail 'systemd-run rejects --wait together with --scope on current systemd'
fi

# --- migration order ---

canonical_migrations=(
  20260827000000_sync_v1
  20260829000000_sync_v1_hardening
  20260910000000_real_use_v2
  20260915000000_recurrence_removal_provenance
  20260916000000_title_history_conflict_ordering
)

rg -q 'provisioning_poc/src/index\.ts' "$CHECKS" ||
  fail 'The migration check must derive its digests from the Worker manifest'
rg -q 'sha256sum --check' "$CHECKS" ||
  fail 'The migration check must verify migration digests'
for migration in "${canonical_migrations[@]}"; do
  rg -q "$migration" "$CHECKS" ||
    fail "The canonical migration is missing from the check: ${migration}"
done

bash "$CHECKS" migration-order "$REPO_ROOT" >/dev/null ||
  fail 'The migration check rejected the canonical migration history'

migration_fixture="${WORK_DIR}/migration-fixture"
mkdir -p "${migration_fixture}/supabase/migrations" "${migration_fixture}/provisioning_poc/src"
cp "${REPO_ROOT}"/supabase/migrations/*.sql "${migration_fixture}/supabase/migrations/"
cp "$WORKER_MANIFEST" "${migration_fixture}/provisioning_poc/src/index.ts"

bash "$CHECKS" migration-order "$migration_fixture" >/dev/null ||
  fail 'The migration check rejected an unmodified copy of the repository history'

drifted_migration="20260910000000_real_use_v2.sql"
printf -- '-- tampered\n' >>"${migration_fixture}/supabase/migrations/${drifted_migration}"
if bash "$CHECKS" migration-order "$migration_fixture" >/dev/null 2>&1; then
  fail 'The migration check accepted a migration whose contents drifted'
fi
cp "${REPO_ROOT}/supabase/migrations/${drifted_migration}" \
  "${migration_fixture}/supabase/migrations/${drifted_migration}"

missing_migration="20260829000000_sync_v1_hardening.sql"
mv "${migration_fixture}/supabase/migrations/${missing_migration}" "${WORK_DIR}/${missing_migration}"
if bash "$CHECKS" migration-order "$migration_fixture" >/dev/null 2>&1; then
  fail 'The migration check accepted a missing canonical migration'
fi
mv "${WORK_DIR}/${missing_migration}" "${migration_fixture}/supabase/migrations/${missing_migration}"

printf -- 'select 1;\n' >"${migration_fixture}/supabase/migrations/20260917000000_extra.sql"
if bash "$CHECKS" migration-order "$migration_fixture" >/dev/null 2>&1; then
  fail 'The migration check accepted an additional migration'
fi
rm "${migration_fixture}/supabase/migrations/20260917000000_extra.sql"

sed 's/d01e184c1c530e57a3bba20abf2fbf302a106f916be1196ee69736260f938c13/0000000000000000000000000000000000000000000000000000000000000000/' \
  "$WORKER_MANIFEST" >"${migration_fixture}/provisioning_poc/src/index.ts"
if bash "$CHECKS" migration-order "$migration_fixture" >/dev/null 2>&1; then
  fail 'The migration check accepted a Worker manifest with a drifted digest'
fi

# --- secret scan ---
#
# The placeholder literals below are the intentional redaction/rejection
# fixtures used by the unit and Worker suites; the scan must not report them.
rg -q 'sb_secret_abcdefghijklmnopqrstuvwxyz' "$CHECKS" ||
  fail 'The documented placeholder fixtures are no longer recognized'

bash "$CHECKS" secret-scan "$REPO_ROOT" >/dev/null ||
  fail 'The secret scan reported a finding in the repository'

fixture_dir="${WORK_DIR}/fixtures"
mkdir -p "$fixture_dir"
{
  printf "const rejected = 'sb_secret_abcdefghijklmnopqrstuvwxyz';\n"
  printf "const rejectedPrefix = 'sb_secret_abcdefghijklmnopqrst';\n"
  printf "const rejectedSuffixed = 'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789';\n"
  printf "const rejectedServiceRole = 'service_role_abcdefghijklmnopqrstuvwxyz';\n"
  printf "const rejectedJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature';\n"
} >"${fixture_dir}/redaction_fixtures.dart"

bash "$CHECKS" secret-scan "$fixture_dir" >/dev/null ||
  fail 'The secret scan reported an intentional placeholder fixture'

# These values are assembled at run time so this repository never contains a
# contiguous secret-shaped literal, while the scan must still reject each one.
fake_token_a='9Qw8Er7Ty6Ui5Op4As3Df2Gh1Jk2Lm'
fake_token_b='5Kd9Lm2Np7Qr4St6Uv8Wx0Yz3Ab6Cd'
fake_token_c='hbGciOiJIUzI1NiJ9Qw8Er7Ty6Ui5'
fake_secret="sb_secret_${fake_token_a}"
fake_service_role="service_role_${fake_token_b}"
fake_jwt="eyJ${fake_token_c}."

check_detected() {
  local label="$1" directory="$2"
  if bash "$CHECKS" secret-scan "$directory" >/dev/null 2>&1; then
    fail "The secret scan accepted ${label}"
  fi
}

mkdir -p "${WORK_DIR}/leak-secret" "${WORK_DIR}/leak-service-role" \
  "${WORK_DIR}/leak-jwt" "${WORK_DIR}/fixture-mixed"
printf 'const key = "%s";\n' "$fake_secret" >"${WORK_DIR}/leak-secret/leak.dart"
printf 'const key = "%s";\n' "$fake_service_role" >"${WORK_DIR}/leak-service-role/leak.dart"
printf 'const token = "%s";\n' "$fake_jwt" >"${WORK_DIR}/leak-jwt/leak.dart"
printf 'details: "sb_secret_abcdefghijklmnopqrstuvwxyz" leaked: "%s"\n' \
  "$fake_secret" >"${WORK_DIR}/fixture-mixed/leak.dart"

check_detected 'a secret-shaped value' "${WORK_DIR}/leak-secret"
check_detected 'a service-role-shaped value' "${WORK_DIR}/leak-service-role"
check_detected 'a JWT-shaped value' "${WORK_DIR}/leak-jwt"
check_detected 'a secret-shaped value next to a placeholder fixture' "${WORK_DIR}/fixture-mixed"
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

printf 'release_gate regression: PASS (11 tables, composite task_tags projection, owned direct DML, 5 canonical migrations, placeholder-aware secret scan)\n'
