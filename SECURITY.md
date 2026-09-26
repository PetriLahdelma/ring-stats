# Security Policy

## Supported versions

Security fixes are made on the latest source revision and latest published
release. Older builds are not guaranteed to receive updates.

## Reporting a vulnerability

Please report suspected vulnerabilities through the repository's private
security-advisory feature. Do not include OAuth client secrets, access tokens,
refresh tokens, health data, or other personal information in a public GitHub
issue.

Include, when possible:

- the affected version or commit;
- the macOS version and hardware architecture;
- reproduction steps and expected impact; and
- a minimal proof of concept with all personal data and secrets removed.

You should receive an acknowledgement within seven days. Please allow a
reasonable remediation period before public disclosure.

## Security design

- Users bring their own Oura developer application credentials.
- OAuth credentials and tokens are stored as generic-password items in the
  user's macOS Keychain and are not committed to this repository.
- Health responses are held in memory for display and are not persisted by the
  application; API and OAuth requests use ephemeral, no-cache URL sessions.
- OAuth completes through a short-lived callback listener bound to localhost.
- The application talks directly to documented Oura HTTPS endpoints. It has no
  project-operated analytics, advertising, telemetry, or health-data server.

## Release integrity

Official release artifacts should be signed with a Developer ID Application
certificate, notarized by Apple, and stapled. Verify a downloaded application
or disk image before opening it:

```bash
codesign --verify --verbose=2 "Ring-Stats-1.0.dmg"
xcrun stapler validate "Ring-Stats-1.0.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "Ring-Stats-1.0.dmg"
```

After mounting the disk image, the enclosed application signature can be
checked with `codesign --verify --deep --strict --verbose=2 "Ring Stats.app"`.

Never publish signing certificates, private keys, notary passwords, OAuth
client secrets, or exported Keychain data.
