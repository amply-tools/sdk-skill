# SDK cheatsheet — Android / Kotlin

Package: `tools.amply:sdk-android` (Maven Central).

Like iOS, the Android SDK is **instance-based**. Construct an `Amply` with a config and your `Application`. Hold the reference on `Application` so it lives as long as the process.

## Install

In `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("tools.amply:sdk-android:0.15.0")
}
```

Or `app/build.gradle` (Groovy):

```groovy
implementation 'tools.amply:sdk-android:0.15.0'
```

Pin to the latest release — check Maven Central for the current version. **Pin `0.15.0` or later** (Mini-app campaigns need 0.12.0, template variables in campaign links 0.13.0, Test on device (`handleUrl`), Show after and `getLastCampaignTouch` 0.15.0). Listener registration changed shape in 0.9.0 — see *Withdrawing a listener* below; the examples here are written against it and will not compile on 0.8.x. (Event-history audience targeting needs 0.6.1+, which 0.12.0 satisfies.)

## Upgrading the SDK version — bump, refresh, verify, rebuild

Editing the version literal isn't enough. Gradle caches resolved modules in `~/.gradle/caches`, and a dynamic version (`+` / `latest.release`), a `resolutionStrategy.force`, or a BOM / platform constraint can hold or override what actually resolves. After changing the version:

1. **Refresh + re-resolve** — don't rely on the IDE's incremental sync:
   ```bash
   ./gradlew :app:dependencies --refresh-dependencies > /dev/null
   ```
2. **Verify the *resolved* version** — what Gradle actually selected, including any forced override (not just the declared literal):
   ```bash
   ./gradlew :app:dependencyInsight --dependency tools.amply:sdk-android --configuration debugRuntimeClasspath
   # → tools.amply:sdk-android:<X> (selected). A "<Y> -> <X>" line means something is forcing the version.
   ```
3. **Rebuild** — `./gradlew :app:assembleDebug` (or your variant).
4. **Confirm at runtime** — per SKILL.md Phase 7 "Version bumps (any platform)": the device session must report the expected `sdkVersionNormalized`.

## Initialize — in `Application.onCreate`

```kotlin
package com.example.app

import android.app.Application
import tools.amply.sdk.Amply
import tools.amply.sdk.config.AmplyConfig

class MyApp : Application() {
    lateinit var amply: Amply
        private set

    override fun onCreate() {
        super.onCreate()

        val config = AmplyConfig(
            appId = BuildConfig.AMPLY_APP_ID,
            apiKeyPublic = BuildConfig.AMPLY_KEY_PUBLIC,
            apiKeySecret = BuildConfig.AMPLY_KEY_SECRET,
            defaultConfig = null,
            // Optional: configBaseUrl, backendBaseUrl — only when targeting dev/staging.
        )
        amply = Amply(config = config, application = this)
    }
}
```

Or, with the builder DSL (clearer for keys split across config sources):

```kotlin
import tools.amply.sdk.config.amplyConfig

val config = amplyConfig {
    api {
        appId = BuildConfig.AMPLY_APP_ID
        apiKeyPublic = BuildConfig.AMPLY_KEY_PUBLIC
        apiKeySecret = BuildConfig.AMPLY_KEY_SECRET
    }
    // network { configBaseUrl = "..."; backendBaseUrl = "..." }   // optional
}
amply = Amply(config = config, application = this)
```

`AmplyConfig` requires `appId`, `apiKeyPublic`, `apiKeySecret`, and `defaultConfig` (pass `null` if not used). `apiKeySecret` is a real secret — don't commit it to a public sample, and treat it like any other backend secret in CI.

Register it in the manifest:

```xml
<application
    android:name=".MyApp"
    ... >
```

Read keys from `BuildConfig` (defined via `gradle.properties` + `buildConfigField` in Gradle), **never hard-coded** in source. Pull `apiKeySecret` from the same secret source you use for backend keys (CI variable, signed `.envrc`, encrypted properties).

There is **no static `AmplySDK.initialize(context, "API_KEY")`** — that's a common mis-recollection. Use the constructor.

## Track events

