# SDK cheatsheet — Android / Kotlin

Package: `tools.amply:sdk-android` (Maven Central).

Like iOS, the Android SDK is **instance-based**. Construct an `Amply` with a config and your `Application`. Hold the reference on `Application` so it lives as long as the process.

## Install

In `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("tools.amply:sdk-android:0.1.9")
}
```

Or `app/build.gradle` (Groovy):

```groovy
implementation 'tools.amply:sdk-android:0.1.9'
```

Pin to the latest release — check `multiplatform-library-template/gradle.properties` (`VERSION_NAME`) or Maven Central.

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
amply.registerDeepLinkListener(object : DeepLinkListener {
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
amply.setSystemEventsListener(object : SystemEventsListener {
    override fun onSystemEvent(/* ... */) { /* ... */ }
})
```

## Public surface (API table)

| Method | Signature | Notes |
|---|---|---|
| Construct | `Amply(config: AmplyConfig, application: Application)` | |
| `track` | `fun track(event: String, properties: Map<String, Any> = emptyMap())` | |
| `setUserId` | `fun setUserId(userId: String?)` | |
| `setCustomProperty` | `fun setCustomProperty(key: String, value: Any)` | Property keys: max 255 chars (Kotlin SDK). For cross-platform safety with RN clients, prefer ≤32. |
| `setCustomProperties` | `fun setCustomProperties(properties: Map<String, Any>)` | Batch — preferred over a `forEach { setCustomProperty(...) }` loop. |
| `getCustomProperty` | `suspend fun getCustomProperty(key: String): Any?` | Suspend; returns `null` when key is not set. |
| `removeCustomProperty` / `clearCustomProperties` | | |
| `registerDeepLinkListener` | `fun registerDeepLinkListener(listener: DeepLinkListener)` | |
| `setSystemEventsListener` | `fun setSystemEventsListener(listener: SystemEventsListener)` | |
| `setLogLevel` / `getLogLevel` / `setLogListener` | | |

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
