# Architecture

Ring Stats is a dependency-free Swift package assembled into a macOS app by the
repository scripts. SwiftUI renders content; AppKit owns menu-bar, panel, window,
and click behavior.

## Package targets

| Target | Holds | Knows about Oura |
| --- | --- | --- |
| `RingStatsCore` | Models, freshness and merging, the `HealthProvider` boundary, diagnostics, Keychain storage, the loopback callback, network sessions | No. Error messages take the provider's name as a parameter |
| `RingStatsOura` | `OuraProvider`, `OuraAPI`, `OAuthClient`, Oura response models, scopes, endpoints, and score bands | Yes |
| `RingStats` | The app: AppKit shell, SwiftUI views, `AppViewModel`, diagnostics report | Only in `ProviderRegistry`, which chooses the provider; a test keeps the `RingStatsOura` import there. Onboarding and credits copy names Oura through `descriptor.displayName` and `descriptor.developerPortal`, except the About window's trademark notice |

Cross-target declarations use `package` access, so nothing is public outside
the package. Providers are compiled in, not loaded as plugins.

## Provider boundary

A provider conforms to `HealthProvider`: a `ProviderDescriptor` (identity,
capabilities, and the scope each metric needs), an account (`OAuthServicing`:
sign-in, connection state, revocation), and a snapshot source
(`SnapshotFetching`). `AppViewModel` works only through this boundary. It asks
the descriptor which scopes to request and drops metrics the provider does not
support before fetching.

`Metric` cases keep their vendor's meaning. Another provider's recovery score
is a different measure from Oura's Readiness and would get its own case. Only
quantities that really are shared, such as battery percentage
(`BatteryReading`), have one neutral shape. Scope and endpoint names in
diagnostics (`AuthorizationScope`, `DiagnosticEndpoint`) are created only from
string literals, so a provider cannot log runtime text through them.

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
                         │  HealthProvider
                    OuraProvider
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
- `Diagnostics.swift` (Core) defines the typed `DiagnosticEvent` model and the
  unified-log and in-memory `DiagnosticsLog`. `DiagnosticsReport.swift` (app)
  builds the redacted report.
- `AppViewModel.swift` is the `@MainActor` state boundary. It owns the typed app
  state, five-minute refresh TTL, stale snapshot retention, authorization
  orchestration, and explicit refresh/cancel/disconnect actions.
- `OAuthClient.swift` is an actor that creates authorization requests, exchanges
  and refreshes tokens, shares one in-flight token refresh, and revokes access.
- `CallbackServer.swift` owns the temporary loopback listener on port 43828 and
  validates the callback method, path, host, and OAuth state.
- `OuraAPI.swift` is an actor that fetches enabled metrics and battery
  concurrently, converts API failures into typed errors, and records source
  dates/times.
- `KeychainCredentialStore.swift` stores Client ID, Client Secret, current
  access/refresh tokens, and any access tokens awaiting revocation as
  generic-password items.
- `Models.swift` (Core) defines metrics, snapshot freshness and merging,
  persisted metric configuration, and typed application/error state.
- `HealthProvider.swift` (Core) defines the provider boundary.
- `OuraProvider.swift` and `OuraModels.swift` (Oura) define Oura's descriptor,
  scope derivation, endpoints, response models, and score bands.

## Data lifecycle

1. The user registers `http://localhost:43828/oauth/callback` and supplies their
   own Oura Client ID and Client Secret.
2. Ring Stats saves those credentials in Keychain and requests scopes derived
   from enabled metrics plus `ring_configuration` for battery.
3. Oura redirects the browser to the temporary loopback listener. Ring Stats
   validates the callback and exchanges the code at the documented token
   endpoint.
4. `OuraAPI` requests only enabled metrics plus battery. Results become one
   in-memory `HealthSnapshot`; health responses are not written to a database.
