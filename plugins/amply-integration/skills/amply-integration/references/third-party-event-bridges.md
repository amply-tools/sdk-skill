# Third-party SDK event bridges

Some SDKs are the **source of truth** for events the team wants to see in Amply, but they don't fire app-side `.track()` calls directly. Common examples: RevenueCat (purchase events), Superwall (paywall lifecycle), Adjust / AppsFlyer (attribution), Sentry breadcrumbs.

This reference tells the audit (Phase 2) what to do when it detects these patterns: don't treat the SDK call as an event or property-write detect, **but** check whether a parallel app-side bridge to Amply exists. If not — flag in Observations with the recommended wiring location and what props to capture. Per the SKILL.md Scope discipline rule, the skill does **not** write the bridge code automatically (interactive mode may offer to draft it; autopilot just observes).

**Why a bridge pays twice (Amply SDK 0.6.1+):** a forwarded event is not just a campaign trigger — it becomes an **audience condition**. Once `Purchase` is bridged, campaigns can target *"`Purchase` happened at least 2 times"* or *"first `PaywallShown` more than 7 days ago"* — with event property filters (e.g. only purchases where `currency` equals `"USD"`) — and no further app code. An unbridged SDK keeps that entire targeting axis invisible to Amply, so a missing bridge now costs both the trigger **and** the Who side of every future campaign.

## The bridges

| 3rd-party SDK | Detect pattern | Natural hook for Amply bridge | Recommended Amply event / write | Recommended props |
|---|---|---|---|---|
| **RevenueCat — purchase** | `Purchases.shared.purchase(...)`, `Purchases.purchase(package:)` | The completion handler / success callback (Swift: `purchaseHandler`; RN: `Purchases.purchasePackage().then(...)`) | `Amply.track('Purchase', { ... })` | `productId` (categorical, fine), `price` (number), `currency` (String, 3-letter code), `period` (`'monthly'`/`'yearly'`/...), `is_trial_start` (boolean) |
| **RevenueCat — entitlement state** | `Purchases.shared.getCustomerInfo()`, `Purchases.shared.customerInfoStream`, delegate `purchases(_:receivedUpdated:)` | Wherever `CustomerInfo` is consumed and stored to app state | property-writes: `Amply.setCustomProperty(...)` per key | `subscription_status` (`free`/`trial`/`active`/`expired`/`in_grace_period`), `subscription_plan` (productId), `trial_ends_at` (DateTime native / epoch number RN) |
| **Adapty** | `Adapty.makePurchase(...)`, `Adapty.getProfile(...)`, `AdaptyProfile` delegate | Same shape as RevenueCat | Same — `Purchase` event + `subscription_*` property-writes | Same |
| **Superwall** | `Superwall.shared.register(event:)`, `Superwall.shared.handler` (PaywallDelegate), `Superwall.subscribe(...)` (RN) | `delegate.handleSuperwallEvent(_:)` — fires `paywallOpen`, `paywallClose`, `transactionStart`, `transactionComplete`, `transactionFail`, etc. | `Amply.track('PaywallShown' / 'PaywallDismissed' / 'Purchase' / 'PurchaseFailed' / ...)` | `placement_id`, `paywall_id` (categorical fine — usually short slug), `experiment_id` (categorical), `trigger_event` |
| **RevenueCatUI / Paywall.swift** | `PaywallView`, `presentPaywallIfNeeded()` modifiers | `onPurchaseCompleted`, `onPurchaseFailure`, `onRestoreCompleted` view modifiers | Same as RevenueCat purchase | Same |
| **Branch / AppsFlyer / Adjust — attribution** | `Branch.getInstance().userCompletedAction(...)`, `AppsFlyerLib.shared().logEvent(...)`, `Adjust.trackEvent(...)` | These are attribution-tier — usually mirror business events to attribution provider | property-write: `Amply.setCustomProperty('referral_source', ...)` if attribution callback delivers a source | `referral_source` (categorical), `campaign_name` (categorical if short slug; flag if it's a UUID) |
| **Sentry breadcrumbs** | `Sentry.addBreadcrumb({ category, message, data })` | N/A — breadcrumbs are diagnostic, not analytics events | DO NOT auto-mirror | — |
| **FullStory / Smartlook / UXCam — session-replay** | `FullStory.event(...)`, `Smartlook.trackCustomEvent(...)`, `UXCam.logEvent(...)` | N/A — session-replay is for support / UX research | DO NOT auto-mirror | — |
| **OneSignal — push tags** | `OneSignal.sendTag(key, value)` | Where push targeting is set | property-write per tag if the value is categorical | per `key` |

## When the audit detects a 3rd-party SDK use without a bridge

Audit row goes to Observations, format:

```
RevenueCat purchase calls detected at `src/iap.ts:42`, `src/iap.ts:118`. No
app-side `track('Purchase', ...)` call found in proximity (same file or
nearby callback). Amply campaigns that target on purchase events (e.g.
RateReview after first purchase, post-purchase upsell) require an app-side
event to be fired after RC's success handler. Suggested wiring:
`Purchases.shared.purchase(...) { result in
   if case .success(let info) = result {
       amply.track(event: "Purchase", properties: ["product_id": ..., ...])
   }
 }`.
Decide whether to wire this — out of scope for this skill, but offered as
a starting point. Interactive mode can draft the code on request.
```

In autopilot the row stays as an Observation. In interactive mode the agent may ask "want me to draft the bridge for this 3rd-party SDK call?" and only writes code if the human confirms.

## Out-of-MVP scope

Out-of-the-box bridges (the Amply SDK auto-listening to RC / Superwall / Adjust callbacks without app code) are planned for a future release. Until then, the bridge is app-code that the team writes. The audit's job is to surface the gap, not to write the bridge.
