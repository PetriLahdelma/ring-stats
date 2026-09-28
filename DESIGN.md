---
name: Ring Stats
description: A calm independent macOS menu-bar status strip for ring-derived wellness data.
colors:
  signal-blue: "#375377"
  separator: "#DAD3CA"
  ink: "#181B1F"
  white: "#FFFFFF"
  canvas-warm: "#F4F1EC"
  alert: "#E05C4E"
  alert-text: "#B23A2E"
typography:
  metric:
    fontFamily: ".AppleSystemUIFontRounded, -apple-system, sans-serif"
    fontSize: "28pt"
    fontWeight: 500
    lineHeight: 1
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12pt"
    fontWeight: 600
    lineHeight: 1.2
  caption:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "10pt"
    fontWeight: 400
    lineHeight: 1.25
rounded:
  popover: "20pt"
  control: "8pt"
spacing:
  xs: "4pt"
  sm: "8pt"
  md: "16pt"
  lg: "24pt"
components:
  score-arc:
    backgroundColor: "{colors.signal-blue}"
    textColor: "{colors.ink}"
    size: "84pt"
  popover:
    backgroundColor: "{colors.canvas-warm}"
    textColor: "{colors.ink}"
    rounded: "{rounded.popover}"
    padding: "24pt"
---

# Design System: Ring Stats

## Overview

**Creative North Star: “The Quiet Signal Strip”**

Ring Stats uses its own warm-neutral palette, split-ring mark, compact score geometry, and native macOS controls. Oura appears only as the factual data provider; its logo, named palette, proprietary fonts, product silhouette, and application chrome are not reproduced.

The menu-bar popover is one horizontally scrollable shortcut strip, a slim battery row, and a compact options menu. There are no cards, tabs, headings, or decorative analytics.

**Key Characteristics:**
- Warm canvas with dark ink typography.
- One signal-blue data arc across all normal scores.
- Transparent unfilled arcs and centers; no gray donut background.
- Native SF Symbols for generic system actions only.
- Equal-width shortcut items, horizontal scrolling, and dense first-glance legibility.

## Colors

Use dark ink and white as the functional base, with signal blue and a warm separator as independent primary signifiers. Secondary colors are rare state accents.

### Primary
- **Signal Blue** (`#375377`): all normal score arcs, active controls, and focus.
- **Separator** (`#DAD3CA`): the footer divider and quiet boundaries.

### Secondary
- **Alert** (`#E05C4E`): low-battery and unavailable icons only (3.21:1 on canvas, enough for graphics).
- **Alert Text** (`#B23A2E`): "Not updated" and failure text (5.27:1 on canvas). Landscape uses `#FFD4CC`, which keeps 4.5:1 over the brightest part of the photograph. See [ACCESSIBILITY.md](ACCESSIBILITY.md).

### Neutral
- **Ink** (`#181B1F`): primary text and menu-bar template artwork.
- **Canvas Warm** (`#F4F1EC`): popover canvas.
- **White** (`#FFFFFF`): setup/about window surfaces where native separation helps.

**The One Blue Rule.** Normal scores share Signal Blue. Multiple unrelated score colors would turn the strip into a generic fitness dashboard.

## Typography

Use SF Pro through SwiftUI's system text styles. Do not bundle or imitate Oura's proprietary AkkuratLL or Editorial New fonts.

- **Metric** (`28pt`, medium, rounded design): score numerals.
- **Label** (`12pt`, semibold): Sleep, Readiness, Activity, and Battery.
- **Caption** (`10pt`, regular): Optimal/Good/Fair/Pay attention, charging state, and attribution.

Use tabular numerals for values. Sentence case only.

## Layout

All type and tile geometry scale with Appearance > Text size (1, 1.15, or 1.3 times). The figures below are at Standard.

The popover defaults to 680pt wide and can be resized horizontally from 420pt to 840pt, with 24pt outer padding. Its chosen width persists. The rounded arrow remains visually anchored to the menu-bar icon while either side is resized. A horizontal scroll view contains 92pt metric tiles with 16pt gaps. Default order is Readiness, Sleep, Activity, Heart Rate, and Stress; Resilience is available through customization. There is no Customize tile or button in the popover; stats are customized from Appearance in the options menu, so nothing competes with health data. When tiles continue past an edge, that edge fades over 28pt, and VoiceOver hears "More stats are available by scrolling". Visible shortcuts can be dragged into a new order directly in the popover, using the same stored order as Appearance. A one-pixel warm separator divides shortcuts from the battery and options row. The refresh status sits at the top trailing edge inside the existing top inset:

