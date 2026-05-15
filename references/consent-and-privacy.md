# Consent & privacy gating

Amply is part of the analytics surface area of an app — anything you can do with Mixpanel-style tracking, you can do here. That means **the same consent rules that gate Mixpanel must gate Amply.**

## Detection — what to grep for

| Framework | Marker | Notes |
|---|---|---|
| **iOS ATT** | `import AppTrackingTransparency`, `ATTrackingManager.requestTrackingAuthorization` | Required by Apple before tracking with IDFA. The Amply iOS SDK reads IDFA when allowed; refresh device properties after the user grants permission. |
| **Google UMP (Android, sometimes iOS)** | `com.google.android.ump`, `UserMessagingPlatform` | EEA / UK GDPR consent. |
| **OneTrust** | iOS `OneTrust`, Android `com.onetrust.cmp.sdk` | |
| **Didomi** | iOS `Didomi`, Android `io.didomi.sdk` | |
| **Iubenda** | `iubenda` package or imported web SDK | |
| **TrustArc / Cookiebot** | rare in mobile, often web-only | |
| **Custom consent manager** | `consentManager`, `hasAnalyticsConsent`, `acceptedTracking` patterns in source | The most common case in production apps. |

## Default policy — match the project's posture, don't unilaterally tighten

The single most important rule: **mirror the consent posture of the existing analytics stack.** If the project already runs Amplitude / Adjust / Firebase **ungated**, gating Amply alone would be inconsistent — privacy review will see "Amply blocked, Amplitude wide open" and flag the mismatch, not the alignment. The Amply team's preferred default is below, but **the project's existing posture wins** when it contradicts it. Document the choice explicitly in the audit so a future reviewer can re-evaluate when the rest of the stack tightens.

| Project posture for the existing analytics stack | What to do with Amply |
|---|---|
| **Ungated** (Amplitude / Firebase / Adjust fire from launch, no consent flag) | Fire Amply the same way. Note in the audit "Amply matches existing project posture — revisit when the stack adds a gate". |
| **Functional-analytics consent** (a single boolean flag gates all behavioural events) | Apply the same flag to Amply. Implement in the wrapper. |
| **Full marketing consent** (separate flag for marketing/identifier events) | Apply the marketing flag to Amply for events with identifiers; apply the functional flag (if present) for purely behavioural events. |
| **No analytics at all yet, Amply is the first** | Set up a single functional-analytics flag and gate Amply behind it. Document the decision. |

### Always-on rules (regardless of posture)

| Rule | Rationale |
|---|---|
| Strip / hash PII at the wrapper before forwarding | Email, phone, raw IP, full name, government IDs must never leave the device as Custom Property values, even with consent. |
| Use deterministic opaque user IDs in `setUserId` | Not email. |
| Reset on logout: `setUserId(null)` + `clearCustomProperties()` | Hygiene; required for user-deletion compliance. |
| Reset on consent revocation | If consent flips `true → false` mid-session, stop forwarding new events to Amply; optionally `clearCustomProperties()`. |

The wrapper templates in `wrapper-patterns.md` show a baseline gate — adjust to the project's posture per the table above.

## PII rules

Never set as Custom Property values: email, phone number, postal address, raw IP, full name, government IDs, raw payment details. The skill's `stripPii` helper has a starter blocklist (`email`, `phone`, `address`, `ip`) — extend it for the project's known field names.

If the team needs a "user is in EU" or "user is logged in" flag for targeting, encode it as a derived Boolean (`is_eu`, `is_logged_in`) — never the underlying identifier.

## Reset semantics

When the user logs out:

```
setUserId(null)
clearCustomProperties()
```

If the consent flag flips from `true` → `false` mid-session:

- Stop forwarding new events to Amply (early-return in the wrapper).
- Optionally call `clearCustomProperties()` if the project's privacy policy promises immediate scrub.
- Do **not** retroactively delete already-sent events from Amply — file that with the Amply team via support if a user requests data deletion.

## What to put in `amply-audit.md`

```
Consent framework: <ATT | UMP | custom | none>
Consent gate applied to Amply: <yes (function) | yes (full opt-in) | no — flag for review>
PII strip list: <comma-separated keys>
Logout reset: <wired | not wired — TODO>
```
