# SDK cheatsheet — iOS / Swift

Package: `AmplySDK` — distributed as a binary XCFramework via Swift Package Manager or CocoaPods.

The iOS SDK is **instance-based**, not a singleton. You construct an `Amply` with a config and hold a strong reference for the lifetime of the app.

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
            defaultConfig: nil
            // Optional: configBaseUrl, backendBaseUrl — only set when pointing at dev/staging.
        )
        amply = Amply(config: config)
        return true
    }
}
```

`AmplyConfig` requires `appId`, `apiKeyPublic`, `apiKeySecret`, and `defaultConfig` (pass `nil` if you don't ship one). `apiKeySecret` is a real secret — don't commit it to a public README or sample.

For SwiftUI:

```swift
import SwiftUI
import AmplySDK

@main
struct MyApp: App {
    @StateObject private var amplyHolder = AmplyHolder()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(amplyHolder) }
    }
}

final class AmplyHolder: ObservableObject {
    let amply: Amply
    init() {
        let appId = Bundle.main.object(forInfoDictionaryKey: "AmplyAppId") as! String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeyPublic") as! String
        let secretKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeySecret") as! String
        amply = Amply(config: AmplyConfig(
            appId: appId,
            apiKeyPublic: publicKey,
            apiKeySecret: secretKey,
            defaultConfig: nil
        ))
    }
}
```

Pull keys from `Info.plist` (xcconfig-driven) or a `.xcconfig`-managed env. **Never hard-code in source.**

There is no `AmplySDK.shared` and no `AmplySDK.initialize(...)` — those are common mis-recollections.

## Track events

```swift
amply.track(event: "PaywallShown", properties: ["screen": "home", "source": "cta_banner"])
```

The `event:` argument label is required. Properties dictionary is `[String: Any]`.

## Identify users

```swift
amply.setUserId("user-123")    // login
amply.setUserId(nil)           // logout — also call clearCustomProperties()
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
| `setUserId` | `func setUserId(_ id: String?)` |
| `setCustomProperty` | `func setCustomProperty(key: String, value: Any)` |
| `setCustomProperties` | `func setCustomProperties(properties: [String: Any])` |
| `getCustomProperty` | `func getCustomProperty(key: String) async -> Any?` |
| `removeCustomProperty` | `func removeCustomProperty(key: String)` |
| `clearCustomProperties` | `func clearCustomProperties()` |
| `registerDeepLinkListener` | `func registerDeepLinkListener(listener: DeepLinkListener)` |
| `setSystemEventsListener` | `func setSystemEventsListener(listener: SystemEventsListener)` |
| `setLogLevel` | `func setLogLevel(level: String)` |

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
```

## ATT / IDFA

Refresh device properties after the user grants ATT permission so the cached values match the new state. The SDK exposes a `refreshProperties()` (or equivalent) on its device dataset — see the iOS sample apps in `multiplatform-library-template/samples/`.
