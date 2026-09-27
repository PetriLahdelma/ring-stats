# Releasing

Only publish artifacts produced from a reviewed, clean commit. CI artifacts are
ad-hoc signed test outputs, not public releases.

The delivery order is binding: build and recoverably install a local candidate,
obtain explicit user approval for its tree (Gate A), and only then perform any
push, pull request, tag, signing, or notarization action. After producing the
reviewed/notarized artifact, install that exact artifact locally and obtain a
second exact-hash approval (Gate B) before public upload.

## Prerequisites

- Apple Developer Program membership
- A `Developer ID Application` certificate available to `security find-identity`
- A `notarytool` profile stored in Keychain
- A clean tree at an exact annotated `v*` tag on the fetched `origin/main`
- `native/Info.plist` version matching the tag without its `v` prefix
- A Gate A marker matching `dist/candidate-manifest.json`

Store a notary profile once:

```bash
xcrun notarytool store-credentials "ring-stats-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Do not place notary credentials, certificates, or private keys in the
repository or shell scripts.

## Local candidate and Gate A

```bash
BUILD_ARCHS="arm64 x86_64" scripts/build_app.sh
scripts/verify_release_artifacts.sh
scripts/install_local_candidate.sh "dist/Ring Stats.app"
```

After the user inspects this installed candidate and explicitly approves it,
record that exact message locally (never manufacture or infer it):

```bash
scripts/write_approval_marker.sh gate-a \
  "dist/candidate-manifest.json" \
  "<exact user approval message>"
scripts/verify_approval_gate.sh gate-a "dist/candidate-manifest.json"
scripts/preflight_remote_collaboration.sh
```

These markers are procedural content-integrity records, not cryptographic proof
of human authorship. Use the supported preflight/release wrappers; direct raw
Git or GitHub commands are technically capable of bypassing the procedure.

## Prepare and tag

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `native/Info.plist`.
2. Move completed entries from **Unreleased** in `CHANGELOG.md` into a dated
   version section.
3. Run the contributor verification commands.
4. Commit the release preparation using the repository's Lore commit format,
   open a pull request, and merge it after required checks pass.
5. Fast-forward the local branch to the reviewed remote commit, then create an
   annotated tag whose version matches the plist:

   ```bash
   git switch main
   git pull --ff-only origin main
   version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
   git tag -a "v$version" -m "Release Ring Stats $version"
   ```

The release script rejects a lightweight tag, dirty tree, version mismatch,
tag that is not the exact `origin/main` commit, or non-Developer-ID signing
identity. Set `RELEASE_BRANCH_REF` only when the protected release branch is
intentionally different.

## Build, sign, and notarize

```bash
APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_NOTARY_PROFILE="ring-stats-notary" \
BUILD_ARCHS="arm64 x86_64" \
scripts/sign_and_notarize.sh
```

The script builds the universal app and DMG, verifies the bundle, submits it to
Apple, staples and validates the ticket, runs Gatekeeper assessment, and writes
evidence to `dist/release-metadata/`.

Run the artifact verifier once more with the final DMG:

```bash
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
DMG_PATH="$PWD/dist/Ring-Stats-$version.dmg" scripts/verify_release_artifacts.sh
cp "dist/release-metadata/Ring-Stats-$version.dmg.sha256" "dist/"
(cd dist && shasum -a 256 -c "Ring-Stats-$version.dmg.sha256")
```

## Publish

Install the app from the final notarized artifact, obtain explicit approval of
that exact artifact, and record/verify Gate B:

```bash
artifact="dist/Ring-Stats-<version>.dmg"
scripts/install_final_artifact.sh "$artifact"
scripts/write_approval_marker.sh gate-b "$artifact" "<exact user approval message>"
scripts/preflight_publication.sh "$artifact"
```

Push the reviewed commit and annotated tag, create GitHub release notes from the
matching changelog section, and upload:

- `dist/Ring-Stats-<version>.dmg`
- `dist/release-metadata/Ring-Stats-<version>.dmg.sha256`

Download both public assets and verify the checksum again before announcing the
release. Do not promote the Oura integration or enable donations until written
Oura confirmation has been received.
