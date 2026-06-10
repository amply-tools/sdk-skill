# SDK cheatsheet — React Native / Expo

Package: `@amplytools/react-native-amply-sdk`

The RN SDK exposes a **module with static-style methods** — different from the instance pattern used on native iOS / Android.

## Install

```bash
yarn add @amplytools/react-native-amply-sdk
# or: npm install @amplytools/react-native-amply-sdk
# or: pnpm add @amplytools/react-native-amply-sdk
```

**Config plugin in `app.json` — only for Expo Prebuild Workflow or Expo Managed projects.** Identify your RN flavour via `references/platform-detection.md` §2 *before* touching `app.json`.

```json
{
  "expo": {
    "plugins": ["@amplytools/react-native-amply-sdk"]
  }
}
```

**Build command — always read the project's `package.json` scripts first.** What follows is the *canonical fallback* per flavour. If the project already has `scripts.ios` / `scripts.android` / `scripts.dev:ios` / a `fastlane` lane / `eas build` setup, **prefer that** even if it doesn't match the canonical command (legacy scripts are common and not always worth rewriting during integration).

**Run the build yourself** (per the SKILL.md *Build & verify yourself* contract): execute it via shell, read the output, and fix-then-rebuild on failure. Don't tell the user to "try building and let me know" — only Xcode-UI-only actions and on-device permission prompts go to the human.

| Flavour | After `yarn add @amplytools/react-native-amply-sdk` | Canonical fallback build |
|---|---|---|
| **A. Pure Bare RN** | Don't touch `app.json`. | `npx react-native run-ios` / `run-android` |
| **B. Bare RN + Expo Modules** | **Do NOT add the plugin to `app.json`** — it would be a no-op (no `prebuild` ever runs in this flavour). **Do NOT run `expo prebuild`** — it would wipe the hand-managed `ios/` and `android/` folders. **Do NOT manually `cd ios && pod install` as a first step** — the run script does it. | `npx expo run:ios` / `run:android` |
| **C. Expo Prebuild Workflow** | Add the plugin entry, then `npx expo prebuild --clean` (regenerates `ios/`/`android/`). | `npx expo run:ios` / `run:android` after `prebuild` |
| **D. Expo Managed** | Add the plugin entry. | `eas build -p ios` / `-p android` |

It is common for a Flavour-B project to have **mixed** scripts — e.g. `yarn ios` calls `react-native run-ios` (legacy from initial RN init) while `yarn android` calls `expo run:android` (added later). Both work for Flavour B; don't normalise them as part of the integration. Use whichever the project ships.

Distinguishing B from C is the most common mistake: check `git ls-files ios/ android/` — if there are hand-edited Swift / Kotlin files, you're in B and `prebuild` is destructive.

## Upgrading the SDK version — JS *and* native, both layers

