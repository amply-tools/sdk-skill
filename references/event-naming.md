# Event naming conventions

## The two conventions

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
- Reserve `_count` suffix for counter properties.
- Reserve `_at` suffix for timestamps (DateTime / epoch number).

## Don't double-count

If the existing wrapper already sends `paywall_shown` to Mixpanel, fan out to Amply as `PaywallShown` from the same call site. **Do not** add a second `Amply.track('PaywallShown')` next to it — that would mean two writes per event and two divergent code paths to maintain.
