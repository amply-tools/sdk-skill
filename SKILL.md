---
name: amply-integration
description: Use when the user wants to integrate the Amply SDK (amply.tools) into a mobile app — React Native, Expo, iOS / Swift, Android / Kotlin, or Kotlin Multiplatform — wire campaign deeplinks, forward existing analytics events into Amply, set Custom Properties for targeting, or audit a project's product analytics for Amply's Who/When/What campaign model. Triggers include phrases like "add Amply", "install Amply SDK", "set up Amply", "integrate amply.tools", "Amply campaigns", "Amply deeplink", "Amply custom properties".
---

# Amply Integration

## Overview

Amply is an in-app orchestration layer: it decides what users see after they open the app, based on context, **without a release**. It coordinates with — but does not replace — RevenueCat, your analytics vendor, push provider, or attribution tooling.

This skill walks the user through an opinionated, end-to-end integration:

1. Detect the platform, package manager, navigation library, and SDK version gates.
2. Audit the existing analytics layer and propose how to forward events into Amply.
3. Apply PII hygiene at the wrapper (strip PII, hash IDs, wire logout reset). Do **not** wrap Amply in a runtime consent gate — see Phase 2.5.
4. Build a Who / When / What readiness audit for Amply's campaign model.
5. Generate a thin wrapper (or extend an existing one) so Amply is called from one place.
6. Wire the deeplink listener with the platform-correct signature.
7. Hand off with verification steps.

**Core principle:** never silently make a destructive choice. Detect → propose → confirm → execute.

**Scope discipline:** this skill integrates Amply. It does **not** refactor the project's existing analytics, fix bugs in unrelated code, or propose architectural changes. When the audit detects something that looks suboptimal outside Amply's scope (one-shot writes of mutable properties, `*_changed` events without parallel property-writes, BI-only wrappers, mixed event-name conventions, 3rd-party SDK uses without an Amply bridge), it goes into `## 9. Observations` of the audit — a neutral fact the team can act on or ignore. Only items that are **prerequisites for Amply to function** (deeplink scheme registration, env-loading, listener wiring) go into `## 8. Required for Amply to work` as prescribed action items. Interactive mode may offer to draft optional bridges; autopilot only observes.

## When to Use

- The user says "integrate Amply" / "add the Amply SDK" / mentions `@amplytools/react-native-amply-sdk`, `tools.amply:sdk-android`, `tools.amply:sdk-kmp`, or `AmplySDK` (Swift).
- The user wants Amply campaigns, deeplinks, or Custom Properties wired up.
- The user wants a product-analytics audit oriented toward Amply targeting.

**Don't use for:** debugging Amply backend issues, building marketing copy about Amply, or generic mobile analytics work that has nothing to do with Amply.

## Tool-name note

The workflow below uses tool-neutral verbs — *open*, *modify*, *grep*, *run shell command*. If your host needs an explicit translation between named tools, see `references/codex-tools.md`.

## Mode

The skill operates in one of two modes:

- **`autopilot`** — at every multi-option decision point, the skill picks the documented default and logs the choice in the final audit. No questions to the human. Use this for batch / overnight / CI runs.
- **`interactive`** — at every decision with 2 or more valid options, the skill presents them to the human and waits for a selection. Use this when a human is actively reviewing each step.

Resolve the mode in this order; use the first hit:

1. The invoking message explicitly says `mode: autopilot` or `mode: interactive`.
2. The env var `AMPLY_SKILL_MODE` is set to one of those values.
3. Ask the human once: "Run autopilot or interactive?" — record the answer for the rest of the run. Skip the question if the agent context is clearly autonomous (batch job, no terminal attached).

Every phase below that has 2+ valid options consults this single value. Do not re-ask per phase.

## Workflow

The workflow runs Phase 0 (toolchain check) once, then the nine main phases. Numbering uses `2.5` and `5.5` for sub-steps that piggyback on the preceding phase. Run all phases on a fresh integration; returning users may re-run individual phases.

### Phase 0 — Toolchain check (MCPs)

Before anything else, check two MCPs:

1. **Context7** — mirrors live `docs.amply.tools`; authoritative for SDK reference questions when present. See `references/context7-mcp.md` for detection + free install command + autonomous-mode fallback.
2. **Amply MCP** (`@amplytools/amply-mcp`) — direct backend automation: signup, login, register applications, fetch `apiKeyPublic` + `apiKeySecret`. When connected, the skill can complete a full integration without the user ever opening the Amply admin UI. See `references/amply-mcp.md` for detection (`claude mcp list | grep -i amply`), install (`claude mcp add amply -- npx -y @amplytools/amply-mcp`), the campaign + project/application + auth tools available, and the recommended one-shot `amply_ensure_app`. For agents that want to set up campaigns programmatically, authoring tools (`amply_create_campaign`, `amply_describe_targeting`) are also available — see `references/amply-mcp.md`. Same autonomous-mode rule as Context7 — don't install MCPs without explicit consent.

### Phase 0.5 — Goal sanity check

**Before any discovery work**, restate the user's goal and map it onto what Amply actually does. The most expensive failure mode is integrating Amply for a goal it cannot serve. Use this 5-point checklist:

| Goal phrasing | Amply role | Host-app role |
|---|---|---|
| "Show a custom popup to the user" | ❌ Amply does not render UI. | Host renders the popup. Amply fires a Deeplink at the right moment; host responds with whatever screen the deeplink routes to. |
| "A/B test which popup variant a user sees" | ⚠ partial. Amply chooses *which* deeplink fires (per-campaign), can target on Custom Properties. **Amply does not split traffic.** | Host assigns the bucket (typically a coin-flip persisted in storage + pushed as a Custom Property) and renders both variants. |
| "Send a push notification / email" | ❌ Not Amply. | Use a push provider / email provider. Amply can deeplink users to a screen *after* they open the app. |
| "Throttle prompts / rate-limit asks" | ✅ Repeat Rules + Frequency Limits on the campaign. | Implement the deeplink target. |
| "Trigger an in-app action based on user history" | ✅ via Custom Property targeting + a triggering event. | Fire the triggering event; maintain the relevant Custom Properties; implement the deeplink target. |

In `autopilot`, write one paragraph at the top of the audit: "Your stated goal `<X>` maps onto Amply as follows: Amply will <Y>, your app must <Z>." If any element of the goal lands in the ❌ column, surface that as the first item of the audit. The integration may still be worth doing for the parts Amply *can* do, but the team needs to know upfront where they'll need their own infrastructure.

In `interactive`, present the table to the human and ask "does this match what you want Amply for?" before continuing.

### Phase 1 — Discovery + version gating

Identify the primary platform, package manager, and navigation library. See `references/platform-detection.md`. **Stop and warn** if the project fails any version gate (RN < 0.79, RN New Architecture not enabled, Expo SDK < 53, Android `minSdk` < 24 for RN target / < 21 for KMP, iOS deployment target < 15.1 for RN target / < 14.1 for KMP). Echo the detected stack back as one block; ask once: "is this right?"

**For RN projects: identify the flavour precisely** — Pure Bare RN, Bare RN + Expo Modules, Expo Prebuild Workflow, or Expo Managed. The check is `git ls-files ios/ android/`: hand-managed native folders → "no prebuild ever", regardless of whether `expo` is in `package.json`. This single distinction drives whether you touch `app.json` plugins and whether `expo prebuild` is safe to run.

### Phase 1b — Amply app resolution

After Phase 1 has detected `platform`, `bundleId`, and a project name, resolve the Amply application **once**, here, before any wrapper or key work in later phases.

If the Amply MCP (Phase 0) is connected:

