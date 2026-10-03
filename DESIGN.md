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
- **Secondary Ink** (Ink at 62%, 4.65:1 on Canvas Warm): captions, theme circles, and the reorder grip in the windows. Never the system secondary gray, which is 3.88:1 on the canvas. Solid Ink under Increase Contrast, as is every theme's secondary text.
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

Use native macOS popover/window elevation. The Ring Stats theme adds no custom shadows, glass layers, gradients, or visual effects; Landscape permits only a dark photographic contrast veil, and Holographic only its bundled pastel marble.

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

### Holographic
- "Black on holographic": pastel marbled foil like the examples in OpenReplay's "Creating Holographic Effects in CSS". Flowing, warped bands of pink, butter yellow, pale cyan, lavender, and mint.
- The marble is domain-warped noise mapped through a repeating pastel ramp, rendered once by `scripts/assets/holographic_marble.swift` (2400 by 1200, seed 21) and bundled like the Landscape photo. It fills the popover at every width and height.
- Gauges, icons, numbers, labels, the battery glyph, and actions use Holographic Ink (`#0D0F10`); details use Ink at 68%.
- Failure text and the low-battery icon use Holographic Alert (`#8C2A1F`), because the standard alert reds fall below 4.5:1 on the marble's darkest pink.
- Like Ring Stats, it keeps score gauges; only color and background change.
- Under the pointer the foil twists up to 3 degrees toward the pointer's side and pinches in at the pointer (Core Image `CIPinchDistortion`), then eases back when the pointer leaves. Only the background moves; text and gauges stay still. Reduce Motion keeps it flat.

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
- Below Text size, a Low battery alert switch (off by default) explains itself in one caption line. Turning it on asks macOS for notification permission; if denied, the switch returns to off and the caption says where to allow notifications.
- Every available metric can be shown or hidden; at least one remains visible.
- Ordering persists and can be changed by native row dragging in Appearance or direct dragging in the popover; nonvisual Move Up/Down accessibility actions remain available.
- Keyboard: Tab reaches the tiles; Left and Right Arrow move focus and scroll the tile into view; Option-Left and Option-Right move the focused stat and announce its position. Nothing is focused when the popover opens.
- Focus ring: keyboard focus draws a 2pt ring in the theme's action color, 6pt outside the tile, following a 14pt continuous corner. It replaces the system's rectangular ring, which ignored the tile's lift and offset. A click or drag also focuses a tile but shows no ring.
- Pointer: an open hand over a tile and a closed hand while dragging (macOS 15 and later). The dragged tile lifts to 106% scale; no shadow, keeping the Ring Stats theme free of custom shadows.
- Drag reordering is a contained move interaction: the active metric tracks the
  pointer directly from a stable render slot, neighboring metrics animate into
  provisional positions after their centers are crossed, and a valid release
  produces one short source snap before the stored order commits without replay.
  Leaving the strip restores the original preview, and Reduced Motion removes
  the positional interpolation.

### Battery Row
- A native macOS battery symbol followed by the percentage. While the ring charges, a bolt is cut out of the battery fill, as macOS does, so it stays visible at every level.
- Not charging is the usual state and shows no text. A charging ring adds "Charging", and a ring in its charger at 100% reads "Charged". VoiceOver always hears the state, including "Not charging", because it cannot see the bolt.
- The row shows no reading age. Oura only receives a battery reading when the ring syncs through the Oura phone app, and a ring loses only about 0.5 to 1% an hour, so the age adds noise without changing what the user does.
- “Battery 92%” and “Charging” are separate text elements with no middle dot; the primary battery text uses full emphasis and charging state 68% ink (at least 4.5:1).
- When the battery request fails, the last reading stays and the row adds “Not updated” in Alert Text.
- When the battery permission is missing, the row reads “Needs access” and the popover offers Enable Battery Access.
- In Landscape, the battery glyph and primary battery text are pure white.
- In the Ring Stats theme, Alert is permitted on the battery icon only below 20% or when the reading is unavailable; text follows the theme’s foreground hierarchy.