- While fetching: a small spinner and "Refreshing…".
- After a successful refresh: "Updated just now" for three seconds, then it fades out so the strip stays quiet.
- When data is older than the five-minute refresh window: "Updated 12m ago", visible.
- After a partial refresh: "Some stats not updated" in Alert Text, visible.
- After a failed refresh: "Update failed · 1h ago" in Alert Text, visible.

The status is always available to VoiceOver, including while faded out, and it re-evaluates every second.

Users resize the popover horizontally only. Its height follows its content and is refitted after a resize or refresh, so wrapped text never clips. Connection, Appearance, and About & Credits appear in separate compact windows.

## Elevation & Depth

Use native macOS popover/window elevation. The Ring Stats theme adds no custom shadows, glass layers, gradients, or visual effects; Landscape permits only a dark photographic contrast veil.

## Themes

### Ring Stats
- Warm canvas, Ink text, and Signal Blue gauges and actions.
- This remains the default theme.

### Landscape
- An original bundled Nordic landscape photograph spans the entire popover width and height.
- A dark vertical veil protects contrast without obscuring the terrain.
- Score charts are replaced by a white native icon and number, with the metric name and the same detail line as the default theme beneath. Landscape changes presentation only: every label, band, and state that appears in Ring Stats appears here too.
- Numbers, labels, battery artwork, dividers, and actions use white with controlled opacity hierarchy.
- The photo contains no embedded UI, text, logos, people, or product imagery.
- Settings stays on the stable Ring Stats surface so theme selection remains predictable and legible.

## Shapes

Circular status geometry is the signature language. Buttons and window surfaces follow native macOS corner behavior. The menu-bar item uses the original Ring Stats split-ring silhouette as a monochrome template image; battery uses the native macOS battery symbol family.

## Components

### Metric Tile Anatomy
Every tile has the same zones in the same order (`MetricTileAnatomy` in code), so themes and metrics vary content, never layout:

1. **Visual zone**, `84pt` square: score ring, or icon above value.
2. **Value baseline**: every value sits on the baseline of a 28pt reference line, including Resilience's 18pt level, so mixed sizes align without per-metric offsets.
3. **Title**, 12pt semibold, `12pt` below the visual zone.
4. **Detail**, 11pt, one line: score band, source day ("From yesterday"), sample age ("bpm · 7m ago"), or state ("Not updated", "Needs access", "No data yet", "Unavailable"). Every possible detail fits the 92pt tile; a test measures them.

### Score Donut
- `84pt` square with only an `8pt` Signal Blue trimmed arc; the unfilled remainder and center stay transparent over Canvas Warm.
- Score centered in 28pt rounded system type with tabular numerals.
- Metric and qualitative label below the ring.
- Missing state uses no arc, an em dash, and an explicit caption.
- A stale value dims to 62% and its detail reads "Not updated" in Alert Text.

### Extended Metrics
- Heart Rate shows the latest Oura sample as BPM and never presents it as a 0–100 score.
- Stress shows today’s high-stress duration in rounded minutes plus the daily summary when available.
- Resilience shows Oura’s published level (`Limited` through `Exceptional`) and is hidden by default.
- Non-score metrics use icon-and-value presentation rather than a fabricated progress donut.

### Stat Customization
- Appearance, from the options menu or the status-item menu, holds the shared stats configuration. The popover has no separate customize control.
- Every available metric can be shown or hidden; at least one remains visible.
- Ordering persists and can be changed by native row dragging in Appearance or direct dragging in the popover; nonvisual Move Up/Down accessibility actions remain available.
- Keyboard: Tab reaches the tiles; Left and Right Arrow move focus and scroll the tile into view; Option-Left and Option-Right move the focused stat and announce its position. Nothing is focused when the popover opens.
- Drag reordering is a contained move interaction: the active metric tracks the
  pointer directly from a stable render slot, neighboring metrics animate into
  provisional positions after their centers are crossed, and a valid release
  produces one short source snap before the stored order commits without replay.
  Leaving the strip restores the original preview, and Reduced Motion removes
  the positional interpolation.

