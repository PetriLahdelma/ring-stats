# Privacy Policy

Effective: September 26, 2026

Ring Stats is a local macOS application maintained by Digitaltableteur. This
policy describes the open-source application as
distributed from this repository. A modified build may behave differently;
review its source and distributor's policy before using it.

## Data the app accesses

After you authorize access through Oura's OAuth flow, Ring Stats derives the
requested scopes from the statistics enabled in Appearance:

- daily Readiness, Sleep, and Activity scores;
- heart-rate samples;
- daily stress and resilience data; and
- ring configuration data used to display battery and charging status.

Battery status always requires the `ring_configuration` scope. Daily scores and
Resilience use `daily`, Heart Rate uses `heartrate`, and Stress uses `stress`.
Only enabled statistics are fetched. Hiding a statistic stops its endpoint from
being requested on later refreshes, but it does not remove a permission already
granted to the current OAuth token. Revoke or reauthorize to change the token's
permissions.

Ring Stats also stores local display preferences such as theme, visible metric
order, and popover width. These preferences are not health data.

## How data is used and stored

Health responses are fetched directly from Oura over HTTPS, used to render the
current interface, and retained only in application memory. Ring Stats does
not write health responses to disk, create a health-history database, sell
data, use data for advertising, or use data to train an AI or machine-learning
model. Network requests use a dedicated ephemeral session with URL caching and
cookie persistence disabled.

Your Oura developer Client ID, Client Secret, current OAuth access token, and
OAuth refresh token are stored locally as device-only generic-password items in
your macOS Keychain. If replacement authorization succeeds but revocation of an
older access token is temporarily unavailable, that old access token is also
kept in Keychain in a revocation queue. Ring Stats retries every queued token on
later authenticated requests and removes each one after successful revocation
or when you disconnect. When the data-protection Keychain is unavailable to a
local build, Ring Stats uses the compatible macOS Keychain. The app does not
embed a shared Client Secret.

Local interface preferences are stored using macOS `UserDefaults`. The OAuth
callback is received by a temporary IPv4 loopback listener at
`http://127.0.0.1:43828/oauth/callback`; it is not a remote project server.

Early development builds could store OAuth JSON under
`~/Library/Application Support/Ring Stats Public/Legacy Secrets/`. Current
builds migrate readable legacy values into Keychain and delete each plaintext
file only after the Keychain write succeeds. They also migrate older compatible
Keychain items into the data-protection Keychain when available. A migration
failure is shown to the user instead of silently treating the account as
disconnected.

## Data sharing

Ring Stats does not operate an analytics, telemetry, advertising, crash-report,
or health-data collection service. The application communicates with Oura to
authenticate and retrieve the data you requested. Your browser and Oura may
process information under their own privacy policies when you authorize the
application.

## Retention and deletion

Health responses disappear when the in-memory application state is replaced or
the app quits. A failed refresh may leave the previous in-memory snapshot on
screen with a stale warning until the next successful refresh or until the app
quits. Choosing **Disconnect & Delete Local Data** attempts to revoke
the current Oura authorization and removes the saved Client ID, Client Secret,
current and queued access tokens, and refresh token from the macOS Keychain. Local display
preferences remain in `UserDefaults` until the preference domain is removed.
Deleting the application by itself does not revoke the OAuth token, delete
Keychain items, or remove preferences.

If remote revocation cannot complete because the device is offline, local
secrets are still removed. You can separately revoke access through your Oura
account or developer controls.

## Your choices

You decide whether to connect an account and which permissions to approve. You
may deny authorization, reauthorize with different permissions, disconnect,
or delete locally stored credentials at any time. Ring Stats cannot display
data for a permission you do not grant.

## Security

The application uses macOS Keychain protections and HTTPS connections, but no
software can guarantee absolute security. Keep macOS updated, protect your
login account, do not share developer credentials, and report suspected
vulnerabilities according to [SECURITY.md](SECURITY.md).

## Children and medical use

Ring Stats is not directed to children and is not a medical device. It presents
wellness information returned by Oura and does not provide diagnosis or medical
advice.

## Changes and contact

Material changes will be documented in this file and its effective date will
be updated. Non-sensitive privacy questions may use the repository's issue
tracker. Report deletion failures or any matter involving health data,
credentials, tokens, or other private information through
[GitHub private vulnerability reporting](https://github.com/PetriLahdelma/ring-stats/security/advisories/new),
not a public issue.

Use of Oura services is also governed by Oura's own terms and privacy policy.
This project is independent and is not affiliated with or endorsed by Oura.
