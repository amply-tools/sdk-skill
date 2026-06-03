# Analytics vendor detection

Use this during Phase 2. The skill greps for vendor signatures in `package.json`, `Podfile`, Gradle dependency declarations, and source files. For each vendor, also grep for the **call sites** so the audit captures `file:line` and the property keys/types being passed.

**Two classes of call sites:** track-event calls (`.track`, `.logEvent`, `.capture`) and property-write calls (`.people.set`, `.setUserProperty`, `.identify(_, traits)`). These have different decision trees and different audit tables — see `references/event-naming.md` for the events tree and `references/property-writes.md` for the property-writes tree.

**System-event overlap:** the SDK auto-fires a set of system events (`SessionStarted`, `SessionFinished`, etc.). Project events that overlap (e.g. `session_start`, `app_open`) must NOT be mirrored to Amply. See `references/system-events.md`.

**3rd-party SDK bridges:** some SDKs (RevenueCat, Superwall, Adjust) are the source of business events but don't fire app-side `.track()` directly. The audit detects them and flags bridge gaps in Observations. See `references/third-party-event-bridges.md`.

## Detection signatures by vendor

| Vendor | Package / dependency markers | Native call-site patterns |
|---|---|---|
| **Firebase Analytics** (native) | iOS: `pod 'Firebase/Analytics'`, `import FirebaseAnalytics`. Android: `implementation("com.google.firebase:firebase-analytics-ktx")`, `import com.google.firebase.analytics.ktx.analytics`. | Swift: `Analytics.logEvent(name, parameters:)`. Kotlin: `Firebase.analytics.logEvent(name) { ... }`, `firebaseAnalytics.logEvent(name, bundle)`. |
| **Firebase Analytics** (RN) | `@react-native-firebase/analytics`, `expo-firebase-analytics` (deprecated; flag it), `@react-native-firebase/app`. | `analytics().logEvent(name, params)`. |
| **Amplitude** | iOS: `pod 'AmplitudeSwift'`, `import AmplitudeSwift`. Android: `com.amplitude:analytics-android`. RN: `@amplitude/analytics-react-native`. | Swift: `Amplitude.instance.track(BaseEvent(eventType: ...))`. Kotlin: `amplitude.track(name, props)`. TS: `track('Event', props)` or `amplitude.track(...)`. |
| **Mixpanel** | iOS: `pod 'Mixpanel-swift'`. Android: `com.mixpanel.android:mixpanel-android`. RN: `mixpanel-react-native`. | Swift: `Mixpanel.mainInstance().track(event:, properties:)`. Kotlin: `mixpanelAPI.track(name, props)`. TS: `Mixpanel.track(event, props)` or `mixpanel.track(...)`. |
| **Segment** | iOS: `pod 'Analytics'` (or `pod 'Segment-Analytics-Swift'`). Android: `com.segment.analytics.kotlin:android`. RN: `@segment/analytics-react-native`. | Swift: `analytics.track(name:, properties:)`. Kotlin: `analytics.track(name, props)`. TS: `analytics.track(event, properties)`. |
| **RudderStack** | RN: `@rudderstack/rudder-sdk-react-native`. iOS: `pod 'Rudder'`. Android: `com.rudderstack.android.sdk:core`. | TS: `rudder.track(event, props)`. Native: similar `track(...)` API. |
| **PostHog** | RN: `posthog-react-native`. iOS: `pod 'PostHog'`. Android: `com.posthog:posthog-android`. | TS: `posthog.capture(event, props)`. Swift: `PostHogSDK.shared.capture(event, properties:)`. |
| **Heap** | iOS: `pod 'HeapAnalytics'`. Android: `io.heap.core:heap-android`. | Swift: `Heap.shared.track(event, properties:)`. |
| **mParticle** | iOS: `pod 'mParticle-Apple-SDK'`. Android: `com.mparticle:android-core`. RN: `@mparticle/react-native-mparticle`. | TS / Swift / Kotlin: `MParticle.logEvent(...)` style. |
| **Snowplow** | iOS: `pod 'SnowplowTracker'`. Android: `com.snowplowanalytics:snowplow-android-tracker`. RN: `@snowplow/react-native-tracker`. | `tracker.track(...)` / `Snowplow.tracker(name).track(event)`. |
| **TelemetryDeck** | iOS: `import TelemetryClient`. (iOS-only, swift package). | `TelemetryDeck.signal("event")`. |
| **Countly** | iOS: `pod 'Countly'`. Android: `ly.count.android:sdk`. | `Countly.sharedInstance().recordEvent(name)`. |
| **Sentry** (when used as analytics, e.g. breadcrumbs) | `@sentry/react-native`, iOS `Sentry`, Android `io.sentry:sentry-android`. | `Sentry.captureMessage(...)`, `Sentry.addBreadcrumb({ category, message, data })`. Sentry isn't an analytics tool but **events fired via breadcrumbs / metrics may need Amply mirroring** if the team relies on them for behavioural data. Flag explicitly. |
| **Datadog RUM** | iOS: `pod 'DatadogCore'`, `pod 'DatadogRUM'`. Android: `com.datadoghq:dd-sdk-android-rum`. RN: `@datadog/mobile-react-native`. | `DatadogRum.shared.addAction(...)`, `addUserAction(...)`, `addError(...)`. |
| **New Relic** | iOS: `pod 'NewRelicAgent'`. Android: `com.newrelic.agent.android:android-agent`. | `NewRelic.recordCustomEvent(...)`, `NewRelic.recordMetric(...)`. |
| **UXCam** | iOS: `pod 'UXCam'`. Android: `com.uxcam:uxcam`. | `UXCam.logEvent(name, props)`. |
| **Smartlook** | iOS: `pod 'Smartlook-iOS-SDK'`. Android: `com.smartlook.android:sdk`. | `Smartlook.trackCustomEvent(...)`. |
| **Braze** | iOS: `pod 'BrazeKit'`. Android: `com.braze:android-sdk-base`. RN: `@braze/react-native-sdk`. | `Braze.shared.logCustomEvent(name, properties:)`. |
| **Iterable** | iOS: `pod 'Iterable-iOS-SDK'`. Android: `com.iterable:iterableapi`. | `IterableAPI.track(event:, dataFields:)`. |
| **Airship** | iOS: `pod 'Airship'`. Android: `com.urbanairship.android:urbanairship-core`. | `UAirship.analytics().add(CustomEvent(...))`. |
| **OneSignal** | iOS / Android / RN: `OneSignal*` packages. | `OneSignal.sendTag(...)` (treated as user property; not really analytics). |
| **Customer.io** | iOS: `pod 'CustomerIO-Tracking'`. Android: `io.customer.android:tracking`. RN: `customerio-reactnative`. | `CustomerIO.shared.track(name:, data:)`. |
| **Intercom** | iOS: `pod 'Intercom'`. Android: `io.intercom.android:intercom-sdk`. RN: `@intercom/intercom-react-native`. | `Intercom.logEvent(name, metaData:)`. |
| **Branch** | RN: `react-native-branch`. iOS: `pod 'BranchSDK'`. Android: `io.branch.sdk.android:library`. | `Branch.getInstance().userCompletedAction(...)` / `BranchEvent`. |
| **AppsFlyer** | RN: `react-native-appsflyer`. iOS: `pod 'AppsFlyerFramework'`. Android: `com.appsflyer:af-android-sdk`. | `AppsFlyerLib.shared().logEvent(...)`. |
| **Adjust** | RN: `react-native-adjust`. iOS: `pod 'Adjust'`. Android: `com.adjust.sdk:adjust-android`. | `Adjust.trackEvent(AdjustEvent(eventToken: ...))`. |
| **Kochava** | iOS: `pod 'KochavaTracker'`. Android: `com.kochava.tracker:tracker`. | `Kochava.shared.send(...)`. |
| **Singular** | iOS: `pod 'Singular-SDK'`. Android: `com.singular.sdk:singular_sdk`. | `Singular.event(name, props)`. |
| **AppMetrica** | iOS: `pod 'YandexMobileMetrica'`. Android: `com.yandex.android:mobmetricalib`. RN: `react-native-appmetrica` / `appmetrica-sdk`. | `AppMetrica.reportEvent(name, params)`. Common in CIS-region apps. |
| **Flurry** | iOS: `pod 'Flurry-iOS-SDK'`. Android: `com.flurry.android:analytics`. | `Flurry.logEvent(name, parameters)`. |
| **Matomo** (mobile) | iOS: `pod 'MatomoTracker'`. Android: `com.github.matomo-org:matomo-sdk-android`. | `MatomoTracker.shared.track(...)`, `tracker.track(TrackHelper...)`. |
| **CleverTap** | iOS: `pod 'CleverTap-iOS-SDK'`. Android: `com.clevertap.android:clevertap-android-sdk`. RN: `clevertap-react-native`. | `CleverTap.sharedInstance()?.recordEvent(name, properties:)`. |
| **MoEngage** | iOS: `pod 'MoEngage-iOS-SDK'`. Android: `com.moengage:moe-android-sdk`. RN: `react-native-moengage`. | `MoEngage.trackEvent(...)`. |
| **WebEngage** | iOS: `pod 'WebEngage'`. Android: `com.webengage:android-sdk`. RN: `react-native-webengage`. | `WebEngage.sharedInstance().analytics().track(name, props)`. |
| **Pendo** | iOS: `pod 'Pendo'`. Android: `sdk.pendo.io:pendoIO`. RN: `rn-pendo-sdk`. | `Pendo.track(name, properties)` — primarily product analytics + in-app guides. |
| **FullStory** | iOS: `pod 'FullStory'`. Android: `com.fullstory:instrumentation-full`. RN: `@fullstory/react-native`. | `FullStory.event(name, properties)` — session-replay focused; treat events similarly to Heap/Sentry breadcrumbs (curated allow-list before mirroring to Amply). |
| **RevenueCat** *(purchase analytics — not generic analytics)* | RN: `react-native-purchases`. iOS: `pod 'RevenueCat'`. Android: `com.revenuecat.purchases:purchases`. | `Purchases.shared.purchase(...)`, `Purchases.shared.getCustomerInfo(...)`. **Source of subscription state** — feed `subscription_status`, `trial_ends_at` Custom Properties from RC's `CustomerInfo`. |
| **Adapty** | RN: `react-native-adapty`. iOS: `pod 'Adapty'`. Android: `io.adapty:android-sdk`. | Same role as RevenueCat — feed entitlements into Amply Custom Properties. |
| **Superwall** | RN: `@superwall/react-native-superwall`. iOS: `pod 'SuperwallKit'`. Android: `com.superwall.sdk:superwall-android`. | Paywall-specific; use Superwall events (e.g. `Superwall.shared.track(...)`) as inputs for `paywall_*` Amply events. |