### Battery Row
- A native macOS battery symbol followed by percentage and charging state.
- Oura only receives a battery reading when the ring syncs through the Oura phone app. Once that reading is at least two hours old, the row adds “Synced 5h ago”; younger readings show no age, because a ring loses only about 0.5 to 1% an hour. The exact age is always in the tooltip and the VoiceOver label (“Ring last synced 1h ago”).
- “Battery 92%” and “Not charging” are separate text elements with no middle dot; the primary battery text uses full emphasis, charging state 68% ink, and sample age 62% ink (both at least 4.5:1).
- When the battery request fails, the last reading stays and the sample age is replaced by “Not updated” in Alert Text.
- When the battery permission is missing, the row reads “Needs access” and the popover offers Enable Battery Access.
- In Landscape, the battery glyph and primary battery text are pure white.
- In the Ring Stats theme, Alert is permitted on the battery icon only below 20% or when the reading is unavailable; text follows the theme’s foreground hierarchy.

### About & Credits
- Lives inside a compact native hamburger menu; no persistent icon-and-text link appears in the popover.
- Opens a focused native window containing only the creator credit “Digitaltableteur,” Oura attribution, independence disclaimer, and app version.
- Contains no appearance, OAuth, reauthorization, connection-status, or quit controls.

### Appearance
- Opens as its own fixed-size native window and contains theme plus stat configuration.
- Uses two stacked full-width selection rows with persistent descriptions; the choices never compete for horizontal space.
- A segmented Text size control (Standard, Large, Extra Large) sits below the theme choices.
- Keeps both theme descriptions rendered at all times and uses a fixed 500×690pt content size (scaled by Text size), so switching themes or stats cannot resize the window.
- Provides visibility toggles, native row reordering with a focusable passive grip, keyboard Up/Down movement while that grip is focused, boundary-aware nonvisual Move Up/Down accessibility actions, and a reset action for every metric.
- Contains nothing related to credits or OAuth.

### Connection
- Opens independently from the disconnected Connect action and from both menu surfaces in every configured state, at a fixed 460×440pt.
- First-run setup is three steps with a step indicator: create the Oura application (with why it is needed), add the callback URL (Copy confirms visibly and to VoiceOver), and enter credentials (with “Stored only in this Mac’s Keychain”). While the browser flow runs, the window says so and offers Cancel.
- A new connection ends on “Connected securely”; **Show My Stats** closes the window and opens the popover.
- Once configured, Connection shows status, Reauthorize Permissions, and **Disconnect & Delete Local Data**.

### Diagnostics
- A fixed 560×520pt window reachable from both menus.
- Explains that the report contains no health values, credentials, tokens, or identifiers, shows it in full as selectable monospaced text, and offers Refresh Report, Copy, and Save….

### Popover Options Menu
- The visible control is the `line.3.horizontal` SF Symbol without an additional disclosure indicator.
- Menu items are Appearance, Connection, About & Credits, Diagnostics…, a divider, Refresh Now, Reauthorize Permissions, another divider, and Quit Ring Stats.
- The glyph uses the theme action color.
- Reauthorize Permissions is disabled when stored credentials are unavailable or authorization is already running.

### Menu-Bar Context Menu
- An AppKit-owned status item dispatches clicks explicitly: left-click opens the SwiftUI popover; right-click or Control-click opens a native menu.
- The status item uses the original 17pt Ring Stats split-ring template asset.
- Connection remains available in every state. Refresh Now requires a connected account; Reauthorize Permissions requires stored developer credentials. Both are disabled while the app is already loading.
- Diagnostics… sits with Appearance, Connection, and About & Credits.
- Quit Ring Stats remains available as the final menu action.

## Do's and Don'ts

### Do:
- **Do** keep enabled metrics in the user-selected order and make horizontal overflow discoverable.
- **Do** keep donut centers and unfilled segments free of gray background fills.
- **Do** refresh automatically when the popover appears.
- **Do** show refresh progress, confirm success briefly, and keep old or failed states visible; retain each stat's prior value with an explicit “Not updated” after a transient failure.
- **Do** identify Oura as the data provider in Credits.
- **Do** use native macOS focus, keyboard, and VoiceOver behavior.

### Don't:
- **Don't** use Oura's name as the product name or theme name, or reproduce its logo, product silhouette, named palette, proprietary fonts, slogans, or application chrome.
- **Don't** introduce cards, trends, recommendations, or navigation.
- **Don't** color each normal score differently.
- **Don't** place setup controls in the normal connected popover.
