# Accessibility

[PRODUCT.md](PRODUCT.md) promises keyboard access, VoiceOver support,
sufficient contrast, reduced motion, and that no state relies on color alone.
This page records the evidence for each promise and what still needs a person
to verify. An item is **Verified** only when an automated test or a recorded
manual check proves it.

## Rules

These rules apply to every change, by people and by coding agents alike. A
pull request that breaks one is not merged. Each names the WCAG 2.2 success
criterion it serves and what enforces it. They are written for SwiftUI and
AppKit; web techniques such as ARIA do not apply.

1. **Measure contrast; never estimate it.** Text meets 4.5:1 and icons,
   arcs, and control glyphs meet 3:1 against the worst-case background of
   every theme, including the brightest pixel of the Landscape photograph
   and the darkest pixel of the Holographic marble. Add every new color
   token to `themeTextColorsMeetWCAGContrastForSmallText` and to the table
   below. Do not use the system `.secondary` or `.tertiary` styles for text
   on the warm canvas; they measure 3.88:1 and 2.2:1 there. Use
   `Palette.secondaryInk` or the theme's `secondaryContent`. (1.4.3, 1.4.11)
2. **Respect Increase Contrast.** Faded text and control tokens become solid
   while it is on (`AppTheme.increasesContrast`). Never add a faded token
   that ignores it. (1.4.3, 1.4.11)
3. **Never rely on color alone.** Every state that has a color also has
   text: stale tiles say "Not updated", failures say so, the low battery
   alert names the level. (1.4.1)
4. **Name every control, and include its visible text.** Icon-only controls,
   such as the ☰ menu and the reorder grip, get an `accessibilityLabel`. A
   control with visible text keeps that text at the start of its label, so
   Voice Control can find it by what it shows. (1.1.1, 2.5.3, 4.1.2)
5. **Group each stat into one element.** A tile reads as title, value, and
   state ("Readiness, 84, Good"), not as separate fragments. Decorative
   images are hidden from VoiceOver; menu icons are decorative and the
   titles carry the meaning. (1.3.1, 1.1.1)
6. **Announce what changes out of sight.** When something a person asked for
   finishes or fails and the change is easy to miss, post an
   `AccessibilityNotification.Announcement`: a refresh, a reorder, a copy,
   a connection. Do not announce background refreshes. (4.1.3)
7. **Everything works from the keyboard.** Every action has a keyboard path:
   Escape closes the popover, Tab reaches the stats, arrows move between
   them, Option-arrows reorder them, and every window completes without a
   pointer. Focus is always visible; prefer native controls, which draw the
   system focus ring. (2.1.1, 2.4.7, 2.4.11)
8. **Dragging always has an alternative.** Every drag, such as reordering
   stats, also works with keys and with VoiceOver actions ("Move Up",
   "Move Down"). (2.5.7)
9. **Respect Reduce Motion.** Read `accessibilityReduceMotion` and skip
   reordering animation, status fades, spinners, and the Holographic twist
   and pinch. Hover effects are decorative only and never carry
   information. (2.3.3, 1.4.13)
10. **Text grows without breaking.** The Text size setting scales every view,
    and no tile detail truncates at any size or popover width
    (`everyTileDetailFitsTheTileWithoutTruncation`,
    `everyTextSizeRendersWithinBounds`). (1.4.4, 1.4.10)
11. **Custom targets are at least 24 by 24 points.** Custom controls such as
    the ☰ menu (28 points) and the reorder grip (24 points) meet it; native
    controls keep their system size. (2.5.8)
12. **Notifications stand alone.** A notification's text makes sense
    without opening the app: "Your ring is at 15%". (3.3.1)
13. **Record the evidence.** When behavior changes, update the matrix below,
    and when a manual check is run, add it to the log.

Status key: **Verified** (automated), **Verified** (manual, dated), **Needs
manual check** (implemented, not yet confirmed with assistive technology), or
**Gap** (known shortfall).

## Matrix

