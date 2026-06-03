# Wrapper patterns

Always route Amply calls through a single module — either the project's existing analytics wrapper, or a thin one introduced by this skill. Four rules apply to every template:

1. **Preserve existing call shape** — your codebase keeps using the same `track('paywall_shown', { screen: 'home' })` it always has.
2. **Inherit the existing wrapper's signature.** If the existing `logEvent` / `track` is **synchronous** (Amplitude, Firebase native, Mixpanel native), keep it synchronous and fire-and-forget the Amply call (`void Amply.track({...})` — Amply's RN `track` returns a Promise but you don't have to await it). Forcing the existing wrapper async would ripple to every call site in the codebase. The templates below show the async form because RN's `Amply.track` is async — adapt to sync if that's what the project already uses.
3. **Do the convention translation in the wrapper** — PascalCase event names and snake_case property keys for the Amply call only. Do not rename the project's events.
4. **Strip / hash PII** at the wrapper before forwarding to Amply: email, phone, raw IP, full name, government IDs, raw payment details. This is hygiene, not consent — see `consent-and-privacy.md` for why Amply (a first-party product-feature SDK) does not need a runtime consent gate.

## Template — TypeScript (RN / Expo)

```ts
// src/analytics/index.ts
import Mixpanel from 'mixpanel-react-native';
import Amply from '@amplytools/react-native-amply-sdk';

const PII_KEYS = new Set(['email', 'phone', 'address', 'ip']);

function pascalCase(name: string): string {
  return name
    .split(/[\s_\-]+/)
    .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
    .join('');
}

function stripPii<T extends Record<string, unknown>>(props: T): T {
  const out = { ...props };
  for (const key of Object.keys(out)) {
    if (PII_KEYS.has(key.toLowerCase())) delete out[key];
  }
  return out;
}

// RN SDK only accepts string | number | boolean as property values.
// Drop arrays / objects / undefined; coerce Date to epoch ms; stringify the rest defensively.
function coerceForRn(props: Record<string, unknown>): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(props)) {
    if (value === null || value === undefined) continue;
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      out[key] = value;
    } else if (value instanceof Date) {
      out[key] = value.getTime();
    } else {
      // Arrays / nested objects are not supported by the RN SDK — drop them.
      // Log so the team notices their tracking shape is wider than Amply accepts.
      if (__DEV__) console.warn(`[amply] property "${key}" of unsupported type — dropped`);
    }
  }
  return out;
}

export async function track(name: string, props: Record<string, unknown> = {}) {
  // 1. Existing analytics — unchanged.
  Mixpanel.track(name, props);

  // 2. Amply fan-out.
  await Amply.track({
    name: pascalCase(name),
    properties: coerceForRn(stripPii(props)),
  });
}

export function setUserId(id: string | null) {
  Mixpanel.identify(id ?? '');
  Amply.setUserId(id);
}

export function setUserProperties(props: Record<string, unknown>) {
  Mixpanel.getPeople().set(props);
  Amply.setCustomProperties(coerceForRn(stripPii(props)));
}

export function logout() {
  Mixpanel.reset();
  Amply.setUserId(null);
  Amply.clearCustomProperties();
}
```

If the project ships a typed event catalogue (`type AnalyticsEvent = 'paywall_shown' | ...`), keep the type — wrap it.

## Template — Swift (iOS)

```swift
// AnalyticsService.swift
import AmplySDK
import FirebaseAnalytics

final class AnalyticsService {
    static let shared = AnalyticsService()
    private var amply: Amply!

    func bootstrap(amply: Amply) {
        self.amply = amply
    }

    func track(_ name: String, properties: [String: Any] = [:]) {
        // Existing analytics
        Analytics.logEvent(name, parameters: properties)

        // Amply fan-out
        let stripped = stripPii(properties)
        amply.track(event: pascalCase(name), properties: stripped)
    }

    func setUserId(_ id: String?) {
        Analytics.setUserID(id)
        amply.setUserId(userId: id)
    }

    func setUserProperties(_ props: [String: Any]) {
        for (k, v) in props { Analytics.setUserProperty("\(v)", forName: k) }
        amply.setCustomProperties(properties: stripPii(props))
    }

    func logout() {
        Analytics.setUserID(nil)
        amply.setUserId(userId: nil)
        amply.clearCustomProperties()
    }

    private func pascalCase(_ s: String) -> String {
        s.split(whereSeparator: { ["_", "-", " "].contains($0) })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    private func stripPii(_ props: [String: Any]) -> [String: Any] {
        let pii: Set<String> = ["email", "phone", "address", "ip"]
        return props.filter { !pii.contains($0.key.lowercased()) }
    }
}
```

Bootstrap from the same place that constructs `Amply`:

```swift
let amply = Amply(config: cfg)
AnalyticsService.shared.bootstrap(amply: amply)
self.amply = amply
```

## Template — Kotlin (Android)

