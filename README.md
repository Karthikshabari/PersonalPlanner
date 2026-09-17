# Personal Planner

Local-first day planner for Linux desktop and Android. Tasks, categories,
reviews, and timer data live in a local SQLite database (Drift); cloud sync is
optional and runs against a user-owned Supabase project that is created through
the provisioning Worker in this repository.

## Requirements

- Flutter (stable channel, Dart SDK `^3.13.1` — see `pubspec.yaml`).
- Linux desktop builds: `clang`, `cmake`, `ninja-build`, `pkg-config`, and the
  GTK 3 development headers, in addition to the Flutter Linux desktop
  toolchain (`flutter doctor` reports what is missing).
- Android builds: Android SDK (set `ANDROID_HOME` or `ANDROID_SDK_ROOT`) and a
  JDK 17+; `flutter doctor` must report the Android toolchain as ready.
- Optional, only for local Supabase work or Worker deployment: Node.js/npm.

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

The Planner runs fully offline with no configuration. Cloud features stay
unavailable (and are reported as such in the UI) until the build-time
configuration below is supplied.

## Configuration

All client configuration is compile-time and consists only of public values.
It is passed with `--dart-define` or with an ignored local JSON file.

| Value | Purpose |
|---|---|
| `SUPABASE_URL` | URL of your own Supabase project. |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable (client-safe) key of that project. |
| `PROVISIONING_BASE_URL` | Base URL of the deployed provisioning Worker. |

```bash
# Static, pre-provisioned project:
flutter run -d linux \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>

# In-app, user-owned project provisioning (needs the Worker URL):
flutter run -d linux --dart-define=PROVISIONING_BASE_URL=https://<worker-host>
```

For local development copy `supabase.example.json` to `supabase.local.json`
(ignored by Git) and use `--dart-define-from-file=supabase.local.json`.

Never commit real credentials. Only the project URL and publishable key belong
in a client build; Management tokens, OAuth client secrets, service-role keys,
Android signing material (`android/key.properties`, keystores), `.env` files,
and `supabase.local.json` are ignored and must stay on your machine.

## Building

```bash
# Linux desktop (bundle under build/linux/x64/release/bundle)
flutter build linux --release

# Android APK (debug needs no signing setup)
flutter build apk --debug

# Android release: copy android/key.properties.example to
# android/key.properties and fill in your upload keystore. Without that file the
# release build stays unsigned instead of falling back to the debug keystore.
flutter build apk --release
```

Android packaging and local-data policy (application ID gate, signing, backup
restrictions) is documented in [android/README.md](android/README.md).

## Tests and release gate

```bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 -r compact
bash tool/release_gate_test.sh        # static checks of the gate itself
./tool/release_gate.sh --local        # analyze + tests + Linux/Android builds
```

`integration_test/provisioning_e2e_test.dart` drives the real provisioning
Worker against a real user-owned project and is opt-in; see the header of that
file for the required `--dart-define` values. `tool/README.md` documents the
staging and Android device gates, which are never run by default.

## Repository layout

| Path | Contents |
|---|---|
| `lib/` | Flutter application source (features, core, platform). |
| `test/`, `integration_test/` | Unit, widget, and opt-in integration tests. |
| `assets/branding/` | Branding assets referenced by `pubspec.yaml`. |
| `android/`, `linux/` | Platform packaging, resources, and signing examples. |
| `supabase/migrations/` | Canonical, immutable database migration history. |
| `supabase/tests/` | Database-level regression SQL. |
| `provisioning_poc/` | Canonical Cloudflare Worker that provisions a user-owned Supabase project plus its tests (the `_poc` name is historical; it is the deployed implementation). |
| `tool/` | Release-gate automation and its regression test. |

## Provisioning Worker (optional)

The Worker is only needed to create/repair a user-owned Supabase project. It
requires its own Cloudflare secrets (`OAUTH_SESSION_KEY`,
`SUPABASE_OAUTH_CLIENT_SECRET`) configured in Cloudflare — never in this
repository:

```bash
cd provisioning_poc
npm ci
npm run check      # tsc --noEmit
npm test           # vitest worker tests
npm run deploy:dry # bundles without deploying
```

Local Supabase CLI work (migrations, local database) uses the CLI pinned by the
root `package.json`: run `npm ci` at the repository root and then
`npx supabase <command>`.
