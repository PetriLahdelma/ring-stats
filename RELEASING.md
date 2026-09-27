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
- A clean tree at an exact annotated and signed `v*` tag on the fetched
  `origin/main`
- A Git signing key (SSH or GPG) configured for tags, with its public key
  published so others can verify
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
5. Fast-forward the local branch to the reviewed remote commit, then create a
   signed tag whose version matches the plist. Tag only after the release
   pull request is merged, so the tag lands on the exact protected-branch
   commit rather than a pre-merge sibling:

   ```bash
   git switch main
   git pull --ff-only origin main
   version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
   git tag -s "v$version" -m "Release Ring Stats $version"
   git verify-tag "v$version"
   ```

One-time signing setup with an SSH key (a GPG key works the same way through
`gpg.format openpgp`):

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global tag.gpgsign true
printf '%s %s\n' "$(git config user.email)" "$(cat ~/.ssh/id_ed25519.pub)" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

Add the same public key to GitHub as a signing key so the tag shows as
verified.

`scripts/verify_release_tag.sh`, run by the release script, rejects a
lightweight or unsigned tag, a version mismatch, or a tag that is not the exact
`origin/main` commit; the release script also rejects a dirty tree or a
non-Developer-ID signing identity. Set `RELEASE_BRANCH_REF` only when the
protected release branch is intentionally different. `ALLOW_UNSIGNED_TAG=1`
skips only the signature check and must be justified in the release notes.
Tags v1.0 through v1.1.1 predate this rule and are not rewritten.

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

Push the signed tag, create GitHub release notes from the matching changelog
section, and upload:

- `dist/Ring-Stats-<version>.dmg`
- `dist/release-metadata/Ring-Stats-<version>.dmg.sha256`
- `dist/Ring-Stats-<version>-provenance.zip`
- `dist/Ring-Stats-<version>-provenance.zip.sha256`
- `dist/Ring-Stats-<version>.cdx.json` (CycloneDX SBOM)
- `dist/Ring-Stats-<version>.intoto.json` and its `.sig` (or `.asc`)

The release script generates the SBOM with `scripts/generate_sbom.sh`, writes
an in-toto statement with a SLSA provenance predicate binding the DMG, SBOM,
and provenance archive to the signed tag and commit
(`scripts/create_release_attestation.sh`), and signs it with the same key as
the tag (`scripts/sign_release_file.sh`). Publish the maintainer's
allowed-signers line in `SECURITY.md` so anyone can verify.

CI separately attests the unsigned artifacts it builds on `main` with GitHub
artifact attestations. Those attestations describe CI builds, not the public
notarized release.

Download both public assets and verify the checksum again before announcing the
release. Do not promote the Oura integration or enable donations until written
Oura confirmation has been received.
