# Amplitude plugin

For an app that tracks with Amplitude, Amply can read what the app already sends there, with one line and no wrapper:

```ts
import { amplyPlugin } from '@amplytools/react-native-amply-sdk/amplitude';

amplitude.add(amplyPlugin());
```

The import path matters: the plugin has its own entry point, it is not exported from the package root, so an app that does not import it carries none of its code.

The plugin is a destination plugin of Amplitude. Every event the app tracks still goes to Amplitude unchanged; a copy reaches Amply on the device, in time to start a campaign and to build event history for audiences. The direction is one way: Amplitude to Amply.

The skill carries one silent variable for this, `eventPathway`: `plugin` or `wrapper`. It is set in Phase 2 by the checklist below and read by Phases 3 and 5.

## Where it is available

| Detected | Plugin? | Needs |
|---|---|---|
| `@amplitude/analytics-react-native` | **yes** | `>= 1.5.16`, and `@amplytools/react-native-amply-sdk` **`>= 0.17.0`** |
| `@amplitude/react-native` (the old package) | no | `wrapper` |
| `amplitude-ios` | no | `wrapper` |
| `com.amplitude:android-sdk` | no | `wrapper` |
| `AmplitudeSwift`, `com.amplitude:analytics-android` (native, current SDKs) | **not yet** | `wrapper`. There is no native Android or iOS adapter yet. Do not offer one and do not describe it as coming on a date. |

So today the plugin exists for React Native and Expo only. A native Swift, Kotlin or KMP app stays on the wrapper, whatever Amplitude version it runs.

If the app is on `@amplitude/analytics-react-native` below 1.5.16, or on an Amply SDK below 0.17.0, say so and offer the upgrade; until it is done the pathway is `wrapper`.

## Choosing the pathway

`eventPathway = plugin` only when **every** row holds. Otherwise `wrapper`, and the failing row is the reason written into the audit.

| Condition | How to check |
|---|---|
| Versions fit (table above) | `package.json`, lock file. For a project with no Amply installed yet, judge the version the skill will install (the cheatsheet pin, 0.17.0 or later), not the absence of one |
| One Amplitude instance | no `createInstance(...)`, or it is clear which one is the main one |
| The plugin can be added before the first meaningful event | `amplitude.add(...)` fits next to `amplitude.init(...)` |
| Amplitude is the main path of events | most tracking calls go through it |
| Gated calls will not double | `trackGated` calls Amply directly and is not replaced by the plugin. If the same moment is also sent to Amplitude, exclude it in `filter`; if it is not sent to Amplitude, no filter is needed |
| Frequent events are named | loops, scroll, timers, polling: out through `filter` |
| `userId` policy is chosen | the app already calls `Amply.setUserId` with its own id, or rewrites `user_id` in its own Amplitude plugin: `syncUserId: false`. Also read the app's logout path: if it does not clear Amplitude's user (no `amplitude.reset()`, no `setUserId(undefined)`), the plugin never sees a logout, so `syncUserId: false` and the app keeps its `Amply.setUserId`. Do **not** add `reset()` to fix it: it rotates Amplitude's device id, which attribution tools read |
| No Amplitude enrichment plugin of the app's own that is async | the app has none, or `syncUserId: false` (see *Audit notes*) |
| Nothing already mirrors `track` to Amply | first find every import of the Amply package (`@amplytools/react-native-amply-sdk`, default or named, e.g. `import { track } from '...'`) and the local names it brings in, then grep the calls of those names (`Amply.track`, `amply.track`, a bare `track(...)`, `trackEvent`, `trackGated`), including inside a sink or wrapper file. A plain `Amply.track` / `amply.track` of a moment Amplitude also carries is a mirror; a `trackGated` call is not. Third-party `trackEvent` calls (e.g. `Adjust.trackEvent()`) do not count, only calls on the Amply SDK do. A mirror means `eventPathway = wrapper`, plus an Observation naming the `file:line` hits. See *An app that already sends to Amply* |

## New integration

Under `plugin` there is no plain `Amply.track` for anything Amplitude carries, in new code or in an existing wrapper (`wrapperStrategy = extend` still applies to the rest of the wrapper). An event Amplitude does not carry either goes through Amplitude first, or stays a direct Amply call if the audit decides so. Initialise Amply as in the cheatsheet (`await Amply.initialize(...)`), then add the plugin beside `amplitude.init`:

```ts
amplitude.add(amplyPlugin({ filter, transform, userProperties }));
```

The line does not have to wait for `Amply.initialize`: events, id changes and copied user properties wait, in order, up to 100 items, until Amply starts. So no existing synchronous function has to become async for the plugin.

