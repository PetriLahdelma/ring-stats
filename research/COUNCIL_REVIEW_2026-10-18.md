# Council review, 2026-10-18

Five seats reviewed Ring Stats 1.4.0 plus the unmerged user guide: market and
positioning, growth and distribution, UX and onboarding, engineering and
correctness, security and privacy. Each seat read the repository; the market
and growth seats also searched the web and read the repository's traffic and
release data. External claims that drive a product change were re-checked
against the primary source before being acted on.

Baseline on the day: 3 stars, 56 downloads since the 2026-09-29 launch, 42
README views by 7 visitors in the previous 14 days, 0 Discussions, 9 open
issues. Google returns nothing for Ring Stats on "oura menu bar mac"; GitHub's
own search does.

## Verdict

The product is sound and the posture is good; the problem is reach, and one
onboarding step that sends people to the Oura portal twice. The single fact
that changes the plan: Oura discontinued Oura on the Web on 2026-10-05
(support.ouraring.com article 43392924561171), so for the first time Oura
members are searching for a desktop surface and the first-party one is gone.
The promotion hold in ROADMAP P0.1 was protecting against a risk every
comparable free tool ignores; it now applies to funding only.

## Market and positioning

Target user, restated: an Oura member who works at a Mac all day, already
keeps Raycast or similar utilities in the menu bar, and checks Readiness and
ring battery before planning the day's effort. Sizing: about 5M paying
members (S-1 coverage, 2026-09-28), roughly 30% at a Mac during the day,
1 to 3% menu-bar-utility adopters: a ceiling of 15k to 45k installs. The
closest comparable with public numbers, the Raycast Oura extension, has 571
installs.

The real competitors are not Oura's widgets or Ring Widget. Verified on
2026-10-18:

| | Vitra | Raycast Oura extension | oura-bar | Cracked Oura |
|---|---|---|---|---|
| Form | Mac and Windows desktop app, menu-bar readout on Mac | 9 Raycast commands incl. a menu-bar item | Swift + Bun menu-bar app, build from source | Electron dashboard |
| Price | 19 or 29 euro one-time | Free | Free, MIT | Free |
| Ring battery | No | No | No | No |
| Own Oura developer app | Not stated | Yes | Yes | No (data export) |
| History on disk | Yes | No | No | Yes |

Ring Stats is the only one that shows the ring battery, and the only one that
is free, signed, notarized, and native at the same time. Battery was bullet
four of eight in the README and is now in the pitch.

Positioning: Ring Stats is the free, native Mac menu-bar glance at today's
Oura scores and ring battery, with no server so health data goes from Oura
to the Mac and nowhere else. Now that Oura on the Web is gone, it is the
fastest way for a desk-bound Oura member to see Readiness and battery without
reaching for a phone.

## Growth and distribution

Everything below is a passive listing the roadmap already allowed, ranked by
expected downloads per hour of work. None is done yet; all are user-side
because they publish under the maintainer's name.

1. awesome-mac pull request, Menu Bar Tools (116k stars; entry must be synced
   into the four language READMEs).
2. open-source-mac-os-apps pull request (51k stars; `applications.json`,
   categories Menubar and Medical).
3. macmenubar.com submission (Health category has no wearable app).
4. awesome-swift-macos-apps pull request (the maintainer posts each new entry
   on X).
5. Compress the README images (2.7 MB above the fold) and record the 6 to 8
   second Holographic GIF; the GIF is the asset every listing and post needs.
6. Seed three Discussions so the tab is not empty: which ring and Mac,
   Gen2 and Intel reports wanted, ideas for the five-second glance.
7. Topics: `macos-menubar`, `smart-ring`, `oura-api`, `sleep-tracking`,
   `readiness`; and an entry in awesome-quantified-self.
8. The Oura confirmation email, now scoped to funding only; the published
   address is api-support@ouraring.com, or the portal's review form.

Then, no longer blocked: one post in r/ouraring positioned as the free,
open-source, no-server answer to the dashboard shutdown, with the GIF.

## UX and onboarding

Ranked by effect on activation. Done in this review unless marked.

1. Steps 1 and 2 forced two trips to the portal: the create form asks for
   the redirect URI, which the app revealed one step later. The flow is now
   two steps; the URI and its Copy button sit beside the portal link.
2. Browser-side failures (redirect mismatch, wrong client ID, membership
   block) were invisible: the window said "Waiting…" forever. After 20
   seconds it now names the likely cause.
3. The membership requirement was in the README and the guide but not in
   the app. It is on step 1.
