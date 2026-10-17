# SDK cheatsheet — iOS / Swift

Package: `AmplySDK` — distributed as a binary XCFramework via Swift Package Manager or CocoaPods.

The iOS SDK is constructed instance-style — `Amply(config:)` — and the host app holds a strong reference. Note that even though the public API is instance-style, the SDK keeps **process-global** state (Keychain entries, local database, network client). Treating it as a de-facto singleton is the right mental model — do not construct two `Amply` instances concurrently.

## Install — Swift Package Manager

In Xcode → File → Add Packages → enter the public repo URL. In `Package.swift`:

```swift
.package(url: "https://github.com/amply-tools/amply-sdk-ios.git", from: "0.15.0"),
```

Then add `AmplySDK` to the target's `dependencies`.

## Install — CocoaPods

```ruby
pod 'AmplySDK', '~> 0.15.0'
```

Then `pod install`.

**Pin `0.15.0` or later** (both managers; Mini-app campaigns need 0.12.0, template variables in campaign links 0.13.0, Test on device (`handleUrl`), Show after and `getLastCampaignTouch` 0.15.0; the pod declares iOS 15.0 since 0.13.0). Listener registration changed shape in 0.9.0 — see *Withdrawing a listener* below; the examples here are written against it and will not compile on 0.8.x. (Event-history audience targeting needs 0.6.1+, which 0.12.0 satisfies.)

## Upgrading the SDK version — resolve, verify, rebuild, re-ship

Changing the pinned version (in `Package.swift`, the Xcode package UI, or `Package.resolved`) is **not** enough on its own. `AmplySDK` is a **binary `.xcframework` target**, so SwiftPM keeps linking a previously-resolved checkout/artifact from the DerivedData `SourcePackages` cache until you force a re-resolve. A naive rebuild then silently links the **old** binary — and the version pin will *look* correct in `Package.resolved` the whole time.

After any version change, do all four — and run them yourself; do **not** defer the resolve to the human's "Resolve Package Versions" click:

1. **Force a clean resolve** (CLI, not the Xcode UI):
   ```bash
   xcodebuild -resolvePackageDependencies -project <App>.xcodeproj -scheme <Scheme>
   ```
   If the checkout doesn't move to the target version (binary-target cache staleness), clear the cache and resolve again:
   ```bash
   rm -rf <DerivedData>/SourcePackages    # e.g. ~/Library/Developer/Xcode/DerivedData/<App>-*/SourcePackages
   xcodebuild -resolvePackageDependencies -project <App>.xcodeproj -scheme <Scheme>
   ```
2. **Verify the resolved version** — the SPM twin of the CocoaPods `Podfile.lock` check. Both the pin **and** the on-disk checkout must read the target version:
   ```bash
   grep -A3 amply-sdk-ios <App>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved   # → "version" : "<X>"
   git -C <DerivedData>/SourcePackages/checkouts/amply-sdk-ios describe --tags                        # → <X>
   ```
3. **Rebuild** — and, for a shipped app, **re-archive + re-upload**. A pin edit that never produced a new build means users still run the old SDK: "edited `Package.resolved`" ≠ "shipped the new SDK".
4. **Confirm at runtime which SDK actually ran.** Launch the build and check that the device's session reports the expected `sdkVersionNormalized` (visible in the Amply admin / session payload). This is the decisive check — it catches a stale binary that steps 1–3 can all miss. Note: SDK **≤ 0.5.0 hard-coded `sdkVersionNormalized` to `1.0.0`**, so this assertion only becomes meaningful once the build is ≥ 0.5.1 (build-time version); below that, rely on the `git describe` check in step 2.

