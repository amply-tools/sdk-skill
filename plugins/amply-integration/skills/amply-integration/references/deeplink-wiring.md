# Deeplink listener wiring per navigation library

The Amply server delivers **Deeplink** actions to your registered listener. The listener decides where to take the user. Three rules:

1. **Match the platform-correct signature** — see SDK cheatsheets.
2. **Hold a strong reference** — the SDK does not retain listeners on iOS / Android.
3. **Return `true` only when handled** — `false` lets other listeners or the OS-level handler try.

## Pattern A — React Navigation, simple single-target

Use when the app has no existing `linking.config` (or the deeplink schemes you'll receive from Amply don't overlap with what's already in `linking.config`).

```ts
// App.tsx
import React, { useEffect, useRef } from 'react';
import Amply from '@amplytools/react-native-amply-sdk';
import { NavigationContainer, createNavigationContainerRef } from '@react-navigation/native';

const navigationRef = createNavigationContainerRef();

export default function App() {
  const unsubscribeRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const unsub = await Amply.addDeepLinkListener((event) => {
        if (cancelled) return;
        const { url } = event;
        if (url.startsWith('amply://promo')) {
          navigationRef.navigate('Promo', { url, info: event.info });
        }
      });
      unsubscribeRef.current = unsub;
    })();
    return () => {
      cancelled = true;
      unsubscribeRef.current?.();
    };
  }, []);

  return <NavigationContainer ref={navigationRef}>{/* ... */}</NavigationContainer>;
}
```

## Pattern A.1 — React Navigation, re-use existing `linking.config`

**Use this when the project already ships a rich `linking.config`** with `prefixes`, `screens` mapping, query parsers, nested navigators — typical for apps where deeplinks have been a first-class feature. Hardcoding `navigationRef.navigate('Promo', ...)` would bypass all that wiring.

**Pre-flight: the `NavigationContainer` must have a ref.** The Amply listener fires from outside React's render tree and needs a stable handle to dispatch nav actions. If the project's `<NavigationContainer>` doesn't already have `ref={navigationRef}`, **add it first** as a tiny, non-invasive prep edit:

```ts
import { createNavigationContainerRef } from '@react-navigation/native';
export const navigationRef = createNavigationContainerRef();

// in the component that renders NavigationContainer:
<NavigationContainer ref={navigationRef} linking={linking} {...rest}>
```

This is one line + one export, doesn't affect any existing screen, and unlocks the deeplink listener below.

The bridge is `getStateFromPath` + `getActionFromState` (`@react-navigation/native` ≥ 7):

```ts
// App.tsx — re-use existing linking config for Amply deeplinks
import Amply from '@amplytools/react-native-amply-sdk';
import {
  NavigationContainer,
  createNavigationContainerRef,
  getStateFromPath,
  getActionFromState,
} from '@react-navigation/native';
import { linking } from './linking'; // project's existing config

const navigationRef = createNavigationContainerRef();

export default function App() {
  useEffect(() => {
    let unsub: (() => void) | undefined;
    (async () => {
      unsub = await Amply.addDeepLinkListener((event) => {
        if (!navigationRef.isReady()) return;

        // Strip scheme prefix so getStateFromPath sees a path that matches `linking.config.screens`.
        const path = stripScheme(event.url, linking.prefixes);
        const state = getStateFromPath(path, linking.config);
        if (!state) return; // unhandled — let the rest of the app deal with it

        const action = getActionFromState(state, linking.config);
        if (action) navigationRef.dispatch(action);
        else navigationRef.resetRoot(state);
      });
    })();
    return () => unsub?.();
  }, []);

  return <NavigationContainer ref={navigationRef} linking={linking}>{/* ... */}</NavigationContainer>;
}

function stripScheme(url: string, prefixes: readonly string[]): string {
  for (const prefix of prefixes) {
    if (url.startsWith(prefix)) return url.slice(prefix.length).replace(/^\/?/, '/');
  }
  // Fallback: strip any scheme like `amply://`.
  return url.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '/');
}
```

Why this matters: every existing deeplink target the app already supports (paywalls, profile sub-screens, dynamic content) becomes a valid Amply campaign target automatically — no per-target wiring.

If the project's `linking.config` types don't expose `prefixes` as a tuple, fall back to the regex `stripScheme`. If `linking.config` is a function (`getStateFromPath` accepts a config object, not a function), call the function first.

## Pattern B — expo-router (RN/Expo)

```ts
// app/_layout.tsx
import { useEffect } from 'react';
import { router } from 'expo-router';
import Amply from '@amplytools/react-native-amply-sdk';

