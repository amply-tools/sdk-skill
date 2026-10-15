# Who / When / What — campaign-model readiness audit

This is the heart of Phase 4. For each candidate Amply campaign, walk the same three steps the admin panel uses: **Who** (targeting) → **When** (triggering) → **What** (action). At each step, list what the codebase already supplies and what's missing.

## Who — targeting

Amply matches users with a combination of:

| Source | What you can target on |
|---|---|
| **Device properties** (auto-collected) | Countries (include/exclude), OS Version, App Version, App Install Version, Applications, Install Date |
| **Custom Properties** (set by the app) | Any key the app pushes via `setCustomProperty` / `setCustomProperties`. Operators: `=`, `≠`, `>`, `<`, `≥`, `≤`, `is set`, `is not set` (depending on type) |
| **Event history** (recorded by the SDK; **Amply SDK 0.6.1+**) | Any event the app fires via `track()`. Two condition kinds: **count** — `how many times` the event has happened (`exactly`, `not exactly`, `more than`, `fewer than`, `at least`, `at most`), plus `has happened` (ever) / `has never happened`; **date** — when it first or last happened (`first occurrence` / `last occurrence`), relative (`more than N days ago` — with an "…or never" variant — / `within the last N days`) or absolute (`before` / `after` a date, whole UTC days). Event property filters narrow which occurrences count — `equals` / `not equals` for text values, plus `greater than` / `less than` for numbers — and apply to both counts and dates. Up to **20 event conditions per campaign**. |
| **Campaign history** (recorded by the SDK) | Whether this user has seen another campaign: `seen` how many times, `first seen` / `last seen` when. Use it to keep campaigns from stacking ("not shown the welcome sheet yet", "saw the paywall more than 7 days ago"). |

**Event-history caveats for the audit:**

- Only apps running **Amply SDK 0.6.1+** match event conditions — devices on older SDK builds simply don't match those campaigns. For fleets with older installed builds, counter Custom Properties remain the fallback (see `custom-properties.md` § Counter properties).
- History starts the first time the Amply SDK ran **on that device** — for a new install that is the install, for an app that adds Amply later it is the update that shipped the SDK. Events fired earlier don't exist, and history is per device: an action the same person took on another phone is not visible. Evaluation happens on-device and works offline.
- **Install Date has the same origin.** It is when Amply first ran on the device, not when the app was installed. For an app that added Amply recently, "installed more than 30 days ago" matches nobody until 30 days after that update — pick the threshold with that in mind.

**Designing a condition — check in this order before proposing app changes:**

1. **Can event history express it?** "Hasn't done X for N days" is `last occurrence` → `more than N days ago` (add "…or never" if people who never did X belong in the audience). "Did X at least N times" is a count. Narrow both with event property filters — every filter must match (AND) — so `kind = weight` or `action = created` keeps unrelated or corrected records out. Prefer this to a new Custom Property: it needs no app change.
2. **Use a Custom Property only for state that events can't carry** — something that existed before the SDK did, happened on another device, or is a current fact rather than a history (household size, plan, a date that lives in the app's own database). Report facts about the app, not answers computed for one campaign.
3. **A condition on a property the device hasn't set is false, not zero.** `household_size = 0` does not match a device that never reported `household_size`. Use this deliberately: a campaign keyed on a new property stays silent on older builds until they update. Use `is not set` when "never reported" should match.

**Recency recipes — "hasn't done X for N days" is built in; never add a `last_x_at` property for it:**

| Ask | Condition |
|---|---|
| "Hasn't done X in 7 days" (and people who never did it count) | Event `X` → `last happened` → `not in the last 7 days` (the "…or never" mode) |
| "Hasn't done X in 7 days, but did it at some point" | Event `X` → `last happened` → `more than 7 days ago` |
| "Did X within the last 3 days" | Event `X` → `last happened` → `less than 3 days ago` |
| "First did X more than 30 days ago" (a veteran) | Event `X` → `first happened` → `more than 30 days ago` |
| "Back after 14+ days away" | Trigger `SessionStarted`; Who: `SessionFinished` → `last happened` → `more than 14 days ago` — or, closer to the product, the app's core value event (`LessonCompleted`, `WorkoutLogged`) last happened more than 14 days ago |

