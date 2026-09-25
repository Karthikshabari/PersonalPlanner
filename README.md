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

For Android, connect a device or start an emulator, then run
`flutter run -d <android-device-id>`.

The Planner runs fully offline with no configuration. Normal Android and Linux
builds also include the public production provisioning Worker URL, so cloud
setup is available without a local JSON file. No Planner data is sent until a
user explicitly provisions storage and signs in.

## Configuration

All client configuration is compile-time and consists only of public values.
The production provisioning Worker URL is the built-in default. A
`--dart-define` can override it for staging or an isolated test; static
Supabase configuration remains an explicit development fallback.

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

# Optional staging/isolated-test override for in-app provisioning:
flutter run -d linux --dart-define=PROVISIONING_BASE_URL=https://<staging-worker-host>
```

For the explicit static fallback, copy `supabase.example.json` to
`supabase.local.json` (ignored by Git) and use
`--dart-define-from-file=supabase.local.json`. `provisioning.local.json` is
also ignored if a local Worker override is useful.

```bash
cp supabase.example.json supabase.local.json
```

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

### Linux desktop URI integration

Browsers can only hand a callback link back to the application when the desktop
environment knows which application owns the scheme. Both platforms register the
same scheme (`com.personalplanner.personalplanner`), with one destination per
callback purpose:

| URI | Purpose |
|---|---|
| `com.personalplanner.personalplanner://login-callback` | Planner user account confirmation |
| `com.personalplanner.personalplanner://management-callback` | Supabase authorization returned to the app |

Android registers both intent filters in `android/app/src/main/AndroidManifest.xml`.
On Linux, install the per-user desktop entry and register the scheme after
installing or building the bundle:

```bash
flutter build linux --release
linux/packaging/register_uri_scheme.sh
xdg-mime query default x-scheme-handler/com.personalplanner.personalplanner
```

The script only writes inside `$XDG_DATA_HOME` (default `~/.local/share`) and
points the desktop entry at the bundle executable. Without it, a browser that a
confirmation email or the provisioning Worker redirects to one of the URIs above
cannot activate a running Personal Planner window.

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
For optional `flutter drive` runs, use the conventional
`test_driver/integration_test.dart` driver with
`--driver=test_driver/integration_test.dart --target=<integration-test-file>`.

## Repository layout

| Path | Contents |
|---|---|
| `lib/` | Flutter application source (features, core, platform). |
| `test/`, `integration_test/` | Unit, widget, and opt-in integration tests. |
| `assets/branding/` | Branding assets referenced by `pubspec.yaml`. |
| `android/`, `linux/` | Platform packaging, resources, and signing examples. |
| `supabase/migrations/` | Canonical, immutable database migration history. |
| `supabase/tests/` | Database-level regression SQL. |
| `provisioning/` | Cloudflare Worker that provisions a user-owned Supabase project, with its tests and deployment configuration. |
| `tool/` | Release-gate automation and its regression test. |

## Provisioning Worker (optional)

The Worker is only needed to create/repair a user-owned Supabase project. It
requires Cloudflare bindings configured on the deployed Worker — never real
values in this repository. Copy the example only for local Worker development:

```bash
cp provisioning/.dev.vars.example provisioning/.dev.vars
```

The production `/v1/provisioning/*` flow requires:

| Binding | Purpose |
|---|---|
| `OAUTH_SESSION_KEY` | Long random key used to encrypt short-lived Management OAuth material. |
| `SUPABASE_OAUTH_CLIENT_ID` | Public identifier for your Supabase Management OAuth application. |
| `SUPABASE_OAUTH_CLIENT_SECRET` | Secret for the Supabase Management OAuth application. |
| `SUPABASE_OAUTH_REDIRECT_URI` | Registered callback URL, ending in `/oauth/callback`. |

The retained legacy `/poc/*` browser routes additionally require
`POC_PHASE`, `POC_ORGANIZATION_SLUG`, `POC_PROJECT_NAME`, and
`POC_PROJECT_REF`. They target an isolated disposable project and are not used
by the Flutter client's production provisioning flow.

All eight names are declared under `secrets.required` so Wrangler can generate
types and refuse a deployment with missing bindings without committing any
account-specific value. Configure them as Cloudflare secrets in the Worker
dashboard (Settings > Variables and Secrets) before the next deployment. The
OAuth client ID and redirect URI are public identifiers, but they use the same
external binding mechanism to keep this repository environment-neutral.

The Worker name and the provisioning URL built into the Flutter client are
intentionally unchanged: the URL is public and existing app builds depend on
it. A branded custom domain is the appropriate future privacy/branding change;
changing or hiding the current `workers.dev` URL would not provide
authentication.

Then validate locally without deploying:

```bash
cd provisioning
npm ci
npm run cf:types   # regenerate generic Worker binding types
npm run check      # tsc --noEmit
npm test           # vitest worker tests
npm run deploy:dry # bundles without deploying
```

Local Supabase CLI work (migrations, local database) uses the CLI pinned by the
root `package.json`: run `npm ci` at the repository root and then
`npx supabase <command>`.
