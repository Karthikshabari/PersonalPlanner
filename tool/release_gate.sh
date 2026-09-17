#!/usr/bin/env bash
set -Eeuo pipefail

# Release-gate automation for Personal Planner.
#
# Safe defaults:
#   ./tool/release_gate.sh --local
#
# External checks are opt-in and staging-only:
#   RELEASE_GATE_ALLOW_STAGING=1 ./tool/release_gate.sh --all
#
# The script never uses a service-role key, never deletes remote data, and only
# addresses the explicitly supplied Android package/device.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR="${REPO_ROOT}/artifacts/release-gate/${RUN_ID}"

MODE="local"
case "${1:-local}" in
  --local|local) MODE="local" ;;
  --staging|--live|staging) MODE="staging" ;;
  --device|device) MODE="device" ;;
  --all|all) MODE="all" ;;
  --help|-h)
    sed -n '1,32p' "$0"
    printf '\nUsage: %s [--local|--staging|--device|--all]\n' "$0"
    exit 0
    ;;
  *) printf 'Unknown mode: %s\n' "$1" >&2; exit 64 ;;
esac

mkdir -p "${REPORT_DIR}"

declare -a CHECK_NAMES=()
declare -a CHECK_STATUSES=()
declare -a CHECK_LOGS=()
declare -a CHECK_SECONDS=()
OVERALL="PASS"
MEMORY_LIMIT_MODE="unavailable"

record_check() {
  local name="$1" status="$2" seconds="$3" log="$4"
  CHECK_NAMES+=("$name")
  CHECK_STATUSES+=("$status")
  CHECK_SECONDS+=("$seconds")
  CHECK_LOGS+=("$log")
  if [[ "$status" == "FAIL" ]]; then OVERALL="FAIL"; fi
  if [[ "$status" == "BLOCKED" && "$OVERALL" != "FAIL" ]]; then OVERALL="BLOCKED"; fi
}

run_check() {
  local name="$1"; shift
  local log="${REPORT_DIR}/${name}.log"
  local start end status seconds exit_code
  start="$(date +%s)"
  if "$@" >"$log" 2>&1; then
    status="PASS"
  else
    exit_code=$?
    if [[ "$exit_code" == 125 ]] || rg -qi \
      'read-only file system|flutter sdk cache|cannot write.*cache' "$log"; then
      status="BLOCKED"
    else
      status="FAIL"
    fi
  fi
  end="$(date +%s)"
  seconds=$((end - start))
  record_check "$name" "$status" "$seconds" "$(basename "$log")"
}

blocked_check() {
  local name="$1"; shift
  local log="${REPORT_DIR}/${name}.log"
  printf '%s\n' "$*" >"$log"
  record_check "$name" "BLOCKED" 0 "$(basename "$log")"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

write_report() {
  local md="${REPORT_DIR}/report.md" json="${REPORT_DIR}/report.json" i
  {
    printf '# Release gate %s\n\n' "$RUN_ID"
    printf '%s\n\n' "Overall: ${OVERALL}"
    printf 'Memory limiter: `%s`\n\n' "$MEMORY_LIMIT_MODE"
    printf 'Mode: `%s`\n\n' "$MODE"
    printf '| Check | Result | Seconds | Log |\n|---|---:|---:|---|\n'
    for i in "${!CHECK_NAMES[@]}"; do
      printf '| `%s` | **%s** | %s | [%s](%s) |\n' \
        "${CHECK_NAMES[$i]}" "${CHECK_STATUSES[$i]}" "${CHECK_SECONDS[$i]}" \
        "${CHECK_LOGS[$i]}" "${CHECK_LOGS[$i]}"
    done
  } >"$md"
  {
    printf '{"run_id":"%s","mode":"%s","overall":"%s","checks":[' \
      "$(json_escape "$RUN_ID")" "$(json_escape "$MODE")" "$OVERALL"
    for i in "${!CHECK_NAMES[@]}"; do
      [[ "$i" -gt 0 ]] && printf ','
      printf '{"name":"%s","status":"%s","seconds":%s,"log":"%s"}' \
        "$(json_escape "${CHECK_NAMES[$i]}")" "${CHECK_STATUSES[$i]}" \
        "${CHECK_SECONDS[$i]}" "$(json_escape "${CHECK_LOGS[$i]}")"
    done
    printf ']}\n'
  } >"$json"
}

on_exit() {
  write_report || true
  printf 'Release gate: %s\nReport: %s\n' "$OVERALL" "$REPORT_DIR"
}
trap on_exit EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1
}

