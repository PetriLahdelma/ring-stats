# Architecture

Ring Stats is a dependency-free Swift package assembled into a macOS app by the
repository scripts. SwiftUI renders content; AppKit owns menu-bar, panel, window,
and click behavior.

## Runtime components

```text
NSStatusItem / AppDelegate
        │
        ├── StatusPopoverPanel ── SwiftUI MenuPopoverView
        ├── Connection window (staged onboarding)
        ├── Appearance window
        ├── About window
        └── Diagnostics window
                         │
                    AppViewModel
                    ┌────┴─────┐
               OAuthClient   OuraAPI
                    │           │
          KeychainCredentialStore
                    │
             Oura HTTPS APIs
```

- `RingStatsApp.swift` owns `NSStatusItem`, the resizable `NSPanel`, native
  context menu, outside-click/Escape dismissal, and refresh-on-open trigger.
- `Views/` holds one file per surface: `PopoverChrome` (bubble shell and
  background), `MenuPopoverView` (strip, footer, refresh status),
  `MetricGauge` (the tile and its `MetricTileAnatomy`), `MetricReordering`,
  `AppearanceSettingsView`, `ConnectionSettingsView` (three-step onboarding and
  management), `AboutCreditsView`, `DiagnosticsView`, and `Theme` tokens.
- `Diagnostics.swift` defines the typed `DiagnosticEvent` model, the
  unified-log and in-memory `DiagnosticsLog`, and the redacted
  `DiagnosticsReport`.
- `AppViewModel.swift` is the `@MainActor` state boundary. It owns the typed app
  state, five-minute refresh TTL, stale snapshot retention, authorization
  orchestration, and explicit refresh/cancel/disconnect actions.
- `OAuthClient.swift` is an actor that creates authorization requests, exchanges
  and refreshes tokens, shares one in-flight token refresh, and revokes access.
- `CallbackServer.swift` owns the temporary `127.0.0.1:43828` listener and
  validates the callback method, path, host, and OAuth state.
- `OuraAPI.swift` is an actor that fetches enabled metrics and battery
  concurrently, converts API failures into typed errors, and records source
  dates/times.
- `KeychainCredentialStore.swift` stores Client ID, Client Secret, current
  access/refresh tokens, and any access tokens awaiting revocation as
  generic-password items.
- `Models.swift` defines metrics, scope derivation, snapshot freshness, persisted
  configuration, and typed application/error state.

## Data lifecycle

1. The user registers `http://127.0.0.1:43828/oauth/callback` and supplies their
   own Oura Client ID and Client Secret.
2. Ring Stats saves those credentials in Keychain and requests scopes derived
   from enabled metrics plus `ring_configuration` for battery.
3. Oura redirects the browser to the temporary loopback listener. Ring Stats
   validates the callback and exchanges the code at the documented token
   endpoint.
4. `OuraAPI` requests only enabled metrics plus battery. Results become one
   in-memory `HealthSnapshot`; health responses are not written to a database.
5. Reopening the popover refreshes data when the snapshot is at least five
   minutes old or any stat failed last time. A manual refresh always requests
   data. Each refresh is merged with the previous snapshot per metric: a stat
   whose request failed transiently keeps its last value marked stale, the
   battery does the same, missing permission and "no data yet" are shown as
   they are, and the outcome (succeeded, partial, failed) drives the status
   line. A whole-refresh failure keeps the previous snapshot.
6. Disconnect attempts remote revocation and deletes local credentials and
   tokens even when revocation cannot complete.

## Persistence boundaries

| Data | Storage | Lifetime |
| --- | --- | --- |
| Health snapshot | Process memory | Until replaced or app quits |
| OAuth credentials and current/queued tokens | macOS Keychain | Until successful revocation, disconnect, or manual deletion |
| Empty OAuth migration tombstone | macOS Keychain | May remain after token deletion to prevent legacy-token reimport |
| Theme, metric order/visibility, width | `UserDefaults` | Until preference-domain deletion |
| OAuth state/callback listener | Process memory | One authorization attempt |
| Diagnostic events (no values or secrets) | Unified log and a 200-event memory buffer | macOS log retention; buffer until quit |

Old compatible Keychain items and early JSON files under
`~/Library/Application Support/Ring Stats Public/Legacy Secrets/` are migrated
only after the new Keychain write succeeds. Cleanup of the weaker copy is
best-effort and retried on later reads without blocking access to the protected
credential.

## Security boundaries

- OAuth and health requests use dedicated ephemeral sessions with caching and
  cookies disabled and finite request/resource timeouts.
- The app connects only to documented Oura HTTPS endpoints and the numeric local
  loopback callback.
- Reauthorization stores a working replacement token before revoking the old
  token. Failed old-token revocations remain queued in Keychain and are retried
  without making the replacement unusable.
- The app has no project-operated backend, analytics, crash reporting, ads, or
  third-party runtime dependencies.
- A stable bundle identifier and Developer ID signature support consistent
  Keychain access across releases.

## Build and release boundaries

`swift test -Xswiftc -warnings-as-errors` runs the automated suite, grouped by
boundary, and renders the state gallery to `.build/state-gallery/` with
geometry, parity, truncation, and contrast assertions.
CI also assembles a universal app and ad-hoc DMG, verifies architecture, bundle
metadata, signature, app icon, mountability, and scans artifacts for paths or
likely secrets.

Every local candidate retains matching executable/dSYM UUIDs and a manifest
bound to the actual Git tree content. Candidate installation is transactional:
the prior app moves to a unique Trash recovery path and is restored after an
install failure. Local approval markers live only in ignored `.omx/approvals/`;
Gate A is tree-bound and Gate B is exact-artifact- and installed-binary-bound.

Authenticated releases are separate: `scripts/sign_and_notarize.sh` requires a
clean exact annotated and signed version tag on the protected branch commit
(checked by `scripts/verify_release_tag.sh`), a Developer ID identity, and a
Keychain notary profile. It records source, tag signature, toolchain,
dependency, signature, checksum, and notarization evidence under
`dist/release-metadata/` and packages it as a publishable provenance archive.
See [THREAT_MODEL.md](THREAT_MODEL.md) for the security reasoning.
