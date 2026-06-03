# SDK cheatsheet — iOS / Swift

Package: `AmplySDK` — distributed as a binary XCFramework via Swift Package Manager or CocoaPods.

The iOS SDK is constructed instance-style — `Amply(config:)` — and the host app holds a strong reference. Note that even though the public API is instance-style, the SDK keeps **process-global** state (Keychain entries, local database, network client). Treating it as a de-facto singleton is the right mental model — do not construct two `Amply` instances concurrently.

## Install — Swift Package Manager

In Xcode → File → Add Packages → enter the public repo URL. In `Package.swift`:

```swift
.package(url: "https://github.com/amply-tools/amply-sdk-ios.git", from: "0.1.0"),
```

Then add `AmplySDK` to the target's `dependencies`.

## Install — CocoaPods

```ruby
pod 'AmplySDK', '~> 0.1'
```

Then `pod install`.

## Initialize — `AppDelegate` (UIKit) or `@main App` (SwiftUI)

`AmplyConfig` from Swift takes **six positional parameters**. The last three accept `nil` but you must pass them — Kotlin's default values do not propagate through the XCFramework's Swift import.

```swift
import AmplySDK

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var amply: Amply!  // strong reference — keeps the SDK alive

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let appId = Bundle.main.object(forInfoDictionaryKey: "AmplyAppId") as! String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeyPublic") as! String
        let secretKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeySecret") as! String

        let config = AmplyConfig(
            appId: appId,
            apiKeyPublic: publicKey,
            apiKeySecret: secretKey,
            defaultConfig: nil,
            configBaseUrl: nil,   // override for dev/staging
            backendBaseUrl: nil   // override for dev/staging
        )
        amply = Amply(config: config)
        return true
    }
}
```

For SwiftUI on **iOS 17+ / Xcode 15+** — use `@Observable` + `@State` (not `@StateObject`/`ObservableObject`):

```swift
import SwiftUI
import AmplySDK

@main
struct MyApp: App {
    @State private var amplyHolder = AmplyHolder()
    var body: some Scene {
        WindowGroup { ContentView().environment(amplyHolder) }
    }
}

@Observable
final class AmplyHolder {
    let amply: Amply
    init() {
        let appId = Bundle.main.object(forInfoDictionaryKey: "AmplyAppId") as! String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeyPublic") as! String
        let secretKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeySecret") as! String
        amply = Amply(config: AmplyConfig(
            appId: appId,
            apiKeyPublic: publicKey,
            apiKeySecret: secretKey,
            defaultConfig: nil,
            configBaseUrl: nil,
            backendBaseUrl: nil
        ))
    }
}
```

For iOS 16 and older targets, fall back to `@StateObject private var amplyHolder = AmplyHolder()` + `final class AmplyHolder: ObservableObject`.

There is no `AmplySDK.shared` and no `AmplySDK.initialize(...)` — those are common mis-recollections.

## Key handling — where to put the three values

> **`apiKeySecret` is a client-embedded secret. Anything that ends up in the `.ipa` is extractable** (`strings myapp.app/Info.plist`, class-dump, etc.). Choose the tier that matches what you're protecting:

| Tier | When to use | Recipe |
|---|---|---|
| **Dev / staging only** | local builds, internal TestFlight builds with throwaway keys | `xcconfig`-driven `Info.plist` keys (`AmplyAppId`, `AmplyKeyPublic`, `AmplyKeySecret`). Add `Amply.xcconfig` to `.gitignore` and check in `Amply.xcconfig.template`. Acceptable because the keys are not the prod ones. |
| **Production with CI** | App Store / Enterprise builds | Inject the prod `apiKeySecret` at archive time from CI secrets — write `Amply.xcconfig` (or run a build phase script that patches `Info.plist`) just before `xcodebuild archive`. The repo never sees the prod value. Still extractable from the `.ipa`. |
| **Production, high-security** | regulated apps, fintech, healthcare | If your threat model requires `apiKeySecret` to not exist on-device at all, the integration cannot proceed without SDK + Amply-backend support that does not currently ship as a documented public API. Open a conversation with your security team and Amply support before designing around this — do not ship a workaround that *looks* like a session-exchange while still embedding the secret. |

**Default for autopilot:** dev/staging tier (xcconfig-driven `Info.plist`) with a `TODO(amply): rotate via CI before App Store submission` line in `AmplyKeys.swift`. Surface the tier choice in the audit report so the team can opt up.

### Modern Xcode 14+ projects (`GENERATE_INFOPLIST_FILE = YES`)

New SwiftUI templates ship without a static `Info.plist`. Two paths:

