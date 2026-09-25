#!/usr/bin/env bash
set -Eeuo pipefail

# Reusable checks for tool/release_gate.sh.
#
# They live in their own file so that tool/release_gate_test.sh can exercise
# them directly: release_gate.sh performs top-level work as soon as it is run,
# so its checks cannot be called in isolation from there.
#
# Usage:
#   tool/release_gate_checks.sh secret-scan [ROOT]
#   tool/release_gate_checks.sh migration-order [ROOT]
#
# ROOT defaults to the current directory. Each check exits 0 when the tree is
# clean, 1 when it reports a finding, and 64 for an unknown check name.

# Canonical, immutable migration history of the user-owned Supabase backend.
# Names and order are pinned here; the expected digests are derived from the
# Worker manifest so this gate cannot drift from the bundle that is deployed.
CANONICAL_MIGRATIONS=(
  20260827000000_sync_v1
  20260829000000_sync_v1_hardening
  20260910000000_real_use_v2
  20260915000000_recurrence_removal_provenance
  20260916000000_title_history_conflict_ordering
  20260917000000_initial_sync_baseline
)

# Secret shapes that must never be committed: Supabase secret/service-role
# keys, private key headers, and JWT-looking values.
SECRET_PATTERN='(sb_secret_[A-Za-z0-9_-]{20,}|service_role_[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|eyJ[A-Za-z0-9_-]{20,}\.)'

# Exact placeholder literals used by the redaction and rejection fixtures in
# test/unit/sync/** and provisioning/test/**. They are deliberately not
# credentials: they are the values the tests assert are rejected or redacted.
# Only these literals are recognized; a secret-shaped value that is not one of
# them is still reported, even when it sits on the same line as a fixture.
SAFE_FIXTURES=(
  'sb_secret_abcdefghijklmnopqrstuvwxyz'
  'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789'
  'sb_secret_abcdefghijklmnopqrst'
  'sb_secret_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'
  'service_role_abcdefghijklmnopqrstuvwxyz'
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
)

CLEANUP_DIRS=()
cleanup() {
  local dir
  for dir in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$dir" ]] && rm -rf -- "$dir"
  done
}
trap cleanup EXIT

usage() {
  printf 'Usage: %s secret-scan|migration-order [ROOT]\n' "${0##*/}"
}

secret_scan() {
  local root="${1:-.}"
  local work matches unexpected allowed status token

  work="$(mktemp -d)"
  CLEANUP_DIRS+=("$work")
  matches="${work}/matches"
  unexpected="${work}/unexpected"
  allowed="${work}/allowed"

  set +e
  rg --no-filename --only-matching --hidden \
    --glob '!supabase.local.json' \
    --glob '!.git/**' \
    --glob '!build/**' \
    --glob '!.dart_tool/**' \
    --glob '!artifacts/**' \
    -- "$SECRET_PATTERN" "$root" >"$matches"
  status=$?
  set -e
  if ((status > 1)); then
    printf 'secret scan: ripgrep failed (status %s)\n' "$status" >&2
    return 1
  fi

  if [[ ! -s "$matches" ]]; then
    printf 'secret scan: no secret-shaped values found\n'
    return 0
  fi

  sort -u "$matches" >"${work}/tokens"
  printf '%s\n' "${SAFE_FIXTURES[@]}" | sort -u >"$allowed"
  grep -Fvx -f "$allowed" "${work}/tokens" >"$unexpected" || true

  if [[ ! -s "$unexpected" ]]; then
    printf 'secret scan: only the documented placeholder fixtures are present\n'
    return 0
  fi

  printf 'secret scan: unexpected secret-shaped value(s):\n' >&2
  while IFS= read -r token; do
    printf '  %s\n' "$token" >&2
    rg --line-number --fixed-strings --hidden \
      --glob '!supabase.local.json' \
      --glob '!.git/**' \
      --glob '!build/**' \
      --glob '!.dart_tool/**' \
      --glob '!artifacts/**' \
      -- "$token" "$root" 2>/dev/null | head -n 3 | sed 's/^/    /' >&2 || true
  done <"$unexpected"
  return 1
}