**The trigger-event trap.** The triggering occurrence is recorded *before* the audience is evaluated. A condition on the **same event as the trigger** therefore always sees it as "just now": `last happened more than N days ago` on the trigger event never matches, and a count includes the current occurrence (`at least 5` fires on the 5th). For "came back after a gap", put the recency condition on a *different* event than the trigger (the table's last row).

**No OR.** All Who conditions combine with AND. "Bought once OR NPS ≥ 9" is two campaigns, not one.

**Not available as built-in targeting:**

- Cohort intersection / set membership beyond the simple compare operators.
- AI-powered segmentation — long-term roadmap, not buildable today.

### Audit output per campaign

| Field | Example |
|---|---|
| Required device properties | `country = US`, `app_version >= 2.0.0` |
| Required Custom Properties | `subscription_status = 'free'` |
| Required event history | `PaywallShown` happened `at least` 3 times (Amply SDK 0.6.1+) |
| Already populated? | ✅ `subscription_status` set from RevenueCat. ✅ `PaywallShown` fires from `src/paywall.tsx:42`. |
| Action | None — the event condition needs no app code. (Fleet below SDK 0.6.1? Fall back to a `paywall_view_count` counter — see `custom-properties.md`.) |

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

**Three action types exist:**

1. **`Mini-app`** (Amply SDK **0.12.0+**) — a screen built and published in **Amply Studio** (the builder in the admin) and drawn by the SDK over the app: full screen, bottom sheet, centred card, or story. The team styles it in the app's own colours and fonts, with light/dark variants and per-locale copy (the device locale picks it). Its buttons run a fixed list of actions: record an event (sent through the SDK under the author's name), open a deep link (delivered to the app's deeplink listener), request a store review, save answers as Custom Properties, move between screens, close. Closing or moving to another screen ends the list, so a deep link goes **before** the close. Copy can show the device's Custom Properties through Studio variables; button links are constants (no per-user substitution). A Studio document must be published before a campaign can use it; the MCP can attach a published one (`documentId` + `versionId`) but cannot author or publish it.
2. **`Deeplink`** — admin field is a URL; SDK calls the registered deeplink listener; the host app routes to a screen and renders whatever UI it wants.
3. **`RateReview`** — no extra config; the SDK invokes the platform's native in-app review dialog.

**Off-limits in the audit — flag and reject:**

| Asked for | Reality |
|---|---|
| A popup / sheet / card / onboarding screen | ✅ a **Mini-app** if it can be built from Studio's components; otherwise a Deeplink to a host-rendered screen. Never promise arbitrary native UI drawn by Amply. |
| Push notification | ❌ — Amply does not send pushes. Use a deeplink to trigger the app's own push provider if relevant. |
| Email / SMS / cross-channel | ❌ — Amply is in-app only. |
| Custom payload to a server endpoint | ❌ — the only payload is the deeplink URL + info map delivered to the listener (and, for a Mini-app, the events and properties it records). |
| A/B test with statistical-significance dashboard | ❌ — not generally available. Two campaigns to disjoint segments are possible; there is no experiment framework to offer. |

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

- **Who** — segment by `referral_source` / `cpp_id` Custom Property + built-in **Install Date** `less than 1 day ago` (Install Date is when Amply first ran on the device — fine for a new install).
- **When** — `SessionStarted` (system event), Repeat Rule `on 1`.
- **What** — `Deeplink` to onboarding-A or onboarding-B.

### 2. Paywall versioning without releases

- **Who** — `subscription_status = 'free'`, country in target list.
- **When** — `PaywallTrigger` event (a synthetic event the app fires when the paywall *would* appear).
- **What** — `Deeplink` to remote-rendered paywall variant.

### 3. Post-trial recovery flow

- **Who** — `subscription_status = 'expired'`, `trial_ended_at < 48h`.
- **When** — `SessionStarted` with `Repeat Rule: on 1, 2, 3 globally`, `Frequency Limit: 1 per day`.
- **What** — `Deeplink` to recovery-offer screen.

### 4. Reactivation after inactivity

- **Who** — event `SessionFinished` last happened `more than 14 days ago` (or the app's core value event, e.g. `LessonCompleted`). No `last_session_at` property — event history already knows. Don't put the condition on `SessionStarted` itself: see *The trigger-event trap*.
- **When** — `SessionStarted`.
- **What** — `Mini-app` welcome-back sheet, or `Deeplink` to a reactivation screen.

### 5. Seasonal / event-based campaigns

- **Who** — country / locale-targeted; restrictive Custom Property gates.
- **When** — any in-app event the team picks (`SessionStarted`, `HomeViewed`).
- **What** — `Mini-app` sheet or story, or `Deeplink` to the seasonal banner.

### 6. RateReview after positive moment

- **Who** — event condition `Purchase` happened `at least` 1 time (Amply SDK 0.6.1+; below that, `total_purchases >= 1` counter). Targeting has no OR — an `nps_score >= 9` audience is a second campaign.
- **When** — event such as `PurchaseCompleted` or `LessonCompleted`, `Repeat Rule: on 1`, `Frequency Limit: lifetime 1`.
- **What** — `RateReview`.

## Deliverable

For each campaign the team wants, the audit emits a block following the structure above. Anything missing is a **gap** the team must close before the campaign can ship — usually a property the app doesn't yet set, an event it doesn't yet fire, or an event-param key it doesn't yet attach.
