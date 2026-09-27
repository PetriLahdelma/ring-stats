# Contributing

Thank you for improving Ring Stats. Keep changes narrow, test observable
behavior, and preserve the project's privacy and independent identity.

## Requirements

- macOS 14 or later
- Xcode 26 or another toolchain supporting Swift tools version 6.2
- Git

No third-party package installation is required.

## Verify a checkout

From the repository root:

```bash
swift test -Xswiftc -warnings-as-errors
BUILD_ARCHS="arm64 x86_64" scripts/build_app.sh
scripts/verify_release_artifacts.sh
scripts/verify_candidate_manifest.sh
scripts/tests/test_delivery_safety.sh
```

The build stays under `dist/`. To launch it without replacing an installed copy:

```bash
open "dist/Ring Stats.app"
```

To verify the local DMG as CI does:

```bash
SKIP_BUILD=1 scripts/create_dmg.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
DMG_PATH="$PWD/dist/Ring-Stats-$version.dmg" scripts/verify_release_artifacts.sh
```

These local artifacts are ad-hoc signed and are not public release candidates.
The build retains `dist/Ring Stats.app.dSYM` and writes
`dist/candidate-manifest.json`. Install a candidate recoverably with
`scripts/install_local_candidate.sh "dist/Ring Stats.app"`; inspect it locally
before any remote collaboration or release action.

## Change guidelines

- Add or update tests before changing security-, state-, time-, or persistence-
  sensitive behavior.
- Keep UI state and errors typed. Do not infer permissions by searching strings.
- Preserve metric-aware scopes and fetching; hidden metrics must not generate
  health endpoint requests.
- Keep health responses in memory. Do not add telemetry, analytics, crash
  reporting, or a health-history database without an explicit project decision.
- Use only documented Oura endpoints. Do not add BLE reverse engineering,
  browser automation, scraping, or extracted app assets.
- Do not add dependencies without prior discussion.
- Do not commit credentials, health data, signing material, local paths, logs,
  Oura brand assets, or screenshots containing private information.
- Update user, privacy, architecture, release, design, and changelog documents
  when observable behavior changes.

## Pull requests

Use the pull-request template. State the user-visible effect, privacy/security
impact, and exact verification performed. Keep unrelated cleanup separate.

Public issues are for non-sensitive reports only. Use
[private vulnerability reporting](https://github.com/PetriLahdelma/ring-stats/security/advisories/new)
for vulnerabilities, credentials, tokens, health data, or other private
information.