assert_no_project_processes() {
  local leftovers attempt
  for attempt in 1 2 3 4 5; do
    leftovers="$(ps -eo pid=,comm=,args= | awk \
      -v root="$REPO_ROOT" '$2 == "flutter_tester" && $0 ~ root {print}')"
    # Gradle daemons are shared user services and may legitimately remain
    # alive after a build; they are not evidence of a project leak.
    if [[ -z "$leftovers" ]]; then return 0; fi
    sleep 2
  done
  printf '%s\n' "$leftovers"
  return 1
}

flutter_bin="${FLUTTER_BIN:-flutter}"
run_with_memory_limit() {
  local limit="$1"; shift
  if [[ "$MEMORY_LIMIT_MODE" != "systemd-cgroup" ]]; then
    printf 'Required memory cap %s is unavailable; command was not started.\n' \
      "$limit" >&2
    return 125
  fi
  # A scoped run stays in the foreground and already reports the wrapped
  # command's exit status, so `--wait` is unnecessary. Current systemd rejects
  # it ("--wait may not be combined with --scope", verified on systemd 259).
  systemd-run --user --scope --collect --quiet \
    --property="MemoryMax=${limit}" -- "$@"
}

memory_cap_available() {
  require_command systemd-run || return 1
  systemd-run --user --scope --collect --quiet \
    --property=MemoryMax=128M -- true >/dev/null 2>&1
}

local_checks() {
  run_check git_diff_check git -C "$REPO_ROOT" diff --check
  run_check cached_diff_check git -C "$REPO_ROOT" diff --cached --check
  run_check secret_scan bash "$REPO_ROOT/tool/release_gate_checks.sh" secret-scan "$REPO_ROOT"
  run_check migration_order bash "$REPO_ROOT/tool/release_gate_checks.sh" migration-order "$REPO_ROOT"
  run_check manifest_safety bash -c '
    rg -q "android:allowBackup=\"false\"" android/app/src/main/AndroidManifest.xml &&
    test -f android/app/src/main/res/xml/backup_rules.xml &&
    test -f android/app/src/main/res/xml/data_extraction_rules.xml
  '
  run_check flutter_analyze "$flutter_bin" analyze --no-pub
  run_check focused_tests run_with_memory_limit 4G "$flutter_bin" test test/widget/templates_crud_test.dart --no-pub --concurrency=1
  run_check full_tests run_with_memory_limit 4G "$flutter_bin" test --no-pub --concurrency=1 -r compact
  run_check linux_release_build run_with_memory_limit 6G "$flutter_bin" build linux --release
  run_check android_release_build run_with_memory_limit 6G "$flutter_bin" build apk --release
  run_check no_project_processes assert_no_project_processes
  run_check memory_snapshot bash -c 'free -h; ps -eo pid=,comm=,rss= | awk '\''$2 == "flutter_tester" || $2 == "dart" || $2 == "java" {print}'\'' || true'
}

select_memory_limit_mode() {
  case "${RELEASE_GATE_MEMORY_MODE:-auto}" in
    systemd)
      if ! memory_cap_available; then
        MEMORY_LIMIT_MODE="unavailable (systemd requested)"
        return
      fi
      MEMORY_LIMIT_MODE="systemd-cgroup"
      ;;
    auto)
      if memory_cap_available; then
        MEMORY_LIMIT_MODE="systemd-cgroup"
      else
        MEMORY_LIMIT_MODE="unavailable"
      fi
      ;;
    *)
      MEMORY_LIMIT_MODE="unavailable (invalid RELEASE_GATE_MEMORY_MODE)"
      ;;
  esac
}