## Per-language grep patterns to run

Starter regexes for the audit. Run them across `src/`, `ios/`, `android/`, `commonMain/`. Capture `file:line` + 5 lines of context so the agent can read property keys and (for property-writes) sample values.

### Track-event calls

```
# TypeScript / JavaScript
\b(analytics|Analytics|tracker|track)\.(track|capture|logEvent|identify)\b
\bMixpanel(\.|_).*\.track\b
\bposthog\.capture\b
\bamplitude\.track\b
\bSegment\.track\b
\bfirebase\.analytics\(\)\.logEvent\b
\b@react-native-firebase/analytics\b

# Swift
\bAnalytics\.logEvent\(\b
\bAmplitude\.instance\.track\(\b
\bMixpanel\.mainInstance\(\)\.track\(\b
\bPostHogSDK\.shared\.capture\(\b
\b\.track\(name:\s*[\"\']\b
\bSegmentAnalytics(Cocoa)?\b

# Kotlin
\bFirebase\.analytics\.logEvent\b
\bfirebaseAnalytics\.logEvent\b
\bamplitude\.track\b
\bMixpanelAPI\b
\bSnowplow\b
```

### Property-write calls

```
# TypeScript / JavaScript
\bmixpanel\.people\.(set|set_once|increment|union)\b
\bamplitude\.setUserProperti(es|y)\b
\bnew\s+Identify\(\)|\bIdentify\(\)\.set\b
\banalytics\.identify\(
\bposthog\.identify\(|\bposthog\.setPersonProperties\b
\brudder(stack)?\.identify\(
\bsetUserProperty\(
\bHeap\.addUserProperties\b
\bOneSignal\.sendTag(s)?\b
\bBraze\.shared\.setCustomAttribute\b

# Swift
\bMixpanel\.mainInstance\(\)\.people\.(set|set_once|increment)\(
\bAmplitude\.instance\.setUserProperties\(\b
\bAmplitude\.instance\.identify\(\b
\bAnalytics\.setUserProperty\(
\b\.identify\(\s*userId:\b
\bPostHogSDK\.shared\.identify\(
\bBraze\.shared\.setCustomAttribute\(

# Kotlin
\bmixpanel\.people\b
\bamplitude\.setUserProperti(es|y)\b
\bFirebase\.analytics\.setUserProperty\b
\bfirebaseAnalytics\.setUserProperty\b
\bposthog\.identify\b|\bposthog\.setPersonProperties\b
\bOneSignal\.sendTag\b
```

