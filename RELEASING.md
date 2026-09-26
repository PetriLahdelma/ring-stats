# Releasing

Only publish artifacts produced from a reviewed, clean commit. CI artifacts are
ad-hoc signed test outputs, not public releases.

## Prerequisites

- Apple Developer Program membership
- A `Developer ID Application` certificate available to `security find-identity`
- A `notarytool` profile stored in Keychain
- A clean tree at an exact annotated `v*` tag
- `native/Info.plist` version matching the tag without its `v` prefix

Store a notary profile once:

```bash
xcrun notarytool store-credentials "ring-stats-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Do not place notary credentials, certificates, or private keys in the
repository or shell scripts.

## Prepare and tag

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `native/Info.plist`.
2. Move completed entries from **Unreleased** in `CHANGELOG.md` into a dated
   version section.
3. Run the contributor verification commands.
4. Commit the release preparation using the repository's Lore commit format.
5. Create an annotated tag whose version matches the plist:

   ```bash
   git tag -a v1.1 -m "Release Ring Stats 1.1"
   ```

The release script rejects a lightweight tag, dirty tree, version mismatch, or
non-Developer-ID signing identity.

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

Push the reviewed commit and annotated tag, create GitHub release notes from the
matching changelog section, and upload:

- `dist/Ring-Stats-<version>.dmg`
- `dist/release-metadata/Ring-Stats-<version>.dmg.sha256`

Download both public assets and verify the checksum again before announcing the
release. Do not promote the Oura integration or enable donations until written
Oura confirmation has been received.