staging_checks() {
  if [[ "${RELEASE_GATE_ALLOW_STAGING:-}" != "1" ]]; then
    blocked_check staging_opt_in 'Set RELEASE_GATE_ALLOW_STAGING=1 explicitly to enable disposable Supabase checks.'
    return
  fi
  local missing=()
  for variable in SUPABASE_TEST_URL SUPABASE_TEST_PROJECT_REF SUPABASE_TEST_PUBLISHABLE_KEY \
    SUPABASE_TEST_ALPHA_EMAIL SUPABASE_TEST_ALPHA_PASSWORD SUPABASE_TEST_BETA_EMAIL SUPABASE_TEST_BETA_PASSWORD; do
    [[ -n "${!variable:-}" ]] || missing+=("$variable")
  done
  if ((${#missing[@]})); then
    blocked_check staging_credentials "Missing staging-only variables: ${missing[*]}"
    return
  fi
  if ! require_command supabase; then
    blocked_check supabase_cli 'Supabase CLI is unavailable; no live project was contacted.'
    return
  fi
  if ! require_command curl || ! require_command jq; then
    blocked_check staging_http_tools 'curl and jq are required for token-free, publishable-key REST checks.'
    return
  fi

  run_check supabase_migration_list supabase migration list --project-ref "$SUPABASE_TEST_PROJECT_REF"
  run_check supabase_db_push supabase db push --project-ref "$SUPABASE_TEST_PROJECT_REF" --yes
  run_check supabase_migration_list_after supabase migration list --project-ref "$SUPABASE_TEST_PROJECT_REF"
  run_check staging_source_table_count bash -c '
    test "$(rg -c "^create table if not exists public\\.(tasks|categories|subtasks|tags|task_tags|recurring_rules|task_templates|daily_reviews|weekly_reviews|timer_sessions)" supabase/migrations/20260827000000_sync_v1.sql | awk -F: "{sum += \\$2} END {print sum+0}")" -eq 10
    test "$(rg -c "^create table if not exists public\\.day_contexts" supabase/migrations/20260910000000_real_use_v2.sql | awk -F: "{sum += \\$2} END {print sum+0}")" -eq 1
  '
  # The REST/RPC checks intentionally record only HTTP status and sanitized
  # assertions. Access/refresh tokens and response bodies never enter reports.
  run_check staging_rls_and_rpc bash -c '
    set -Eeuo pipefail
    base="${SUPABASE_TEST_URL%/}"
    header=(-H "apikey: ${SUPABASE_TEST_PUBLISHABLE_KEY}" -H "Content-Type: application/json")
    temp_dir="$(mktemp -d)"
    trap '\''rm -rf "$temp_dir"'\'' EXIT

    new_uuid() { cat /proc/sys/kernel/random/uuid; }

    login() {
      local output="$1" email="$2" password="$3" code
      code="$(curl --silent --show-error --output "$output" --write-out "%{http_code}" \
        -X POST "$base/auth/v1/token?grant_type=password" "${header[@]}" \
        --data "{\"email\":\"$email\",\"password\":\"$password\"}")"
      [[ "$code" == 200 ]] || {
        printf 'authentication_failed_http=%s\n' "$code"
        return 1
      }
      cat "$output"
    }

    request() {
      local output="$1"
      shift
      curl --silent --show-error --output "$output" --write-out "%{http_code}" "$@"
    }

    assert_empty_or_denied() {
      local code="$1" output="$2" label="$3" shape
      case "$code" in
        200|206)
          jq -e '\''type == "array" and length == 0'\'' "$output" >/dev/null || {
            shape="$(jq -r '\''type'\'' "$output" 2>/dev/null || printf invalid)"
            printf '%s_http=%s_body_shape=%s\n' "$label" "$code" "$shape"
            return 1
          }
          ;;
        401|403)
          ;;
        *)
          printf '%s_http=%s\n' "$label" "$code"
          return 1
          ;;
      esac
    }

    assert_no_mutation_result() {
      local code="$1" output="$2" label="$3" shape
      case "$code" in
        200|201|202|204)
          jq -e '\''type == "array" and length == 0'\'' "$output" >/dev/null || {
            shape="$(jq -r '\''type'\'' "$output" 2>/dev/null || printf invalid)"
            printf '%s_http=%s_body_shape=%s\n' "$label" "$code" "$shape"
            return 1
          }
          ;;
        400|401|403|404)
          ;;
        *)
          printf '%s_http=%s\n' "$label" "$code"
          return 1
          ;;
      esac
    }

    staging_select_columns() {
      case "$1" in
        task_tags) printf 'task_id,tag_id' ;;
        *) printf 'id' ;;
      esac
    }

    alpha="$(login "$temp_dir/alpha-login.json" "$SUPABASE_TEST_ALPHA_EMAIL" "$SUPABASE_TEST_ALPHA_PASSWORD")"
    beta="$(login "$temp_dir/beta-login.json" "$SUPABASE_TEST_BETA_EMAIL" "$SUPABASE_TEST_BETA_PASSWORD")"
    alpha_token="$(jq -er .access_token <<<"$alpha")"
    beta_token="$(jq -er .access_token <<<"$beta")"
    alpha_id="$(jq -er .user.id <<<"$alpha")"
    test "$alpha_id" != "null"

    alpha_category_id="$(new_uuid)"
    alpha_operation_id="$(new_uuid)"
    alpha_created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    alpha_payload="$(jq -nc \
      --arg id "$alpha_category_id" \
      --arg name "RG-${alpha_category_id}" \
      --arg created "$alpha_created_at" \
      '\''{id:$id,name:$name,color_hex:"#112233",sort_order:0,is_focus:0,created_at:$created}'\'')"
    alpha_rpc_body="$(jq -nc \
      --arg operation "$alpha_operation_id" \
      --arg record "$alpha_category_id" \
      --argjson payload "$alpha_payload" \
      '\''{p_operation_id:$operation,p_table_name:"categories",p_record_id:$record,p_operation:"insert",p_expected_server_version:null,p_payload:$payload}'\'')"
    alpha_create_code="$(request "$temp_dir/alpha-create.json" \
      -X POST "$base/rest/v1/rpc/apply_sync_operation" \
      "${header[@]}" -H "Authorization: Bearer $alpha_token" \
      --data "$alpha_rpc_body")"
    [[ "$alpha_create_code" == 200 ]] && \
      jq -e '\''.status == "applied"'\'' "$temp_dir/alpha-create.json" >/dev/null

    for table in tasks categories subtasks tags task_tags recurring_rules task_templates daily_reviews weekly_reviews timer_sessions day_contexts; do
      select_columns="$(staging_select_columns "$table")"
      code="$(request "$temp_dir/beta-${table}.json" \
        "$base/rest/v1/$table?user_id=eq.$alpha_id&select=${select_columns}&limit=1" \
        "${header[@]}" -H "Authorization: Bearer $beta_token")"
      assert_empty_or_denied "$code" "$temp_dir/beta-${table}.json" "beta_${table}"
    done

    alpha_direct_payload="$(jq -nc \
      --argjson payload "$alpha_payload" \
      --arg user "$alpha_id" \
      '\''$payload + {user_id:$user}'\'')"
    beta_post_code="$(request "$temp_dir/beta-post.json" \
      -X POST "$base/rest/v1/categories" "${header[@]}" \
      -H "Authorization: Bearer $beta_token" --data "$alpha_direct_payload")"
    assert_no_mutation_result "$beta_post_code" "$temp_dir/beta-post.json" beta_post

    beta_patch_code="$(request "$temp_dir/beta-patch.json" \
      -X PATCH "$base/rest/v1/categories?id=eq.$alpha_category_id" \
      "${header[@]}" -H "Authorization: Bearer $beta_token" \
      --data '\''{"name":"RG-forged"}'\'')"
    assert_no_mutation_result "$beta_patch_code" "$temp_dir/beta-patch.json" beta_patch

    beta_delete_code="$(request "$temp_dir/beta-delete.json" \
      -X DELETE "$base/rest/v1/categories?id=eq.$alpha_category_id" \
      "${header[@]}" -H "Authorization: Bearer $beta_token")"
    assert_no_mutation_result "$beta_delete_code" "$temp_dir/beta-delete.json" beta_delete

    forged_body="$(jq -nc \
      --arg operation "$(new_uuid)" \
      --arg record "$alpha_category_id" \
      --arg user "$alpha_id" \
      --argjson payload "$alpha_payload" \
      '\''{p_operation_id:$operation,p_table_name:"categories",p_record_id:$record,p_operation:"insert",p_expected_server_version:null,p_payload:($payload + {user_id:$user})}'\'')"
    forged_code="$(request "$temp_dir/forged-rpc.json" \
      -X POST "$base/rest/v1/rpc/apply_sync_operation" "${header[@]}" \
      -H "Authorization: Bearer $beta_token" --data "$forged_body")"
    [[ "$forged_code" -ge 400 && "$forged_code" -lt 500 ]]

    mismatch_body="$(jq -nc \
      --arg operation "$(new_uuid)" \
      --arg record "$(new_uuid)" \
      --argjson payload "$alpha_payload" \
      '\''{p_operation_id:$operation,p_table_name:"categories",p_record_id:$record,p_operation:"insert",p_expected_server_version:null,p_payload:$payload}'\'')"
    mismatch_code="$(request "$temp_dir/mismatch-rpc.json" \
      -X POST "$base/rest/v1/rpc/apply_sync_operation" "${header[@]}" \
      -H "Authorization: Bearer $beta_token" --data "$mismatch_body")"
    [[ "$mismatch_code" -ge 400 && "$mismatch_code" -lt 500 ]]

    alpha_check_code="$(request "$temp_dir/alpha-after.json" \
      "$base/rest/v1/categories?id=eq.$alpha_category_id&select=id,name&limit=1" \
      "${header[@]}" -H "Authorization: Bearer $alpha_token")"
    [[ "$alpha_check_code" == 200 || "$alpha_check_code" == 206 ]] &&
      jq -e --arg id "$alpha_category_id" \
        '\''type == "array" and length == 1 and .[0].id == $id and .[0].name == ("RG-" + $id)'\'' \
        "$temp_dir/alpha-after.json" >/dev/null

    printf "beta_rls_tables=11 direct_dml=denied-or-empty forged_rpc_http=%s identity_rpc_http=%s alpha_unchanged=true\n" \
      "$forged_code" "$mismatch_code"
  '
}