### 3rd-party SDK uses (for bridge gap check — see `third-party-event-bridges.md`)

```
\bPurchases\.shared\.purchase\b
\bPurchases\.shared\.getCustomerInfo\b
\bPurchases\.shared\.customerInfoStream\b
\bPurchases\.purchasePackage\b
\bAdapty\.makePurchase\b
\bAdapty\.getProfile\b
\bSuperwall\.shared\.register\b
\bhandleSuperwallEvent\b
\bonPurchaseCompleted\b|\bonPurchaseFailure\b   # RevenueCatUI / Paywall.swift
\bBranch\.getInstance\(\)\.userCompletedAction\b
\bAppsFlyerLib\.shared\(\)\.logEvent\b
\bAdjust\.trackEvent\b
```

## Existing-wrapper detection

Check whether most analytics calls go through one module:

| File-name pattern | Likely a wrapper |
|---|---|
| `analytics.ts`, `analytics.tsx`, `Tracker.ts`, `useAnalytics.ts`, `analytics/index.ts` | Yes (RN/TS) |
| `Analytics.swift`, `AnalyticsService.swift`, `Telemetry.swift`, `Tracker.swift` | Yes (iOS) |
| `Analytics.kt`, `AnalyticsService.kt`, `Tracker.kt`, `Telemetry.kt` | Yes (Android / KMP) |

Also look for **constants modules** (`event_names.ts`, `Events.kt`, `AnalyticsEvent.swift`) — generated event-name enums or sealed classes are a strong signal of a typed wrapper. The skill should integrate Amply through that wrapper, preserving its typing.

## When NOT to extend the existing wrapper (Phase 2.5 fork)

Switch to a new minimal wrapper only if:

- The existing wrapper is **server-only / BI-only** and cannot fire from the device.
- The existing wrapper is **typed against a vendor-specific schema** (e.g. Segment plan-driven types) so adding Amply events would force schema breakage.
- The existing wrapper is **gated behind aggressive consent rules** that would block targeting Amply campaigns even for users who consented to in-app personalisation.
- The existing wrapper has **performance constraints** (batched / debounced) that would mask Amply's near-real-time triggering behaviour.

Document the exception in `amply-audit.md` so the team can revisit later.
