# Changelog

All notable user-visible changes are documented here. The project uses
versioned GitHub releases and annotated tags for new releases.

## Unreleased

### Accessibility

- VoiceOver announces the result of Refresh Now: "Stats updated", that some
  stats could not be updated, or "Update failed".
- Increase Contrast now turns faded detail text, window captions, and
  control glyphs solid.
- Small text in the Appearance, Connection, Diagnostics, and About windows
  now meets 4.5:1 contrast; the system gray it used measured 3.88:1. The
  unselected theme circle and the reorder grip are now clearly visible.
- ACCESSIBILITY.md now starts with the rules every change must follow.
- Stat tiles no longer show the system's rectangular focus box after a
  click or drag. Keyboard focus draws a rounded ring in the theme's color
  instead, and the pointer becomes a hand over a tile and while dragging it.

### Fixed

- The popover menu shows its icons again on macOS 27, which hides menu item
  icons unless an app asks for them. Reauthorize Permissions and Quit now
  have icons too.

## 1.3.5 (2026-10-03)

### Security

- Release provenance archives are now free of local paths in every form. The
  1.3.4 archive still carried the build machine's folder path in the candidate
  manifest, where it was written JSON-escaped, and a temporary-folder path in
  its debug symbols. Paths are now rewritten in both forms, the build maps the
  temporary folder out of debug symbols, and publishing fails on any local
  path. No release has contained credentials or keys.

## 1.3.4 (2026-10-02)

### Security

- The sign-in listener closes each connection only after macOS has stopped
  watching it, answers requests where it reads them so every connection stays
  counted and closable, and accepts connections in bounded batches so a
  program connecting nonstop cannot starve sign-in.
- Release provenance archives no longer include the build machine's local
  folder paths, and publishing fails if any remain. Earlier archives contain
  the maintainer's build paths; they hold no credentials or keys.

## 1.3.3 (2026-10-02)

### Security

- During sign-in, another app on the Mac could listen on the
  `127.0.0.1:43828` callback address alongside Ring Stats 1.3.2 and receive
  the authorization code. Ring Stats now holds the callback port exclusively
  on both `127.0.0.1` and `::1`. The code alone cannot be exchanged without
  your Client Secret.

## 1.3.2 (2026-10-02)

### Fixed

- New connections could not be set up: Oura's developer portal now rejects
  the `http://127.0.0.1:43828/oauth/callback` redirect with "http protocol is
  only allowed for localhost". Ring Stats now uses
  `http://localhost:43828/oauth/callback` for new connections and listens on
  both loopback addresses. Existing connections keep the address they
  registered.

## 1.3.1 (2026-10-02)

### Fixed

- The Stress and Resilience icons were swapped compared with the Oura app.
  Stress now shows waves and Resilience shows wind lines.

## 1.3.0 (2026-09-30)

### Added

- Holographic theme: black gauges, icons, and text on pastel marbled
  holographic foil, which twists slightly and pinches under the pointer.
- Background refresh: Ring Stats refreshes the visible stats every 30 minutes,
  so they are current when you open the popover. On battery power or in Low
  Power Mode it waits at least two hours between fetches.
- Low battery alert, off by default in Appearance: one notification when the
  ring drops below 20%, and another only after it has charged.

### Changed

- The connection window's main action is now a solid blue button and Back is
  a blue outline, so the next step stands out even when the window is not
  active.

## 1.2.0 (2026-09-28)

### Fixed

- The charging bolt disappeared into the battery icon above about half charge.
  It is now cut out of the fill, as in macOS, and shows at every level.
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
- Small failure text now meets 4.5:1 contrast.
- Opening the popover no longer puts a focus ring on the first stat.

### Changed

- The battery row no longer says "Not charging". A charging ring reads
  "Charging", and one in its charger at 100% reads "Charged".
- The status line shows a spinner and "Refreshing…" while fetching, confirms
  "Updated just now" for three seconds and then fades, and stays visible when
  data is old or a refresh failed or was partial.
- Landscape keeps score labels, so both themes show the same information.
- The battery row no longer shows when the reading was sampled.
- Customize left the metric strip; stats are customized from Appearance in
  the menu. The strip fades at edges where more stats continue.
- Connection is now a three-step guided setup that ends on "Connected
  securely" and opens the popover.
- Release tags must be signed, and releases publish a provenance archive.

### Added

- Shortcuts actions: "Get Ring Stat" returns any of the six stats, and "Get
  Ring Battery" returns the battery percentage. Both refresh from Oura when
  the data is more than five minutes old and write nothing to disk.
- Text size: a stepped slider in Appearance, from a small to a large "Aa",
  offers Standard, Large, and Extra Large, scaling the popover's text and
  tiles and every window.
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