```kotlin
amply.track(event = "PaywallShown", properties = mapOf(
    "screen" to "home",
    "source" to "cta_banner",
))
```

## Identify users

```kotlin
amply.setUserId("user-123")    // login
amply.setUserId(null)          // logout — also call clearCustomProperties()
```

## Custom Properties

Allowed value types: `String`, `Int`, `Long`, `Float`, `Double`, `Boolean`, `DateTimeValue`.

```kotlin
amply.setCustomProperties(mapOf(
    "subscription_status" to "trial",
    // Counter — fallback only for fleets below Amply SDK 0.6.1; on 0.6.1+ target the Purchase event count directly.
    "total_purchases" to 0,
    "notifications_enabled" to true,
))
amply.setCustomProperty("locale", "en-US")

// Suspend retrieval — call from a coroutine.
val value = amply.getCustomProperty("subscription_status")

amply.removeCustomProperty("locale")
amply.clearCustomProperties()   // call on logout
```

## Deeplink listener

The interface is `tools.amply.sdk.actions.DeepLinkListener`:

```kotlin
package tools.amply.sdk.actions

interface DeepLinkListener {
    fun onDeepLink(url: String, info: Map<String, Any>): Boolean
}
```

Implement it (anonymous object or class) — **two parameters**, **`Boolean` return**:

```kotlin
val deepLinkToken = amply.registerDeepLinkListener(object : DeepLinkListener {
    override fun onDeepLink(url: String, info: Map<String, Any>): Boolean {
        if (url.startsWith("amply://")) {
            navigator.routeAmplyDeeplink(url, info)
            return true
        }
        return false
    }
})
```

There is **no lambda DSL** overload — `amply.registerDeepLinkListener { ... }` will not compile against the public interface.

## System events

```kotlin
val systemEventsToken = amply.setSystemEventsListener(object : SystemEventsListener {
    override fun onEvent(event: EventInterface) { /* ... */ }
})
```

## Withdrawing a listener (SDK 0.9.0+)

Every registration returns a `ListenerToken`. **Keep it** — it is the only thing that withdraws
that registration:

```kotlin
val token = amply.registerDeepLinkListener(myListener)
// later, when the component that owns myListener goes away:
amply.removeDeepLinkListener(token)
```

Withdrawal takes the **token**, never the listener object. Passing a token that is no longer the
installed one is a no-op — so a component being torn down cannot silence the one that has already
replaced it.

**Who needs to care.** An `Application`-scoped listener that lives for the whole process never has
to withdraw. Anything shorter-lived does: an `Activity`, a Compose screen, a feature module. A
listener left installed after its owner is gone keeps that owner reachable for the life of the
process, and the SDK keeps calling it.

**Gates too.** `registerGate` returns a token and `unregisterGate(token)` withdraws it. A gate left
behind by a component that is gone parks the next gated call on that URL for the whole fail-open
timeout, with nothing on screen.

## Public surface (API table)