RN is the easiest place to ship a half-upgrade. Bumping the npm package updates the **JS** layer, but the **native** SDK (iOS Pod / Android Gradle, pinned by this package's podspec / `build.gradle`) only changes when you re-install native. A JS-only bump runs new TypeScript against the **old** native bridge — green `tsc` / `jest`, broken at runtime. After changing the version:

1. **JS layer** — `yarn add @amplytools/react-native-amply-sdk@<X>` (updates `package.json` + lockfile). Upgrading in place: `rm -rf node_modules && yarn install`, and restart Metro with `--reset-cache`.
2. **Native layer — re-install, don't assume:**
   - **Bare / Expo-Modules (A/B):** iOS → `cd ios && pod install` (or `pod update AmplySDK` if the podspec's native pin moved); Android → Gradle sync / `./gradlew :app:dependencies --refresh-dependencies`.
   - **Expo Prebuild (C):** `npx expo prebuild --clean` regenerates `ios/` + `android/` against the new package.
   - **Expo Managed (D):** rebuild via `eas build` so the new native SDK is pulled in the cloud.
3. **Verify both layers** — JS: new version in `yarn.lock` / `node_modules/@amplytools/react-native-amply-sdk/package.json`; iOS native: `AmplySDK (<x>)` in `ios/Podfile.lock`; Android native: `dependencyInsight` shows `tools.amply:sdk-android:<x>` (see `sdk-cheatsheet-android.md`).
4. **Confirm at runtime** — per SKILL.md Phase 7 "Version bumps (any platform)": the session must report the expected `sdkVersionNormalized`. This is what catches a JS / native mismatch the build won't.

## Initialize

`Amply.initialize(...)` is **only correct on the RN/Expo SDK**. iOS and Android native are instance-based — do not use this signature there.

```ts
import Amply from '@amplytools/react-native-amply-sdk';

await Amply.initialize({
  appId: process.env.EXPO_PUBLIC_AMPLY_APP_ID!,
  apiKeyPublic: process.env.EXPO_PUBLIC_AMPLY_KEY!,
  // apiKeySecret: process.env.EXPO_PUBLIC_AMPLY_KEY_SECRET, // optional on RN
  debug: __DEV__,         // optional
  logLevel: 'info',       // optional: 'none' | 'error' | 'warn' | 'info' | 'debug'
});
```

`apiKeySecret` **is accepted** by the RN config (`apiKeySecret?: string | null`) but is **not required** — unlike the native iOS/Android SDKs, where it's mandatory in `AmplyConfig`. Pass it only if your Amply tenant requires it; otherwise leave it off.

Call once, as early as possible — root component mount, `index.ts`, or an effect that runs before any `track`.

## Track events

The RN payload is **an object**, not positional args:

```ts
await Amply.track({
  name: 'PaywallShown',
  properties: { screen: 'home', source: 'cta_banner' },
});
```

## Identify users

```ts
Amply.setUserId('user-123');     // login
Amply.setUserId(null);            // logout — also call clearCustomProperties()
```

## Custom Properties (a.k.a. user attributes)

**Allowed value types: `string | number | boolean` only** (the RN SDK exports `type CustomPropertyValue = string | number | boolean`). No `DateTime` / `Date`, no arrays, no nested objects on the RN public surface — encode timestamps as epoch numbers or ISO strings.

Limits per the RN SDK JSDoc:
- Property **keys**: max 32 characters.
- Property **string values**: max 255 characters.

```ts
Amply.setCustomProperties({
  subscription_status: 'trial',
  total_purchases: 0,
  notifications_enabled: true,
});

// Single property:
Amply.setCustomProperty('locale', 'en-US');

// Read / clear:
const value = await Amply.getCustomProperty('subscription_status');
// value is `string | number | boolean | null` — null when the key is not set.
Amply.removeCustomProperty('locale');
Amply.clearCustomProperties(); // call on logout
```

## Deeplink listener

```ts
const unsubscribe = await Amply.addDeepLinkListener((event) => {
  // event: { url: string; info: Record<string, unknown>; consumed: boolean }
  if (event.url.startsWith('amply://')) {
    navigation.navigate('Promo', { url: event.url, info: event.info });
  }
});

// On teardown:
unsubscribe();
```

Capture `unsubscribe` in component state / a ref so you can call it on unmount.

## System events

```ts
const unsub = await Amply.addSystemEventListener((evt) => {
  console.log('Amply system event:', evt);
});
// `Amply.addSystemEventsListener` and `Amply.systemEvents.addListener` are aliases.
```

## Inspection helpers

The RN SDK exposes a few methods for debugging and audit work:

```ts
const recent = await Amply.getRecentEvents(30);          // newest first; { id, name, type, timestamp, properties }[]
const deviceSnapshot = await Amply.getDataSetSnapshot({ kind: '@device' });
const userSnapshot = await Amply.getDataSetSnapshot({ kind: '@user' });
const sessionSnapshot = await Amply.getDataSetSnapshot({ kind: '@session' });

Amply.removeAllListeners();   // unsubscribe all currently-registered deeplink listeners.
```

The published `DataSetType` union in `@amplytools/react-native-amply-sdk` ≤ 0.2.9 is:

```ts
type DataSetType =
  | { kind: '@device' }
  | { kind: '@user' }
  | { kind: '@session' }
  | { kind: '@triggeredEvent'; data: TriggeredEventData }
  | { kind: '@events'; data: EventsDataSetEvent[] };
```

Notably, **`@custom` is not in the published RN union** even though it exists in the Android / iOS native surface. If you need a snapshot of custom properties for an audit, read them back via `getCustomProperty(key)` per key, or upgrade to a newer RN package version once `@custom` is exposed there. Always verify against the installed package's `node_modules/@amplytools/react-native-amply-sdk/src/nativeSpecs/NativeAmplyModule.ts`.

## Public surface (API table)

| Method | Notes |
|---|---|
| `Amply.initialize(config)` | Async. `{ appId, apiKeyPublic, debug?, logLevel? }`. |
| `Amply.track({ name, properties? })` | **Object payload**. |
| `Amply.setUserId(id \| null)` | |
| `Amply.setCustomProperty(key, value)` / `setCustomProperties(map)` | Values: `string \| number \| boolean`. |
| `Amply.getCustomProperty(key)` | Async. |
| `Amply.removeCustomProperty(key)` / `clearCustomProperties()` | |
| `Amply.trackGated(event, properties?)` | Async. Resolves `{ outcome: 'proceed', reason: 'completed' \| 'failOpen' } \| { outcome: 'cancelled' }`. **Never rejects.** |
| `Amply.registerGate(baseUrl, presenter, options?)` | Async. `options: { onAbort?: 'cancel' \| 'proceed', timeoutMs?: number }`. Returns `Promise<() => void>` (unregister). `presenter: (params, info, resolution) => void`. |
| `Amply.addDeepLinkListener(listener)` | Async; returns `unsubscribe`. |
| `Amply.addSystemEventListener(listener)` / `addSystemEventsListener` / `systemEvents.addListener` | Three aliases for the same async-returns-`unsubscribe` listener. |
| `Amply.removeAllListeners()` | Unsubscribe all registered deeplink listeners. |
| `Amply.getRecentEvents(limit)` | Async; returns recent events newest-first. |
| `Amply.getDataSetSnapshot(type)` | Async; `type` is one of the dataset shapes (`@device`, `@user`, `@custom`, `@session`, `@triggeredEvent`, `@events`). |
| `Amply.setLogLevel(level)` / `getLogLevel()` | `'none' \| 'error' \| 'warn' \| 'info' \| 'debug'` |
| `Amply.isInitialized()` | |

## Gate API (SDK 0.5.0+)

`GateDecision` shape: `{ outcome: 'proceed', reason: 'completed' | 'failOpen' } | { outcome: 'cancelled' }`.

The presenter is a plain callback: `(params: Record<string, string>, info: Record<string, unknown>, resolution: { resolve: (result: 'completed' | 'dismissed' | 'unavailable') => void }) => void`.

### Gate example

```ts
// At startup — after Amply.initialize
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

// At a gate-able moment
const decision = await Amply.trackGated('SaveTapped', { screen: 'editor' });
if (decision.outcome === 'proceed') {
  performSave();
} else {
  showCancelledFeedback();
}
```

> **SDK 0.5.0 breaking change:** `trackEvent(..., onProceed, onCancel)` and `registerCampaignPresenter` are removed. Use `trackGated` + `registerGate`.

## Requirements

- React Native ≥ 0.79, **New Architecture enabled** (Bridgeless / Fabric / TurboModules).
- Expo SDK ≥ 53.
- Android API 24+; **iOS 15.1+** (the bundled `AmplyReactNative.podspec` in `0.2.x` declares `platforms = { :ios => '15.1' }` and depends on the native `AmplySDK ~> 0.2.5`). Older RN-SDK READMEs say iOS 13.0+; the package actually fails `pod install` below 15.1. Verify against the podspec of the version you pin.

## Common mistakes (rewrite on sight)

```ts
// ❌ Positional track arguments — not supported.
Amply.track('PaywallShown', { screen: 'home' });

// ❌ DateTime values on RN.
Amply.setCustomProperty('trial_ends_at', new Date()); // RN does not accept Date here.
//   Workaround: store as ISO string or Unix epoch number.

// ❌ Synchronous initialize — initialize returns a Promise.
Amply.initialize({ ... });   // missing await; tracking calls before it resolves are dropped.

// ❌ Ignoring the unsubscribe — leaks listeners across hot reloads.
await Amply.addDeepLinkListener(...);
```