| Area | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| Contrast | Small text meets 4.5:1 in every theme | Verified (automated) | `themeTextColorsMeetWCAGContrastForSmallText`; ratios below |
| Contrast | Icons and arcs meet 3:1 | Verified (calculated) | Signal blue 6.99:1, alert icon 3.21:1 on canvas |
| Contrast | Window captions and control glyphs meet 4.5:1 | Verified (automated) | `Palette.secondaryInk` 4.65:1 in `themeTextColorsMeetWCAGContrastForSmallText`; replaced the system secondary label color (3.88:1), the unselected theme circle (2.21:1), and the reorder grip (1.96:1) |
| Color independence | Every value and state appears as text | Verified (automated) | `staleTileSaysSoInTextAndToVoiceOver`, detail copy tests, state gallery |
| Truncation | Tile detail text is never cut off | Verified (automated) | `everyTileDetailFitsTheTileWithoutTruncation` |
| Theme parity | Themes show the same lines and labels | Verified (automated) | `themesKeepTheSameLayoutForEveryState` |
| Widths | Layout holds at 420, 680, and 840 pt | Verified (automated) | `popoverStatesRenderWithinBoundsAtEverySupportedWidth` |
| Overflow | Hidden stats are discoverable | Verified (automated) plus hint | Edge fades from `MetricStripLayout.overflow`; VoiceOver hint "More stats are available by scrolling" |
| Reduced motion | Reordering, settling, and status fades do not animate | Verified (automated) for reordering; Needs manual check for status fade and spinner | `reducedMotionReorderSettlementIsImmediate`; `RefreshStatusView` and `ScoreLoadingSpinner` read `accessibilityReduceMotion` |
| VoiceOver labels | Each tile reads title, value, and state | Verified (automated) for label text; Needs manual check for reading order | `MetricGauge.accessibilityLabel` tests |
| VoiceOver status | Refresh status is readable even when visually hidden | Needs manual check | Always-present accessibility element in `RefreshStatusView` |
| VoiceOver announcements | Reorder, copy, and connection success are announced | Needs manual check | `AccessibilityNotification.Announcement` in reorder, callback copy, diagnostics copy, and connection |
| VoiceOver announcements | Refresh Now announces its result | Verified (automated) for text; Needs manual check in use | `explicitRefreshAnnouncesEveryOutcome`; posted after Refresh Now from either menu, never for background refreshes |
| Keyboard | Popover dismisses with Escape | Verified (automated) | `statusPopoverEscapeInvokesCancellationHandler` |
| Keyboard | Onboarding completes without a pointer | Needs manual check | Default-action buttons on every step, focused Client ID field |
| Keyboard | Stats can be reordered without a pointer | Needs manual check | Focusable grip with Up/Down keys and Move Up/Down actions in Appearance |
| Keyboard | Metric strip is reachable, scrollable, and reorderable without a pointer | Verified (automated) for logic and focus path; Needs manual check in use | `arrowKeysMoveFocusAcrossVisibleStatsOnly`, `optionArrowMovesAStatPastItsVisibleNeighbor`; `openingThePopoverDoesNotFocusAStatTile` proves Tab reaches a tile while nothing is focused on open |
| Focus | Focus is visible on every control | Verified (automated) for stat tiles; Needs manual check elsewhere | Stat tiles draw `MetricFocusRing` in the theme's action color (3:1 or more in every theme), rendered in the `keyboard-focus` gallery state; it shows only for keyboard focus (`focusCameFromPointer`). Other controls are native; the reorder grip uses the system focus ring |
| Increased contrast | Increase Contrast makes faded text and control glyphs solid | Verified (automated) for tokens; Needs manual check in use | `increaseContrastMakesSecondaryTextSolid`; `AppTheme.increasesContrast` reads the system setting when views draw |
| Text size | Text can be enlarged | Verified (automated) | Appearance > Text size (Standard, Large, Extra Large) scales type and tile geometry everywhere. `everyTextSizeRendersWithinBounds`, `everyTileDetailFitsTheTileWithoutTruncation` at every size, `popoverHeightDoesNotDependOnWidth` at every size, `windowsRenderAtExtraLargeText`. macOS does not apply Dynamic Type to SwiftUI text on the Mac, so the system setting cannot drive it |
| Localization | Layout survives longer translations | Gap | English only; truncation tests cover current copy |

