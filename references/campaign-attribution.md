# Campaign attribution — the explicit mark and the team's own analytics

A campaign's goals (`who-when-what-audit.md` → *Goal*) credit conversions by window with no app
code. Two small app-side additions make the credit exact and put it into the analytics the team
already reads (Amplitude, Mixpanel, …). Both are optional; propose them for paywall, offer and
upgrade campaigns. They change the purchase call site, so in `autopilot` record them in the audit
rather than editing payment code unasked.

## 1. Put the campaign on the purchase event

**Which campaign** — in this order:

1. **The purchase started from the campaign.** The deeplink handler's `info` always carries
   `campaignId` and `campaignName`; pass them along with the route. Or write them into the link —
   `myapp://paywall?amply_campaign_id={@campaign.id}&amply_campaign_name={@campaign.name}`
   (template variables, SDK 0.13.0+) — and read them from the URL on the screen it opens.
2. **It happened somewhere else, soon after** (closed the offer, bought from settings):
   `getLastCampaignTouch(withinMs)` — **SDK 0.15.0+**. Returns the campaign most recently shown or
   completed within `withinMs` (inclusive, capped at 30 days) as `{campaignId, campaignName, kind
   (shown | engaged), atMs}`, or null. Null before init and when nothing qualifies; touches are
   forgotten when a signed-in user id changes or is cleared (logout). Use the goal's window as `withinMs`.

**Send** `amply_campaign_id` (+ `amply_campaign_name`) as properties of the purchase event, and
send **that same event to Amply (`track`) and to the app's analytics** — through the existing
wrapper, at the one call site. Amply accepts the mark when the event carries exactly one
`amply_campaign_id`, it names a campaign of this project, and the device saw or completed that
campaign within the 30 days before; then it counts for that campaign even outside the goal's
window. Otherwise the event still counts by window. The mark params are never part of a goal's
filters — don't add them to the goal definition.

```swift
// iOS — fromLink: the two amply_campaign_* values onDeepLink took from info["campaignId"] / info["campaignName"]
func campaignProperties(fromLink: [String: Any]?) async -> [String: Any] {
    if let fromLink { return fromLink }
    guard let touch = try? await amply.getLastCampaignTouch(withinMs: 24 * 60 * 60 * 1000) else { return [:] }
    return ["amply_campaign_id": touch.campaignId, "amply_campaign_name": touch.campaignName]
}
// at purchase: analytics.track("PurchaseCompleted", base.merging(await campaignProperties(fromLink: link)) { $1 })
```

```kotlin
// Android / KMP
suspend fun campaignProperties(fromLink: Map<String, Any>?): Map<String, Any> {
    if (fromLink != null) return fromLink
    val touch = amply.getLastCampaignTouch(24 * 60 * 60 * 1000L) ?: return emptyMap()
    return mapOf("amply_campaign_id" to touch.campaignId, "amply_campaign_name" to touch.campaignName)
}
```

```ts
// React Native
async function campaignProperties(fromLink?: Record<string, string>) {
  if (fromLink) return fromLink;
  const touch = await Amply.getLastCampaignTouch(24 * 60 * 60 * 1000); // never rejects for a valid window
  return touch ? { amply_campaign_id: touch.campaignId, amply_campaign_name: touch.campaignName } : {};
}
// at purchase: analytics.track('PurchaseCompleted', { sku, price, ...(await campaignProperties(link)) })
```

Fleet below SDK 0.15.0: only the link path exists — skip step 2 rather than raising the pin for it.

## 2. Forward campaign shows for funnels

For "campaign shown → purchased" in the team's analytics, forward `CampaignShown` (and
`CampaignResolved` for mini-app / gated outcomes) from the system-events listener, under the same
property names as the purchase (`amply_campaign_id`, `amply_campaign_name`). Both events carry
`campaignId`; `campaignName` from **SDK 0.15.0+**.

**Merge, don't replace.** On iOS / Android / KMP the SDK keeps **one** system-events listener —
`setSystemEventsListener` replaces the previous one. If the app already sets one, add the
forwarding inside it. On RN, `addSystemEventListener` subscriptions coexist, but still extend the
existing handler so forwarding lives in one place.

```kotlin
override fun onEvent(event: EventInterface) {
    // ...existing handling stays...
    if (event.name == "CampaignShown" || event.name == "CampaignResolved") {
        analytics.track("Amply${event.name}", mapOf(
            "amply_campaign_id" to (event.properties["campaignId"] ?: ""),
            "amply_campaign_name" to (event.properties["campaignName"] ?: ""),
            "amply_result" to (event.properties["result"] ?: "shown"),
        ))
    }
}
```

Swift is the same shape (`func onEvent(event: EventInterface)`); RN reads `event.properties`.

**Expect the two tools to differ.** Their windows, user identity and offline/sampling rules differ;
compare campaigns inside one tool, don't reconcile totals across them.
