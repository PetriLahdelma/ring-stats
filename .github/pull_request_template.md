## Outcome

<!-- What user-visible or maintainer-visible result does this produce? -->

## Scope

<!-- List the intentional changes and any explicitly excluded work. -->

## Privacy and security

- [ ] No credentials, tokens, health data, personal paths, signing material, or private screenshots are included.
- [ ] Scope, collection, storage, callback, Keychain, or deletion changes are documented and tested, or are not applicable.
- [ ] Only documented Oura endpoints are used.

## Verification

- [ ] `swift test -Xswiftc -warnings-as-errors`
- [ ] `BUILD_ARCHS="arm64 x86_64" scripts/build_app.sh`
- [ ] `scripts/verify_release_artifacts.sh`
- [ ] Relevant manual checks are described below.

## Documentation

- [ ] User, privacy, architecture, design, release, and changelog documents are updated, or are not affected.

## Notes