If more than 100 items pile up before Amply starts, the oldest events are dropped first. Adding the plugin twice does nothing the second time.

The plugin replaces only event forwarding. The user id on logout, Custom Properties and gated calls stay in the wrapper (below), so an existing wrapper is trimmed, not deleted. If a new integration has nothing of that kind, no wrapper is written.

## An app that already sends to Amply

A plugin and a mirrored `track` at the same time double every event. So:

- **`autopilot`: do not switch.** `eventPathway = wrapper`; the plugin goes into audit § 9 as an Observation. The app may have live campaigns on the names it sends today, and an automatic switch cannot see them.
- **`interactive`: offer the replacement**, removing the mirroring in the same change, and show the names that would change before touching anything.

**Before switching, compare what the old wrapper cut.** A property key the wrapper shortened (say to 32 characters) now arrives whole, up to 100, so a campaign targeting the cut name stops matching. List every key over 32 characters (or over whatever the wrapper cut to) and the campaigns that use the old name before the switch.

**Dead helpers.** `pascalCaseEventName` splits on the common `[\s_\-.]+`, so an app's own PascalCase helper may become unused after the switch; check and report it, do not delete it unasked.

The plugin passes names as Amplitude has them, with no PascalCase. An app whose Amply events are PascalCase keeps those names with a `transform`:

```ts
import { amplyPlugin, pascalCaseEventName } from '@amplytools/react-native-amply-sdk/amplitude';

amplitude.add(
  amplyPlugin({
    transform: (e) => ({ name: pascalCaseEventName(e.event_type) }),
  }),
);
```

Write it as the arrow function. `transform: pascalCaseEventName` is wrong: `transform` receives the whole event, not the name.

## Audit decision to plugin option

The decisions of Phase 3 become the plugin's options:

| Audit decision | Option |
|---|---|
| `skip-*` (system overlap, BI-only, `skip-frequent`) | `filter: (e) => !SKIPPED.has(e.event_type)` |
| A `trackGated` moment that the app also sends to Amplitude | the same `filter`; a gated moment Amplitude never sees needs no entry |
| `skip-pii` for a property outside the built-in PII list | `transform` that returns `properties` without it. The plugin blocks exactly `email`, `phone`, `address`, `ip`, `full_name`, `firstname`, `lastname`, in any letter case; `first_name`, `last_name`, `phone_number` and the like pass. The audit lists every such key found in event properties, and each is dropped in `transform` |
| A user property used for targeting | `userProperties: ['plan', 'subscription_status']` (a list of keys, or a function; there is no "all") |
| A screen view is wanted | `autocapture: ['[Amplitude] Screen Viewed']`. The `[Amplitude] ` prefix is stripped from the name and from property keys **before** `filter` and `transform` run: the event reaches Amply as `Screen Viewed` with key `Screen Name`, and that is the name for campaign triggers and for `filter` / `transform` |
| The app forwards Amply system events into its analytics (`campaign-attribution.md`) | exclude the forwarded names in `filter`, e.g. `filter: (e) => !e.event_type.startsWith('Amply')`. Read the names the app really forwards; do not assume the prefix |
| The app manages the user id itself | `syncUserId: false`, and the app keeps calling `Amply.setUserId` |
| A name must stay PascalCase | `transform` with `pascalCaseEventName` (above) |
| Debugging a gap | `debug: true` (logs what is skipped and why) |

What the plugin already does, so the audit does not repeat it as a decision: `session_start`, `session_end`, `$identify` and `$groupidentify` never become Amply events; Amplitude's automatic events (names that start with `[Amplitude] `) are off unless listed in `autocapture`; Amply's own system event names are refused; PII keys (`email`, `phone`, `address`, `ip`, `full_name`, `firstname`, `lastname`), `null`, objects and non-finite numbers are dropped from properties; a limit of 60 events a minute per name and 300 in total stops loops. An opted-out Amplitude user sends nothing.

`filter` and `transform` get a copy of the event; changing it does not change what Amplitude sends. If either throws, that event is dropped from Amply and Amplitude is not affected.

User properties are not copied by default. With `userProperties`, only `$set` and `$unset` of the listed keys are applied; a value must be a string up to 255 characters, a finite number or a boolean, and the key up to 32 characters.

## What the plugin does not replace

Keep these in the wrapper (or in the app), and take the mirrored `track` out of it:

