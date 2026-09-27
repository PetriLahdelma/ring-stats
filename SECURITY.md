# Security Policy

## Supported versions

Security fixes are made on the latest source revision and latest published
release. Older builds are not guaranteed to receive updates.

## Reporting a vulnerability

Report suspected vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/PetriLahdelma/ring-stats/security/advisories/new).
The feature is enabled for this repository. Do not include OAuth client secrets,
access tokens, refresh tokens, health data, or other personal information in a
public GitHub issue.

Include, when possible:

- the affected version or commit;
- the macOS version and hardware architecture;
- reproduction steps and expected impact; and
- a minimal proof of concept with all personal data and secrets removed.

You should receive an acknowledgement within seven days. Please allow a
reasonable remediation period before public disclosure.

## Security design

- Users bring their own Oura developer application credentials.
- OAuth credentials, current tokens, and access tokens queued after a temporary
  revocation failure are stored as generic-password items in the user's macOS
  Keychain with device-only accessibility and are not committed to this
  repository. Queued revocations are retried and cleared on success or
  disconnect. Older compatible Keychain items and early plaintext development
  files are migrated only when the protected write succeeds.
- Health responses are held in memory for display and are not persisted by the
  application; API and OAuth requests use ephemeral, no-cache URL sessions.
- OAuth completes through a short-lived callback listener bound to the numeric
  IPv4 loopback address `127.0.0.1`.
- The application talks directly to documented Oura HTTPS endpoints. It has no
  project-operated analytics, advertising, telemetry, or health-data server.

## Release integrity

Official release artifacts should be signed with a Developer ID Application
certificate, notarized by Apple, and stapled. Verify a downloaded application
or disk image before opening it, replacing `<version>` with the downloaded
release number:

```bash
shasum -a 256 -c "Ring-Stats-<version>.dmg.sha256"
codesign --verify --verbose=2 "Ring-Stats-<version>.dmg"
xcrun stapler validate "Ring-Stats-<version>.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "Ring-Stats-<version>.dmg"
```

After mounting the disk image, the enclosed application signature can be
checked with `codesign --verify --deep --strict --verbose=2 "Ring Stats.app"`.

The release script requires a clean tree, an exact annotated `v*` tag whose
version matches the bundle, a Developer ID Application identity, and a
Keychain-backed notary profile. It records source, toolchain, dependency,
signature, checksum, and notarization evidence under `dist/release-metadata/`.
CI separately assembles and verifies an ad-hoc-signed universal application and
DMG; CI artifacts are test evidence, not authenticated public releases.

Never publish signing certificates, private keys, notary passwords, OAuth
client secrets, or exported Keychain data.
