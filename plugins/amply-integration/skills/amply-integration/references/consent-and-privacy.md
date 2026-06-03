# Consent & privacy

> **Amply is a campaign-orchestration product-feature SDK, not a tracking-analytics SDK.** It serves your app's own functionality — which screen to show next, which deeplink to fire, when to ask for a review — using first-party data sent to your own Amply backend. **The consent considerations that apply to Mixpanel / Amplitude / Adjust do not map onto Amply directly.** Read this whole page once; the temptation to "wrap Amply in a consent gate" is real, and almost always wrong.

## What the SDK already does correctly

- **IDFA (Apple advertising identifier)** is read only if `ATTrackingManager.trackingAuthorizationStatus() == Authorized`. If not authorised, the SDK ships `null` for IDFA. Source: `multiplatform-library-template/library/src/iosMain/.../DeviceDataSetImpl.kt:49-63`.
- **The SDK does NOT call `requestTrackingAuthorization`.** Showing the ATT prompt is host-app responsibility, not Amply's. Whatever ATT result your app already has, Amply respects it.
- **Everything else** — IDFV (per-vendor uuid), device model, OS version, locale, app version — is shipped to your own Amply backend as first-party product context. None of it is "tracking" in the ATT/GDPR-consent sense.

## What you (the integrator) need to do

Pick one of two postures. **There is no third posture.**

### Default — construct `Amply(config:)` at app start

Right for the vast majority of apps.

- The SDK handles IDFA gating correctly by itself; nothing to do.
- Other data sent to your own Amply backend is first-party context for product-feature delivery. Lawful basis under GDPR is typically *performance of contract* or *legitimate interest* — not *consent*.
- ATT/GDPR explicit consent is for ads, cross-vendor tracking, data resale — none of which Amply does.
- **No runtime consent gate around Amply is needed or appropriate.**

### Strict — defer construction until your app decides to enable Amply for this user

Right when:
- A user category should never run Amply (kids' accounts, free tier without campaign features, accounts flagged for special handling).
- Your privacy team requires explicit acknowledgement before any first-party product-feature SDK activates.

The mechanism is one line of conditional code in your host app:

```swift
// Don't construct until your business rule is satisfied
if shouldEnableAmplyFor(user) {
    self.amply = Amply(config: amplyConfig)
}
// Otherwise: never construct. Amply doesn't run. Done.
```

That's it. **Do not** build an `AmplyConsentManager` / consent flag / three-state gate around the constructed instance — if Amply is constructed, it runs (that's its product surface); if you don't want it to run, don't construct it.

## Why the "wrap Amply in consent" pattern is wrong

It conflates two different things that share the word *consent*:

| Concept | What it actually is | Where it lives |
|---|---|---|
| **ATT consent** (Apple) | Permission to attach the cross-vendor advertising identifier (IDFA) to outgoing data | Host app prompts ATT. SDK reads the result. |
| **GDPR consent** (EU) | One of several lawful bases for processing personal data. Required for ads / tracking / resale; **not** required for first-party product features | Host app handles legal-grade collection of consent. |
| **App product decision** ("show Amply campaigns to this user, yes/no") | Your business logic | Construct Amply or don't. |

Building a runtime `AmplyConsentManager` confuses team members ("we have an Amply consent gate, must be ATT-related") and produces dead defensive code. Privacy reviewers later spend cycles asking "do we need to consent-gate this?" — the answer is no; the doc that suggested the gate was wrong.

## When you already show an ATT prompt for *other* reasons

If the app shows an ATT prompt for AdMob / attribution SDK / etc., Amply doesn't change that. The ATT decision is shared across the app via `ATTrackingManager.trackingAuthorizationStatus()`. Amply reads that single value automatically. No additional Amply-specific consent flow.

After the user grants ATT, IDFA becomes available to Amply on the next read — Amply's `DeviceDataSetImpl.getAdId()` is called per session-context refresh, so the new value picks up naturally. Force-refresh is not needed for typical use.

## Always-on hygiene (regardless of posture)

These are real engineering rules, unrelated to consent:

| Rule | Rationale |
|---|---|
| **Strip / hash PII at the wrapper before forwarding** to Amply: email, phone, raw IP, full name, government IDs, raw payment details. | PII has its own legal-grade handling (GDPR Article 6 + 9), separate from consent. Never appropriate to ship raw PII to Amply, even when the user has consented to whatever. |
| **Use deterministic opaque user IDs in `setUserId(userId:)`** — not email, not phone. Hash with a stable salt held outside the device. | Opaque IDs make user-deletion compliance possible without rotating Amply data. |
| **Reset on logout**: `setUserId(userId: nil)` + `clearCustomProperties()`. | Hygiene + user-deletion compliance. Not consent. |

## PII rules

Never set as Custom Property values: email, phone number, postal address, raw IP, full name, government IDs, raw payment details. The skill's `stripPii` helper has a starter blocklist (`email`, `phone`, `address`, `ip`) — extend it for the project's known field names.

If the team needs a "user is in EU" or "user is logged in" flag for targeting, encode it as a derived Boolean (`is_eu`, `is_logged_in`) — never the underlying identifier.

## Reset semantics

When the user logs out:

```swift
amply.setUserId(userId: nil)
amply.clearCustomProperties()
```

These are correct hygiene. They are NOT a "consent revocation" pattern.

If a user *deletes their account* and your privacy policy promises immediate scrub, additionally file a data-deletion request via Amply support — the locally-cached data is gone after `clearCustomProperties()`, but anything already sent to your Amply backend isn't deleted by client-side action.

## What to put in `amply-audit.md`

```
Amply posture: <default — construct unconditionally | strict — gated by <business rule>>
ATT result handling: <SDK reads status automatically — no action needed>
PII strip list: <comma-separated keys>
Logout reset: <wired | not wired — TODO>
```

There is intentionally no row for "consent flag applied to Amply" — that's not a thing you do.