- `trackGated` and `registerGate`.
- The deeplink listener and `handleUrl` forwarding.
- Custom Properties that do not come from Amplitude user properties (RevenueCat state, locale, install date).
- Forwarding Amply system events to the app's analytics (`campaign-attribution.md`). **This must be excluded in `filter`:** a name such as `AmplyCampaignShown` tracked into Amplitude would come straight back into Amply as an ordinary custom event (it is not a reserved name). Open the app's forwarding code, collect the exact names it sends, and write them into `filter` (`!e.event_type.startsWith('Amply')` only if that is really their shape).
- `Amply.setUserId` / `clearCustomProperties`: with the default `syncUserId: true` the plugin follows Amplitude's user id at login, so do **not** add a `setUserId` call there. Logout stays in the app: `amplitude.reset()`, then `Amply.setUserId(null)` and `clearCustomProperties()`, in that order. Amplitude does not signal `reset()` to the plugin, so without the direct call a logout followed by closing the app leaves the old user in Amply. With `syncUserId: false` every `setUserId` stays in the app.

## Audit notes and checks

Write these into the audit as Observations (§ 9) when they apply, with the exact change. `autopilot` does not edit the app's code for them; `interactive` offers the change.

1. **`reset()` or a direct Amply call right after a `track` that matters.** Any direct Amply call right after a `track` overtakes that event by about 10 to 16 ms: `setUserId`, `setCustomProperty`, `clearCustomProperties`. Flag those call sites the same way as `amplitude.reset()`, with the same bounded wait and, in `autopilot`, an Observation. If the app calls `amplitude.reset()` straight after a `track` it cares about (a logout event, a purchase), it must wait for the event first, with a bounded wait, then call `amplitude.reset()`:

   ```ts
   await Promise.race([amplitude.track('Logged Out').promise, new Promise((r) => setTimeout(r, 500))]);
   amplitude.reset();
   ```

   The `.promise` alone never settles offline, so a logout handler that awaits it would hang; the 500 ms cap keeps it moving. Without the wait, Amplitude applies the event on a timer, after the user is already cleared, so the event reaches Amply without a user, looking like an event after logout. The audit flags every such call site with `file:line`. In `autopilot` the audit gets an Observation with the exact change (the bounded wait above at that site) and the skill does not edit the site; in `interactive` it offers the change.
2. **Its own async Amplitude plugin, or a rewritten `user_id`.** If the app has an enrichment plugin of its own that does asynchronous work, or one that rewrites `user_id`, the plugin cannot always tell which user an event belongs to. Pass `syncUserId: false`, keep `Amply.setUserId` calls in the app, and put an audit note saying why.
3. **Logout without the direct call.** If the app's logout path calls `amplitude.reset()` but not `Amply.setUserId(null)`, and the app closes before another event, Amply keeps the old id until the next sign-in. The audit flags that path with `file:line` and the one-line change. Keep the order `amplitude.reset()`, then `Amply.setUserId(null)`: the other way round, an event in between brings the old user back.
4. **Expo Go.** There is no native module in Expo Go: the plugin warns once and then does nothing.
5. **Reading `.promise` as delivery.** `amplitude.track(x).promise` reports the first destination, usually Amply, not delivery to Amplitude. App code that reads it (a success flag, a retry, a "sent" log) must not treat it as delivery to Amplitude; the audit flags such call sites as an Observation.
6. **A frequent event** found in the audit is `skip-frequent` and goes into `filter`, not into a "later" list.

## What to say to the user

Offer it once, in the audit conversation, in the user's language. In English:

> You already track with Amplitude, so you do not need a separate Amply layer. One line, `amplitude.add(amplyPlugin())`, sends what you already track to Amply on the device: campaigns can start on those events and audiences can use their history. Events keep the names they have in Amplitude, nothing changes in what Amplitude receives, and I will exclude `<frequent events>` so Amply is not flooded. This needs `@amplytools/react-native-amply-sdk` 0.17.0 or later; you are on `<version>`. Go ahead?

For an app with its own wrapper add: "Your Amply calls in the wrapper would be removed in the same change, and the event names Amply sees would be `<same | PascalCase kept through a transform>`."

When the pathway is `wrapper`, do not mention the plugin unless the user asks; put the failing row in the audit.

## Verifying

- The Amply admin shows an Amplitude event arriving after one tracked action (Phase 7; this is the human's check, as always).
- A `filter`-ed event is absent from Amply and still present in Amplitude.
- Logout changes the user once, and a cold start without a signed-in user does not call `setUserId`.
- Every `reset()` call site from note 1 has its Observation in the audit (and, if the user accepted the change in `interactive`, the bounded wait); the events before logout carry the user only after that change.
