# Privacy Policy

Effective: September 26, 2026

Ring Stats is a local macOS application maintained by Digitaltableteur. This
policy describes the open-source application as
distributed from this repository. A modified build may behave differently;
review its source and distributor's policy before using it.

## Data the app accesses

After you authorize access through Oura's OAuth flow, Ring Stats requests only
the scopes needed to display the selected menu-bar statistics:

- daily Readiness, Sleep, and Activity scores;
- heart-rate samples;
- daily stress and resilience data; and
- ring configuration data used to display battery and charging status.

Ring Stats also stores local display preferences such as theme, visible metric
order, and popover width. These preferences are not health data.

## How data is used and stored

Health responses are fetched directly from Oura over HTTPS, used to render the
current interface, and retained only in application memory. Ring Stats does
not write health responses to disk, create a health-history database, sell
data, use data for advertising, or use data to train an AI or machine-learning
model. Network requests use a dedicated ephemeral session with URL caching and
cookie persistence disabled.

Your Oura developer Client ID, Client Secret, OAuth access token, and OAuth
refresh token are stored locally as generic-password items in your macOS
Keychain. The app does not embed a shared Client Secret.

Local interface preferences are stored using macOS `UserDefaults`. The OAuth
callback is received by a temporary listener at
`http://localhost:43828/oauth/callback`; it is not a remote project server.

## Data sharing

Ring Stats does not operate an analytics, telemetry, advertising, crash-report,
or health-data collection service. The application communicates with Oura to
authenticate and retrieve the data you requested. Your browser and Oura may
process information under their own privacy policies when you authorize the
application.

## Retention and deletion

Health responses disappear when the in-memory application state is replaced or
the app quits. Choosing **Disconnect & Delete Local Data** attempts to revoke
the current Oura authorization and removes the saved Client ID, Client Secret,
access token, and refresh token from the macOS Keychain. Local display
preferences can also be removed by deleting the app's preferences through
macOS or by removing the application and its preference domain.

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
be updated. Privacy questions and deletion problems may be submitted through
the repository's issue tracker. Do not include health data, OAuth credentials,
or other private information in a public issue.

Use of Oura services is also governed by Oura's own terms and privacy policy.
This project is independent and is not affiliated with or endorsed by Oura.
