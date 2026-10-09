# Contributing

Thank you for improving Ring Stats. This guide is the whole process. Follow
it step by step; a pull request that skips a step will be asked to go back
to it.

Ring Stats is a small, privacy-first macOS menu-bar app for smart rings. Every
change should keep it glanceable, private, Mac-native, and independent of any
ring vendor's brand. Read [PRODUCT.md](PRODUCT.md) and
[ROADMAP.md](ROADMAP.md) before proposing anything larger than a fix.

## Ways to help without code

- **Accessibility testing.** Run the manual procedure in
  [ACCESSIBILITY.md](ACCESSIBILITY.md) with VoiceOver, keyboard only, Reduce
  Motion, or Increase Contrast, and report what you find.
- **Usability sessions.** Take part in or run a session from
  [research/USABILITY_STUDY.md](research/USABILITY_STUDY.md).
- **Ring owners.** If you own a ring listed as a candidate in
  [research/RING_PROVIDERS.md](research/RING_PROVIDERS.md), you can confirm
  how its API behaves with a real account.
- **Translations,** once localization lands (see the issue list).
- **Bug reports** with clear reproduction steps.

## 1. Find or propose the work

1. **Look for an issue.** Issues labeled
   [`good first issue`](https://github.com/PetriLahdelma/ring-stats/labels/good%20first%20issue)
   are small and well defined. Issues labeled
   [`help wanted`](https://github.com/PetriLahdelma/ring-stats/labels/help%20wanted)
   are larger and welcome outside help.
2. **Claim it.** Comment on the issue that you are working on it before you
   start. If an issue is claimed and has had no activity for 14 days, ask in
   a comment whether you can take it over.
3. **Propose before building anything new.** For a feature, a new setting, a
   new ring, a dependency, or any change to privacy, sign-in, or storage,
   open a [Discussion](https://github.com/PetriLahdelma/ring-stats/discussions)
   or a feature request first and wait for the maintainer to agree. Pull
   requests for unagreed features are closed, however good the code is.
4. **Fixes can go straight to a pull request** when they are small and
   obviously correct: a crash, a typo, a broken link, a failing test.

## 2. Ground rules

These are not negotiable. A pull request that breaks one is not merged.

- **Rings only.** Ring Stats supports smart rings. Bands and watches are out
  of scope.
- **Documented vendor APIs only.** No Bluetooth reverse engineering, browser
  automation, scraping, private endpoints, or assets extracted from a vendor
  app.
- **No server, no aggregator.** Health data travels only between the vendor
  and the user's Mac. Do not add a backend, proxy, or third-party health-data
  service.
- **Health data stays in memory.** No telemetry, analytics, crash reporting,
  or health-history database.
- **No shared secrets.** Never embed a client secret. Each user brings their
  own credentials, stored in Keychain.
- **Hidden stats are not fetched.** Requests stay limited to the stats a user
  has enabled, except when a Shortcuts action asks for a stat by name.
- **No new dependencies** without prior agreement. The project uses only
  Apple frameworks.
- **No vendor marks.** Do not add vendor logos, icons, or other brand assets,
  and do not imply endorsement. See [TRADEMARKS.md](TRADEMARKS.md).
- **Never commit** credentials, tokens, health data, signing material, logs,
  local paths, or screenshots containing private information. Screenshots
  must use the state gallery's synthetic data.
- **Security issues go private.** Report vulnerabilities, or anything
  involving credentials, tokens, or health data, through
  [private vulnerability reporting](https://github.com/PetriLahdelma/ring-stats/security/advisories/new),
  never in a public issue or pull request. See [SECURITY.md](SECURITY.md).

## 3. Set up

Requirements:

- macOS 14 or later
- Xcode 26 or 27, or another toolchain supporting Swift tools version 6.2.
  Release builds pin SwiftPM's native build engine (`--build-system native`),
  because Xcode 27's Swift Build engine writes the build machine's paths into
  every swiftmodule and so into the dSYM.
- Git

No package installation is needed.

1. Fork the repository on GitHub and clone your fork.
2. Create a branch from the latest `main`. Name it after the change, in
   lowercase with hyphens, for example `battery-threshold` or
   `fix-stale-heart-rate`.
3. Run the full verification once before changing anything (step 5), so you
   know your setup works.

You do not need an Oura account or a ring. The tests use fakes, and Oura's
public sandbox provides realistic data (step 5).

## 4. Make the change

### Scope

- **One change per pull request.** Keep unrelated cleanup, refactors, and
  formatting out; send them separately.
- **Do not bump the version** in `native/Info.plist` and do not add release
  headings to the changelog. The maintainer does both when releasing.

### Code

- Follow the surrounding code: its naming, access levels (`package` across
  modules), comment density, and structure. The module layout and the
  provider boundary are described in [ARCHITECTURE.md](ARCHITECTURE.md).
- Keep UI state and errors typed. Do not infer permissions or states by
  searching strings.
- Record diagnostics only through `DiagnosticEvent` cases. Never add a case
  that carries free text, health values, identifiers, or response bodies.
- A new ring's stats get their own `Metric` cases. Do not map another
  vendor's score onto an existing Oura one; only truly shared quantities,
  such as battery percentage, share a shape.
- Swift 6 strict concurrency applies. Warnings are errors.

### Tests

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Name a test as a sentence about behavior, for example
  `staleOrUnknownBatteryNeverAlerts`.
- Put a test in the suite for the boundary it exercises: `AppViewModelTests`,
  `ProviderBoundaryTests`, `OuraAPITests`, `OAuthClientTests`,
  `InfrastructureSecurityTests`, `DiagnosticsTests`, `StateGalleryTests`, and
  the feature suites beside them. `RingStatsTests.swift` holds the older
  free-standing tests of pure helpers (score bands, status text, reorder
  math, contrast); add to a suite instead of there. Shared fakes live in
  `TestSupport.swift`.
- Wait on explicit gates (`Gate`, `waitUntil`, `HTTPHold`), and assert on
  what happened, never on elapsed wall-clock time. Never `sleep`.
- Write the test first for security-, state-, time-, or persistence-sensitive
  behavior, and show it failing without your change.
- Tests must run offline. A test that needs the network must be opt-in, as
  `OuraSandboxTests` is.

### UI

- Check every new or changed view in the state gallery (step 5), in all
  three themes, at narrow and wide popover widths.
- Check it against [ACCESSIBILITY.md](ACCESSIBILITY.md): VoiceOver labels,
  keyboard access, Reduce Motion, and contrast. Update its matrix when
  behavior changes.
- Customization lives only in **Appearance** in the popover menu. Do not add
  a second settings button or icon.

### Writing

- User-facing text is short, plain, and specific. Say what happened and what
  to do next.
- Do not use em dashes in code comments, user-facing text, or documentation.
  Use commas, colons, semicolons, or separate sentences.

### Documentation

Update every document whose subject your change touches, in the same pull
request:

| If you change | Update |
|---|---|
| Anything a user can see or do | [CHANGELOG.md](CHANGELOG.md), under `## Unreleased` |
| Data collected, stored, or sent | [PRIVACY.md](PRIVACY.md), [THREAT_MODEL.md](THREAT_MODEL.md) |
| Modules, the provider boundary, runtime flow | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Visual design, copy, or layout | [DESIGN.md](DESIGN.md) |
| Accessibility behavior | [ACCESSIBILITY.md](ACCESSIBILITY.md) |
| Build, signing, or release scripts | [RELEASING.md](RELEASING.md) |
| Shipped roadmap items | [ROADMAP.md](ROADMAP.md) |

### Commits

- Subject line: imperative, sentence case, no trailing period, at most 72
  characters, no prefix such as `feat:`. Example:
  `Let users choose the low-battery threshold`.
- Body: explain why the change is needed and what it does, wrapped at 72
  characters. Leave the how to the diff.
- If an AI tool helped write the change, say so in the pull request. You are
  still responsible for understanding and verifying every line.

The maintainer squash-merges every pull request, so the pull request title
becomes the commit subject on `main`. Give it the same form.

## 5. Verify locally

Run all of these from the repository root. Every command must exit 0.

```bash
swift test -Xswiftc -warnings-as-errors
BUILD_ARCHS="arm64 x86_64" scripts/build_app.sh
scripts/verify_release_artifacts.sh
scripts/verify_candidate_manifest.sh
scripts/tests/test_delivery_safety.sh
scripts/tests/test_sandbox_keychain.sh
scripts/tests/test_container_migration.sh
```

Then, depending on what you changed:

- **UI:** `swift test` writes a state gallery of every popover state, theme,
  and width, plus each onboarding step, to `.build/state-gallery/`. Open
  `.build/state-gallery/popover/index.html` and review every state your
  change affects. The gallery tests check bounds, theme parity,
  width-independent height, truncation
  (`everyTileDetailFitsTheTileWithoutTruncation`), and contrast
  (`themeTextColorsMeetWCAGContrastForSmallText`).
- **Oura client or its response models:** run the real client against Oura's
  public sandbox. It needs the network but no account or ring:

  ```bash
  RING_STATS_LIVE_SANDBOX=1 swift test --filter OuraSandboxTests
  ```

- **Visual regressions:** each gallery folder also gets a `hashes.json`
  with the SHA-256 of every render. Font rendering differs between Macs, so
  comparing is opt-in: copy a known-good `hashes.json` aside and run
  `RING_STATS_GALLERY_BASELINE=/path/to/hashes.json swift test`; renders
  whose hash changed are reported.

- **Untested code:** `scripts/coverage_report.sh` prints line coverage
  grouped by the boundaries in [ARCHITECTURE.md](ARCHITECTURE.md). Use it to
  find gaps, not as a number to maximize.

The build stays under `dist/`. Launch it without replacing an installed copy:

```bash
open "dist/Ring Stats.app"
```

Local builds are signed ad hoc and are not release candidates. Shortcuts
actions do not run in ad-hoc builds, because macOS requires a Team ID; to test
them, build with `CODESIGN_IDENTITY` set to your own Developer ID Application
identity.

To build and check the DMG as a release would:

```bash
SKIP_BUILD=1 scripts/create_dmg.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
DMG_PATH="$PWD/dist/Ring-Stats-$version.dmg" scripts/verify_release_artifacts.sh
```

## 6. Open the pull request

1. Rebase your branch on the latest `main` and run step 5 again.
2. Open the pull request against `main` and fill in every section of the
   template.
3. **Outcome:** the user-visible effect in one or two sentences.
4. **Verification:** paste the summary line of each command from step 5, for
   example `Test run with 174 tests in 17 suites passed`. Do not just tick
   boxes.
5. **UI changes:** attach before and after screenshots from the state
   gallery.
6. Link the issue the pull request resolves, for example `Closes #12`.

GitHub Actions results are not a merge requirement. The maintainer runs the
full verification locally before merging.

## 7. Review and merge

- The maintainer reviews within about a week. Automated reviewers may also
  comment; address each comment with a change or a reply explaining why not.
- Push follow-up commits to the same branch. Do not force-push after review
  starts, so reviewers can see what changed.
- Once the change is approved and passes local verification, the maintainer
  squash-merges it. It ships in the next signed, notarized release.
- Only the maintainer tags, signs, notarizes, and publishes releases. See
  [RELEASING.md](RELEASING.md).

## Conduct

Be kind, assume good intent, and keep discussion on the work. No harassment,
personal attacks, or discriminatory language, in any project space. Never ask
anyone to share health data, credentials, or tokens. The maintainer may hide
comments, lock threads, or block participants who do not follow this.

## License

Ring Stats is released under the [MIT License](LICENSE). By contributing, you
agree that your contribution is licensed under the same terms and that you
have the right to submit it.
