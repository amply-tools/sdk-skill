# Who / When / What — campaign-model readiness audit

This is the heart of Phase 4. For each candidate Amply campaign, walk the same three steps the admin panel uses: **Who** (targeting) → **When** (triggering) → **What** (action). At each step, list what the codebase already supplies and what's missing.

## Who — targeting

Amply matches users with a combination of:

| Source | What you can target on |
|---|---|
| **Device properties** (auto-collected) | Countries (include/exclude), OS Version, App Version, App Install Version, Applications, Install Date |
| **Custom Properties** (set by the app) | Any key the app pushes via `setCustomProperty` / `setCustomProperties`. Operators: `=`, `≠`, `>`, `<`, `≥`, `≤`, `is set`, `is not set` (depending on type) |

**Not available as built-in targeting:**

- "User has fired event X N times" — workaround: maintain a counter Custom Property (see `custom-properties.md`).
- Cohort intersection / set membership beyond the simple compare operators.
- AI-powered segmentation — long-term roadmap, not buildable today.

### Audit output per campaign

| Field | Example |
|---|---|
| Required device properties | `country = US`, `app_version >= 2.0.0` |
| Required Custom Properties | `subscription_status = 'free'`, `paywall_view_count >= 3` |
| Already populated? | ✅ `subscription_status` set from RevenueCat. ❌ `paywall_view_count` not set. |
| Action | App needs a counter — see Phase 3.6. |

## When — triggering

Three sub-blocks combine:

### Triggering Event

The campaign listens for an event name fired via `track()`. **Pick from the events the app actually fires** — if the audit found no `Purchase` event in Phase 2, you cannot trigger on it.

### Event-parameter matching (Event Param rules)

After picking an event, the admin panel lets you filter on **parameters** (the values inside the `properties` map):

- `parameter name` — must match a key in the `properties` map the app passes to `track`.
- `value type` — `String` / `Number` / `Boolean`.
- compare operator — `===`, `≠`, and for Number: `>`, `<`, `≥`, `≤`.
- compared value.

**This is why the analytics audit captures property keys and types.** A campaign like *"give a discount to users who bought a USD subscription"* needs:

- `Purchase` event fired by the app, with
- `currency` property (key) of type `String`
- ...and an Event Param rule `currency === "USD"`.

If the app fires `Purchase` without `currency`, the campaign cannot exist as designed. Surface this gap in the audit.

### Repeat Rules

- Mode: `on` (specific occurrences) or `every` (recurring).
- Numeric chips: `every 3`, `on 3, 4, 5`.
- Scope: `globally` (lifetime counter) / `in session` (resets per session).

### Frequency Limits

- Lifetime cap: `Show campaign N times (total)`.
- Minimum interval between impressions: `at least N {hours|minutes|days}`.
- Per-session cap: `1 time per session`.

### Audit output per campaign

| Field | Example |
|---|---|
| Triggering event | `Purchase` |
| Event present in code? | ✅ fires from `useIap.ts:42` |
| Event Param rules required | `currency === "USD"` |
| Param present in current event payload? | ❌ — wrapper currently sends `{ sku, price }`, no `currency`. |
| Repeat Rule | `on 1` (first purchase only) |
| Frequency Limits | None |

## What — action

**Only two action types exist:**

1. **`Deeplink`** — admin field is a URL; SDK calls the registered deeplink listener; the host app routes to a screen and renders whatever UI it wants.
2. **`RateReview`** — no extra config; the SDK invokes the platform's native in-app review dialog.

**Off-limits in the audit — flag and reject:**

| Asked for | Reality |
|---|---|
| Amply-rendered popup / modal / sheet | ❌ — Amply does not draw UI. The host app renders the popup in response to a Deeplink. |
| Push notification | ❌ — Amply does not send pushes. Use a deeplink to trigger the app's own push provider if relevant. |
| Email / SMS / cross-channel | ❌ — Amply is in-app only. |
| Custom payload to a server endpoint | ❌ — the only payload is the deeplink URL + info map delivered to the listener. |
| A/B test with statistical-significance dashboard | ❌ — not a built-in feature. Two campaigns to disjoint segments are possible; there is no experiment framework. |

### Audit output per campaign

| Field | Example |
|---|---|
| Action type | `Deeplink` |
| Deeplink URL | `amply://promo/usd-discount-25` |
| Listener wired? | ✅ — `App.tsx:27` |
| Host-app screen for the deeplink | `PromoScreen` |
| URL scheme registered in `Info.plist` / `AndroidManifest.xml`? | ❌ — TODO |

## Top use cases — checklist mapping

For each Amply core use case from the product overview, the audit should produce a self-contained block.

### 1. Entry-based onboarding routing

- **Who** — segment by `referral_source` / `cpp_id` Custom Property + `install_date < 24h`.
- **When** — `AppOpened` event with property `is_first_launch === true`.
- **What** — `Deeplink` to onboarding-A or onboarding-B.

### 2. Paywall versioning without releases

- **Who** — `subscription_status = 'free'`, country in target list.
- **When** — `PaywallTrigger` event (a synthetic event the app fires when the paywall *would* appear).
- **What** — `Deeplink` to remote-rendered paywall variant.

### 3. Post-trial recovery flow

- **Who** — `subscription_status = 'expired'`, `trial_ended_at < 48h`.
- **When** — `AppOpened` with `Repeat Rule: on 1, 2, 3 globally`, `Frequency Limit: 1 per day`.
- **What** — `Deeplink` to recovery-offer screen.

### 4. Reactivation after inactivity

- **Who** — `last_session_at < 14d ago`. Requires the app to push `last_session_at` as DateTime.
- **When** — `AppOpened`.
- **What** — `Deeplink` to reactivation screen.

### 5. Seasonal / event-based campaigns

- **Who** — country / locale-targeted; restrictive Custom Property gates.
- **When** — any in-app event the team picks (`AppOpened`, `HomeViewed`).
- **What** — `Deeplink` to the seasonal banner.

### 6. RateReview after positive moment

- **Who** — `total_purchases >= 1` OR `nps_score >= 9`.
- **When** — event such as `PurchaseCompleted` or `LessonCompleted`, `Repeat Rule: on 1`, `Frequency Limit: lifetime 1`.
- **What** — `RateReview`.

## Deliverable

For each campaign the team wants, the audit emits a block following the structure above. Anything missing is a **gap** the team must close before the campaign can ship — usually a property the app doesn't yet set, an event it doesn't yet fire, or an event-param key it doesn't yet attach.
