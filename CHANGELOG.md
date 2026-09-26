# Changelog

All notable user-visible changes are documented here. The project uses
versioned GitHub releases and annotated tags for new releases.

## Unreleased

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

- OAuth redirect/listener mismatch between `localhost` and IPv4 loopback.
- Indefinite loading, stale-data ambiguity, case-sensitive SwiftPM test layout,
  callback fragmentation/cancellation, and full-screen/Escape popover behavior.

## 1.0 — 2026-09-26

- First public Ring Stats release.
- Developer ID-signed, Apple-notarized universal DMG with SHA-256 checksum.
- Readiness, Sleep, Activity, Heart Rate, Stress, optional Resilience, battery,
  customization, and two visual themes.
- Bring-your-own Oura OAuth credentials stored in macOS Keychain.
