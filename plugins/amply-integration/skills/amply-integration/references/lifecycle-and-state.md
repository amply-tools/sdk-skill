# Lifecycle & state

Three rules cut across all platforms:

1. **The Amply instance must outlive the activity / view it was created in.** Process lifetime, not screen lifetime.
2. **Listeners are not retained by the SDK.** Strong reference belongs to the registering object.
3. **Initialise Amply before the first `track` / `setCustomProperties`** — calls before init are dropped.

## RN / Expo

The RN module is global / static-style. No object retention required. Two things to watch:

- **Hot reloading** can register the deeplink listener twice — capture the `unsubscribe` and call it on cleanup.
- The `await Amply.initialize(...)` promise must resolve before any `track` call. In Bare RN, do this in `App.tsx`'s `useEffect` and gate the rest of the tree with a "ready" boolean.

```ts
const [amplyReady, setAmplyReady] = useState(false);

useEffect(() => {
  (async () => {
    await Amply.initialize({ appId, apiKeyPublic, debug: __DEV__ });
    setAmplyReady(true);
  })();
}, []);

if (!amplyReady) return <Splash />;
return <RootNavigator />;
```

## iOS / Swift

The `Amply` instance is held by the `AppDelegate` (UIKit) or by an `ObservableObject` in the SwiftUI app:

```swift
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var amply: Amply!  // strong ref
    var deeplinkListener: AmplyListener!  // strong ref — listener is NOT retained by SDK
}
```

Construct from `application(_:didFinishLaunchingWithOptions:)`. Avoid constructing inside a `lazy var` whose first access is deep in the UI — initialisation latency stalls the first event.

For `@main App`:

```swift
@main
struct MyApp: App {
    @StateObject private var amplyHolder = AmplyHolder()
    init() {
        let listener = AmplyListener(...)
        amplyHolder.amply.registerDeepLinkListener(listener: listener)
        amplyHolder.deeplinkListener = listener  // strong ref
    }
}
```

ATT permission flow: refresh device properties on the SDK after the user grants permission so cached IDFA values become available to the next config fetch.

## Android / Kotlin

`Amply` lives on the `Application` subclass:

```kotlin
class MyApp : Application() {
    lateinit var amply: Amply
    override fun onCreate() {
        super.onCreate()
        amply = Amply(config = ..., application = this)
    }
}
```

The deeplink listener is held on the activity / single-activity host. **Do not** unregister inside `onPause` and re-register in `onResume` — the SDK only allows one registration per listener type and double-registration semantics aren't documented. Register once in `onCreate`, drop in `onDestroy` (or just rely on Application lifetime if you have a single-activity app).

```kotlin
class MainActivity : ComponentActivity() {
    private val listener = object : DeepLinkListener { ... }
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        (application as MyApp).amply.registerDeepLinkListener(listener)
    }
}
```

## KMP

The instance is constructed via `expect/actual` (see `sdk-cheatsheet-kmp.md`). On each platform, the same lifetime rule applies: hold strong references to both the `Amply` and the `DeepLinkListener` from the platform shell.

## Init ordering

If your codebase has bootstrap order issues (Amply needs to be ready before the first navigation event but is initialised inside a `useEffect` / coroutine), buffer early calls in the wrapper:

```ts
let buffered: Array<() => void> = [];
let ready = false;
export async function track(...args) {
  if (!ready) {
    buffered.push(() => doTrack(...args));
    return;
  }
  return doTrack(...args);
}
function flush() {
  ready = true;
  for (const fn of buffered) fn();
  buffered = [];
}
```

Call `flush()` after `await Amply.initialize(...)` resolves.

## What to capture in `amply-audit.md`

```
Amply instance held by:    <AppDelegate / Application / SwiftUI ObservableObject / KMP shared singleton>
Deeplink listener held by: <same>
Init point:                <file:line>
First-event ordering:      <safe / buffered / TODO>
Logout reset hook:         <file:line / TODO>
```