### Action Buttons
- A step's main action uses the primary style: Signal Blue fill with white text (about 8:1). Back and Cancel use the secondary style: a 1pt Signal Blue outline with Signal Blue text on the canvas (about 7:1).
- Both are custom styles because `.borderedProminent` turns grey whenever its window is not the active one, which erased the hierarchy in the connection window. A disabled primary fades to 45% rather than turning grey.
- In-content utilities such as Copy keep the neutral system style, so only one button per step reads as the next step.

### About & Credits
- Lives inside a compact native hamburger menu; no persistent icon-and-text link appears in the popover.
- Opens a focused native window containing only the creator credit “Digitaltableteur,” Oura attribution, independence disclaimer, and app version.
- Contains no appearance, OAuth, reauthorization, connection-status, or quit controls.

### Appearance
- Opens as its own fixed-size native window and contains theme plus stat configuration.
- Uses two stacked full-width selection rows with persistent descriptions; the choices never compete for horizontal space.
- A stepped Text size slider sits below the theme choices, running from a small "Aa" to a large "Aa" as in macOS. Its three steps are Standard, Large, and Extra Large, and VoiceOver reads the step name. The two "Aa" labels show fixed sizes and do not scale.
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
- The visible control is the `line.3.horizontal` SF Symbol without an additional disclosure indicator, in the theme action color.
- It opens the same native menu as the menu-bar icon's right-click menu (below), so the two never differ. It opens on mouse down, and from the keyboard with Space, Return, or Down Arrow once Tab reaches it, which works with the system Keyboard navigation setting off. Keyboard focus draws a 2pt theme-colored ring 2pt outside the button with an 8pt corner.
- Refresh Now announces its result to VoiceOver.
- Reauthorize Permissions is disabled when stored credentials are unavailable or authorization is already running.

### Menu-Bar Context Menu
- An AppKit-owned status item dispatches clicks explicitly: left-click opens the SwiftUI popover; right-click or Control-click opens a native menu.
- The status item uses the original 17pt Ring Stats split-ring template asset.
- Connection remains available in every state. Refresh Now requires a connected account; Reauthorize Permissions requires stored developer credentials. Both are disabled while the app is already loading.
- Diagnostics… sits with Appearance, Connection, and About & Credits.
- Quit Ring Stats remains available as the final menu action.
- Items: Appearance…, Connection…, About & Credits, Diagnostics…, a divider, Refresh Now (⌘R), Reauthorize Permissions, another divider, and Quit Ring Stats (⌘Q).
- Every item has an SF Symbol icon: `paintpalette`, `person.crop.circle`, `info.circle`, `stethoscope`, `arrow.clockwise`, `key`, and `power`. macOS 27 hides symbol images in menus of apps built with an earlier SDK, so each symbol is redrawn as a template image (`AppDelegate.menuIcon`). The icons are decorative; the titles carry the meaning.

## Do's and Don'ts

### Do:
- **Do** keep enabled metrics in the user-selected order and make horizontal overflow discoverable.
- **Do** keep donut centers and unfilled segments free of gray background fills.
- **Do** refresh automatically when the popover appears.
- **Do** show refresh progress, confirm success briefly, and keep old or failed states visible; retain each stat's prior value with an explicit “Not updated” after a transient failure.
- **Do** identify Oura as the data provider in Credits.
- **Do** use native macOS focus, keyboard, and VoiceOver behavior, and follow the rules in [ACCESSIBILITY.md](ACCESSIBILITY.md).

### Don't:
- **Don't** use Oura's name as the product name or theme name, or reproduce its logo, product silhouette, named palette, proprietary fonts, slogans, or application chrome.
- **Don't** introduce cards, trends, recommendations, or navigation.
- **Don't** color each normal score differently.
- **Don't** place setup controls in the normal connected popover.
