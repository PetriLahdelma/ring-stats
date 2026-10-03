<!-- Read CONTRIBUTING.md first. Features, settings, new rings, dependencies,
and privacy, sign-in, or storage changes need an agreed issue or Discussion
before a pull request. -->

## Outcome

<!-- The user-visible or maintainer-visible effect, in one or two sentences. -->

Closes #

## Scope

<!-- The intentional changes, and anything deliberately left out. -->

## Privacy and security

- [ ] No credentials, tokens, health data, local paths, signing material, logs, or private screenshots are included.
- [ ] Only documented vendor endpoints are used; no server, aggregator, scraping, or reverse engineering.
- [ ] Changes to scopes, collection, storage, the callback, Keychain, or deletion are tested and documented, or there are none.

## Verification

<!-- Paste the summary line of each command, for example
"Test run with 174 tests in 17 suites passed". Every command must exit 0. -->

- `swift test -Xswiftc -warnings-as-errors`:
- `BUILD_ARCHS="arm64 x86_64" scripts/build_app.sh`:
- `scripts/verify_release_artifacts.sh`:
- `scripts/verify_candidate_manifest.sh`:
- `scripts/tests/test_delivery_safety.sh`:
- `scripts/tests/test_sandbox_keychain.sh`:
- `scripts/tests/test_container_migration.sh`:
- `RING_STATS_LIVE_SANDBOX=1 swift test --filter OuraSandboxTests` (if the Oura client changed):

## UI

<!-- For UI changes: before and after screenshots from the state gallery, and
the accessibility checks you ran. Otherwise write "No UI change". -->

## Documentation

- [ ] CHANGELOG.md (under Unreleased) and every other affected document are updated, or nothing is affected.
- [ ] No version bump and no release heading.

## AI assistance

<!-- If an AI tool helped write this change, say which parts. -->
