# Ring Stats council review, 2026-10-09

Five independent reviews of main at `0c3415e` (1.3.6 plus the unreleased
keyboard work): correctness, security and privacy, UX and design, growth,
and engineering health. Each reviewer read the code and documents on their
own; the growth reviewer also searched the Oura community and comparable
apps. The findings below are the ones that survived cross-checking against
the code. Where two reviewers reached the same conclusion from different
angles, it is marked **(2 reviewers)**.

Repository facts at review time: 3 stars, 0 forks, about 20 DMG downloads
across 10 releases, 42 merged pull requests all by the maintainer, 8 open
starter issues with no outside comments, CI green on macos-26.

## Verdict in one paragraph

The engineering is well above what a two-week-old solo project usually has:
typed diagnostics that cannot carry secrets, a loopback listener with an
adversarial test suite, atomic Keychain state with migration, fail-closed
release provenance, and an honest threat model. The product is genuinely
glanceable and honest about freshness. What holds it back is not quality but
three gaps: a handful of real bugs in refresh, token, and battery logic that
tests did not reach; a first impression (README, grey first-run button, no
Dark Mode) that undersells it; and zero discoverability. Fixing the bugs is a
week; the README and metadata are a day; Dark Mode and a value in the menu
bar are the two features most likely to turn users into sharers.

## 1. Bugs, ranked (all verified against the code)

| # | Severity | Where | What goes wrong | Fix |
|---|---|---|---|---|
| 1 | High | `OuraAPI.swift:387`, `Models.swift:455` | `Retry-After` is parsed with `TimeInterval.init`, which accepts `inf`, `nan`, and `1e400`; `Int(ceil(retryAfter))` then traps. A malformed 429 crashes the app; a huge finite value silently suppresses refresh-on-open until relaunch. | Parse with `Int`, accept only `1...3600`, clamp in `retryDelay`. |
| 2 | Medium | `AppViewModel.swift:105-111`, `:218-225` | A caller waiting on an in-flight refresh computes "covered" once and never re-checks. Two waiters (a Shortcut wanting an extra metric and Refresh Now) can both start after the first refresh ends, run concurrently, fight over `state`, and the later one can drop readings the earlier fetched. `authorize()` has the same shape and can show "Connected" while the browser flow is still live. | Loop: `while let running = refreshTask { recompute covered; await; if covered return }`; same loop in `authorize()`. |
| 3 | Medium | `OAuthClient.swift:171-174`, `:258-264` | A successful token refresh is written to Keychain before memory. If the save fails (locked Keychain, `errSecInteractionNotAllowed`), the new pair is discarded, the consumed refresh token is replayed next time, Oura answers `invalid_grant`, and the user is sent back through the browser although a valid token was received. `exchange()` has the same order. | For a freshly obtained token, update memory first, then persist; surface a save failure as a non-fatal warning. |
| 4 | Medium | `BackgroundPolicies.swift:34-43` | The low-battery alert re-arms only on a sample with `isCharging == true`. The app samples every 30 min (2 h on battery), so a ring charged between samples comes back as `100%, not charging` and the alert stays disarmed for every future drain until relaunch. | Also re-arm when the level recovers, e.g. `level >= threshold + 30`. |
| 5 | Medium | `Models.swift:322-325` | A battery reading kept after a transient failure has no timestamp and no retention limit. Metrics expire after 24 h; the battery is shown, and returned by the Shortcut, for as long as the endpoint keeps failing. ARCHITECTURE.md line 101 says the battery "does the same" as metrics; it does not. | Add `batteryFetchedAt` to `HealthSnapshot` and apply `staleRetentionLimit`. |
| 6 | Medium-low | `BackgroundRefresher.swift:75-79`, `BackgroundPolicies.swift:15-19` | The battery-power policy keys off `lastUpdatedAt`, which only advances on success. With no network or no data yet, a laptop on battery refreshes every 30 min instead of every 2 h, the exact case the policy exists for. | Use the later of the last success and the last attempt. |
| 7 | Low | `OuraAPI.swift:116-125`, `:286-289` | A stress record with `day_summary` but no `stress_high` becomes an `.available` reading with value "—", counts as data, and the Shortcut returns the literal "—". The fallback detail "High stress" appears when the summary is missing, which reads like a diagnosis. | Require `stress_high`; neutral fallback detail. |
| 8 | Low | `ShortcutAnswers.swift:85-89`, `BackgroundRefresher.swift:68-70` | `authorizationExpired` is cleared by `updateConnectionState()` before the Shortcut checks for it, so Shortcuts say "not connected" instead of "authorization expired", and `errorMessage` is left set while the popover shows the empty state. | Check for expiry before `updateConnectionState()`; preserve the state or clear the message. |
| 9 | Low | `OuraAPI.swift:156-159` | When every metric legitimately has no data and only the battery request fails transiently, the whole refresh is reported failed instead of "No data yet" plus a stale battery. | Count a successful empty response as success. |
| 10 | Low | `AppViewModel.swift:150-153` | The "already fresh" shortcut sets `.connected` without clearing a stale `errorMessage`, so the error line stays under fresh tiles. | Clear it on that branch. |
| 11 | Low | `CallbackServer.swift:196` | `DispatchGroup.wait()` inside an actor pins a cooperative-pool thread for up to the 10 s deadline while a peer trickles bytes. | `closed.notify` into a continuation. |
| 12 | Low | `Theme.swift` (`increasesContrast`) **(2 reviewers)** | Increase Contrast is read at draw time, not observed; toggling it with the popover open does not redraw. | Observe `NSWorkspace.didChangeAccessibilityDisplayOptionsNotification`. |

