# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS 14 or later; native SwiftUI/AppKit menu-bar accessory

## Users

The primary user is the owner of an Oura Ring using a Mac who wants a fast glance at today's core status without opening a phone app or a full analytics product.

## Product Purpose

Provide a native macOS menu-bar utility for selected Readiness, Sleep, Activity, Heart Rate, Stress, and Resilience values plus current ring battery state. Success means the user clicks one menu-bar icon, understands each value and its freshness in seconds, and dismisses the popover.

## Positioning

Ring Stats is deliberately smaller than a dashboard: a top-bar status surface with no history, coaching, navigation, or persistent health database.

## Operating Context

The Oura Ring continues syncing through the official phone app. Ring Stats reads synchronized values through Oura API V2 after a one-time OAuth setup. Its normal interface is a macOS menu-bar icon and compact horizontal popover.

## Capabilities and Constraints

- Live exclusively as a macOS menu-bar accessory with no Dock icon.
- Show a horizontally scrollable shortcut strip ordered by default as Readiness, Sleep, Activity, Heart Rate, Stress, then Customize.
- Keep Readiness, Sleep, and Activity as 0–100 scores; show Heart Rate as latest BPM and Stress as today’s high-stress minutes.
- Offer Resilience as an optional shortcut with its Oura level, hidden by default.
- Let Appearance persistently hide, show, and reorder shortcuts while keeping at least one stat visible.
- Let users drag visible shortcuts directly in the popover; the shared order updates Appearance immediately.
- Let users resize the popover horizontally from 420pt to 840pt and persist the chosen width.
- Show ring battery percentage and charging status in a compact row.
- Provide Appearance, Connection, About & Credits, Refresh Now, Reauthorize Permissions, and Quit Ring Stats inside a compact hamburger menu in the popover.
- Keep Appearance, About & Credits, and Connection as separate native views with one clear responsibility each; stat customization lives inside Appearance.
- Use an AppKit-owned status item so left-click opens the SwiftUI popover and right-click or Control-click reliably opens native Appearance, Connection, About & Credits, Refresh Now, Reauthorize Permissions, and Quit Ring Stats actions.
- Let the user switch persistently between the default Ring Stats theme and an independent Landscape photo theme from the Appearance view.
- Permit a separate first-run connection window only until OAuth is configured.
- Authenticate with Oura OAuth2 authorization-code flow through `http://127.0.0.1:43828/oauth/callback`; derive `daily`, `heartrate`, and `stress` from enabled metrics and always request `ring_configuration` for battery.
- Refresh on open when the last successful snapshot is at least five minutes old; allow an explicit refresh at any time.
- Preserve the last successful in-memory snapshot across transient failures and label it stale; expose source-day or sample-age context when values are older.
- Fetch only enabled statistics plus battery. Hiding a statistic changes collection as well as presentation.
- Keep client credentials and OAuth tokens encrypted in macOS Keychain and provide explicit revocation and local deletion controls.
- Keep health data ephemeral; do not persist a health-history database.
- Add no third-party runtime dependencies.
- Direct BLE and automated Membership Hub scraping remain out of scope.

## Brand Commitments

Use an independent warm-neutral palette, original Ring Stats split-ring mark, native system icons, and a calm macOS hierarchy. Do not use Oura's logo, wordmark, product silhouette, proprietary fonts, named palette, slogans, or copied application chrome. Credits identify Digitaltableteur as the creator and Oura as the data provider and trademark owner without implying endorsement.

## Evidence on Hand

- Oura API V2 provides the three daily score collections and latest ring battery data.
- The native Swift implementation and its 60 focused tests are the sole shipped application surface.

## Product Principles

- One click, one glance, one dismissal.
- Native macOS behavior before custom chrome.
- Theme choice changes presentation only; data, labels, accessibility, and interaction remain identical.
- Calm, independent restraint without identity impersonation.
- Always show missing or stale states honestly.
- Keep credentials secure and health data transient.

## Accessibility & Inclusion

Support keyboard navigation, VoiceOver labels, increased contrast, and reduced motion. Never rely on donut color alone; every value and state must appear as text.
