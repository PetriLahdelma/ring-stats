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

[THREAT_MODEL.md](THREAT_MODEL.md) describes assets, trust boundaries,
mitigations, and accepted residual risks in detail.

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
- Operational diagnostics use a typed event model with no free-text payloads,
  so health values, tokens, credentials, and upstream response bodies cannot be
  logged. The Diagnostics report is shown to the user and never transmitted.

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

Future releases also publish `Ring-Stats-<version>-provenance.zip`
with its checksum. It contains the source commit, the tag signature, toolchain
and dependency records, code-signature details, the candidate manifest, dSYM
UUIDs and symbols, and the notarization result. Release tags are signed; verify
one in a clone with `git verify-tag v<version>` using the maintainer's public
key.

The release script requires a clean tree, an exact annotated and signed `v*`
tag on the fetched protected branch commit whose version matches the bundle, a Developer ID Application identity, and a
Keychain-backed notary profile. It also refuses to sign or notarize without a
Gate A marker explicitly approving the matching local candidate tree. It records
source, toolchain, dependency, signature, checksum, and notarization evidence
under `dist/release-metadata/`.

Public upload is a separate Gate B: the exact notarized artifact and the locally
installed final binary must match the explicit approval marker. Run
`scripts/preflight_publication.sh <artifact>` immediately before publication.
Approval markers remain local under ignored `.omx/approvals/` and must record
the user's explicit message. They are procedural integrity records binding
reviewed content, not cryptographic proof of who typed an approval. The supported
wrappers enforce them, but direct raw `git` or `gh` commands can bypass that
procedure; maintainers must not use those bypasses for release operations.
CI separately assembles and verifies an ad-hoc-signed universal application and
DMG; CI artifacts are test evidence, not authenticated public releases.

Never publish signing certificates, private keys, notary passwords, OAuth
client secrets, or exported Keychain data.