| Method | Signature | Notes |
|---|---|---|
| Construct | `Amply(config: AmplyConfig, application: Application)` | |
| `track` | `fun track(event: String, properties: Map<String, Any> = emptyMap())` | |
| `setUserId` | `fun setUserId(userId: String?)` | |
| `setAppLanguage` | `fun setAppLanguage(tag: String?)` — SDK 0.14.0+. The language the app shows, any form (`pt-BR`, `pt_BR`, `zh-Hant`); `null` = automatic. Config: `appLanguage` in `AmplyConfig`. |
| `setCustomProperty` | `fun setCustomProperty(key: String, value: Any)` | Property keys: max 255 chars (Kotlin SDK). For cross-platform safety with RN clients, prefer ≤32. |
| `setCustomProperties` | `fun setCustomProperties(properties: Map<String, Any>)` | Batch — preferred over a `forEach { setCustomProperty(...) }` loop. |
| `getCustomProperty` | `suspend fun getCustomProperty(key: String): Any?` | Suspend; returns `null` when key is not set. |
| `removeCustomProperty` / `clearCustomProperties` | | |
| `trackGated` | `suspend fun trackGated(event: String, properties: Map<String, Any> = emptyMap()): GateDecision` — suspends until campaign resolves; returns `GateDecision.Proceed(reason)` or `GateDecision.Cancelled`. | Call from a coroutine. |
| `registerGate` | `fun registerGate(...): ListenerToken` — call once at startup. | Returns the token that withdraws it. |
| `unregisterGate` | `fun unregisterGate(token: ListenerToken)` | |
| `registerDeepLinkListener` | `fun registerDeepLinkListener(listener: DeepLinkListener): ListenerToken` | |
| `removeDeepLinkListener` | `fun removeDeepLinkListener(token: ListenerToken)` | Takes the **token**, not the listener. |
| `handleUrl` | `fun handleUrl(url: String): Boolean` — SDK 0.15.0+. | Forward every URL the Activity is opened with (`onCreate` + `onNewIntent`, `ACTION_VIEW` data), before your own routing; `true` = an Amply test link (Test on device), don't route it. See `deeplink-wiring.md`. |
| `setSystemEventsListener` | `fun setSystemEventsListener(listener: SystemEventsListener): ListenerToken` | |
| `clearSystemEventsListener` | `fun clearSystemEventsListener(token: ListenerToken)` | One listener per SDK: a second `set` replaces the first — extend the existing one. |
| `getLastCampaignTouch` | `suspend fun getLastCampaignTouch(withinMs: Long): CampaignTouch?` — SDK 0.15.0+. | Campaign last shown / completed within the window (≤ 30 d): `campaignId`, `campaignName`, `kind` (`SHOWN` / `ENGAGED`), `atMs`. See `campaign-attribution.md`. |
| `setLogListener` | `fun setLogListener(listener: LogListener): ListenerToken` | No longer accepts `null`. |
| `clearLogListener` | `fun clearLogListener(token: ListenerToken)` | |
| `setLogLevel` / `getLogLevel` | | |

## Gate API (SDK 0.5.0+)

`GateDecision.Proceed(reason: ProceedReason)` / `GateDecision.Cancelled`. `ProceedReason.Completed` / `ProceedReason.FailOpen`.

`CampaignPresenter` interface:

```kotlin
interface CampaignPresenter {
    fun present(params: Map<String, String>, info: Map<String, Any>, resolution: CampaignResolution)
    fun dismiss()
}
// CampaignResolution.resolve(result) where CampaignResult is .Completed / .Dismissed / .Unavailable
```

`AbortPolicy.Cancel` (default) / `AbortPolicy.Proceed`.

### Gate example

```kotlin
// At startup — in Application.onCreate, after constructing amply
amply.registerGate(
    baseUrl = "https://campaigns.example.com",
    presenter = MyCampaignPresenter(),
    onAbort = AbortPolicy.Cancel,
    timeoutMs = 60_000,
)

// At a gate-able moment — inside a coroutine scope
viewModelScope.launch {
    val decision = amply.trackGated(
        event = "SaveTapped",
        properties = mapOf("screen" to "editor"),
    )
    when (decision) {
        is GateDecision.Proceed -> performSave()
        is GateDecision.Cancelled -> showCancelledFeedback()
    }
}
```

## Requirements

- Android `minSdk` 24+ (RN target) / 21+ (KMP library).
- Kotlin 1.9+ for KMP consumers; pure Android consumers can stay on whatever Kotlin version their AGP supports.

## Rate Review caveat

Google Play's in-app review API only delivers a real prompt in **Play Store-distributed release builds**. Debug builds use a fake review manager with a debug dialog. Mention this to the user any time a campaign uses the `RateReview` action.

## Common mistakes (rewrite on sight)

```kotlin
// ❌ Static initialize — does not exist on this SDK.
AmplySDK.initialize(context, "API_KEY")

// ❌ Lambda DSL deeplink listener — no overload.
amply.registerDeepLinkListener { url -> ... }

// ❌ DeepLinkListener with the wrong signature.
override fun onDeepLink(url: String) { ... }   // missing info, missing Boolean return.

// ❌ Constructing without Application — required.
val amply = Amply(config = cfg)   // compile error / runtime error.
```