4. The first-value moment was five "Not published" tiles under "Updated
   just now", which reads as broken. A caption under the strip explains the
   sync, and the status line reads "Checked just now · nothing published
   yet". The Connected step says the same.
5. The credentials step had no route back to the portal. It has a link.
6. The guide pointed "Needs access" at the menu instead of the Enable button
   under the stats. Fixed in the guide. Open: a visible action for
   "Unavailable" when no prior value exists.
7. The disconnected popover did not reduce the perceived cost of connecting.
   It now says free, two minutes, your own app.
8. See 4.

The connected popover answers "how am I today" in five seconds at every
width; no change there.

## Engineering and correctness

Six findings, five confirmed by tracing the path, all fixed with a test.

1. High. `updateConnectionState()` clobbered `.authorizing` when the
   background scheduler or a Shortcut ran while the browser was open; the
   Connection window lost its Cancel button and re-enabled the fields. Guarded
   on pending tasks. Test: `updateConnectionStateDuringPendingAuthorizationKeepsAuthorizing`.
2. Medium. `performRefresh` demoted `.authorizationExpired` to
   `.configured` on popover open, so Shortcuts said "not connected" instead of
   "expired". Test: `popoverRefreshAfterExpiryKeepsAuthorizationExpired`.
3. Medium. `QueryDates` formatted with the machine's time zone, not the
   calendar's; the range test failed on any Mac west of UTC. Test:
   `dayStringHonorsCalendarTimeZone`.
4. Low-medium. A Retry-After longer than the TTL was clamped to the TTL on
   popover open, re-hitting the limited endpoint. Test:
   `rateLimitedRetryAfterLongerThanTTLDefersTheRetry`.
5. Low. A port held by another copy of Ring Stats surfaced as "Address
   already in use". It now says so in the app's words. Test:
   `startOnAnOccupiedPortExplainsTheConflict`.
6. Plausible. A refresh finishing after a disconnect or invalidation wrote
   its token back. Guarded. Test:
   `refreshFinishingAfterInvalidateDoesNotResurrectTheToken`.

Judged non-issues: the waiter loops, the callback listener lifecycle, token
lifecycle edge cases, wake from sleep, Shortcuts on cold launch, memory.
Still open from earlier reviews: `DispatchGroup.wait` in the listener, tile
ages not ticking while the popover is open, Increase Contrast read at draw
time.

## Security and privacy

The posture is sound: the loopback listener, Keychain attributes, typed
diagnostics, Shortcuts output, and CI pinning match PRIVACY.md and
THREAT_MODEL.md. Seven findings, one worth code.

1. Medium, fixed. The legacy plaintext credentials file inside the app
   container is writable by any process running as the user, and a
   `redirectURI` planted there was used as the OAuth redirect: the consent
   screen would have sent the code to the attacker. The redirect sent is now
   always one of the two loopback forms. Test:
   `aSavedRedirectOutsideTheLoopbackIsIgnored`.
2. Low, accepted. Oura's revoke endpoint takes the access token as a query
   parameter. Documented.
3. Low, fixed. `ALLOW_UNSIGNED_TAG=1` contradicted the published guarantee
   that releases are built only from signed tags. Removed.
4. Low, fixed. The provider's raw `error` value was shown to the user.
   Mapped. Test: `callbackErrorsAreNotEchoedToTheUser`.
5. Document accuracy, fixed. "Device-only accessibility" holds in the
   data-protection Keychain; SECURITY.md says so now.
6. Document drift, fixed. The pre-1.3.2 redirect statement in the threat
   model.
7. Info, fixed. `CODEOWNERS` now routes the release path (scripts, workflow,
   entitlements, Package.swift) to the maintainer.

## What this review changed

- App: two-step onboarding with the redirect URI on step 1, portal link on
  step 2, browser-error hint, membership line, nothing-published caption and
  status, disconnected caption, the six engineering fixes, the redirect
  allow-list, mapped callback errors, the port-in-use message.
- Documents: README pitch (battery, Oura on the Web), the "Compared with"
  table against the real competitors, PRODUCT.md user, ROADMAP P0.1 narrowed
  to funding, FUNDING.yml buttons off until confirmation, THREAT_MODEL,
  SECURITY, RELEASING, DESIGN, the user guide, CHANGELOG, CODEOWNERS.
- Tests: 205, up from 196.

## What is left for the maintainer

In order: upload nothing new (the social preview is set); record the GIF and
compress the images; open the four listing pull requests and the directory
submission; seed the three Discussions; add the five topics; send the
funding email; post once in r/ouraring. Then the next council measures
downloads per listing.
