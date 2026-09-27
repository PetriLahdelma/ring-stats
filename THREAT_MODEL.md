# Threat Model

This document describes what Ring Stats protects, from whom, and where its
protections stop. It covers the app as built from this repository and the
release process in [RELEASING.md](RELEASING.md). Report suspected weaknesses
through [SECURITY.md](SECURITY.md).

## Assets

| Asset | Where it lives | Why it matters |
| --- | --- | --- |
| Oura Client ID and Client Secret | macOS Keychain | Lets anyone holding them run OAuth as the user's developer application |
| OAuth access and refresh tokens | macOS Keychain | Read access to the user's Oura health data until revoked |
| Health readings | Process memory only | Personal wellness data |
| OAuth `state` and authorization code | Process memory, one attempt | Can complete an authorization if intercepted |
| Developer ID signing identity and notary profile | Maintainer's Keychain | Controls which binaries macOS trusts as Ring Stats |
| Release tags and artifacts | GitHub | Users decide what to install from them |

## Trust boundaries

1. **The Mac and its logged-in user.** Ring Stats trusts macOS, Keychain
   access control, and the user's account. A process already running as the
   same user with Keychain access can read what Ring Stats can read.
2. **The loopback interface.** The OAuth callback crosses from the browser to
   the app over `127.0.0.1:43828` during one authorization attempt.
3. **The network.** All Oura traffic is HTTPS to documented Oura hosts.
4. **Oura.** Ring Stats trusts Oura's OAuth and API responses only after
   status and schema checks. It never displays raw upstream bodies.
5. **The release pipeline.** Users trust that a published DMG was built from a
   reviewed commit by the maintainer.

## Bring-your-own OAuth credentials

Oura issues API access through developer applications. Ring Stats has no
backend, so it cannot hold a shared Client Secret safely; any secret embedded in
a distributed app is extractable. Each user therefore creates their own
application and enters its Client ID and Client Secret.

- **Mitigated:** no shared secret exists to leak; a compromise of one user's
  credentials affects only that user's application.
- **Mitigated:** credentials are stored as device-only Keychain items, preferring
  the data-protection Keychain, and are deleted on disconnect.
- **Accepted:** the Client Secret is a long-lived secret on the user's Mac. It
  is only as safe as the macOS account. Users can rotate it in the Oura portal.
- **Accepted:** onboarding asks a consumer to handle a developer secret. The
  staged Connection flow explains why and where it is stored, but cannot remove
  the requirement.

## OAuth callback

The redirect URI is the numeric `http://127.0.0.1:43828/oauth/callback`, not
`localhost`, following RFC 8252 section 8.3. A browser resolving `localhost` may
try `::1` first, where another local process could be listening.

- **Mitigated:** the listener binds only to `127.0.0.1`, exists only during an
  authorization attempt, and shuts down after one valid callback, a timeout,
  cancellation, or disconnect.
- **Mitigated:** requests are validated for method, path, host header, and a
  random per-attempt `state`. Stray, malformed, or reset connections are
  rejected without ending the flow; headers may arrive fragmented.
- **Mitigated:** an intercepted authorization code is not enough on its own;
  exchanging it also requires the Client Secret, which never leaves the app
  except in the token request to Oura.
- **Residual risk:** a malicious process running as the same user could bind
  port 43828 first. Ring Stats starts its listener before opening the browser,
  so in that case it reports an error and never opens Oura's consent page, and
  no code is issued. A process that binds the port after the listener closes
  gains nothing, because each `state` is single-use. Oura does not document PKCE
  support; if it does in future, adding PKCE would further bind the code to this
  attempt.

## Tokens and revocation

- Reauthorization stores the new token before revoking the old one, so a
  failed or cancelled flow never leaves the user signed out.
- Concurrent callers share one in-flight token refresh, preventing two uses of
  a single-use refresh token.
- A rejected refresh (`invalid_grant`) durably clears the token and moves the
  app to an "authorization expired" state instead of retrying forever.
- Failed revocations of replaced tokens are queued in Keychain and retried.
- Disconnect deletes local secrets even when remote revocation fails, and says
  so. Deleting the app alone does not revoke tokens; the privacy policy and
  README explain this.

## Keychain migration

Early development builds stored OAuth JSON under
`~/Library/Application Support/Ring Stats Public/Legacy Secrets/`, and some
builds used the file-based login Keychain.

- **Mitigated:** values migrate into the preferred Keychain before any weaker
  copy is deleted, so a failed write cannot lose the credential.
- **Mitigated:** cleanup of weaker copies is retried on later reads.
- **Mitigated:** an empty migration tombstone prevents a legacy token that macOS
  refused to delete from being re-imported after disconnect.
- **Residual risk:** if file permissions block cleanup, a plaintext legacy file
  can remain. The privacy policy tells affected users how to remove it.

## Local data and diagnostics

- Health readings are never written to disk by the app.
- Diagnostic events go to the macOS unified log and an in-memory buffer. The
  event type has no case that accepts free text; payloads are limited to metric
  names, endpoint identifiers, HTTP status codes, and error kinds. Tests plant
  health values and secret-like strings and verify none reach the report.
- The Diagnostics window shows the full report for review before the user
  copies or saves it. Nothing is transmitted.

## Sandboxing

Ring Stats is signed with the hardened runtime and notarized, but it is not
App Sandboxed. It needs outbound HTTPS and a short-lived inbound loopback
listener, both of which the sandbox allows with the `network.client` and
`network.server` entitlements, so sandboxing is feasible.

- **Current decision:** not yet enabled. The app has no file access, plug-ins,
  or third-party code, so the sandbox would mainly limit the impact of a code
  execution bug. The cost is Keychain access-group and migration testing across
  existing installs.
- **Tracked:** sandboxing is on the roadmap. Adopting it must preserve access
  to existing Keychain items or migrate them.

## Release pipeline and key custody

- The Developer ID certificate and notary credentials live only in the
  maintainer's Keychain and are never placed in the repository, CI, or scripts.
- `scripts/sign_and_notarize.sh` refuses to sign unless HEAD is an exact,
  annotated, cryptographically signed `v*` tag on the fetched protected branch
  commit, with a matching bundle version and a clean tree.
- Releases publish a SHA-256 checksum and a provenance archive containing the
  source commit and tag signature, toolchain, dependency list, code signatures,
  candidate manifest, dSYM UUIDs and symbols, and the notarization result.
- **Residual risk:** a compromised maintainer machine could sign a malicious
  build. Notarization, tag signatures, and published provenance make such a
  build detectable after the fact but cannot prevent it. There is no second
  maintainer or hardware-backed signing today.
- **Residual risk:** CI does not produce signed builds or attestations; public
  releases are built locally.

## Out of scope

- An attacker with the user's macOS password or administrator access.
- Compromise of Oura's services or of the user's Oura account.
- Physical access to an unlocked Mac.
