# Release-gate automation

Run the safe local gate from the repository root:

```bash
./tool/release_gate.sh --local
```

It runs whitespace checks, a source secret scan, migration/backup checks,
Flutter analysis, the focused template test, the full test suite, Linux and
Android release builds, and a post-run process/memory check. Flutter tests and
builds are sequential and use a user-scoped 4 GiB/6 GiB cgroup when the host
supports it. If no safe cgroup is available, those capped checks are reported
as `BLOCKED` rather than started under an address-space `ulimit` or reported as
passing.

The migration check verifies the five canonical migrations against the digests
in `provisioning_poc/src/index.ts`, so the gate cannot drift from the migration
bundle the Worker deploys. The secret scan reports every secret-shaped value
except the placeholder literals the redaction/rejection fixtures already use.
Both checks live in `tool/release_gate_checks.sh` and are covered by
`tool/release_gate_test.sh`.

Reports and per-check logs are written to
`artifacts/release-gate/<UTC-run-id>/`; that directory is ignored by Git.
The command exits `0` for passing local checks, `1` for a failed check, and `2`
when a requested external gate is blocked by missing prerequisites.

Run the local regression for the staging assertion source independently of any
Supabase credentials:

```bash
bash tool/release_gate_test.sh
```

## Optional staging checks

Use only a disposable Supabase project and disposable confirmed accounts. The
runner requires all of these local environment variables:

```text
RELEASE_GATE_ALLOW_STAGING=1
SUPABASE_TEST_URL
SUPABASE_TEST_PROJECT_REF
SUPABASE_TEST_PUBLISHABLE_KEY
SUPABASE_TEST_ALPHA_EMAIL
SUPABASE_TEST_ALPHA_PASSWORD
SUPABASE_TEST_BETA_EMAIL
SUPABASE_TEST_BETA_PASSWORD
```

Then run:

```bash
RELEASE_GATE_ALLOW_STAGING=1 ./tool/release_gate.sh --staging
```

This applies/list-checks migrations and performs publishable-key REST/RPC
isolation probes. It creates a disposable Alpha fixture, asserts empty
cross-account bodies across all eleven synced tables, checks direct DML and both
forged RPC identity cases, and verifies the Alpha fixture is unchanged. It
never accepts or requests a service-role key, never deletes remote rows, and
does not print tokens or response bodies. Missing Supabase CLI, `curl`, `jq`,
credentials, or staging opt-in is reported as `BLOCKED`, not silently skipped.

## Optional Android checks

Set an explicit device serial; an arbitrary connected device is never selected:

```bash
ANDROID_SERIAL='<adb-serial>' ./tool/release_gate.sh --device
```

The device gate checks the selected package, captures filtered diagnostics, and
uses package-scoped process recovery as prerequisites. It does not clear data,
uninstall apps, or force-stop unrelated packages. The command remains
`BLOCKED` until native notification, timer, reboot, touch, and visual behavior
are recorded through the physical checklist in
`release_gate_manual_verification.md`.

Use `--all` only when both staging credentials and the intended Android device
are available:

```bash
RELEASE_GATE_ALLOW_STAGING=1 ANDROID_SERIAL='<adb-serial>' \
  ./tool/release_gate.sh --all
```