0. **Check auth state first.** Call `amply_status` (or `amply_whoami`). If `authenticated: false`, the autopilot default is to invoke `amply_signup({ email: "<bundleId>-<YYYY-MM-DD>@<project-domain>", password: <generated>, name: "<integrator-name>", organization: "<project-name>" })` and log the credentials in the audit so the team can take ownership of the org. If `authenticated: true` but the user is a stranger to the project (e.g. you're integrating into a team app and the MCP is logged in as a personal account), `interactive`: ask which org to use; `autopilot`: proceed under the existing user and log it.
1. Call `amply_ensure_app({ bundleId, platform, name, projectName?, mintNewKey: false })`.
2. Branch on `result.status`:
   - **`created`** — the app didn't exist; backend returned the first key inline. Carry the returned `envBlock` into Phase 5.
   - **`reused`** — the app already exists; no key was returned (the list endpoint doesn't expose secrets). Consult mode:
     - `interactive`: ask the human — "Existing Amply app found. (1) Mint a new key now, (2) proceed with placeholder values for you to paste from the Amply admin."
     - `autopilot`: re-invoke `amply_ensure_app({ ...same, mintNewKey: true })`. Log "auto-minted new key for reused app" in the audit. Carry the result.
   - **`reused_new_key`** — accept and carry to Phase 5.
   - **`conflict_cross_project`** — STOP. The same `bundleId+platform` is registered in a different project than the one resolved. Surface to the user:
     - `interactive`: ask which project to use; rerun with the correct `projectName`.
     - `autopilot`: fail loudly with the project info from the result and a hint to rerun with the right `projectName` or `allowDuplicateAcrossProjects: true`.

If the MCP is not connected — the manual-paste path. **The skill's manual path matches the MCP path step-for-step; users without the MCP still need account → project → application → key**:

1. **Sign up** at https://app.amply.tools/signup (or log in). Note: organization is created at the same time; the email is the org owner.
2. **Create a project.** Free orgs are limited to a small number; reuse where possible.
3. **Register the application** under the project. Required: `bundleId` (must match `PRODUCT_BUNDLE_IDENTIFIER` exactly) + `platform` (`iOS`/`Android`). The admin returns an `appId` (UUID, **not** the bundleId) plus the first API key inline.
4. **⚠ `apiKeySecret` is shown ONCE at creation.** Copy it to a secure store immediately — there is no way to retrieve it later. If it's lost, mint a new key (orphans the previous one).

Carry all three values (`appId`, `apiKeyPublic`, `apiKeySecret`) into Phase 5 as if the MCP had returned them. Note in the audit that the manual path was used and the team needs to revoke any orphan keys later.

The resolved `envBlock` (or the three manually-pasted values) is the only output Phase 5 needs to consume. Phase 5 no longer discovers keys.

### Phase 2 — Analytics audit

Find existing analytics call sites and classify each one. See `references/analytics-detection.md` for ≥25 vendor fingerprints plus per-language grep patterns.

**Three classes of detect** (different audit tables, different decision trees):

1. **Track-event calls** (`.track`, `.logEvent`, `.capture`, …) — go through the events decision tree in `references/event-naming.md` § "Decision tree per detected call". Result lands in audit § 2.1.
2. **Property-write calls** (`.people.set`, `.setUserProperty`, `.identify(_, traits)`, `.sendTag`, …) — go through the property-writes decision tree in `references/property-writes.md`. Result lands in audit § 2.2.
3. **3rd-party SDK uses** (`Purchases.shared.purchase()`, `Superwall.shared.register()`, `Adjust.trackEvent()`, …) — checked for a parallel app-side bridge. Gaps go to audit § 9.3 as Observations (per Scope discipline). See `references/third-party-event-bridges.md`.

For every call site, capture **file:line plus the property keys and types passed** (and for property-writes, a sample of values where visible — needed for the unique-vs-categorical domain check). Audit rows record both the **Decision** (the outcome) and the **Why** (the rule that fired).

**System-event overlap is the first rule the events tree applies.** Project events that overlap with Amply's auto-fired system events (`session_start` / `app_open` → `SessionStarted`, etc. — see `references/system-events.md`) are dropped, not mirrored. This is **not** optional — duplicates make campaign evaluation noisy.

Decide whether the project already has an analytics wrapper. **Default**: extend the existing wrapper. **Switch to a new wrapper** only if the existing one is server-only, BI-only, vendor-schema-typed in a way that doesn't translate, consent-gated in a way that would block Amply targeting events, or too high-volume to mirror without performance cost. State the exception you found.

This is a multi-option decision — see Mode. In `autopilot`, default to extending the existing wrapper and log the choice in audit § 7.

**Mixed-mode wrappers:** if half the call sites use the typed enum and half pass bare strings (or pass an undeclared event name), do not "clean up" the call sites as part of the integration — that's a separate refactor with separate review risk. Extend the wrapper's runtime contract (it almost certainly accepts `string`) and leave the typing pass for a follow-up. Log this as a finding in the audit report.

### Phase 2.5 — Privacy hygiene (not consent gating)

See `references/consent-and-privacy.md`. The most important reframe: **Amply is a first-party product-feature SDK, not a tracking-analytics SDK**, and the consent considerations that apply to Mixpanel / Amplitude / Adjust do not map onto Amply. Do not wrap Amply in a runtime consent gate.

What you do here, in this exact order:

1. **PII strip**: identify keys in the existing analytics layer that contain PII (email, phone, address, raw IP, full name, government IDs, raw payment details) — strip / hash them in the wrapper before any Amply call.
2. **Opaque user IDs**: confirm that whatever the project passes to `setUserId(userId:)` is opaque (not email/phone). If not, route through a hash with a stable, off-device salt.
3. **Logout hygiene**: wire `setUserId(userId: nil)` + `clearCustomProperties()` on logout. If the app has no logout flow yet, see `references/lifecycle-and-state.md` for the "no login yet" recipe.
4. **ATT** (iOS only): no action needed — the SDK reads `ATTrackingManager.trackingAuthorizationStatus()` automatically and ships IDFA only when authorised. If the app has an ATT prompt for other reasons (AdMob etc.), nothing additional is needed for Amply.
5. **Construction policy**: decide whether your app should construct `Amply(config:)` unconditionally (default — right for ~all apps) or only for certain users (strict — kids' mode, free tier without campaign features, etc.). If strict, the rule is one `if` around the constructor call; no runtime consent flag inside the wrapper.

In `autopilot`, default to construction-unconditional plus the PII / opaque-id / logout hygiene above. Log the choice. **Do not** generate an `AmplyConsentManager` / consent-gated wrapper — that's defensive over-engineering for a problem Amply doesn't have.

### Phase 3 — Event & Custom Property mapping

Build the two audit tables produced by Phase 2 — events (§ 2.1) and user-property writes (§ 2.2). For each row, the Decision and Why come from the decision trees in `references/event-naming.md` and `references/property-writes.md`.

**Do not** rename existing events in the project — translate to PascalCase inside the wrapper for the Amply call only.

Inventory user properties → Amply Custom Properties. Allowed value types: **`String` / `Number` / `Boolean` / `DateTime`** for native SDKs; **`string | number | boolean` only** for the RN SDK (no DateTime via the RN public surface). Anything else → flag as not-supported or apply array-recipe (see `references/custom-properties.md`).

**Hard-exclude defaults for Custom Properties** (also in `references/custom-properties.md`):
- PII keys (email, phone, address, raw_ip, full_name, government_id) → strip / hash; never as Custom Property.
- Unique-per-device or transient identifiers (raw user_id, device_id, advertising_id, session_id, order_id, transaction_id, UUID-shaped values) → skip. Exception: keys named `*_id` whose **values** are categorical (e.g. `screen_id: "paywall_coffee_goals_v2"`) — include after the domain check in `property-writes.md` § Decision tree step 2.
- Free-form timestamps (sub-second precision, raw event timestamps) → skip. Baseline `*_at` properties (install_date, trial_ends_at, last_paywall_view_at, onboarding_completed_at) — supported via DateTime native / epoch number RN.

Propose additional Custom Properties for targeting from `references/custom-properties.md` (`subscription_status`, `trial_ends_at`, `last_paywall_view_at`, `total_purchases`, `onboarding_completed`, `locale`, `install_date`, …). Surface explicitly that **"user fired event X N times" is not a built-in targeting condition** — counters must be maintained in app code and pushed as `*_count` Custom Properties when they change.

**Phase 3 gap check** — before producing § 6 (Who/When/What):

1. **Property-write ↔ event gap** — for every `*_changed` / `*_updated` event detected in Phase 2, verify a parallel property-write exists. If not, add to audit § 9.1 as Observation: "Event `X_changed` fires but no parallel property-write found; Amply campaigns targeting on `X` won't see the change."
2. **Mutable-baseline one-shot writes** — for every property-write whose key matches the mutable baseline (`subscription_status`, `plan`, `is_premium`, `total_purchases`, …) but is written at only one site (init/login), add to audit § 9.2.
3. **3rd-party bridge gaps** — for every detected 3rd-party SDK use (RC purchase, Superwall register, …) without an app-side track call in proximity, add to audit § 9.3 with the suggested wiring from `references/third-party-event-bridges.md`.

Per Scope discipline, these are **observations**, not action items. Interactive mode may offer to draft the bridges; autopilot only records.

### Phase 4 — Who / When / What readiness audit

For each candidate campaign, walk Amply's campaign model — see `references/who-when-what-audit.md`:

- **Who** — list device properties (country, OS / app version, install date) and Custom Properties needed; mark which are populated vs missing.
- **When** — list triggering event(s); flag whether **Event Param** rules are needed (e.g. `Purchase` filtered by `currency = "USD"`); record required keys/types. Note Repeat Rules and Frequency Limits required.
- **What** — confirm the action is **only** `Deeplink` or `RateReview`. Reject any plan involving Amply-rendered popups, push notifications, in-app messages, or cross-channel sends — Amply does not draw UI or send pushes.

Save findings as `amply-audit.md` (template: `references/audit-template.md`). This is a **suggestion document**, not a prescription.

### Phase 5 — Wrapper implementation

Use the templates in `references/wrapper-patterns.md`. Generate / patch wrapper code; preserve existing event shape; add the **platform-correct Amply call**:

- **RN/Expo** — `await Amply.track({ name, properties })` (object payload).
- **iOS Swift** — `amply.track(event: "...", properties: [...])` on the held instance.
- **Android Kotlin** — `amply.track(event = "...", properties = mapOf(...))` on the held instance.
- **KMP** — same as platform target; instance constructed in shared init.

Initialise Amply in the right place using **the platform-correct API** (see SDK cheatsheets):

- RN/Expo: `await Amply.initialize({ appId, apiKeyPublic, debug? })` (static-style module). RN does not require `apiKeySecret`.
- iOS: `let amply = Amply(config: AmplyConfig(appId:, apiKeyPublic:, apiKeySecret:, defaultConfig: nil))` — **`apiKeySecret` is required**; strong reference held by app.
- Android: `val amply = Amply(config = AmplyConfig(appId, apiKeyPublic, apiKeySecret, defaultConfig = null), application = this)` — **`apiKeySecret` is required**; held on `Application`. Or use the `amplyConfig { api { ... } }` builder DSL.

Pull keys from env / build config. **Refuse** to write keys inline — even if the project's own precedent hard-codes other vendors' keys (RevenueCat / Amplitude / etc.) inline. For projects with no existing env-loading pipeline, do one of: (a) suggest adding `react-native-config` / `EXPO_PUBLIC_*` / `BuildConfig` field, and write the Amply call against it with a clear TODO at the call-site; (b) document the choice prominently in the audit and let the user wire env loading on their own next pass. Never silently inline an Amply key just because the project does it elsewhere — `apiKeySecret` in particular must be treated as a real secret.

**Source of the keys:** by the time Phase 5 runs, Phase 1b has already produced an `envBlock` via `amply_ensure_app` (or determined that the MCP isn't connected). Use the `envBlock` as-is. If Phase 1b couldn't run (no MCP), prompt the user for `appId` / `apiKeyPublic` / `apiKeySecret` and tell them where to find them in the Amply admin panel.

For env-loading library choice when the project has none: **this is a multi-option decision — see Mode.** In `autopilot`, default to (a) suggesting the platform-idiomatic config lib (`react-native-config` / `EXPO_PUBLIC_*` / `BuildConfig` field) and writing the Amply call against it with a TODO at the call-site.

Add the package via the project's manager (`yarn add` / Gradle dep / Pod / SPM).

### Phase 5.5 — Lifecycle & state

See `references/lifecycle-and-state.md`. Hold strong references to the Amply instance and the deeplink listener (the SDK does not retain listeners). Initialise Amply **before** the first `track` / `setCustomProperties` call. On login/logout call `setUserId(...)` / `setUserId(null) + clearCustomProperties()`.

### Phase 6 — Deeplink listener wiring

Use `references/deeplink-wiring.md` for the detected navigation library. Phase 6 has two parts — the OS-level scheme registration and the Amply-listener wiring — and they're verified by different commands.

**6a — Scheme registration.** Before Amply can route a Deeplink campaign action into your app, the OS has to know the scheme. iOS: `CFBundleURLTypes` in `Info.plist` (see iOS cheatsheet for the modern Xcode 14+ wrinkle — `INFOPLIST_KEY_CFBundleURLTypes` does not exist as a flat key; use a partial Info.plist). Android: `<intent-filter>` on the launcher activity. Verify with:
- iOS: `xcrun simctl openurl booted "<scheme>://test"` — exercises SwiftUI's `onOpenURL`. Failure (`OSStatus -10814`) means the scheme isn't registered.
- Android: `adb shell am start -a android.intent.action.VIEW -d "<scheme>://test" <package>`.

**6b — Amply listener wiring.** Generate the listener with the **platform-correct signature**:

- **Kotlin** — implement `tools.amply.sdk.actions.DeepLinkListener` with `fun onDeepLink(url: String, info: Map<String, Any>): Boolean`. Register via `amply.registerDeepLinkListener(listener)`. Return `true` when handled.
- **Swift** — conform to `DeepLinkListener`; `func onDeepLink(url: String, info: [String: Any]) -> Bool`. Hold a strong reference. Return `true` when handled.
- **RN** — `const unsubscribe = await Amply.addDeepLinkListener(event => { ... })`. Capture `unsubscribe` and call it on teardown.

`simctl openurl` / `adb am start` only verify 6a — the OS scheme. The Amply listener only fires when the SDK's campaign engine emits a `Deeplink` action via a configured campaign. To verify 6b end-to-end, fire the triggering event from the app and confirm the listener's `onDeepLink` was called (log it in the listener implementation; observe via OSLog on iOS, logcat on Android). **Skipping 6b verification is the #1 way a deeplink integration ships looking healthy but actually broken at runtime.**

**Listener placement note.** The listener is global to the app, not per-screen. Register it once at app startup and have it route into the navigator from there. If you attach the deeplink-handling sheet inside a screen view, deeplinks that arrive while the user is on a different screen will fire but the UI won't respond.

### Phase 7 — Verification handoff

Run the build (or defer to user — UI work needs eyes). Print exact steps to fire a test event and confirm it lands in the Amply admin panel. List remaining human-review TODOs (non-trivial wrapper merges, design questions, env-config that needs ops, consent-flow changes). If the user asks for a commit, prepare one — never auto-commit.

**Platform-specific verification checklist** (the RN flavour matters — see `references/platform-detection.md` §2).

**Always read `package.json` → `scripts.ios` / `scripts.android` first** and prefer whatever the project already uses (`yarn ios`, `yarn dev:ios`, `fastlane ios beta`, `eas build --local`, etc.). The canonical commands below are **fallbacks** for when the project has no run script — or sanity references when the existing script looks legacy / inconsistent with the project's flavour. **It is normal** for a project to have a legacy `react-native run-ios` script on iOS and a modern `expo run:android` script on Android (one was added years ago, the other recently). Don't "fix" the script as part of the Amply integration — that's a separate refactor.

- **Pure Bare RN (Flavour A)** — canonical fallback: `npx react-native run-ios` / `run-android`.
- **Bare RN + Expo Modules (Flavour B)** — canonical fallback: `npx expo run:ios` / `run:android`. They wrap Expo Modules autolinking + `pod install` + dev build. **DO NOT** run `npx expo prebuild` — `ios/` and `android/` are hand-managed and committed; `prebuild` would wipe them. **DO NOT** add the Amply config plugin to `app.json` — it would be a no-op and misleading. **DO NOT** manually `cd ios && pod install` as a first step; the run script does it.
- **Expo Prebuild Workflow (Flavour C)** — append `@amplytools/react-native-amply-sdk` to `app.json` → `expo.plugins`, then `npx expo prebuild --clean` (regenerates `ios/` and `android/`), then the project run script. Without `prebuild`, `MainApplication.kt` doesn't get the `AmplyPackage` registration and `Amply.initialize` rejects with "native module not found".
- **Expo Managed (Flavour D)** — same plugin entry as C; build via `eas build -p ios` / `-p android` so the plugin runs in EAS cloud.
- **Native iOS (Swift, no RN)** — `pod install` (or SPM resolve); verify `AmplySDK ~> 0.2.5` lands in `Podfile.lock`.
- **Native Android (Kotlin, no RN)** — Gradle sync; verify `tools.amply:sdk-android` resolves at the version pinned.
- **All platforms** — full build; verify the Amply module logs `[Amply.Sdk]` lines at debug log level. Confirm a test event lands in the Amply admin panel.

## Quick reference — SDK by platform

| Detected | Package | Cheatsheet |
|---|---|---|
| React Native (bare or Expo) | `@amplytools/react-native-amply-sdk` | `references/sdk-cheatsheet-rn.md` |
| iOS / Swift | `AmplySDK` via SPM or CocoaPods | `references/sdk-cheatsheet-ios.md` |
| Android / Kotlin | `tools.amply:sdk-android` | `references/sdk-cheatsheet-android.md` |
| Kotlin Multiplatform | `tools.amply:sdk-kmp` | `references/sdk-cheatsheet-kmp.md` |

## Common mistakes

| Mistake | Fix |
|---|---|
| Skipping Phase 0 (Context7 check). | Always check; offer to install Context7 if missing — it's free and gives live `docs.amply.tools` answers. |
| Running `npx expo prebuild` in a **Bare RN + Expo Modules** project (Flavour B). | Wipes the hand-managed `ios/` and `android/` folders. Check `git ls-files ios/ android/` first — hand-edited Swift / Kotlin means do not prebuild. Use `pod install` + Gradle sync instead. |
| Adding `"@amplytools/react-native-amply-sdk"` to `app.json` → `expo.plugins` for **Bare RN + Expo Modules** or **Pure Bare RN**. | No-op (the plugin only runs during `prebuild`, which is never run in these flavours). Misleading for future maintainers. Skip the `app.json` edit; rely on `react-native.config.js` autolinking. |
| Constructing native `AmplyConfig` without `apiKeySecret` (or without `defaultConfig`). | Both are required positional/named args on iOS / Android / KMP. RN does not need them. |
| Using `Amply.initialize(...)` on Swift / Kotlin / KMP. | RN/Expo only. Native uses instance constructors `Amply(config:)`. |
| Inventing API methods (`AmplySDK.shared.foo()`, `setDeeplinkHandler { ... }`, `AmplySDK.initialize(context, "API_KEY")`). | Use only methods documented in the platform cheatsheet. |
| Calling Amply SDK from many places instead of a wrapper. | Route through the existing analytics wrapper; fan out from there. |
| Hard-coding `appId` / `apiKeyPublic`. | Pull from `.env`, `Info.plist`, `BuildConfig`, `local.properties`. |
| Using array / nested-object Custom Property values; using DateTime on RN. | Native: `String` / `Number` / `Boolean` / `DateTime` only. RN: `string` / `number` / `boolean` only. |
| Wrapping Amply in a runtime consent gate. | Amply is a first-party product-feature SDK, not tracking analytics — consent gates are defensive over-engineering. If a user shouldn't see Amply campaigns, don't construct the SDK for them. See Phase 2.5. |
| Skipping Phase 4 because the user is in a hurry. | At minimum produce a 5-line gap list — even a short audit pays back. |
| Renaming the app's existing events to PascalCase. | Keep existing names. Translate inside the wrapper for the Amply call only. |
| Forgetting strong references — listener garbage-collected. | Listeners and the Amply instance must be retained explicitly on Swift / Kotlin. |
| Promising Amply-rendered popups, push, email, or cross-channel sends. | Only `Deeplink` and `RateReview` actions exist. Host app renders any UI. |

## Feedback

If the skill gets something wrong or is missing a vendor / framework, see `CONTRIBUTING.md`.
