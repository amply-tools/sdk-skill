# SDK cheatsheet — Kotlin Multiplatform (KMP)

Package: `tools.amply:sdk-kmp` (KMP metadata) plus per-target artefacts (`tools.amply:sdk-android`, native iOS variants via the published XCFramework).

> **Note on authority:** the KMP-side public surface (constructor shape across `androidMain`/`iosMain`, `expect/actual` boundaries) is not exhaustively covered by the public Amply docs, which document the Android / iOS / RN public surfaces. The patterns below are **inferred from the published KMP sample apps**. Verify against the SDK for the version you pin before relying on a specific shape, and add a `[fix]` issue if you find a discrepancy.

In a KMP project, you typically:

1. Construct the `Amply` instance in a **shared** init function.
2. Each platform target (Android `Application`, iOS `AppDelegate`/`@main`, JVM main) calls that init from its own startup code.
3. Strong references still apply on the platform side — KMP code can't keep iOS/Android objects alive on its own.

## Install

In `commonMain` source set's Gradle config:

```kotlin
kotlin {
    sourceSets {
        commonMain {
            dependencies {
                implementation("tools.amply:sdk-kmp:0.1.9")
            }
        }
    }
}
```

For iOS framework consumers (XcodeGen / SwiftUI app shell), the published XCFramework wraps the same library — see `sdk-cheatsheet-ios.md`.

## Upgrading the SDK version

Same mechanics as Android for the Gradle artefacts (`tools.amply:sdk-kmp` + per-target `tools.amply:sdk-android`): force a re-resolve and verify the **resolved** version, not the declared literal — see `sdk-cheatsheet-android.md` → "Upgrading the SDK version" (`--refresh-dependencies`, `dependencyInsight`). The iOS framework consumer follows `sdk-cheatsheet-ios.md` → "Upgrading the SDK version" (SPM or CocoaPods). In every case the decisive check is identical: the running build's session reports the expected `sdkVersionNormalized` (SKILL.md Phase 7 "Version bumps (any platform)").

## Shared init module

```kotlin
// commonMain/AmplyHolder.kt
package myapp

import tools.amply.sdk.Amply
import tools.amply.sdk.config.AmplyConfig

object AmplyHolder {
    lateinit var instance: Amply
        private set

    fun initialize(config: AmplyConfig, platform: PlatformInit) {
        instance = platform.constructAmply(config)
    }
}

expect class PlatformInit {
    fun constructAmply(config: AmplyConfig): Amply
}
```

```kotlin
// androidMain/PlatformInit.kt
package myapp

import android.app.Application
import tools.amply.sdk.Amply
import tools.amply.sdk.config.AmplyConfig

actual class PlatformInit(private val application: Application) {
    actual fun constructAmply(config: AmplyConfig): Amply =
        Amply(config = config, application = application)
}
```

```kotlin
// iosMain/PlatformInit.kt
package myapp

import tools.amply.sdk.Amply
import tools.amply.sdk.config.AmplyConfig

actual class PlatformInit {
    actual fun constructAmply(config: AmplyConfig): Amply =
        Amply(config = config)  // iOS Amply takes config only.
}
```

## Per-platform startup glue

Android — `Application.onCreate`:

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AmplyHolder.initialize(
            config = AmplyConfig(
                appId = BuildConfig.AMPLY_APP_ID,
                apiKeyPublic = BuildConfig.AMPLY_KEY_PUBLIC,
                apiKeySecret = BuildConfig.AMPLY_KEY_SECRET,
                defaultConfig = null,
            ),
            platform = PlatformInit(application = this),
        )
    }
}
```

iOS — `AppDelegate` or `@main App`:

```swift
import shared    // your KMP framework
import AmplySDK

@main
struct MyApp: App {
    init() {
        let appId = Bundle.main.object(forInfoDictionaryKey: "AmplyAppId") as! String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeyPublic") as! String
        let secretKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeySecret") as! String

        AmplyHolder.shared.doInitialize(
            config: AmplyConfig(
                appId: appId,
                apiKeyPublic: publicKey,
                apiKeySecret: secretKey,
                defaultConfig: nil
            ),
            platform: PlatformInit()
        )
    }
}
```

Note on `doInitialize`: Kotlin/Native maps Kotlin `initialize(...)` to a Swift method named `doInitialize(...)` because `initialize` collides with a reserved Swift selector. Verify against the actual generated header for the SDK version you pin.

## Tracking from common code

```kotlin
// commonMain
suspend fun reportPaywallShown(screen: String, source: String) {
    AmplyHolder.instance.track(
        event = "PaywallShown",
        properties = mapOf("screen" to screen, "source" to source),
    )
}