migration_order() {
  local root="${1:-.}"
  local migrations_dir="${root%/}/supabase/migrations"
  # The Worker manifest lives beside the entry module, not in it: a Worker entry
  # module in modules format may only export functions, so the migration bundle
  # (and its digests) must be importable from a non-entry module.
  local manifest_source="${root%/}/provisioning/src/migrations.ts"
  if [[ ! -f "$manifest_source" ]]; then
    manifest_source="${root%/}/provisioning/src/index.ts"
  fi
  local work manifest expected_count index found_entry
  local -a found=()
  local -a manifest_names=()

  if [[ ! -d "$migrations_dir" ]]; then
    printf 'migration check: missing %s\n' "$migrations_dir" >&2
    return 1
  fi
  if [[ ! -f "$manifest_source" ]]; then
    printf 'migration check: missing worker manifest %s\n' "$manifest_source" >&2
    return 1
  fi

  work="$(mktemp -d)"
  CLEANUP_DIRS+=("$work")
  manifest="${work}/manifest"

  while IFS= read -r name; do
    [[ -n "$name" ]] && found+=("$name")
  done < <(
    find "$migrations_dir" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' |
      sed 's/\.sql$//' | sort
  )

  expected_count="${#CANONICAL_MIGRATIONS[@]}"
  if ((${#found[@]} != expected_count)); then
    printf 'migration check: expected %d canonical migrations, found %d (%s)\n' \
      "$expected_count" "${#found[@]}" "${found[*]:-none}" >&2
    return 1
  fi
  for index in "${!CANONICAL_MIGRATIONS[@]}"; do
    if [[ "${found[$index]}" != "${CANONICAL_MIGRATIONS[$index]}" ]]; then
      printf 'migration check: migration %d is %s, expected %s\n' \
        "$((index + 1))" "${found[$index]}" "${CANONICAL_MIGRATIONS[$index]}" >&2
      return 1
    fi
  done

  # Expected digests come from the deployed Worker's migration bundle: the
  # Worker manifest is the single source of truth, so the gate cannot pin a
  # digest that the Worker does not actually deploy.
  while IFS=$'\t' read -r name hash; do
    printf '%s  %s%s.sql\n' "$hash" "${root%/}/supabase/migrations/" "$name"
  done < <(
    sed -n '/^export const MIGRATIONS = \[/,/^\];$/p' "$manifest_source" |
      rg --only-matching 'name: "[0-9a-z_]+"|sha256: "[0-9a-f]+"' |
      sed -e 's/^name: "//' -e 's/^sha256: "//' -e 's/"$//' |
      paste - -
  ) >"$manifest"

  if [[ ! -s "$manifest" ]]; then
    printf 'migration check: %s lists no migration digests\n' "$manifest_source" >&2
    return 1
  fi
  if [[ "$(wc -l <"$manifest")" -ne "$expected_count" ]]; then
    printf 'migration check: worker manifest lists %s migrations, expected %d\n' \
      "$(wc -l <"$manifest")" "$expected_count" >&2
    return 1
  fi

  while IFS= read -r found_entry; do
    manifest_names+=("$found_entry")
  done < <(awk '{print $2}' "$manifest" | sed 's#.*/##; s/\.sql$//')
  for index in "${!CANONICAL_MIGRATIONS[@]}"; do
    if [[ "${manifest_names[$index]}" != "${CANONICAL_MIGRATIONS[$index]}" ]]; then
      printf 'migration check: worker manifest entry %d is %s, expected %s\n' \
        "$((index + 1))" "${manifest_names[$index]}" "${CANONICAL_MIGRATIONS[$index]}" >&2
      return 1
    fi
  done

  if ! sha256sum --check --strict "$manifest"; then
    printf 'migration check: migration contents do not match the worker manifest\n' >&2
    return 1
  fi

  printf 'migration check: %d canonical migrations verified against %s\n' \
    "$expected_count" "$manifest_source"
}

main() {
  local check="${1:-}"
  case "$check" in
    secret-scan)
      shift
      secret_scan "${1:-.}"
      ;;
    migration-order)
      shift
      migration_order "${1:-.}"
      ;;
    -h|--help|help|'')
      usage
      [[ -n "$check" ]] || return 64
      ;;
    *)
      printf 'Unknown check: %s\n' "$check" >&2
      usage >&2
      return 64
      ;;
  esac
}

main "$@"