**CocoaPods variant.** `pod install` alone will **not** move you within an allowed range — it honours the existing `Podfile.lock`. To upgrade: bump the `Podfile` constraint if needed, then `pod update AmplySDK` (if it doesn't move, clear a stale cached pod with `pod cache clean AmplySDK` first). Verify `AmplySDK (<X>)` in `Podfile.lock`, then rebuild and run the same runtime `sdkVersionNormalized` check (step 4).

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
    // Counter — fallback only for fleets below Amply SDK 0.6.1; on 0.6.1+ target the Purchase event count directly.
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
let deepLinkToken = amply.registerDeepLinkListener(listener: router)
self.deeplinkRouter = router  // strong ref required
```

## System events

```swift
final class SystemListener: SystemEventsListener {
    func onEvent(event: EventInterface) { /* event.name, event.properties */ }
}
let systemEventsToken = amply.setSystemEventsListener(listener: systemListener)
```

## Withdrawing a listener (SDK 0.9.0+)

Every registration returns a `ListenerToken`. **Keep it** — it is the only thing that withdraws
that registration:

```swift
let token = amply.registerDeepLinkListener(listener: router)
// later, when whatever owns `router` goes away:
amply.removeDeepLinkListener(token: token)
```

Withdrawal takes the **token**, never the listener object. Passing a token that is no longer the
installed one is a no-op — so a screen being torn down cannot silence the one that replaced it.

**Who needs to care.** An `AppDelegate`-scoped listener that lives for the whole process never has
to withdraw. Anything shorter-lived does. A listener left installed after its owner is gone keeps
that owner reachable for the life of the process, and the SDK keeps calling it.

**Withdraw where teardown actually runs.** For an object the SDK holds, `deinit` is the wrong place
— it will not run while the SDK still has the reference. Withdraw from the explicit teardown hook
your host gives you (a React Native TurboModule uses `-invalidate`).

**Release is not immediate.** After you withdraw, the SDK drops its reference, but the object is
reclaimed on a later garbage-collection cycle rather than at that instant (~10 s observed). Do not
write a test that asserts prompt deallocation.

**Gates too.** `registerGate` returns a token and `unregisterGate(token:)` withdraws it. A gate left
behind by a screen that is gone parks the next gated call on that URL for the whole fail-open
timeout, with nothing on screen.

## Public surface (API table)

| Method | Signature |
|---|---|
| Construct | `Amply(config: AmplyConfig)` — returns instance |
| `track` | `func track(event: String, properties: [String: Any])` |
| `setUserId` | `func setUserId(userId: String?)` — the `userId:` label is required (Kotlin `fun setUserId(userId: String?)` imports unchanged) |
| `setAppLanguage` | `func setAppLanguage(tag: String?)` — SDK 0.14.0+; the `tag:` label is required. The language the app shows, any form (`pt-BR`, `pt_BR`, `zh-Hant`); `nil` = automatic. Config: `AmplyConfig.appLanguage`. |
| `setCustomProperty` | `func setCustomProperty(key: String, value: Any)` |
| `setCustomProperties` | `func setCustomProperties(properties: [String: Any])` |
| `getCustomProperty` | `func getCustomProperty(key: String) async -> Any?` |
| `removeCustomProperty` | `func removeCustomProperty(key: String)` |
| `clearCustomProperties` | `func clearCustomProperties()` |
| `trackGated` | `func trackGated(event: String, properties: [String: Any]) async -> GateDecision` — waits for campaign resolution; returns `.proceed(reason:)` or `.cancelled`. |
| `registerGate` | `func registerGate(baseUrl: String, presenter: CampaignPresenter, onAbort: AbortPolicy, timeoutMs: Int64) -> ListenerToken` — call once at startup. |
| `unregisterGate` | `func unregisterGate(token: ListenerToken)` |
| `registerDeepLinkListener` | `func registerDeepLinkListener(listener: DeepLinkListener) -> ListenerToken` |
| `removeDeepLinkListener` | `func removeDeepLinkListener(token: ListenerToken)` — takes the **token**, not the listener. |
| `handleUrl` | `func handleUrl(url: String) -> Bool` — SDK 0.15.0+. Forward every URL the app is opened with, before your own routing; `true` = an Amply test link (Test on device), don't route it. See `deeplink-wiring.md` → *Forwarding incoming links*. |
| `setSystemEventsListener` | `func setSystemEventsListener(listener: SystemEventsListener) -> ListenerToken` |
| `clearSystemEventsListener` | `func clearSystemEventsListener(token: ListenerToken)` — one listener per SDK: a second `set` replaces the first, so extend the existing one. |
| `getLastCampaignTouch` | `func getLastCampaignTouch(withinMs: Int64) async throws -> CampaignTouch?` — SDK 0.15.0+. Campaign last shown / completed within the window (≤ 30 d): `campaignId`, `campaignName`, `kind` (`.shown` / `.engaged`), `atMs`. See `campaign-attribution.md`. |
| `setLogListener` | `func setLogListener(listener: LogListener) -> ListenerToken` — no longer accepts `nil`. |
| `clearLogListener` | `func clearLogListener(token: ListenerToken)` |
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

## Requirements

- iOS 15.0+ for the CocoaPods spec from 0.13.0 (current Xcode builds nothing older); Swift Package Manager still declares iOS 14.
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

Refresh device properties after the user grants ATT permission so the cached values match the new state. The SDK exposes a `refreshProperties()` (or equivalent) on its device dataset — see the published iOS sample apps.