// Gate-able moment — suspend until campaign resolves
suspend fun trackGatedSave(screen: String): GateDecision =
    AmplyHolder.instance.trackGated(
        event = "SaveTapped",
        properties = mapOf("screen" to screen),
    )
```

`registerGate` takes a platform-side `CampaignPresenter` — call it from platform startup code (Android `Application.onCreate` / iOS `AppDelegate`), not from `commonMain`, because the presenter needs access to the platform UI layer.
```

## Custom Properties from common code

```kotlin
fun applyEntitlements(entitlements: Entitlements) {
    AmplyHolder.instance.setCustomProperties(mapOf(
        "subscription_status" to entitlements.status,
        "total_purchases" to entitlements.totalPurchases,
        "notifications_enabled" to entitlements.pushEnabled,
    ))
}
```

## Deeplink listener — register on each platform

The listener interface lives in `tools.amply.sdk.actions.DeepLinkListener`. Register from platform-side code (so the platform navigation lib is in scope):

- Android: `MainActivity.onCreate` registers a listener that talks to your nav controller.
- iOS: `App.init` (SwiftUI) or `AppDelegate.didFinishLaunching` registers a listener bridged to your iOS navigator.

Both follow the **same** signature (`onDeepLink(url, info) -> Bool`).

## Module layout

The KMP source-set structure (mirroring the SDK's `library/src/` layout):

```
commonMain/
  kotlin/
    myapp/
      AmplyHolder.kt          # shared singleton
      PlatformInit.kt         # expect class
      analytics/Tracker.kt    # shared wrapper that calls AmplyHolder.instance
androidMain/
  kotlin/
    myapp/
      PlatformInit.kt         # actual
iosMain/
  kotlin/
    myapp/
      PlatformInit.kt         # actual
```

## Public surface (API table — commonMain)

| Method | Signature | Notes |
|---|---|---|
| `track` | `suspend fun track(event: String, properties: Map<String, Any> = emptyMap())` | |
| `trackGated` | `suspend fun trackGated(event: String, properties: Map<String, Any> = emptyMap()): GateDecision` | Suspends until campaign resolves. |
| `registerGate` | `fun registerGate(baseUrl: String, presenter: CampaignPresenter, onAbort: AbortPolicy = AbortPolicy.Cancel, timeoutMs: Long = 60_000)` | Call from platform startup, not commonMain. |
| `setUserId` | `fun setUserId(userId: String?)` | |
| `setCustomProperty` | `fun setCustomProperty(key: String, value: Any)` | |
| `setCustomProperties` | `fun setCustomProperties(properties: Map<String, Any>)` | |
| `getCustomProperty` | `suspend fun getCustomProperty(key: String): Any?` | |
| `removeCustomProperty` / `clearCustomProperties` | | |
| `registerDeepLinkListener` | `fun registerDeepLinkListener(listener: DeepLinkListener)` | |

## Gate API (SDK 0.5.0+)

Same types as Android/Kotlin: `GateDecision.Proceed(reason: ProceedReason)` / `GateDecision.Cancelled`; `ProceedReason.Completed` / `ProceedReason.FailOpen`; `AbortPolicy.Cancel` / `AbortPolicy.Proceed`.

`CampaignPresenter` and `CampaignResolution`/`CampaignResult` live in the platform layer — wire them from `androidMain`/`iosMain`.

> **SDK 0.5.0 breaking change:** `trackEvent(..., onProceed, onCancel)` and `registerCampaignPresenter` are removed. Use `trackGated` + `registerGate`.

## Requirements

- Android `minSdk` 21+, iOS deployment target 14.1+.
- Kotlin 1.9+ recommended.

## Common mistakes

- ❌ Calling `Amply(config = cfg)` from `commonMain` — won't compile because Android's constructor requires `application`. Wrap construction in `expect/actual`.
- ❌ Building an `Amply` per UI render — the instance must persist for the process lifetime.
- ❌ Forgetting to ship the XCFramework for the matching version when releasing the KMP library.