device_checks() {
  local adb_bin="${ADB_BIN:-adb}" package_id
  if [[ -z "${ANDROID_SERIAL:-}" ]]; then
    blocked_check android_serial 'ANDROID_SERIAL is required; refusing to select an arbitrary device.'
    return
  fi
  if ! require_command "$adb_bin"; then
    blocked_check adb_available "ADB is unavailable at ${adb_bin}."
    return
  fi
  package_id="$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' android/app/build.gradle.kts | head -n 1)"
  if [[ -z "$package_id" ]]; then
    blocked_check android_package_id 'Could not determine the Android application ID.'
    return
  fi
  run_check prereq_adb_device_state "$adb_bin" -s "$ANDROID_SERIAL" get-state
  run_check prereq_android_package_installed "$adb_bin" -s "$ANDROID_SERIAL" shell pm path "$package_id"
  run_check prereq_android_manifest_runtime "$adb_bin" -s "$ANDROID_SERIAL" shell dumpsys package "$package_id"
  run_check prereq_android_process_recovery "$adb_bin" -s "$ANDROID_SERIAL" shell am kill "$package_id"
  run_check prereq_android_log_snapshot bash -c '
    adb_bin="${ADB_BIN:-adb}"
    "$adb_bin" -s "$ANDROID_SERIAL" logcat -d -v threadtime | rg -i "personal_planner|AndroidRuntime|ForegroundService|notification" || true
  '
  run_check prereq_no_project_processes_after_android assert_no_project_processes
  blocked_check android_native_behavior_manual \
    'Physical reminder, foreground-timer, touch, reboot, and visual behavior require the manual Android release checklist.'
}

select_memory_limit_mode
local_checks
if [[ "$MODE" == "staging" || "$MODE" == "all" ]]; then staging_checks; fi
if [[ "$MODE" == "device" || "$MODE" == "all" ]]; then device_checks; fi

if [[ "$OVERALL" == "FAIL" ]]; then exit 1; fi
if [[ "$OVERALL" == "BLOCKED" ]]; then exit 2; fi
exit 0
