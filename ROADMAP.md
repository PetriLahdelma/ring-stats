# Ring Stats Roadmap

Ring Stats should become the fastest, most trustworthy way to glance at an
Oura user's current state from macOS. It should complement Oura rather than
reproduce its app, keep health data private, and remain useful without becoming
another dashboard.

## Product principles

- **Glanceable, not exhaustive.** Optimize for a five-second menu-bar check.
- **Private by default.** Keep health responses in memory and credentials in
  Keychain; request only scopes required by enabled features.
- **Mac-native.** Prefer menu-bar interactions, Shortcuts, accessibility, and
  system notifications over copied mobile patterns.
- **Honest freshness.** Always distinguish current, delayed, unavailable, and
  permission-limited data.
- **Independent identity.** Do not use Oura marks or imply endorsement.

## P0 — Ready for real users

1. **Obtain written Oura confirmation.** Ask Oura to confirm that the public
   integration, its positioning, and voluntary funding model comply with the
   current API agreement before promoting it broadly.
2. **Ship a signed and notarized DMG.** Add a tagged release process, checksums,
   release notes, and installation instructions. Do not publish ad-hoc builds.
3. **Finish connection diagnostics.** Explain invalid credentials, missing
   scopes, expired authorization, rate limits, network failures, and delayed
   Oura processing in plain language.
4. **Show data freshness.** Display the last successful refresh, provide a
   manual refresh action, and never leave a metric in an indefinite loading
   state.
5. **Complete accessibility QA.** Verify VoiceOver labels and order, keyboard
   navigation, contrast, reduced motion, and larger text at every supported
   popover width.

## P1 — More useful every day

1. **Battery-first utility.** Add an optional low-battery notification with a
   user-controlled threshold and quiet hours.
2. **On-demand context.** Add compact, in-memory 7-day comparisons for enabled
   metrics without persisting a health database or recreating Oura's full
   analytics experience.
3. **Mac automation.** Expose read-only App Intents/Shortcuts for the current
   visible scores and battery state so users can build their own local routines.
4. **Metric-specific detail.** Offer a concise explanation of what each value
   represents, its timestamp, and why it may be absent.
5. **Localization and formatting.** Start with Finnish and English, including
   locale-aware time, duration, and number formatting.

## P2 — Sustainable open source

1. **GitHub Sponsors.** Accept voluntary support for maintenance and releases;
   never gate Oura-connected features, data, support, or downloads by payment.
2. **Public feedback loop.** Use GitHub Discussions for feature requests and
   publish a short privacy-safe issue template for diagnostics.
3. **Release confidence.** Add automated release checks, artifact checksums,
   dependency review, and a documented vulnerability-response cadence.
4. **Measure without surveillance.** Use GitHub stars, releases, downloads,
   issues, and sponsor conversions—never in-app health-data analytics or user
   tracking.

## Commercial boundary

The current [Oura API and MCP Agreement](https://cloud.ouraring.com/legal/api-agreement)
prohibits charging users for access to or use of functionality related to the
Oura API or platform and prohibits competing with or merely replicating Oura.
It also restricts advertising and commercial targeting using Oura data.
Therefore:

- donations must be voluntary and confer no Oura-connected feature or access;
- no paid tier, subscription, convenience fee, sponsor-only build, or ad model
  should be introduced without Oura's prior written approval and legal review;
- health data must never be sold, shared for targeting, or used to train AI;
- new features should enhance the macOS workflow around Oura rather than copy
  the Oura application.

Revisit this boundary whenever Oura changes its agreement or provides written
authorization for a different model.