1. **Stay generated, use `INFOPLIST_KEY_*` build settings** — works for `AmplyAppId` / `AmplyKeyPublic`:
   ```
   INFOPLIST_KEY_AmplyAppId = $(AMPLY_APP_ID)
   INFOPLIST_KEY_AmplyKeyPublic = $(AMPLY_KEY_PUBLIC)
   ```
   `apiKeySecret` does **not** get an `INFOPLIST_KEY_*` because the value would land in the pbxproj. Use path 2 for the secret.
2. **Partial Info.plist + `INFOPLIST_FILE`** — set `GENERATE_INFOPLIST_FILE = NO`, drop an `Info.plist` containing the three Amply keys + any other custom keys (URL types, etc.). On Xcode 16 with synced root groups, place `Info.plist` **outside** the synced source folder (e.g. project-root level) to avoid "Multiple commands produce Info.plist" — the synced group will otherwise also pick it up as a resource. Also set `INFOPLIST_PREPROCESS = YES` + `INFOPLIST_EXPAND_BUILD_SETTINGS = YES` so `$(PRODUCT_BUNDLE_IDENTIFIER)` and friends substitute.

## URL-scheme registration for Amply Deeplink campaigns

Phase 6's `DeepLinkListener` is invoked by Amply's campaign engine — but for **local development** you'll also want `xcrun simctl openurl` to deliver the URL to the app. That requires the scheme to be registered as `CFBundleURLTypes`. There is no flat `INFOPLIST_KEY_*` for `CFBundleURLTypes` (the value is an array of dicts), so projects with `GENERATE_INFOPLIST_FILE = YES` must go through path 2 above (partial Info.plist):

```xml
<!-- partial Info.plist (path 2 above) -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>yourappscheme</string>
    </array>
  </dict>
</array>
```

**Important:** `simctl openurl yourappscheme://...` exercises **SwiftUI's `onOpenURL`**, not Amply's `DeepLinkListener`. The Amply listener fires only when the SDK's campaign engine receives a `Deeplink` action from a configured campaign. Phase 6 should test both:

- **6a — scheme smoke:** `simctl openurl` lands the URL in `onOpenURL` (verifies registration).
- **6b — campaign smoke:** trigger an Amply campaign whose action is `Deeplink: yourappscheme://...` and confirm `DeepLinkListener.onDeepLink` is called (verifies the listener is wired and held).

## Track events

```swift
amply.track(event: "PaywallShown", properties: ["screen": "home", "source": "cta_banner"])
```

The `event:` argument label is required. Properties dictionary is `[String: Any]`.

## Identify users

```swift
amply.setUserId(userId: "user-123")  // login — note required label
amply.setUserId(userId: nil)         // logout — also call clearCustomProperties()
```

## Custom Properties

Allowed value types: `String`, `Int`, `Long` (use `Int64` from Swift), `Float`, `Double`, `Bool`, `DateTimeValue`. The admin panel surfaces these as **String / Number / Boolean / DateTime**.

```swift
amply.setCustomProperties(properties: [
    "subscription_status": "trial",
    "total_purchases": 0,
    "notifications_enabled": true,
])
amply.setCustomProperty(key: "locale", value: "en-US")

// Async retrieval / clear
let value = await amply.getCustomProperty(key: "subscription_status")
amply.removeCustomProperty(key: "locale")
amply.clearCustomProperties()  // call on logout
```

## Deeplink listener

Conform to the KMP-exported `DeepLinkListener` protocol — `func onDeepLink(url: String, info: [String: Any]) -> Bool`. Return `true` when handled, `false` to let other listeners try.

```swift
import AmplySDK

final class AmplyDeeplinkRouter: NSObject, DeepLinkListener {
    private weak var navigator: AppNavigator?
    init(navigator: AppNavigator) {
        self.navigator = navigator
        super.init()
    }

    func onDeepLink(url: String, info: [String: Any]) -> Bool {
        guard url.starts(with: "amply://") else { return false }
        navigator?.handleAmplyDeeplink(url: url, info: info)
        return true
    }
}

// Wire up — keep a strong reference!
let router = AmplyDeeplinkRouter(navigator: appNavigator)
amply.registerDeepLinkListener(listener: router)
self.deeplinkRouter = router  // strong ref required
```

## System events

```swift
final class SystemListener: SystemEventsListener {
    func onSystemEvent(/* SDK-defined params */) { /* ... */ }
}
amply.setSystemEventsListener(listener: systemListener)
```

## Public surface (API table)