Suspicious, not confirmed from code alone:

- Whether Oura's `GET /oauth/revoke` on the previous access token revokes
  only that token or the whole grant. If the latter, reauthorization kills
  the new token seconds later. One check against the real endpoint settles it.
- `finishReordering` sets `settlementID` and clears it only in an animation
  completion; if the popover is ordered out mid-settle, reordering may stay
  disabled until relaunch. Needs a runtime check; a fallback timer is a cheap
  guard.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is passed to the classic
  (file) Keychain on the fallback path; Apple documents it for the
  data-protection keychain. If rejected, the unsandboxed fallback can never
  save.

## 2. Security and privacy

The documents are unusually accurate; nearly every promise is enforced in
code and backed by a test. Keep: typed diagnostics with no string case, the
atomic Keychain item with tombstone, the exclusive dual-stack listener with
its DoS tests, fail-closed provenance redaction, and fixed error messages
that never surface upstream bodies.

Gaps:

1. **Four tracked zero-byte files** `Sources/RingStatsOura/.!78163!OAuthClient.swift`
   and three siblings, committed in #7, compiled into every attested release
   **(2 reviewers)**. Remove them, add `.!*!*` to `.gitignore`, and fail CI on
   dotfiles under `Sources/`.
2. `verify_release_artifacts.sh` never asserts the hardened runtime flag;
   notarization would catch a regression, but only after Gate A. Add a
   `codesign -dvv | grep 'flags=.*runtime'` check.
3. CI grants `id-token: write` and `attestations: write` to the whole job,
   including same-repo PR runs that execute repository scripts. Move the
   attest steps to a second job with `needs: test`.
4. `sign_and_notarize.sh` checks the tag against a local `origin/main`
   without fetching; `ALLOW_UNSIGNED_TAG=1` bypasses signature verification
   invisibly. Fetch first; record any bypass in the attestation predicate.
5. OAuth `state` is compared with `==`. Theoretical over loopback; a
   constant-time compare costs one line.
6. Documentation drift: PRIVACY.md says "IPv4 loopback listener" (it binds
   `::1` too); SECURITY.md tells verifiers to pass `<maintainer-email>` where
   the principal must be the literal `ring-stats@users.noreply.github.com`;
   `CallbackServer.maximumHeaderBytes` at line 18 is dead.

## 3. UX and design

Verified in the state gallery:

1. **First-run Connect and "Enable Stress Access" render grey, as if
   disabled.** The popover panel is never the key window, so
   `.borderedProminent` and `.bordered` draw inactive. DESIGN.md already
   solved this for the Connection window with `primaryAction`; apply it in
   the popover and to Diagnostics' Save. This is the first button a new user
   sees.
