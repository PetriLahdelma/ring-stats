# Ring Stats Roadmap

Ring Stats should remain the fastest, most trustworthy way to glance at an
Oura user's current state from macOS. It should complement Oura rather than
reproduce its app, keep health responses private, and avoid becoming another
dashboard.

## Product principles

- **Glanceable, not exhaustive.** Optimize for a five-second menu-bar check.
- **Private by default.** Keep health responses in memory, credentials in
  Keychain, and requests limited to enabled features.
- **Mac-native.** Prefer menu-bar interactions, accessibility, Shortcuts, and
  system notifications over copied mobile patterns.
- **Honest freshness.** Distinguish current, delayed, unavailable, stale, and
  permission-limited data.
- **Independent identity.** Do not use Oura marks or imply endorsement.

## Shipped

- Developer ID-signed, Apple-notarized universal DMG with a published checksum.
- GitHub Discussions and privacy-safe contribution/security routes.
- Metric visibility and ordering, two themes, resizable popover, and six
  supported statistics.
- Refresh on open with a five-minute TTL, manual refresh, last-update status,
  stale snapshot retention, and source-day/sample-age details.
- Metric-aware scopes and endpoint fetching; hidden metrics are not requested.
- Numeric-loopback OAuth callback, non-destructive reauthorization, shared token
  refresh, typed auth/API failures, and explicit authorization cancellation.
- Connection and local deletion controls reachable from connected and
  disconnected states.
- Keychain migration, callback socket tests, and universal app/DMG verification.
- Per-metric freshness: a stat that fails transiently keeps its last value
  marked "Not updated" and is retried after a minute or Oura's Retry-After.
- Refresh status with progress, a brief success confirmation, and persistent
  old/partial/failed states.
- Theme parity, a formal tile anatomy, Customize removed from the strip, and overflow
  edge fades.
- Three-step guided connection ending on "Connected securely".
- Privacy-safe diagnostics with a reviewable local report.
- State gallery with geometry, parity, truncation, and contrast tests; gate-based
  concurrency tests.
- Threat model, accessibility evidence matrix, and a usability study protocol.
- Signed-tag enforcement and a publishable provenance archive for releases.
- Text size setting, keyboard access to the stats row, App Sandbox, AppKit
  shell tests, a CycloneDX SBOM, and signed release attestations.
- Holographic theme, a stepped text size slider, and the charging bolt and
  "Charged" state in the battery row.
- Read-only Shortcuts actions for any stat and the ring battery.
- Background refresh, slower on battery power, and an optional low ring
  battery notification at 20%.
- Exclusive loopback sign-in listener and local-path-free release provenance.
- Oura sandbox test, and research on which other rings Ring Stats could
  support ([research/RING_PROVIDERS.md](research/RING_PROVIDERS.md)).

## P0: Before broader promotion

1. **Obtain written Oura confirmation.** Confirm that public distribution,
   positioning, promotion, and voluntary funding comply with the current API
   agreement. Broad promotion remains on hold until then; passive listings
   (topics, awesome lists, the README) are fine.
2. **Finish manual accessibility QA.** Contrast, truncation, widths, and theme
   parity are now tested automatically. Run the manual procedure in
   [ACCESSIBILITY.md](ACCESSIBILITY.md) with VoiceOver, keyboard only, Reduce
   Motion, and Increase Contrast, and record the results there.
3. **Run the usability study.** Hold the 5 to 8 sessions in
   [research/USABILITY_STUDY.md](research/USABILITY_STUDY.md), then ship the
   single improvement the findings rank highest.

## P1: More useful every day

1. **Battery-first utility.** The low-battery notification ships at a fixed
   20%. Add a user-controlled threshold and quiet hours.
2. **Metric-specific context.** Explain what each value represents, its source
   date/time, and why it may be absent without copying Oura's analytics product.
3. **Localization.** Start with Finnish and English, including locale-aware
   time, duration, and number formatting.
4. **Update discovery.** Provide a privacy-preserving way to learn that a newer
   signed release exists.

## P2: Hardening

1. **Connection error copy.** Clearer explanations for port conflicts, invalid
   credentials, delayed Oura processing, and unavailable services, using the
   diagnostic event kinds already recorded.

## P2: Sustainable open source

1. **Voluntary support.** A Buy Me a Coffee link is listed in the repository's
   funding file. It unlocks nothing: no feature, data, support, or download
   depends on it, and no Oura data is involved. Keep it that way, and review
   it against the API agreement when Oura's written confirmation arrives.
2. **Release provenance.** Signed tags, a provenance archive, a CycloneDX SBOM,
   and a signed in-toto attestation are in place, and CI attests its own
   builds. Move notarized release builds to an isolated builder once CI is
   dependable.
3. **Measure without surveillance.** Use public repository and release signals,
   never in-app health-data analytics or user tracking.

## Commercial boundary

The current [Oura API and MCP Agreement](https://cloud.ouraring.com/legal/api-agreement)
restricts charging for API-related functionality, competing with or replicating
Oura, advertising, and commercial targeting using Oura data. Until written
confirmation and appropriate legal review are complete:

- do not sell access based on this integration, and keep any voluntary
  support independent of it;
- do not add paid tiers, subscriptions, convenience fees, sponsor-only builds,
  advertising, or commercial targeting;
- never sell health data, share it for targeting, or use it to train AI; and
- keep new features focused on the native macOS workflow rather than copying
  the Oura application.

Re-evaluate these boundaries whenever Oura changes its agreement or provides
written authorization.