export default function RootLayout() {
  useEffect(() => {
    let unsub: (() => void) | undefined;
    (async () => {
      unsub = await Amply.addDeepLinkListener((event) => {
        if (event.url.startsWith('amply://')) {
          const path = event.url.replace('amply://', '/');
          router.push(path);
        }
      });
    })();
    return () => unsub?.();
  }, []);

  return /* ... */;
}
```

## Pattern C — SwiftUI NavigationStack

`@StateObject` cannot be read from `init`. Wire Amply, the coordinator, and the listener inside a single `ObservableObject` holder; expose it to the view tree via `@StateObject`.

```swift
import SwiftUI
import AmplySDK

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var path: [Route] = []
    let amply: Amply
    private var listener: AmplyListener!

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

        listener = AmplyListener { [weak self] url, info in
            guard let route = Route(amplyURL: url) else { return false }
            self?.path.append(route)
            return true
        }
        amply.registerDeepLinkListener(listener: listener)
    }
}

final class AmplyListener: NSObject, DeepLinkListener {
    private let handle: (String, [String: Any]) -> Bool
    init(_ handle: @escaping (String, [String: Any]) -> Bool) { self.handle = handle }
    func onDeepLink(url: String, info: [String: Any]) -> Bool { handle(url, info) }
}

@main
struct MyApp: App {
    @StateObject private var env = AppEnvironment()
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $env.path) { RootView() }
                .environmentObject(env)
        }
    }
}
```

## Pattern D — UIKit AppDelegate

```swift
import UIKit
import AmplySDK

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var amply: Amply!
    var deeplinkListener: AmplyListener!
    var navigator: AppNavigator!

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let appId = Bundle.main.object(forInfoDictionaryKey: "AmplyAppId") as! String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeyPublic") as! String
        let secretKey = Bundle.main.object(forInfoDictionaryKey: "AmplyKeySecret") as! String
        amply = Amply(config: AmplyConfig(
            appId: appId,
            apiKeyPublic: publicKey,
            apiKeySecret: secretKey,
            defaultConfig: nil
        ))

        navigator = AppNavigator(rootWindow: window)
        deeplinkListener = AmplyListener(navigator: navigator)
        amply.registerDeepLinkListener(listener: deeplinkListener)
        return true
    }
}
```

## Pattern E — Compose Navigation (Android)

```kotlin
// MainActivity.kt
class MainActivity : ComponentActivity() {
    private var navController: NavHostController? = null

    private val deeplinkListener = object : DeepLinkListener {
        override fun onDeepLink(url: String, info: Map<String, Any>): Boolean {
            if (!url.startsWith("amply://")) return false
            runOnUiThread { navController?.navigate(url) }
            return true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val controller = rememberNavController()
            // capture for the listener
            LaunchedEffect(controller) { navController = controller }
            // ... NavHost(navController = controller, ...)
        }
        (application as MyApp).amply.registerDeepLinkListener(deeplinkListener)
    }
}
```

## Pattern F — Jetpack Navigation (XML)

```kotlin
class MainActivity : AppCompatActivity() {
    private lateinit var navController: NavController
    private val listener = object : DeepLinkListener {
        override fun onDeepLink(url: String, info: Map<String, Any>): Boolean {
            return runCatching { navController.navigate(Uri.parse(url)) }.isSuccess
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        navController = findNavController(R.id.nav_host_fragment)
        (application as MyApp).amply.registerDeepLinkListener(listener)
    }
}
```

## Test commands

```bash
# iOS Simulator
xcrun simctl openurl booted "amply://promo/123"

# Android — replace <package> with the application id
adb shell am start -a android.intent.action.VIEW -d "amply://promo/123" <package>
```

The scheme `amply://` is a **convention used in examples**, not a built-in scheme — actual scheme is whatever the integrating app registers. Document the chosen scheme in the audit report and in `Info.plist` (`CFBundleURLTypes`) / `AndroidManifest.xml` (`<intent-filter>`).