2. **No Dark Mode.** Every view forces `.light`. A dark-menu-bar user gets a
   cream panel at night. The biggest "not Mac-native" tell, and an
   accommodation issue for light-sensitive users. Give the Ring Stats theme a
   dark canvas that follows the system; keep Landscape and Holographic as
   explicit overrides; let windows follow the system.
3. **Freshness is hidden in the most common state.** "Updated 2m ago"
   disappears between 3 s and 5 min after a refresh. Keep it always visible in
   secondary ink and make it the retry button on failure ("Update failed ·
   1h ago · Retry"), replacing the second error sentence under the strip.
4. **Stale tiles hide their age from sighted users** while VoiceOver hears it.
   Show "Not updated · 2h". Same for the battery beyond 24 h.
5. **"No data yet" under "Updated just now"** reads as a contradiction.
   Say "Not published yet" or "After tonight's sync".
6. At 420 pt the fourth tile is sliced through its digits; snap the width to
   whole tiles. Hidden scroll indicators exclude mouse users without a
   horizontal wheel.
7. Appearance at Extra Large is 1060 pt tall, more than a 13-inch display,
   with 250 pt of empty space under the list; the Connection steps waste
   200 to 300 pt. Size to content.
8. Copy: four terms for one concept ("Reauthorize Permissions", "Enable Stress
   Access", "Needs access", "authorization required"); "I Have Created It" is
   stilted; "42m" reads as metres; heart rate's unit sits on a different line
   from its number; theme summaries describe implementation, not experience;
   "About & Credits" should be "About Ring Stats".
9. Accessibility: the manual check log is still empty; tiles put the value
   inside the label with no `accessibilityValue` or trait; the Diagnostics
   report is one giant `Text`; the disabled last-visible checkbox has no hint;
   the ☰ focus ring in Holographic reads as a selected toggle.

The five changes most likely to make a daily user love it: Dark Mode; an
opt-in value in the menu bar (Readiness, or battery only when low); always
visible, clickable freshness; a global hotkey to open the popover; a
"waiting for today's sleep" state with an opt-in "scores are in" notification.

Mistakes to avoid: trends or history (needs a database, breaks "private by
default"); coloring rings by band (breaks the One Blue Rule and the
color-independence rule); a hosted OAuth proxy or shared secret to shorten
onboarding (erases the product's strongest claim).

## 4. Growth and GitHub stars

Why a visitor does not star today, ranked:

1. The README reads like a compliance document: legal phrasing in sentence
   one, a trademark disclaimer in paragraph two, SHA-256 verification as
   install step 2, and roughly 60 percent of its length on build, sign,
   notarize, and legal. The product screenshot appears after all of that.
2. "Bring-your-own Oura developer credentials" is stated flatly, without the
   reason (no server, no shared secret, data goes Oura to your Mac and nowhere
   else) or the cost (free, two minutes, Oura membership needed for Gen3 and
   Ring 4 API access).
3. No "why this exists" sentence. Oura ships no Mac app at all; its widgets
   are iOS, Android, and Apple Watch only. That absence is the pitch.
4. Nothing moves. The Holographic foil twisting under the pointer is the most
   shareable visual and nobody has seen it.
5. Discoverability is near zero: not on any awesome list, no topics beyond
   five, no homepage URL, no social preview image (link cards on Reddit, HN,
   and Mastodon show nothing). Searching "Oura macOS menu bar" finds
   Cracked-Oura (Electron, 429 stars) and a paid App Store app, not Ring
   Stats.
6. The "review the Oura API Agreement before announcing an integration"
   sentence sits on a user's path to Download and reads as "this might be
   disallowed".
7. **FUNDING.yml now shows a Sponsor button while ROADMAP.md says donations
   are on hold pending Oura's written confirmation.** A journalist or Oura
   would notice. Remove the button or update the roadmap.

Allowed now, by the roadmap's own terms:

- README rewrite to about 90 lines: hero image (Holographic popover) and a
  6 to 8 second GIF, one-line pitch, three buttons (Download, How it connects
  in 2 min, Watch releases), a "why your own Oura app, and why that is the
  point" section with the two gotchas (membership; `localhost` not
  `127.0.0.1`), eight user-facing feature bullets, a short honest "Compared
  with" table (Oura widgets, Ring Widget, Cracked-Oura), and the build and
  release material moved to CONTRIBUTING.md and RELEASING.md.
- Repository metadata: description "Oura ring stats in your Mac menu bar.
  Native, open source, no server."; topics `oura-ring`, `menu-bar-app`,
  `macos-app`, `swiftui`, `quantified-self`, `wearables`, `health`; homepage
  set to Releases; a social preview image.
- A third-party Homebrew tap (`PetriLahdelma/homebrew-ring-stats`); the
  official cask needs 75 stars and 30 days first (225 if self-submitted).
- Awesome-list pull requests: jaywcjlove/awesome-mac, awesome-swift-macos-apps,
  serhii-londar/open-source-mac-os-apps. No awesome-oura list exists; creating
  one is cheap and durable.
- Update discovery (#35): a zero-dependency daily check of a static
  `latest.json` on GitHub Pages, shown as "Update available" in the ☰ menu,
  keeps the no-dependency promise and fits the existing timer. Sparkle 2 is
  the alternative if auto-install matters.

When Oura confirms: one channel per day. r/ouraring phrased as an offer
("looking for Intel testers"), the Oura forum, Show HN with the privacy
architecture in the first comment, Product Hunt, then Mastodon and Bluesky
with the GIF, MacRumors forums, and newsletter tips (MacStories, Six Colors,
9to5Mac apps).

Features that get shared, by shareability over effort: battery done better
than Oura (percentage in the menu bar title, "charge before bed" reminder at
a set time, "last charged 3 days ago"; battery is the most common Oura
complaint after subscription cost); a score in the menu bar title; the
Shortcuts and Raycast story told loudly, with a Raycast Store extension;
Ultrahuman support (#32) as a second community; a Focus-mode hook on low
Readiness via Shortcuts.

Contributor funnel: seven of eight issues have no comments and look
abandoned; add a starter plan, file paths, and a time estimate to each. Split
the seven verification commands into two required for contributors and five
the maintainer runs. Soften "pull requests for unagreed features are closed"
to "open a Discussion first so we do not waste your time". Say in the README
that no ring or account is needed to contribute.

## 5. Engineering health

Keep untouched: `AppViewModel` operation fencing and its gate-driven tests;
`CallbackServer` and its adversarial suite; `HealthSnapshot.merging`; the
`DiagnosticEvent` design; `OAuthClient`'s revocation queue; `TestSupport`;
the transactional installer with failure-point injection; the contrast and
truncation tests; zero `public` declarations.

Top improvements, by value:

1. Remove the four zero-byte files (S).
2. Twelve of thirteen `import RingStatsOura` lines in the app target are
   dead; only `AppViewModel.swift:45` uses the module. Delete them and add a
   test that confines the import to a composition root (S).
3. "Oura" is hard-coded in `RingStatsError` (12 strings, Core), four popover
   strings, the window title, seven Shortcut messages, and all of onboarding,
   while `descriptor.displayName` already exists. This is issue #29; the fix
   is a `ProviderCopy` on the descriptor (M).
4. Wall-clock tests: the trickle test asserts elapsed seconds under 2 s; the
   gallery spins the run loop 50 ms as "let SwiftUI settle"; `tabStops` yields
   three times per Tab. Inject a clock, add `.timeLimit` traits (M).
5. Implementation-pinned assertions: Tab-stop counts as bare numbers, a
   popover height of 261 with an unexplained inset of 11, reorder tests that
   reuse the formulas under test, and a test that reads an undocumented
   CoreGlyphs plist (S-M).
6. Coverage holes at the advertised boundaries: no second `HealthProvider`
   conformer is ever built; every test bypasses
   `authorizeConfiguredApplication`, so the browser-open failure, 300 s
   timeout, state mismatch, and `error=` paths are untested; Keychain tests hit
   the real login Keychain; the Shortcut intents have no test; the
   notification-denied branch is untested (M-L).
7. The state gallery asserts bounds and parity but not content; a wrong
   color, clipped label, or wrong value passes. Add an opt-in baseline diff
   on a pinned runner, and make `windowsRenderAtExtraLargeText` assert the
   height it computes (M).
8. Shell scripts: `fail()` defined in eight scripts, three `working_tree_hash`
   implementations, a 30-line Gate B cross-check duplicated in the writer and
   verifier, dead `mount_dir`, and 40 percent of the delivery-safety test
   silently skipped when `dist/` is absent. One `scripts/lib/common.sh`,
   shellcheck in CI, and a loud SKIPPED (M).
9. CI: only macos-26, so the macOS 14 and 15 behavior the package claims to
   support is never exercised; no `.build` cache; no shellcheck (S-M).
10. `RingStatsApp.swift` (685 lines) and `MenuPopoverView.swift` (714 lines):
    four identical window-show methods, four identical menu wrappers, a 75-line
    menu builder, and a 130-line reorder state machine that belongs in
    `MetricReordering.swift`. Magic numbers (120/800/260 popover clamps, 300 s
    timeout, a 15 s request timeout competing with the session's 30 s).
    Preference keys live in five types across four files (M).

Three refactors that most reduce the cost of Ultrahuman:

- **Sign-in as a provider capability.** `HealthProvider.account` is
  `OAuthServicing`; `AppViewModel` owns the browser flow and the 300 s timeout;
  onboarding hard-codes Oura's three steps. Introduce `AccountServicing` with a
  `SignInMethod` (`.browserOAuth` or `.personalToken`), move the loopback flow
  into Core as a tested `BrowserAuthorizationFlow`, and drive the onboarding
  view from the descriptor. This also makes the untested OAuth error paths
  testable.
- **Open the metric model.** `Metric` is a closed enum whose universe is
  `allCases`; `RingStat` in the intents hand-copies it; views switch on
  `isDailyScore`; the placeholder readings live in the Oura target. Give
  `Metric` a presentation kind, normalize configuration against
  `supportedMetrics`, move placeholders to Core, derive `RingStat` from
  `Metric`.
- **A composition root and provider-neutral copy.** A `ProviderRegistry` in
  the app target selected by a persisted `ProviderID`; `import RingStatsOura`
  confined to it; `RingStatsError` without provider nouns. `OAuthClient.swift:99`
  defaulting scopes from `OuraProvider.descriptor` is a reverse dependency to
  remove.

Documentation claims that are now false: ARCHITECTURE.md says the app knows
about Oura "only where it creates OuraProvider and in onboarding copy"; its
persistence table omits text size and the low-battery flag; it says "numeric
local loopback callback" (now `localhost`, dual-stack). README says "both
themes". RELEASING.md refers to an undefined "Lore commit format" and says to
merge "after required checks pass", contradicting CONTRIBUTING.md. SECURITY.md
says the SBOM and attestation are "future". ROADMAP.md lists "two themes" as
shipped two lines above shipping Holographic. ACCESSIBILITY.md's reorder row
still describes the focusable grip, replaced by list selection. CONTRIBUTING.md's
"never sleep" is contradicted by two tests, and its "one suite per boundary"
by `RingStatsTests.swift` (43 free-standing tests).

## 6. Suggested order

1. **This week, bugs for 1.3.7:** items 1 to 7 in section 1, the grey
   primary buttons, the zero-byte files, the hardened-runtime check, and the
   FUNDING.yml decision. About a week of work; every item has a test to add.
2. **Same week, free wins:** README rewrite, repository metadata, social
   preview, GIF, issue grooming, split verification commands.
3. **Next:** Dark Mode, always-visible freshness with retry, stale ages for
   sighted users, value in the menu bar (opt-in), update check (#35).
4. **Then:** the documentation reconciliation, test de-flaking, script
   library, CI matrix, and the three provider refactors, which together make
   Ultrahuman a one-module addition.
5. **When Oura confirms:** the launch sequence in section 4.