5. Reopening the popover refreshes data when the snapshot is at least five
   minutes old, or at least a minute old (longer if Oura sent Retry-After)
   when a stat failed transiently last time. A manual refresh always requests
   data. Each refresh is merged with the previous snapshot per metric: a stat
   whose request failed transiently keeps its last value marked stale for up
   to 24 hours, the battery does the same, missing permission (including for
   the battery) and "no data yet" are shown as they are, and the outcome
   (succeeded, partial, failed) drives the status line. A whole-refresh
   failure keeps the previous snapshot.
6. Disconnect attempts remote revocation and deletes local credentials and
   tokens even when revocation cannot complete.

## Persistence boundaries

| Data | Storage | Lifetime |
| --- | --- | --- |
| Health snapshot | Process memory | Until replaced or app quits |
| OAuth credentials and current/queued tokens | macOS Keychain | Until successful revocation, disconnect, or manual deletion |
| Empty OAuth migration tombstone | macOS Keychain | May remain after token deletion to prevent legacy-token reimport |
| Theme, metric order/visibility, width, text size, low battery alert, menu bar value | `UserDefaults` | Until preference-domain deletion |
| OAuth state/callback listener | Process memory | One authorization attempt |
| Diagnostic events (no values or secrets) | Unified log and a 200-event memory buffer | macOS log retention; buffer until quit |

Old compatible Keychain items and early JSON files under
`~/Library/Application Support/Ring Stats Public/Legacy Secrets/` are migrated
only after the new Keychain write succeeds. Cleanup of the weaker copy is
best-effort and retried on later reads without blocking access to the protected
credential.

## Security boundaries

- The app runs in the App Sandbox with only network client, network server
  (for the loopback callback), and user-selected file write entitlements.
  A container-migration manifest moves existing preferences on first launch.
- OAuth and health requests use dedicated ephemeral sessions with caching and
  cookies disabled and finite request/resource timeouts.
- The app connects only to documented Oura HTTPS endpoints and its own
  loopback callback listener on `localhost` (IPv4 and IPv6).
- Reauthorization stores a working replacement token before revoking the old
  token. Failed old-token revocations remain queued in Keychain and are retried
  without making the replacement unusable.
- The app has no project-operated backend, analytics, crash reporting, ads, or
  third-party runtime dependencies.
- A stable bundle identifier and Developer ID signature support consistent
  Keychain access across releases.

## Background refresh and low battery alert

`Background/BackgroundRefresher.swift` schedules an `NSBackgroundActivityScheduler`
every 30 minutes. Each pass calls the same `refreshOnOpen` as the popover, so
it fetches only visible stats and reuses fresh data. `BackgroundRefreshPolicy`
(Core) skips a pass on battery power or in Low Power Mode until the data is
about two hours old. `LowBatteryWatcher` observes every snapshot the model
publishes and uses `LowBatteryAlert` (Core) to notify once below 20% until the
ring charges, never for a stale reading. Its state is in memory only.

## Shortcuts actions

`Shortcuts/RingStatsIntents.swift` defines the App Intents and
`ShortcutAnswers.swift` answers them. They run inside the menu-bar app through
`ShortcutBridge`, refresh through `AppViewModel` like a popover open, and read
the in-memory snapshot. Shortcuts finds the actions through
`Contents/Resources/Metadata.appintents`, which `scripts/build_app.sh`
generates with `appintentsmetadataprocessor` from the compiler's constant
values (the protocol list is `native/AppIntentsConstProtocols.json`), because
SwiftPM does not run that Xcode build step. `verify_release_artifacts.sh`
fails a bundle whose metadata is missing either action.

macOS runs App Intents only in apps signed with a Team ID. An ad-hoc signed
local candidate lists the actions in Shortcuts, but running one fails with
"couldn't communicate with the app". Test the actions with a build signed by
setting `CODESIGN_IDENTITY` to a Developer ID identity.

## Build and release boundaries

`swift test -Xswiftc -warnings-as-errors` runs the automated suite, grouped by
boundary (including `AppShellTests`, which drive the real `AppDelegate` with a
stubbed model), and renders the state gallery to `.build/state-gallery/` with
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
