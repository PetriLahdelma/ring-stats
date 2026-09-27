# Accessibility

[PRODUCT.md](PRODUCT.md) promises keyboard access, VoiceOver support,
sufficient contrast, reduced motion, and that no state relies on color alone.
This page records the evidence for each promise and what still needs a person
to verify. An item is **Verified** only when an automated test or a recorded
manual check proves it.

Status key: **Verified** (automated), **Verified** (manual, dated), **Needs
manual check** (implemented, not yet confirmed with assistive technology), or
**Gap** (known shortfall).

## Matrix

| Area | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| Contrast | Small text meets 4.5:1 in both themes | Verified (automated) | `themeTextColorsMeetWCAGContrastForSmallText`; ratios below |
| Contrast | Icons and arcs meet 3:1 | Verified (calculated) | Signal blue 6.99:1, alert icon 3.21:1 on canvas |
| Color independence | Every value and state appears as text | Verified (automated) | `staleTileSaysSoInTextAndToVoiceOver`, detail copy tests, state gallery |
| Truncation | Tile detail text is never cut off | Verified (automated) | `everyTileDetailFitsTheTileWithoutTruncation` |
| Theme parity | Themes show the same lines and labels | Verified (automated) | `themesKeepTheSameLayoutForEveryState` |
| Widths | Layout holds at 420, 680, and 840 pt | Verified (automated) | `popoverStatesRenderWithinBoundsAtEverySupportedWidth` |
| Overflow | Hidden stats are discoverable | Verified (automated) plus hint | Edge fades from `MetricStripLayout.overflow`; VoiceOver hint "More stats are available by scrolling" |
| Reduced motion | Reordering, settling, and status fades do not animate | Verified (automated) for reordering; Needs manual check for status fade and spinner | `reducedMotionReorderSettlementIsImmediate`; `RefreshStatusView` and `ScoreLoadingSpinner` read `accessibilityReduceMotion` |
| VoiceOver labels | Each tile reads title, value, and state | Verified (automated) for label text; Needs manual check for reading order | `MetricGauge.accessibilityLabel` tests |
| VoiceOver status | Refresh status is readable even when visually hidden | Needs manual check | Always-present accessibility element in `RefreshStatusView` |
| VoiceOver announcements | Reorder, copy, and connection success are announced | Needs manual check | `AccessibilityNotification.Announcement` in reorder, callback copy, diagnostics copy, and connection |
| Keyboard | Popover dismisses with Escape | Verified (automated) | `statusPopoverEscapeInvokesCancellationHandler` |
| Keyboard | Onboarding completes without a pointer | Needs manual check | Default-action buttons on every step, focused Client ID field |
| Keyboard | Stats can be reordered without a pointer | Needs manual check | Focusable grip with Up/Down keys and Move Up/Down actions in Appearance |
| Keyboard | Metric strip scrolls without a pointer | Gap | The popover strip has no keyboard scroll; use Appearance to reorder or hide stats |
| Focus | Focus is visible on every control | Needs manual check | Native controls only; custom grip uses system focus ring |
| Increased contrast | Increase Contrast setting is respected | Needs manual check | Colors are fixed tokens; system controls adapt |
| Text size | Text scales with the macOS text-size setting | Gap | Popover uses fixed point sizes sized to the 92 pt tile; macOS does not apply Dynamic Type to these views |
| Localization | Layout survives longer translations | Gap | English only; truncation tests cover current copy |

## Measured contrast

Ratios use WCAG 2.x relative luminance. Default theme text is measured on
Canvas Warm (`#F4F1EC`). Landscape is measured against the brightest pixel of
the bundled photograph under its lightest veil, `rgb(108, 92, 81)`, which is
the worst case; the 95th-percentile background is `rgb(69, 72, 80)`.

| Token | Use | Ratio | Target |
| --- | --- | --- | --- |
| Ink `#181B1F` | Values and titles | 15.34:1 | 4.5:1 |
| Ink at 62% | Details, status, sample age | 4.65:1 | 4.5:1 |
| Ink at 68% | Charging state | 5.64:1 | 4.5:1 |
| Alert text `#B23A2E` | "Not updated", failures | 5.27:1 | 4.5:1 |
| Alert `#E05C4E` | Low-battery icon only | 3.21:1 | 3:1 (non-text) |
| Signal blue `#375377` | Arcs, actions | 6.99:1 | 3:1 |
| White | Landscape values and titles | 6.37:1 worst, 9.08:1 typical | 4.5:1 |
| White at 78% | Landscape details | 4.63:1 worst, 6.30:1 typical | 4.5:1 |
| Landscape alert `#FFD4CC` | Landscape failures | 4.73:1 worst | 4.5:1 |

Before this pass, the battery sample age used ink at 50% (3.23:1) and failure
text used the icon red (3.21:1). Both failed 4.5:1 and were changed.

## Manual check procedure

Run these on the current release with the state gallery open for reference
(`swift test`, then open `.build/state-gallery/popover/index.html`). Record the
date, macOS version, and result in the log below.

1. **VoiceOver order.** Turn on VoiceOver (Command-F5). Open the popover and
   move through it with VO-Right. Expect: refresh status, each tile in order
   ("Readiness, 84, Good"), permission button if shown, battery, Customize,
   menu. Confirm a stale tile reads "Not updated; showing the last known value".
2. **Announcements.** Reorder a stat in Appearance with Up/Down on the focused
   grip and confirm the new position is announced. Copy the callback URL and
   confirm "Callback URL copied".
3. **Keyboard-only onboarding.** Disconnect, then complete all three
   Connection steps using only Tab, Space, and Return.
4. **Reduced motion.** Enable Reduce Motion. Refresh and confirm the status
   label and spinner do not animate; drag a stat and confirm it moves without
   interpolation.
5. **Increase Contrast.** Enable Increase Contrast and check both themes for
   legibility of details and the footer.
6. **Focus.** Tab through Appearance and Connection and confirm a visible focus
   ring on every control.

## Manual check log

| Date | macOS | Checks | Result | By |
| --- | --- | --- | --- | --- |
| Not yet run | | | | |
