# Property writes — a first-class detect class

The audit (Phase 2) recognises **two** kinds of analytics calls, not one:

1. **Track-event calls** — `.track()`, `.logEvent()`, `.capture()`, `.recordEvent()`, etc. Map to `Amply.track(...)`.
2. **Property-write calls** — `.people.set()`, `.setUserProperties()`, `.identify(_, { traits })`, `.setUserProperty()`, etc. Map to `Amply.setCustomProperty(...)`.

These are different signals semantically — one drives campaign **When** (triggering), the other drives campaign **Who** (targeting). The audit captures them in separate tables; decisions and rules differ.

## Alias table — common property-write patterns

When greping for vendor call-sites in Phase 2, recognise these as property-writes (not events):

| Vendor | Property-write pattern | Maps to Amply |
|---|---|---|
| Mixpanel | `mixpanel.people.set({...})`, `mixpanel.people.set_once({...})` | `Amply.setCustomProperty(key, value)` per key (note: `set_once` semantics are app-side — once written it persists, Amply doesn't distinguish) |
| Amplitude | `amplitude.setUserProperties({...})`, `amplitude.setUserProperty(key, value)`, `Identify().set(key, value)` | `Amply.setCustomProperty(...)` per key |
| Segment | `analytics.identify(userId, { traits })` | **split:** `Amply.setUserId(userId)` + `Amply.setCustomProperty(...)` per trait |
| Firebase | `setUserProperty(name, value)`, `analytics.setUserProperties({...})` | `Amply.setCustomProperty(...)` per key |
| PostHog | `posthog.identify(userId, { properties })`, `posthog.setPersonProperties({...})` | split (id + properties) |
| RudderStack | `rudder.identify(userId, { traits })` | split |
| Heap | `Heap.addUserProperties({...})` | `Amply.setCustomProperty(...)` per key |
| Braze | `Braze.shared.setCustomAttribute(key:, value:)` | `Amply.setCustomProperty(...)` |
| Iterable | `IterableAPI.updateUser(dataFields:)` | per-field property write |
| OneSignal | `OneSignal.sendTag(key, value)`, `sendTags({...})` | per-tag property write |
| Customer.io | `CustomerIO.shared.identify(identifier:, body:)` | split |
| Intercom | `Intercom.updateUser(UserAttributes(customAttributes:))` | per-attribute property write |

## Decision tree per property-write detect

For each detected property-write call:

```
1. Key is PII (email, phone, address, raw_ip, full_name, government_id)?
   → skip-pii (do not mirror to Amply; never store PII as Custom Property)

2. Key looks like a unique-per-device or transient identifier (raw user_id,
   raw device_id, advertising_id, session_id, order_id, transaction_id,
   request_id; UUID-shaped values; long hex hashes)?
   → DOMAIN CHECK on the actual values seen at call-site:
       - values look UUID-like (/^[0-9a-f-]{36}$/i), long hex hashes, or
         monotonically-increasing numbers → skip-unique-id
       - values are categorical (e.g. screen_id="paywall_coffee_goals_v2")
         → include with note "verify values are categorical, not unique per
           device" in Observations
   → if values cannot be determined from call-site context →
     include + flag in Observations: "verify values are categorical, not
     unique per device"

3. Value type incompatible with platform target?
   - Native target: allowed = String, Int, Long, Float, Double, Boolean, DateTimeValue
   - RN target: allowed = string, number, boolean (no DateTime)
   - Array values → pick recipe from custom-properties.md (csv / first / count)
   - Object/nested → skip with Observation "Amply does not support nested
     objects; flatten if you need to target on inner keys"

4. Key length OK?
   - RN: ≤ 32 chars; native: ≤ 255 chars
   - over limit → suggest a shorter alias in audit; do not auto-rename

5. Key is a one-shot write of a baseline-mutable property?
   - Baseline mutable list (see custom-properties.md): subscription_status,
     subscription_plan, trial_ends_at, last_paywall_view_at, total_purchases,
     paywall_view_count, onboarding_completed, notifications_enabled,
     att_status, plan, is_premium, ...
   - If the key is in the mutable baseline AND only written at one location
     (init / login) AND there are no other call-sites where this key gets
     refreshed → flag in Observations:
     "key `X` (mutable baseline) is written only at file:line; verify it's
     updated when the underlying state actually changes"
   - This is an observation, NOT an action item. Per Scope discipline in
     SKILL.md — we do not refactor the project's existing analytics.

6. Otherwise → mirror to Amply.setCustomProperty
```

Note on `*_count` keys in the mutable baseline (`total_purchases`, `paywall_view_count`, …): these mirror event occurrences. On **Amply SDK 0.6.1+** campaigns target event history directly (counts, first/last occurrence, property filters), so a *missing* counter is not automatically a gap — flag it only if the fleet runs older SDK builds or the count is derived state a single event can't express. See `custom-properties.md` § Counter properties.

## How property writes interact with `*_changed` events

Many apps fire a parallel `*_changed` event right next to a property-write:

```ts
mixpanel.people.set({ subscription_status: 'active' });
mixpanel.track('subscription_status_changed', { from: prev, to: 'active' });
```

When the audit detects both, the property-write goes to the User-property-writes table (mirror) and the event goes through the events decision tree. The events tree has a dedicated branch for `*_changed` / `*_updated` events — see `references/event-naming.md` § decision tree.

By default the `*_changed` event is **dropped** for Amply. The SDK fires `CustomPropertyChanged` (type=system) automatically on every `setCustomProperty` with the full diff payload `{key, oldValue?, newValue?, timestamp}` and deduplication (only emits when `oldValue != newValue`). Campaigns target `CustomPropertyChanged` directly with Event Param filters on `key` and `newValue` — no app-side `*_changed` event needed.

Exception: if the event carries side-info that the property value alone cannot express (e.g. `source: 'restore_purchases'`, `discount_code: 'BLACK40'`, `rollout_cohort: 'beta-7'`) — then the event stays, renamed to a past-tense action name (e.g. `PlanUpgraded`), with the redundant `from`/`to`/`key` keys stripped in the wrapper. `CustomPropertyChanged` still fires under it.

## Property-write ↔ event gap check

The audit must also surface the inverse mismatch: a `*_changed` event that fires but no parallel property-write is found. Example:

```ts
// In billing.ts:120
analytics.track('plan_upgraded', { from: oldPlan, to: newPlan });
// ... no call to Amply.setCustomProperty('plan', newPlan)
```

In this case, an Amply campaign targeting `Who: plan = 'premium'` will never fire — the property is stale. The audit flags this as an Observation:

> Event `plan_upgraded` fires at `src/billing.ts:120` but no parallel property-write found. Amply campaigns targeting on `plan` won't see the change. Decide whether to mirror to a property-write next to this call-site.

Per Scope discipline — observation, not auto-fix. Team decides.
