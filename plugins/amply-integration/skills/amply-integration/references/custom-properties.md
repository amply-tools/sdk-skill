# Custom Properties catalogue

Custom Properties are user-attached attributes Amply uses for **Who** (targeting). Set them via `setCustomProperty` / `setCustomProperties` on the SDK instance (or the static-style RN module).

## Allowed value types

| SDK | Allowed values | Key length | String value length |
|---|---|---|---|
| Native (iOS, Android, KMP) | `String`, `Int`, `Long`, `Float`, `Double`, `Boolean`, `DateTimeValue` | ≤ 255 chars (Kotlin SDK) | implementation-defined; keep reasonable |
| React Native | `string`, `number`, `boolean` only | ≤ 32 chars (RN JSDoc) | ≤ 255 chars (RN JSDoc) |

Arrays, lists, and nested objects are **not** supported.

The admin panel surfaces these as `String` / `Number` / `Boolean` / `DateTime`.

For cross-platform safety (e.g. an app with a Swift host and a future RN extension), prefer property keys ≤ 32 characters everywhere.

## Array values — three deterministic recipes

It's common for an app to already set array-valued user properties on Amplitude or Mixpanel — `user_interests: string[]`, `user_clusters: string[]`, `feature_flags_active: string[]`, etc. The Amply RN SDK silently rejects array values (the `coerceForRn` helper in `wrapper-patterns.md` drops them with a `__DEV__` warning). Decide **explicitly** which of the three recipes below to apply per key, and document it in the audit:

| Recipe | When to use | Example transformation |
|---|---|---|
| **CSV collapse** (default) | Targeting cares about set membership (`contains 'diving'`). Admin can use `string.contains` in property rules. | `['diving', 'reef']` → `'diving,reef'` |
| **First-value** | Targeting cares about a primary attribute, the rest are noise. | `['diving', 'reef']` → `'diving'` |
| **Drop + counter** | Cardinality matters more than the values themselves. Pair with a Number property. | `['diving', 'reef']` → drop the array; set `user_interests_count: 2` |

Implement in the wrapper, not at call sites. Concrete TS:

```ts
const ARRAY_KEY_STRATEGY: Record<string, 'csv' | 'first' | 'count'> = {
  user_interests: 'csv',
  user_clusters: 'csv',
  user_intents: 'csv',
  // Add more as the audit surfaces them.
};

function applyArrayStrategy(out: Record<string, string | number | boolean>, key: string, arr: unknown[]) {
  const strategy = ARRAY_KEY_STRATEGY[key] ?? 'csv';
  switch (strategy) {
    case 'csv':
      out[key] = arr.filter(v => v != null).map(String).join(',');
      break;
    case 'first':
      if (arr[0] != null) out[key] = String(arr[0]);
      break;
    case 'count':
      out[`${key}_count`] = arr.length;
      break;
  }
}
```

Always list the keys + chosen strategy in `amply-audit.md` so the team can adjust later.

## Recommended baseline catalogue

The skill should propose this set on every integration unless the user opts out. Adapt the **values** to the project; the **keys** are the convention. Exception: rows marked *fallback only* are **not** default proposals — offer them only when the fleet runs Amply SDK < 0.6.1 or the count is derived state (see "Counter properties" below).

| Key | Type | Source | Example |
|---|---|---|---|
| `subscription_status` | String | RevenueCat / Adapty / Superwall / your billing layer | `'free'` / `'trial'` / `'active'` / `'expired'` / `'in_grace_period'` |
| `subscription_plan` | String | Same | `'monthly_premium'`, `'yearly_pro'` |
| `trial_ends_at` | DateTime (native) / number (RN, epoch) | RevenueCat `CustomerInfo.entitlements.trialPeriodEndDate` | `1718640000` |
| `last_paywall_view_at` | DateTime / number | App-side, stamped on paywall view | |
| `total_purchases` | Number | Counter property — fallback only; on Amply SDK 0.6.1+ target the `Purchase` event count directly (see "Counter properties" below) | `3` |
| `paywall_view_count` | Number | Counter property — fallback only; on Amply SDK 0.6.1+ target the `PaywallShown` event count directly (see "Counter properties" below) | `7` |
| `onboarding_completed` | Boolean | App-side, set when the last onboarding step finishes | `true` |
| `onboarding_completed_at` | DateTime / number | Same | |
| `locale` | String | OS locale at session start | `'en-US'` |
| `install_date` | DateTime / number | First launch timestamp, persisted | |
| `app_version_at_install` | String | First-launch app version, persisted | `'1.0.3'` |
| `notifications_enabled` | Boolean | Push permission state | `true` |
| `att_status` | String | iOS only — current ATT status | `'authorized'` / `'denied'` / `'undetermined'` |
| `referral_source` | String | If your install attribution carries one | `'tiktok'` |
| `feature_flags_active` | String | Comma-separated active flags (since arrays aren't supported) | `'new_paywall_v2,grouped_settings'` |

## Counter properties — the fallback for "fire after Nth event"

For apps running **Amply SDK 0.6.1+**, "user fired event X N times" **is a built-in targeting condition** — campaign audience rules target events directly (`how many times` occurrence counts, `has happened` (ever) / `has never happened`, `first occurrence` / `last occurrence` dates, event property filters; up to 20 event conditions per campaign). Prefer that over counters — no app code, no persistence, no write-ordering concerns. See `who-when-what-audit.md` § Who for the full operator vocabulary.

Counter Custom Properties remain the right tool in two cases:

1. **Older installed builds** — devices running an Amply SDK below 0.6.1 never match event conditions; a `*_count` property targets every SDK version the fleet still runs.
2. **Derived state that isn't a single event** — a count that aggregates several events, applies business logic before counting, or must be reset by the app (e.g. "streak length", "items in cart").

The counter pattern, when you need it:

1. Maintain a counter in app code (persisted in storage).
2. Increment when the event fires.
3. Push the new value as a `*_count` Custom Property whenever it changes.
4. Target campaigns on `*_count >= N`.

```ts
// RN example
function recordPaywallView() {
  paywallViewCount += 1;
  Amply.setCustomProperty('paywall_view_count', paywallViewCount);
  Amply.track({ name: 'PaywallShown', properties: { count: paywallViewCount } });
}
```

The audit must list every "after N times" rule the team wants and, per rule, whether a direct event condition (Amply SDK 0.6.1+) or a counter property serves it.

## Properties to NOT set as Custom Properties

- **PII** — email, phone, address, raw IP, full name, government IDs. Strip / hash at the wrapper.
- **High-cardinality identifiers** — order IDs, session IDs, individual UUIDs. These bloat the property store with no targeting value. Use them in event properties (Event Param rules) instead.
- **Frequently-changing values** that aren't useful for targeting — e.g. last seen seconds-ago, current screen. Targeting works at session scope; sub-second updates are wasted writes.

## Initial-set order

On every app launch, set Custom Properties **before** firing any tracked event in the wrapper. Amply evaluates targeting using the property snapshot it sees at trigger time; setting after the trigger means the campaign doesn't pick up the change until next time.

## What goes in `amply-audit.md`

The Phase 3.4 / 3.5 output should include a table:

| Property | Type | Already set? | Source | Why we want it |
|---|---|---|---|---|
| `subscription_status` | String | ❌ | RevenueCat | Required for paywall versioning campaigns |
| `paywall_view_count` | Number | ❌ | App counter | Only if the fleet runs Amply SDK < 0.6.1 — otherwise target `PaywallShown` count directly |
| `onboarding_completed` | Boolean | ✅ (already set) | App | Required for entry-based onboarding routing |
