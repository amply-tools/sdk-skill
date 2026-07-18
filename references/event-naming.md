# Event naming and decision tree

## Decision tree per detected call

For each detected call from existing analytics (event-track or property-write), apply rules in order. **First match wins.** The audit captures both the resulting Decision and the Why (which rule fired).

### Step 1 — Classify the call

- `.track()` / `.logEvent()` / `.capture()` / `.recordEvent()` / `.signal()` etc. → **Events branch** (continue with §2 below)
- `.people.set()` / `.setUserProperties()` / `.setUserProperty()` / `.identify(_, traits)` / `.sendTag()` etc. → **Property-writes branch** (see `references/property-writes.md`)
- 3rd-party SDK call (`Purchases.shared.purchase()`, `Superwall.shared.register()`, etc.) → **3rd-party bridge check** (see `references/third-party-event-bridges.md`)

### Step 2 — Events branch (ordered rules, first match wins)

1. **System-event overlap** — does the event name match an alias of Amply's auto-fired system events (e.g. `session_start` / `app_open` → `SessionStarted`)? See `references/system-events.md` § Overlap table.
   → `skip-system-overlap` — do not mirror to Amply; campaigns target the system event directly.

2. **Property-change event** — does the name end in `_changed` / `_updated` / `_modified`, AND a parallel property-write call exists in the same file / proximate handler?
   → `skip-property-change-event` — drop. The property-write is the single source of truth, AND the SDK auto-fires `CustomPropertyChanged` (type=system) with `{key, oldValue?, newValue?, timestamp}` payload on every `setCustomProperty` (see `references/system-events.md`). Campaigns target `CustomPropertyChanged` directly with Event Param filters on `key` and `newValue` — no app-side `*_changed` event needed.
   → **Exception:** if the event's `properties` payload carries keys NOT trivially derivable from `(key, oldValue, newValue, timestamp)` (e.g. `source: 'restore_purchases'`, `discount_code: 'BLACK40'`, `rollout_cohort: 'beta-7'`) — then `forward-translated-renamed`: keep it but rename to a past-tense action (`SubscriptionStatusChanged` → `PlanUpgraded`) and strip the now-redundant `key`/`from`/`to` keys at the wrapper. The system `CustomPropertyChanged` event still fires on the underlying property-write; the renamed event carries only the side-info.

3. **Property-change event WITHOUT parallel property-write** — `*_changed` event fires, but no matching `.setCustomProperty` / `.people.set` / `.setUserProperty` call is found.
   → still `skip-property-change-event` for the event itself, BUT also emit an Observation in the audit: "Event `X_changed` fires at file:line but no parallel property-write found. Amply campaigns targeting on `X` won't see the change."

4. **PII in name or property keys** — event name or any property key matches PII patterns (email, phone, address, raw_ip, full_name, government_id) or values look identifying.
   → `skip-pii` for the event; OR `forward-translated` but with the PII keys stripped at the wrapper. Note in audit.

5. **High-cardinality property keys** — event carries `orderId` / `transactionId` / `sessionId` / `request_id` / raw UUID values as properties.
   → `forward-translated`, but drop high-cardinality keys at the wrapper. These belong as event-param filters with `is set / is not set` only, never targeting by exact value. Note in audit.

6. **BI-only / server-driven / batched** — event fires only from server-side, or from a wrapper that batches with significant delay (see `references/analytics-detection.md` § "When NOT to extend the existing wrapper").
   → `skip-bi-only` — campaigns need near-real-time triggering; batched events break the model.

7. **High-leverage list match** — name (case-insensitive, after normalisation) matches a high-leverage pattern: `signup`, `paywall_view`, `paywall_shown`, `purchase`, `trial_start`, `trial_end`, `onboarding_complete`, `content_unlock`, `share`, `app_open` (note overlap with §1), `error`.
   → `forward-translated` + mark for campaign use in audit § Who/When/What.

8. **Otherwise** — default-keep.
   → `forward-translated` — let the wrapper translate the name to PascalCase and pass through.

The audit row gets BOTH the resulting Decision (`forward-translated` / `skip-system-overlap` / `skip-pii` / …) and a short Why (which rule fired, in one phrase).

## The two naming conventions

Amply's recommended convention:

- **Event names: PascalCase** — `PaywallShown`, `OnboardingCompleted`, `TrialStarted`, `Purchase`.
- **Property keys: snake_case** — `screen`, `source`, `subscription_status`, `total_purchases`.

Most apps use a different convention internally — `paywall_shown`, `paywallShown`, or all-caps `PAYWALL_SHOWN`.

## Don't rename the project's events

Renaming everything breaks dashboards, alerts, downstream BI tables, and possibly an event schema validation pipeline. The audit should **leave existing event names alone**.

## Translate inside the wrapper, for the Amply call only

The wrapper is the one place that talks to Amply. Translate at that boundary:

```ts
function pascalCase(name: string): string {
  return name
    .split(/[\s_\-]+/)
    .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
    .join('');
}

// In the wrapper:
await Amply.track({ name: pascalCase(internalName), properties: snakeCaseKeys(internalProps) });
```

Property-key translation:

```ts
function snakeCaseKeys<T extends Record<string, unknown>>(props: T): Record<string, T[keyof T]> {
  const out: Record<string, T[keyof T]> = {};
  for (const [key, value] of Object.entries(props) as [keyof T, T[keyof T]][]) {
    const snake = String(key)
      .replace(/([A-Z])/g, '_$1')
      .replace(/[\s\-]+/g, '_')
      .replace(/^_/, '')
      .toLowerCase();
    out[snake] = value;
  }
  return out;
}
```

Same idea in Swift / Kotlin — the wrappers in `wrapper-patterns.md` show the implementation.

## When the project has a typed event catalogue

Many teams maintain a typed event registry — TS unions, Kotlin sealed classes, Swift enums. **Don't fight it.** Add a `toAmplyName(): string` method or a side table that maps each catalogue entry to its Amply equivalent. Example:

```ts
export const EVENT_CATALOGUE = {
  paywall_shown: { amply: 'PaywallShown' },
  trial_started: { amply: 'TrialStarted' },
  purchase_completed: { amply: 'Purchase' },
  // ...
} as const;
```

## Amply-side conventions for the rest

When the user adds **new** events specifically for Amply targeting (post-trial recovery triggers, reactivation triggers), use the convention from the start:

- Event name: PascalCase, no underscores, no dots.
- Property keys: snake_case, no leading numbers.
- Reserve `_count` suffix for counter properties (legacy fallback — apps on Amply SDK 0.6.1+ target event history directly; see `custom-properties.md` § Counter properties).
- Reserve `_at` suffix for timestamps (DateTime / epoch number).

## Don't double-count

If the existing wrapper already sends `paywall_shown` to Mixpanel, fan out to Amply as `PaywallShown` from the same call site. **Do not** add a second `Amply.track('PaywallShown')` next to it — that would mean two writes per event and two divergent code paths to maintain.
