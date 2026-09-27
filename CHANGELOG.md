# Changelog

All notable user-visible changes are documented here. The project uses
versioned GitHub releases and annotated tags for new releases.

## Unreleased

### Fixed

- A stat that fails to refresh keeps its last known value, dimmed and marked
  "Not updated", instead of turning into "Unavailable" while the refresh
  reports success. Failed stats are retried on the next open after a minute,
  or after Oura's Retry-After, and a value older than a day is no longer shown.
- A missing battery permission is shown as "Needs access" with an Enable
  Battery Access action instead of an endless partial refresh.
- The OAuth listener no longer waits forever when its port is already taken.
- The battery gauge rendered white in the default theme; it is signal blue
  again, and the options menu now uses the theme color.
- "Updated now" no longer freezes while the popover stays open.
- Tile details no longer truncate: earlier-day values read "From yesterday",
  and missing permission reads "Needs access".
- Small failure text and the battery sample age now meet 4.5:1 contrast.
- Opening the popover no longer puts a focus ring on the first stat.

### Changed

- The status line shows a spinner and "Refreshing…" while fetching, confirms
  "Updated just now" for three seconds and then fades, and stays visible when
  data is old or a refresh failed or was partial.
- Landscape keeps score labels, so both themes show the same information.
- The battery row shows "Synced 5h ago" only once Oura's newest reading is at
  least two hours old; the exact age is in the tooltip and VoiceOver label.
- Customize moved from the metric strip to the footer, and the strip fades at
  edges where more stats continue.
- Connection is now a three-step guided setup that ends on "Connected
  securely" and opens the popover.
- Release tags must be signed, and releases publish a provenance archive.

### Added

- Text size: Appearance offers Standard, Large, and Extra Large, scaling the
  popover's text and tiles and every window.
- Keyboard access to the stats row: Tab reaches it, arrow keys move and
  scroll, and Option-arrow reorders.
- Ring Stats now runs in the App Sandbox; existing preferences move into its
  container on first launch.
- Releases publish a CycloneDX SBOM and a signed in-toto attestation.
- Diagnostics: privacy-safe events in the macOS unified log and a report you
  can review, copy, or save. It never contains health values or secrets.
- State gallery renders of every popover state, theme, and width.
- THREAT_MODEL.md, ACCESSIBILITY.md, and a usability study protocol.

- Local candidate installation now preserves the prior app at a printed Trash
  recovery path, restores it after injected install failures, and never
  recursively deletes the installed bundle.
- Candidate builds now retain matching universal dSYMs and emit tree-bound
  provenance manifests; explicit local Gate A and exact-artifact Gate B approval
  preflights protect later remote release steps.

## 1.1.1 — 2026-09-27

### Fixed

- Metric reordering now uses a contained move interaction without a copy badge,
  shifts neighboring metrics live, and cancels cleanly when released outside.

## 1.1 — 2026-09-27

### Added

- Five-minute refresh-on-open policy, manual refresh, footer freshness, and
  stale snapshot retention.
- Per-reading source-day or sample-age context.
- Metric-aware OAuth scopes and endpoint fetching.
- Typed app/auth/API state, rate-limit guidance, and authorization cancellation.
- Numeric `127.0.0.1` callback, fragmented callback handling, and resilience to
  invalid local connections.
- Data-protection Keychain preference with compatible-Keychain and plaintext
  migration.
- Connection, privacy, release, and project architecture documentation.
- Universal application/DMG artifact verification and app icon verification.

### Changed

- Reauthorization now obtains and saves a replacement token before attempting
  to revoke the previous token.
- Concurrent token users share one refresh operation.
- Connection and deletion controls remain reachable in all configured states.
- Hidden statistics no longer produce health endpoint requests.
- Older daily values and heart-rate samples no longer appear without freshness
  context; timestamped records are sorted by parsed dates.

### Fixed

- Landscape Resilience values and the Customize icon now align with the other
  metric values.
- Default-theme donut charts no longer clip at the top of their gauge bounds.
- OAuth redirect/listener mismatch between `localhost` and IPv4 loopback.
- Indefinite loading, stale-data ambiguity, case-sensitive SwiftPM test layout,
  callback fragmentation/cancellation, and full-screen/Escape popover behavior.

## 1.0 — 2026-09-26

- First public Ring Stats release.
- Developer ID-signed, Apple-notarized universal DMG with SHA-256 checksum.
- Readiness, Sleep, Activity, Heart Rate, Stress, optional Resilience, battery,
  customization, and two visual themes.
- Bring-your-own Oura OAuth credentials stored in macOS Keychain.
