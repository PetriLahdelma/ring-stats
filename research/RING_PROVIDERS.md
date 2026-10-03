# Ring Providers

Researched 2026-10-03. Ring Stats supports smart rings only, as its name says.
Bands and watches (WHOOP, Polar, Fitbit, Garmin) are out of scope even where
their APIs are good.

## What a provider must offer

Ring Stats is a sandboxed macOS app with no server. A ring can be supported
only if its vendor offers a web API that a Mac app can call directly.

- **Apple Health is not an option.** HealthKit is listed for macOS, but
  `HKHealthStore.isHealthDataAvailable()` returns false there and every call
  fails with `errorHealthDataUnavailable`.
- **Android-only SDKs are not an option.** Samsung Health Data SDK and Health
  Connect run on the phone.
- **Aggregators are not an option.** Terra, Junction, Thryve, and Open
  Wearables route health data through a server, which breaks the promise in
  [PRIVACY.md](../PRIVACY.md) that data travels only between the vendor and
  the Mac. Terra also starts at about $399 a month.
- **No embedded shared secret.** Each user brings their own credentials, as
  with Oura today, or the vendor must support a public-client flow (PKCE).

## Comparison

| Ring | Public web API | How a user gets access | Metrics | Battery | Sandbox | Fits Ring Stats |
|---|---|---|---|---|---|---|
| **Oura** (Gen3, Ring 4) | Yes, v2 REST | User registers their own OAuth app; 10 users per app until Oura approves it. Personal tokens ended Dec 2025. | Readiness, Sleep, Activity, heart rate, Stress, Resilience, and more | Yes, `ring_battery_level` | **Yes, verified** (below) | Supported |
| **Ultrahuman** (Ring AIR, Ring Pro) | Yes, `partner.ultrahuman.com` | Personal API token from Ultrahuman's developer portal for one's own data; OAuth only for approved partners | Sleep and stages, HRV, resting HR, temperature, steps, SpO2, VO2 max, Recovery and Movement indexes | Not documented | Not documented | **Candidate.** Personal token fits the bring-your-own model; unverified |
| **Samsung Galaxy Ring** | No | Samsung says ring APIs are not available to third parties. Data SDK is Android-only and mixes all devices. | | | | No |
| **RingConn** (Gen 1, Gen 2) | No | Apple Health, Health Connect, and file export only | | | | No |
| **Amazfit Helio** | No | Zepp has no official OAuth API; data flows through Apple Health, Health Connect, or aggregators | | | | No |
| **Circular** (Ring 2) | None found | No developer documentation found | | | | No |
| **Movano Evie** | None found | No developer documentation found | | | | No |

## Oura sandbox (verified)

`https://api.ouraring.com/v2/sandbox/usercollection/` serves fixed test data
for any bearer token. A request without an `Authorization` header gets HTTP 400
("Include any string in 'Authorization' header"). With one, every endpoint
Ring Stats uses returns HTTP 200: `daily_readiness`, `daily_sleep`,
`daily_activity`, `heartrate`, `daily_stress`, `daily_resilience`,
`ring_battery_level`, and `ring_configuration`.

`OuraSandboxTests` runs the real `OuraAPI` against it and checks that all six
metrics come back available and the battery decodes. It needs the network, so
it runs only on request:

```bash
RING_STATS_LIVE_SANDBOX=1 swift test --filter OuraSandboxTests
```

`OuraProvider.descriptor.capabilities.hasSandbox` is now `true`. The sandbox
lets the Oura provider be tested end to end without a ring or an account, and
is a model for what to ask other vendors for.

## Ultrahuman, the one candidate

What the documentation says, not yet checked against a real account:

- **Endpoint.** `GET https://partner.ultrahuman.com/api/v1/partner/daily_metrics`
  with the personal token in the `Authorization` header. A date range may
  not exceed 7 days, and times use the user's latest time zone.
- **Token.** Created by the user in Ultrahuman's developer portal. "Anyone with
  this Authorization Key can use the Ultrahuman API as you," so it belongs in
  Keychain like Oura's tokens. A community dashboard also passes the user's
  email, so the exact request shape needs confirming.
- **Partner OAuth.** Scopes `ring_data`, `cgm_data`, and `profile`; client
  credentials are issued on approval. Not needed for the personal-token route.
- **No battery.** The popover's battery row has to become optional per
  provider (`ProviderCapabilities.reportsBattery` already exists).

Fitting it into the app:

- **Its own metrics.** Following [ARCHITECTURE.md](../ARCHITECTURE.md),
  Ultrahuman's Recovery and Movement indexes get their own `Metric` cases
  rather than reusing Oura's Readiness and Activity. Heart rate, HRV, and
  temperature are candidates for shared shapes only if their units and
  sampling really match.
- **Token entry, not sign-in.** A personal token is pasted, not obtained
  through a browser redirect. The account side needs a token-entry variant
  alongside `OAuthServicing`.
- **No vendor marks.** Use Ultrahuman's name only to identify compatibility,
  as with Oura.

## Testing without owning a ring

1. **Vendor sandbox** where one exists (Oura).
2. **Recorded fixtures** built from the vendor's documented responses, run
   through the same stubbed session that `OuraAPITests` uses, plus state-gallery
   renders for the new metrics.
3. **One real account before "supported".** A tester who owns the ring runs a
   diagnostic build. Real data shows what documentation does not: missing
   days, time zones, score scales, late revisions. Until then the provider is
   labeled experimental.

## Next steps

1. Ask Ultrahuman whether personal tokens may be used by a distributed
   third-party app, and whether a sandbox exists. Read their API Terms.
2. Recruit one Ultrahuman owner as a tester.
3. Build the Ultrahuman provider against fixtures: a `RingStatsUltrahuman`
   target, token entry, its own metric cases, an optional battery row.
4. Revisit RingConn, Samsung, and Circular every few months; drop a row only
   when a vendor publishes a web API.

## Sources

- [Oura: The Oura API](https://support.ouraring.com/hc/en-us/articles/4415266939155-The-Oura-API)
- [Oura API v2 reference](https://api.ouraring.com/docs)
- [Ultrahuman UltraSignal API documentation](https://vision.ultrahuman.com/developer-docs)
- [Ultrahuman: Accessing the Partnership API](https://www.ultrahuman.com/blog/accessing-the-ultrahuman-partnership-api/)
- [Open Wearables: Ultrahuman integration](https://openwearables.io/docs/providers/ultrahuman-api-integration)
- [Samsung forum: Galaxy Ring data](https://forum.developer.samsung.com/t/is-there-any-way-to-get-the-raw-health-data-from-the-galaxy-ring/35646)
- [Samsung Health Data SDK](https://developer.samsung.com/health/data/overview.html)
- [RingConn moves to Health Connect](https://ringconn.com/de/blogs/nachricht/ringconn-will-migrate-from-google-fit-to-health-connect)
- [Thryve: Zepp and Amazfit](https://www.thryve.health/features/connections/zepp-amazfit-integration)
- [Apple: Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [Sahha: Terra alternatives and pricing](https://sahha.ai/compare/terra-alternatives/)
