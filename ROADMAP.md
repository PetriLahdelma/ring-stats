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
- Keychain migration, callback socket tests, universal app/DMG verification,
  and 60 automated tests.

The hardening items above are implemented on `main`; users of an earlier
release receive them when the next release is published.

## P0 — Before broader promotion

1. **Obtain written Oura confirmation.** Confirm that public distribution,
   positioning, promotion, and voluntary funding comply with the current API
   agreement. Broad promotion and donations remain on hold until then.
2. **Complete accessibility QA.** Verify VoiceOver order, full keyboard access,
   contrast, reduced motion, and larger text at every supported width.
3. **Publish the hardened release.** Cut an annotated version tag, run the
   authenticated release procedure, and publish its evidence and release notes.
4. **Finish connection diagnostics.** Continue improving explanations for
   port conflicts, invalid credentials, delayed Oura processing, and recovery
   from unavailable services.

## P1 — More useful every day

1. **Battery-first utility.** Add an optional low-battery notification with a
   user-controlled threshold and quiet hours.
2. **Mac automation.** Add read-only App Intents/Shortcuts for visible scores
   and battery state.
3. **Metric-specific context.** Explain what each value represents, its source
   date/time, and why it may be absent without copying Oura's analytics product.
4. **Localization.** Start with Finnish and English, including locale-aware
   time, duration, and number formatting.
5. **Update discovery.** Provide a privacy-preserving way to learn that a newer
   signed release exists.

## P2 — Sustainable open source

1. **Voluntary support, only if approved.** Funding must unlock no
   Oura-connected feature, data, support, or download.
2. **Release provenance.** Add signed tags, attestations, and an SBOM where they
   materially improve verification.
3. **Measure without surveillance.** Use public repository and release signals,
   never in-app health-data analytics or user tracking.

## Commercial boundary

The current [Oura API and MCP Agreement](https://cloud.ouraring.com/legal/api-agreement)
restricts charging for API-related functionality, competing with or replicating
Oura, advertising, and commercial targeting using Oura data. Until written
confirmation and appropriate legal review are complete:

- do not accept donations or sell access based on this integration;
- do not add paid tiers, subscriptions, convenience fees, sponsor-only builds,
  advertising, or commercial targeting;
- never sell health data, share it for targeting, or use it to train AI; and
- keep new features focused on the native macOS workflow rather than copying
  the Oura application.

Re-evaluate these boundaries whenever Oura changes its agreement or provides
written authorization.