| Method | Signature |
|---|---|
| Construct | `Amply(config: AmplyConfig)` — returns instance |
| `track` | `func track(event: String, properties: [String: Any])` |
| `setUserId` | `func setUserId(userId: String?)` — the `userId:` label is required (Kotlin `fun setUserId(userId: String?)` imports unchanged) |
| `setCustomProperty` | `func setCustomProperty(key: String, value: Any)` |
| `setCustomProperties` | `func setCustomProperties(properties: [String: Any])` |
| `getCustomProperty` | `func getCustomProperty(key: String) async -> Any?` |
| `removeCustomProperty` | `func removeCustomProperty(key: String)` |
| `clearCustomProperties` | `func clearCustomProperties()` |
| `trackGated` | `func trackGated(event: String, properties: [String: Any]) async -> GateDecision` — waits for campaign resolution; returns `.proceed(reason:)` or `.cancelled`. |
| `registerGate` | `func registerGate(baseUrl: String, presenter: CampaignPresenter, onAbort: AbortPolicy, timeoutMs: Int64)` — call once at startup. |
| `registerDeepLinkListener` | `func registerDeepLinkListener(listener: DeepLinkListener)` |
| `setSystemEventsListener` | `func setSystemEventsListener(listener: SystemEventsListener)` |
| `setLogLevel` | `func setLogLevel(level: String)` |

## Gate API (SDK 0.5.0+)

`GateDecision` is a sealed class with two nested types: `GateDecision.Proceed(reason: ProceedReason)` and `GateDecision.Cancelled`. Match with `if case .proceed`/`decision is GateDecision.Cancelled`.

`ProceedReason`: `.completed` / `.failopen` (lowercase).

`CampaignPresenter` protocol:

```swift
protocol CampaignPresenter {
    func present(params: [String: String], info: [String: Any], resolution: CampaignResolution)
    func dismiss()
}
// CampaignResolution.resolve(result:) where CampaignResult is .completed / .dismissed / .unavailable
```

`AbortPolicy`: `.cancel` (default — gate returns `.cancelled` on timeout/abort) / `.proceed` (gate returns `.proceed(reason: .failopen)`).

### Gate example

```swift
// At startup — register presenter once
amply.registerGate(
    baseUrl: "https://campaigns.example.com",
    presenter: MyCampaignPresenter(),
    onAbort: .cancel,
    timeoutMs: 60_000
)

// At a gate-able moment (e.g. before Save)
let decision = await amply.trackGated(event: "SaveTapped", properties: ["screen": "editor"])
if case .proceed = decision {
    performSave()
} else {
    // decision is GateDecision.Cancelled — user dismissed or timed out
    showCancelledFeedback()
}
```

> **SDK 0.5.0 breaking change:** `trackEvent(..., onProceed:, onCancel:)` and `registerCampaignPresenter` are removed. Use `trackGated` + `registerGate`.

## Requirements

- iOS 14.1+ (KMP samples). Bumping deployment target to 14.1 is the safe minimum.
- Xcode 15+.

## Common mistakes (rewrite on sight)

```swift
// ❌ Calling initialize on a static type.
AmplySDK.initialize(config: cfg)

// ❌ Using a `shared` singleton — there is no SDK-provided one.
AmplySDK.shared.track(...)

// ❌ Calling track without the event: label.
amply.track("PaywallShown", properties: [...])

// ❌ DeepLinkListener with the wrong shape.
func onDeepLink(url: String) { ... }   // missing info, missing Bool return.

// ❌ Letting the listener be deallocated.
amply.registerDeepLinkListener(listener: AmplyDeeplinkRouter(...))
//   no strong ref kept → listener gets released → callbacks never fire.

// ❌ AmplyConfig with only four args — Swift import requires all six.
AmplyConfig(appId: ..., apiKeyPublic: ..., apiKeySecret: ..., defaultConfig: nil)
//   error: missing arguments for 'configBaseUrl' and 'backendBaseUrl'.

// ❌ setUserId without the userId: label.
amply.setUserId("user-123")    // error: missing argument label 'userId:'.
```

## Logging — observe SDK activity

The SDK uses **OSLog**, not stdout. To see `[Amply.Sdk]` lines from the simulator:

```
xcrun simctl spawn booted log stream --predicate 'subsystem CONTAINS "amply"'
```

`print(...)` from your own wrapper code shows up on stdout, but is unrelated. If you want both visible together, stream the simulator's full log and filter on app PID.

## ATT / IDFA

Refresh device properties after the user grants ATT permission so the cached values match the new state. The SDK exposes a `refreshProperties()` (or equivalent) on its device dataset — see the iOS sample apps in `multiplatform-library-template/samples/`.