## Measured contrast

Ratios use WCAG 2.x relative luminance. Default theme text is measured on
Canvas Warm (`#F4F1EC`). Landscape is measured against the brightest pixel of
the bundled photograph under its lightest veil, `rgb(108, 92, 81)`, which is
the worst case; the 95th-percentile background is `rgb(69, 72, 80)`.
Holographic is measured against the darkest pixel of the bundled marble, pink
`rgb(243, 185, 223)`, which is the worst case for its black text.

| Token | Use | Ratio | Target |
| --- | --- | --- | --- |
| Ink `#181B1F` | Values and titles | 15.34:1 | 4.5:1 |
| Ink at 62% | Details and status | 4.65:1 | 4.5:1 |
| Ink at 68% | Charging state | 5.64:1 | 4.5:1 |
| Alert text `#B23A2E` | "Not updated", failures | 5.27:1 | 4.5:1 |
| Alert `#E05C4E` | Low-battery icon only | 3.21:1 | 3:1 (non-text) |
| Signal blue `#375377` | Arcs, actions | 6.99:1 | 3:1 |
| White | Landscape values and titles | 6.37:1 worst, 9.08:1 typical | 4.5:1 |
| White at 78% | Landscape details | 4.63:1 worst, 6.30:1 typical | 4.5:1 |
| Landscape alert `#FFD4CC` | Landscape failures | 4.73:1 worst | 4.5:1 |
| Holographic ink `#0D0F10` | Holographic values, titles, arcs | 11.73:1 worst | 4.5:1 |
| Holographic ink at 68% | Holographic details | 5.39:1 worst | 4.5:1 |
| Holographic alert `#8C2A1F` | Holographic failures and low-battery icon | 5.20:1 worst | 4.5:1 |
| Secondary ink (ink at 62%) | Window captions, theme circles, reorder grip | 4.65:1 | 4.5:1 |

Before this pass, the battery sample age used ink at 50% (3.23:1) and failure
text used the icon red (3.21:1). Both failed 4.5:1 and were changed. Later,
window captions used the system secondary label color (3.88:1), the
unselected theme circle used ink at 36% (2.21:1), and the reorder grip used
the system secondary color at 55% (1.96:1); all now use secondary ink. Under
Increase Contrast, every secondary token is solid ink.

## Manual check procedure

Run these on the current release with the state gallery open for reference
(`swift test`, then open `.build/state-gallery/popover/index.html`). Record the
date, macOS version, and result in the log below.

1. **VoiceOver order.** Turn on VoiceOver (Command-F5). Open the popover and
   move through it with VO-Right. Expect: refresh status, each tile in order
   ("Readiness, 84, Good"), permission button if shown, battery,
   menu. Confirm a stale tile reads "Not updated; showing the last known value".
2. **Announcements.** Reorder a stat in Appearance with Up/Down on the focused
   grip and confirm the new position is announced. Copy the callback URL and
   confirm "Callback URL copied". Choose Refresh Now and confirm "Stats
   updated" (or the failure) is announced.
3. **Keyboard-only onboarding.** Disconnect, then complete all three
   Connection steps using only Tab, Space, and Return.
4. **Keyboard strip.** Open the popover, press Tab to reach the first stat,
   then Left and Right Arrow to move and scroll, and Option-Right to move a
   stat. Confirm the new position is announced.
5. **Text size.** Set Appearance > Text size to Extra Large and check the
   popover at its narrowest width and every window for clipping.
6. **Reduced motion.** Enable Reduce Motion. Refresh and confirm the status
   label and spinner do not animate; drag a stat and confirm it moves without
   interpolation. In Holographic, move the pointer over the popover and confirm
   the background stays flat.
7. **Increase Contrast.** Enable Increase Contrast, reopen the popover, and
   check that details and the footer turn solid in every theme, and that
   window captions turn solid in Appearance and Connection.
8. **Focus.** Tab through Appearance and Connection and confirm a visible focus
   ring on every control.

## Manual check log

| Date | macOS | Checks | Result | By |
| --- | --- | --- | --- | --- |
| Not yet run | | | | |
