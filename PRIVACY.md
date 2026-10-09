# Privacy Policy

Effective: September 28, 2026

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
order, popover width, text size, the low battery alert, and which value, if
any, to show in the menu bar. These preferences are not health data. The
menu bar value is off by default; when you turn it on, the chosen stat or a
low battery percentage is drawn in the menu bar, where anyone who can see
your screen can read it.

## How data is used and stored

Health responses are fetched directly from Oura over HTTPS, used to render the
current interface, and retained only in application memory. Ring Stats does
not write health responses to disk, create a health-history database, sell
data, use data for advertising, or use data to train an AI or machine-learning
model. Network requests use a dedicated ephemeral session with URL caching and
cookie persistence disabled.

The "Get Ring Stat" and "Get Ring Battery" Shortcuts actions answer from the
same in-memory values. They hand a value only to a shortcut you run, and
what that shortcut does with it is up to you. Ring Stats itself still writes
nothing to disk. An action can fetch a stat that is hidden in the popover,
because running it is an explicit request for that stat.

Your Oura developer Client ID, Client Secret, current OAuth access token, and
OAuth refresh token are stored locally as device-only generic-password items in
your macOS Keychain. If replacement authorization succeeds but revocation of an
older access token is temporarily unavailable, that old access token is also
kept in Keychain in a revocation queue. Ring Stats retries every queued token on
later authenticated requests and removes each one after successful revocation
or when you disconnect. When the data-protection Keychain is unavailable to a
local build, Ring Stats uses the compatible macOS Keychain. The app does not
embed a shared Client Secret.

Ring Stats runs in the macOS App Sandbox, so its local files live in its
container at `~/Library/Containers/com.digitaltableteur.ringstats/`. Local
interface preferences are stored there using macOS `UserDefaults`; on the
first sandboxed launch, macOS moves existing preferences into the container. The OAuth
callback is received by a temporary loopback listener (IPv4 and IPv6) at
`http://localhost:43828/oauth/callback`; it is not a remote project server.

Early development builds could store OAuth JSON under
`~/Library/Application Support/Ring Stats Public/Legacy Secrets/`. Current
builds migrate readable legacy values into Keychain and delete each plaintext
file only after the Keychain write succeeds. They also migrate older compatible
Keychain items into the data-protection Keychain when available. Cleanup of a
weaker copy is best-effort and retried on later reads so a cleanup permission
failure does not make an otherwise valid protected credential unusable. If file
permissions continue to prevent cleanup, remove the legacy directory manually
after confirming the account still connects.

## Diagnostics

Ring Stats records operational events, such as "refresh started", "daily_sleep:
HTTP 503", or "authorization cancelled", to the macOS unified log under the
subsystem `com.digitaltableteur.ringstats`, and keeps the most recent 200 in
memory. These events contain only metric names, Oura endpoint names, HTTP
status codes, and error categories. They never contain health values, your
Client ID or Client Secret, tokens, account identifiers, or response bodies.
macOS manages retention of the unified log.

**Diagnostics…** in the Ring Stats menu shows a report of the app's state and
these recent events. You can read it in full and then copy or save it yourself.
Ring Stats never sends it anywhere.

While the app runs, it refreshes the visible statistics in the background
every 30 minutes, or at most every two hours on battery power or in Low Power
Mode, using the same in-memory handling. If you turn on the low battery alert
in Appearance, macOS shows a local notification with the ring's battery
percentage when it drops below 20%. The notification is created on your Mac
and is not sent anywhere.

## Data sharing

Ring Stats does not operate an analytics, telemetry, advertising, crash-report,
or health-data collection service. The application communicates with Oura to
authenticate and retrieve the data you requested. Your browser and Oura may
process information under their own privacy policies when you authorize the
application.

## Retention and deletion

Health responses disappear when the in-memory application state is replaced or
the app quits. When a refresh fails, entirely or for individual statistics, the
previous in-memory values stay on screen marked "Not updated" until a later
refresh succeeds or the app quits. Choosing **Disconnect & Delete Local Data** attempts to revoke
the current Oura authorization and removes the saved Client ID, Client Secret,
current and queued access tokens, and refresh token from the macOS Keychain. Local display
preferences remain in `UserDefaults` until the preference domain is removed.
Deleting the application by itself does not revoke the OAuth token, delete
Keychain items, or remove preferences.

After token deletion, Ring Stats may retain an empty, non-secret Keychain
migration marker. It contains no credentials or tokens and prevents an older
Keychain alias that macOS would not allow the app to delete from being imported
again on a later launch.

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
