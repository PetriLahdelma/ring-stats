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
- **Alert** (`#E05C4E`): unavailable, stale, or low-battery exceptions only.

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

The popover defaults to 680pt wide and can be resized horizontally from 420pt to 840pt, with 24pt outer padding. Its chosen width persists. The rounded arrow remains visually anchored to the menu-bar icon while either side is resized. A horizontal scroll view contains 92pt shortcut items with 16pt gaps. Default order is Readiness, Sleep, Activity, Heart Rate, Stress, and Customize; Resilience is available through customization. Visible shortcuts can be dragged into a new order directly in the popover, using the same stored order as Appearance. A one-pixel warm separator divides shortcuts from the battery, freshness, and options row.

The popover never resizes vertically: its fixed-height menu-bar composition expands only along the horizontal axis. Connection, Appearance, and About & Credits appear in separate compact windows.

## Elevation & Depth

Use native macOS popover/window elevation. The Ring Stats theme adds no custom shadows, glass layers, gradients, or visual effects; Landscape permits only a dark photographic contrast veil.

## Themes

### Ring Stats
- Warm canvas, Ink text, and Signal Blue gauges and actions.
- This remains the default theme.

### Landscape
- An original bundled Nordic landscape photograph spans the entire popover width and height.
- A dark vertical veil protects contrast without obscuring the terrain.
- Score charts are removed; each metric uses a white native icon and number with the metric name beneath. Detail text remains visible for loading, permission-required, unavailable, or stale/older values so presentation never hides status.
- Numbers, labels, battery artwork, dividers, and actions use white with controlled opacity hierarchy.
- The photo contains no embedded UI, text, logos, people, or product imagery.
- Settings stays on the stable Ring Stats surface so theme selection remains predictable and legible.

## Shapes

Circular status geometry is the signature language. Buttons and window surfaces follow native macOS corner behavior. The menu-bar item uses the original Ring Stats split-ring silhouette as a monochrome template image; battery uses the native macOS battery symbol family.

## Components

### Score Donut
- `84pt` square with only an `8pt` Signal Blue trimmed arc; the unfilled remainder and center stay transparent over Canvas Warm.
- Score centered in 28pt rounded system type with tabular numerals.
- Metric and qualitative label below the ring.
- Missing state uses no arc, an em dash, and an explicit “No data” caption.

### Extended Metrics
- Heart Rate shows the latest Oura sample as BPM and never presents it as a 0–100 score.
- Stress shows today’s high-stress duration in rounded minutes plus the daily summary when available.
- Resilience shows Oura’s published level (`Limited` through `Exceptional`) and is hidden by default.
- Non-score metrics use icon-and-value presentation rather than a fabricated progress donut.

### Stat Customization
- The final shortcut opens Appearance at the shared stats configuration.
- Every available metric can be shown or hidden; at least one remains visible.
- Ordering persists and can be changed by drag reordering or explicit up/down controls.

### Battery Row
- A native macOS battery symbol followed by percentage and charging state.
- “Battery 92%” and “Not charging” are separate text elements with no middle dot; the primary battery text uses full emphasis and charging state uses 50% opacity.
- In Landscape, the battery glyph and primary battery text are pure white.
- In the Ring Stats theme, Alert is permitted on the battery icon only below 20% or when the reading is unavailable; text follows the theme’s foreground hierarchy.

### About & Credits
- Lives inside a compact native hamburger menu; no persistent icon-and-text link appears in the popover.
- Opens a focused native window containing only the creator credit “Digitaltableteur,” Oura attribution, independence disclaimer, and app version.
- Contains no appearance, OAuth, reauthorization, connection-status, or quit controls.

### Appearance
- Opens as its own fixed-size native window and contains theme plus stat configuration.
- Uses two stacked full-width selection rows with persistent descriptions; the choices never compete for horizontal space.
- Keeps both theme descriptions rendered at all times and uses a fixed 500×620pt content size, so switching themes or stats cannot resize the window.
- Provides visibility toggles, explicit up/down ordering controls, and a reset action for every metric.
- Contains nothing related to credits or OAuth.

### Connection
- Opens independently from the disconnected Connect action and from both menu surfaces in every configured state.
- Owns OAuth application credentials, callback URL guidance, connection errors, and reauthorization status.
- Shows the exact numeric callback URL with a Copy action and owns **Disconnect & Delete Local Data**.

### Popover Options Menu
- The visible control is the `line.3.horizontal` SF Symbol without an additional disclosure indicator.
- Menu items are Appearance, Connection, About & Credits, a divider, Refresh Now, Reauthorize Permissions, another divider, and Quit Ring Stats.
- Reauthorize Permissions is disabled when stored credentials are unavailable or authorization is already running.

### Menu-Bar Context Menu
- An AppKit-owned status item dispatches clicks explicitly: left-click opens the SwiftUI popover; right-click or Control-click opens a native menu.
- The status item uses the original 17pt Ring Stats split-ring template asset.
- Connection remains available in every state. Refresh Now requires a connected account; Reauthorize Permissions requires stored developer credentials. Both are disabled while the app is already loading.
- Quit Ring Stats remains available as the final menu action.

## Do's and Don'ts

### Do:
- **Do** keep enabled metrics in the user-selected order and make horizontal overflow discoverable.
- **Do** keep donut centers and unfilled segments free of gray background fills.
- **Do** refresh automatically when the popover appears.
- **Do** show the last successful refresh time and retain prior values with an explicit stale warning after a transient failure.
- **Do** identify Oura as the data provider in Credits.
- **Do** use native macOS focus, keyboard, and VoiceOver behavior.

### Don't:
- **Don't** use Oura's name as the product name or theme name, or reproduce its logo, product silhouette, named palette, proprietary fonts, slogans, or application chrome.
- **Don't** introduce cards, trends, recommendations, or navigation.
- **Don't** color each normal score differently.
- **Don't** place setup controls in the normal connected popover.
