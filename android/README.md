# Android release and local-data policy

## Product identity gate

The current package/application ID (`com.personalplanner.personal_planner`) and
the display name (`Personal Planner`) are development values inherited from the
architecture. Before the first production signing or store submission, the
owner must explicitly approve the permanent application ID, display name,
signing-key owner, and recovery contacts. This repository does not invent or
rotate that irreversible identity.

## Signing

Create `android/key.properties` from `key.properties.example` only after that
approval. The production upload keystore and all passwords must remain outside
Git and outside build artifacts. The Gradle release type uses the production
configuration when all four local properties are present; it never falls back
to the debug keystore. The signing owner is responsible for encrypted backup of
the keystore, recovery access, and documenting the Play/App Store upgrade path.

## Local-data threat model

Planner rows live in the application sandbox SQLite file. Supabase access and
refresh tokens use the platform secure-storage implementation and are not
stored in SQLite, `app_settings`, logs, or exports. This protects against other
ordinary applications without sandbox access, but does not protect data from a
compromised/rooted device, an unlocked device, OS-level debugging, or a user
with filesystem backup access. The app makes no at-rest database-encryption
claim.

## Kotlin plugin compatibility

`android.builtInKotlin=true` is enabled for the current AGP/Flutter setup. The
Flutter 3.44 tool still reports the `flutter_timezone` legacy Kotlin-Gradle
plugin compatibility warning during Android builds, so this remains a tracked
release-gate deviation until the toolchain/package combination removes it.

## Backup policy

Until an encrypted, account-aware restore design exists, planner databases,
local settings, and authentication material are excluded from both cloud backup
and device transfer. `allowBackup=false` is set in the manifest, and both the
legacy `fullBackupContent` and Android 12+ `dataExtractionRules` explicitly
exclude database, file, shared-preference, and external-data domains. This is a
privacy/data-loss tradeoff: reinstall or device replacement requires the
configured account sync; offline-only data is not recoverable from Android
backup.