```kotlin
// AnalyticsService.kt
package com.example.app.analytics

import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.ktx.Firebase
import tools.amply.sdk.Amply

class AnalyticsService(
    private val firebase: com.google.firebase.analytics.FirebaseAnalytics = Firebase.analytics,
) {
    private var amply: Amply? = null

    fun bootstrap(amply: Amply) { this.amply = amply }

    fun track(name: String, properties: Map<String, Any> = emptyMap()) {
        firebase.logEvent(name, properties.toBundle())

        amply?.track(event = pascalCase(name), properties = stripPii(properties))
    }

    fun setUserId(id: String?) {
        firebase.setUserId(id)
        amply?.setUserId(id)
    }

    fun setUserProperties(props: Map<String, Any>) {
        props.forEach { (k, v) -> firebase.setUserProperty(k, v.toString()) }
        amply?.setCustomProperties(stripPii(props))
    }

    fun logout() {
        firebase.setUserId(null)
        amply?.setUserId(null)
        amply?.clearCustomProperties()
    }

    private fun pascalCase(s: String): String =
        s.split('_', '-', ' ')
            .joinToString("") { it.replaceFirstChar(Char::titlecase) }

    private fun stripPii(props: Map<String, Any>): Map<String, Any> {
        val pii = setOf("email", "phone", "address", "ip")
        return props.filterKeys { it.lowercase() !in pii }
    }
}
```

Bootstrap from `Application.onCreate` after constructing `Amply`.

## Template — KMP

Live the wrapper in `commonMain` and let it reach `AmplyHolder.instance` (see `sdk-cheatsheet-kmp.md`). Use `expect/actual` only for vendor SDKs that are not multiplatform-friendly (Firebase, Mixpanel — both have their own KMP wrappers; if not, declare an `expect class VendorAnalytics` and provide platform actuals).

## Gating pattern (SDK 0.5.0+)

Use `trackGated` (instead of `track`) when the app must **pause and wait** for a campaign action to complete before proceeding — e.g. a rewarded ad before Save, a campaign offer before Export.

> **SDK 0.5.0 note:** `trackEvent(..., onProceed, onCancel)` callback continuation and `registerCampaignPresenter` are **removed**. The patterns below replace them entirely.

Register the presenter once at startup (before the first gate-able event fires):

**TypeScript (RN/Expo)**

```ts
// startup — after Amply.initialize
const unregisterGate = await Amply.registerGate(
  'https://campaigns.example.com',
  (params, info, resolution) => {
    showCampaignModal(params, info, {
      onComplete: () => resolution.resolve('completed'),
      onDismiss: () => resolution.resolve('dismissed'),
    });
  },
  { onAbort: 'cancel', timeoutMs: 60_000 },
);

// gate-able call site
export async function trackGatedSave(props: Record<string, unknown> = {}) {
  const decision = await Amply.trackGated('SaveTapped', coerceForRn(stripPii(props)));
  return decision.outcome === 'proceed';
}
```

**Swift (iOS)**

```swift
// startup — amply already constructed
amply.registerGate(
    baseUrl: "https://campaigns.example.com",
    presenter: MyCampaignPresenter(),
    onAbort: .cancel,
    timeoutMs: 60_000
)

// gate-able call site inside AnalyticsService
func trackGatedSave(properties: [String: Any] = [:]) async -> Bool {
    let decision = await amply.trackGated(
        event: "SaveTapped",
        properties: stripPii(properties)
    )
    if case .proceed = decision { return true }
    return false
}
```

**Kotlin (Android / KMP)**

```kotlin
// startup — Application.onCreate, after amply constructed
amply.registerGate(
    baseUrl = "https://campaigns.example.com",
    presenter = MyCampaignPresenter(),
    onAbort = AbortPolicy.Cancel,
    timeoutMs = 60_000,
)

// gate-able call site inside AnalyticsService / commonMain wrapper
suspend fun trackGatedSave(properties: Map<String, Any> = emptyMap()): Boolean {
    val decision = amply.trackGated(
        event = "SaveTapped",
        properties = stripPii(properties),
    )
    return decision is GateDecision.Proceed
}
```

## What the wrapper guarantees

- One place to read for "where is Amply called from?".
- Easy to disable (return early) for debugging or in tests.
- Easy to extend later — add Sentry breadcrumbs, BI fan-out, sampling, etc., without touching call sites.

## "But I want to disable Amply for some users"

If your business logic says some users shouldn't see Amply campaigns (kids' mode, free tier without campaign features, accounts flagged for special handling), **don't add a flag inside the wrapper**. Instead: don't construct `Amply(config:)` for those users. See `consent-and-privacy.md` § "Strict — defer construction".

The wrapper either has an Amply instance (and uses it) or doesn't (and `setUserId` / `track` / etc. become no-ops via optional chaining or nil-checks). One decision point, in the host app, at construction. Not a runtime gate inside the wrapper.

## Anti-patterns to flag

- **Direct `Amply.track(...)` calls scattered across screens.** Reject and route through the wrapper.
- **Wrapping Amply in a runtime "consent" / "tracking enabled" gate.** Defensive over-engineering — Amply is a first-party product-feature SDK, not tracking analytics. If you don't want a user to see Amply, don't construct the SDK for them. See `consent-and-privacy.md`.
- **Wrapper that forwards every event from a high-volume vendor (Sentry breadcrumbs, Datadog RUM events) to Amply.** Add an allow-list of event names — Amply targeting works on a curated set, not the full firehose.
