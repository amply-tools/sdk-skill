# Amply system events

The Amply SDK fires a small set of events automatically as `EventType.SYSTEM`. They don't require any app-side `track()` call — they happen because the SDK runs.

This matters for the audit: if the project's existing analytics fires its own version of these (e.g. a `session_start` event in Mixpanel), **do not mirror that event to Amply**. The SDK is already emitting the canonical equivalent. Campaigns target the system event directly; an app-side mirror would just produce duplicates.

## The system events

| Name (as fired by SDK) | When | Properties |
|---|---|---|
| `SdkInitialized` | After SDK init completes | — |
| `ConfigFetchStarted` | Before remote config fetch | — |
| `ConfigFetchFinished` | After remote config fetch | — |
| `SessionStarted` | At session start | `type: 'cold' \| 'warm'` |
| `SessionFinished` | At session end | — |
| `CampaignShown` | When a campaign action fires | `campaignId` |
| `EventTriggered` | Meta-event for every `track()` call | mirrors the triggering event's name |
| `CustomPropertyChanged` | When any Custom Property is set, updated, removed, or cleared (deduplicated — only fires when `oldValue != newValue`) | `key: String`, `oldValue: Any` (omitted on first set), `newValue: Any` (omitted on remove/clear), `timestamp: Long` (epoch millis) |

(Source: SDK `events/Event.kt → object SystemEvents`. List reflects the SDK at time of writing — future SDK versions may add events; check the constant file in the SDK source if in doubt. `CustomPropertyChanged` requires SDK with that constant present — confirm during integration.)

## Overlap with project's existing analytics

When the audit (Phase 2) finds these patterns in the project, treat them as system-event overlaps and **do not forward to Amply**. The audit row gets `Decision: skip-system-overlap` and a `Why` pointing to this table.

| Project event pattern | Maps to system event | Notes |
|---|---|---|
| `session_start`, `session_started`, `sessionStart`, `app_open`, `appOpened`, `app_foregrounded`, `app_resumed` | `SessionStarted` | The SDK distinguishes cold vs warm via the `type` property of `SessionStarted`. App-side aliases that fire only on cold start still overlap — the campaign filter `type === 'cold'` handles that. |
| `session_end`, `session_ended`, `app_close`, `app_background`, `app_backgrounded` | `SessionFinished` | — |
| `app_launch`, `application_did_finish_launching` (only first time per install) | `SdkInitialized` | Most apps fire `app_launch` on every launch; map to `SessionStarted` instead unless the app explicitly fires it once-per-install. |
| `campaign_shown`, `campaign_impression`, `amply_shown` | `CampaignShown` | Should never originate from app code — if found, the team is double-instrumenting. Flag in Observations. |

## Why this matters for campaign design

Campaigns triggering on session lifecycle work out of the box — point the **When** at `SessionStarted` (type=system) and the campaign fires every session, no app-side wiring needed.

When the audit captures a `*_count` Custom Property that depends on session count (e.g. `paywall_views_count` incremented every session), the increment can hang off the SDK's `SessionStarted` system event in app code — no custom `app_open` event needed.

**`CustomPropertyChanged` enables property-change-driven campaigns without custom events.** Where previously a campaign like "fire deeplink when subscription_status changes to 'expired'" required the app to fire a custom `*_changed` event after each `setCustomProperty` call, now the SDK emits `CustomPropertyChanged` (type=system) automatically. The campaign **When** can target this event directly with Event Param filters on `key === 'subscription_status'` AND `newValue === 'expired'`. Dedup is built in (the SDK only fires when `oldValue != newValue`), and the property persistence is guaranteed independently of the dispatch — a listener failure can't lose the write.

## What to do if the team really wants their own session event

Some teams have analytics-stack reasons to keep an explicit `session_start` event in Mixpanel/Amplitude/etc. — for dashboards, server-side aggregations, retention cohorts. **That's fine** — keep the existing call to those vendors. The audit just says "do not fan it out to Amply too", because:

- The system event is already there.
- Two firings of the same event will produce two campaign evaluations.
- If the campaign filters on `type === 'cold'`, only the system event has that property; the mirrored event won't be filterable cleanly.

The Observation in the audit reads, for these cases: `app fires session_start at file:line; kept for vendor X dashboards, NOT mirrored to Amply (overlaps SessionStarted system event)`.
