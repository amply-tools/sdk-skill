---
name: amply-integration
description: Use when the user wants to integrate the Amply SDK (amply.tools) into a mobile app — React Native, Expo, iOS / Swift, Android / Kotlin, or Kotlin Multiplatform — wire campaign deeplinks, forward existing analytics events into Amply, set Custom Properties for targeting, or audit a project's product analytics for Amply's Who/When/What campaign model — and when designing or configuring an Amply campaign for an app that already has the SDK — who should see it, when, and what the targeting conditions are. Triggers include phrases like "add Amply", "install Amply SDK", "set up Amply", "integrate amply.tools", "Amply campaigns", "Amply deeplink", "Amply custom properties", "design a campaign", "set up a campaign", "campaign targeting", "who should see it", "настроить кампанию", "придумать кампанию", "таргетинг", "кому показать", "build a mini-app", "make a bottom sheet", "make a story", "сделай шторку", "сделай сторис", "собери мини-апп".
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
- The user wants to **build a Mini-app** — a bottom sheet, card, story, onboarding or survey screen Amply shows in the app — with the Amply MCP. Go straight to `references/mini-app-authoring.md`.
- The SDK is already integrated and the user wants to **design or configure a campaign** (who sees it, when, what it does). Skip the integration phases and go straight to `references/who-when-what-audit.md` — start from its *Designing a condition* rules before proposing any new Custom Property or app change.

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

## State the skill carries

The skill is a 9-phase state machine. It threads a small set of variables between phases. **These are silent internal state — never print their names or values back to the user.** Resolve each once; if a later phase observes a value that conflicts with one already set, **surface the conflict — do not silently overwrite it.**

| Variable | Type | Initial | Set when |
|---|---|---|---|
| `mode` | `autopilot` \| `interactive` | unset | § Mode — resolved once, before Phase 0 |
| `platform` | `RN` \| `iOS` \| `Android` \| `KMP` | unset | Phase 1 detection |
| `rnFlavour` | `BareA` \| `BareExpoB` \| `PrebuildC` \| `ManagedD` | unset | Phase 1 (RN only) |
| `amplyApps` | one entry per shipped platform, each `{ platform, appId, apiKeyPublic, apiKeySecret }` | unset | Phase 1b (from the Amply admin) |
| `envBlock` | the env entries assembled from `amplyApps` — two sets when the project ships both platforms | unset | Phase 1b |
| `credentialsBlocked` | `true` when Phase 1b could not obtain real values | `false` | Phase 1b (autopilot) |
| `wrapperStrategy` | `extend` \| `new` | `extend` | Phase 2 analytics audit |
| `phasesCompleted` | set of phase numbers | `{}` | appended at the end of each phase |
| `checkpointsPassed` | set | `{}` | each verification gate (6a scheme, 6b listener, Phase 7 build) |
| `feedbackConsent` | `yes` \| `no` | unset | § Phase 0.6 — asked once, opt-in, default no |
| `frictionRounds` | counter | `0` | +1 each time a verification checkpoint fails and the skill loops back to fix it |
| `rating` | 1–5 | unset | optional; only if the user volunteers one at the final feedback phase |
| `sessionId` | UUID | unset | generated once at Phase 9, just before the POST |
| `telemetrySent` | bool | `false` | set true after the Phase 9 POST (re-entry guard) |
| `curlPreApproved` | bool | `false` | set true after Phase 0.7 writes the allow-rules (Claude Code only) |

`feedbackConsent`, `frictionRounds`, `rating`, `sessionId`, and `telemetrySent` power the opt-in anonymous feedback step (Phase 0.6 consent → Phase 9 delivery). If `feedbackConsent` is not `yes`, none of them are collected or transmitted.

## Workflow

The workflow runs Phase 0 (toolchain check) once, then the nine main phases. Numbering uses `2.5` and `5.5` for sub-steps that piggyback on the preceding phase. Run all phases on a fresh integration; returning users may re-run individual phases.

**Build & verify yourself.** When a phase needs a build, a `pod install`, a Gradle sync, a scheme-registration check, or a test-event run, **the skill runs it** — via shell — and reads the result. Do **not** say *"try building and let me know if it works"* or hand the user a command to run on your behalf. Run `xcodebuild` / `npx expo run:*` / `npx react-native run-*` / `./gradlew` / `pod install` / `xcrun simctl openurl` / `adb` yourself, parse the output, and fix-then-rebuild on failure before escalating. The narrow whitelist of things that genuinely need the human — **everything else you do yourself**:

- Xcode UI-only actions — signing-team selection, a manual Product ▸ Build when no CLI scheme exists. (A package **version change** is *not* one of these: run `xcodebuild -resolvePackageDependencies` yourself and verify the resolved version — see the iOS cheatsheet's "Upgrading the SDK version". Relying on the human's "Resolve Package Versions" click leaves a stale checkout and silently ships the old binary.)
- Amply admin / App Store Connect / Play Console dashboard operations with no MCP equivalent.
- The ATT / OS permission prompt on a physical device, and visual confirmation of on-screen UI ("UI work needs eyes").
- Anything requiring a credential or 2FA the skill doesn't hold.

When something fails, **fix it yourself first** — read the error, apply the known fix from the platform cheatsheet, rebuild — and only escalate once you've exhausted the documented fixes.

### Phase 0 — Toolchain check (MCPs)

Before anything else, check two MCPs:

1. **Context7** — mirrors live `docs.amply.tools`; authoritative for SDK reference questions when present. See `references/context7-mcp.md` for detection + free install command + autonomous-mode fallback.
2. **Amply MCP** — hosted by Amply, so there is nothing to install: `claude mcp add --transport http amply https://api.amply.tools/mcp`, then the user runs `/mcp` and approves in the browser. It covers campaigns, analytics and price management, and — where the server exposes it and the user granted `apps:write` — registering projects and applications and reading their API keys (Phase 1b checks which). See `references/amply-mcp.md` for detection, the tool list, the payload traps in `campaign_create`, and the tools that no longer exist. Same autonomous-mode rule as Context7 — never add an MCP server without explicit consent.

**Tool boundary (which source for what):** use **Context7 for SDK reference** — code snippets, API signatures, version behaviour — and *never* to look up a user's account values. Use the **Amply MCP for account / backend automation** — reading projects, authoring campaigns, analytics — and *never* as a source of SDK reference. Whether it can produce an `appId` and API keys depends on the connection — Phase 1b checks, and falls back to the user when it cannot. Crossing the boundary means either fetching stale code from the backend or burning a backend round-trip on something that lives in the public docs.

### Phase 0.5 — Goal sanity check

**Before any discovery work**, restate the user's goal and map it onto what Amply actually does. The most expensive failure mode is integrating Amply for a goal it cannot serve. Use this 5-point checklist:

| Goal phrasing | Amply role | Host-app role |
|---|---|---|
| "Show a custom popup / sheet / onboarding screen" | ✅ **Mini-app** (Amply SDK 0.12.0+): a sheet, card, full screen or story built in Amply Studio and drawn by the SDK — no app release per change. ⚠ Only what Studio's components can build. | Nothing for a Mini-app beyond the deeplink listener its buttons may use. For native UI Studio can't build, Amply fires a Deeplink and the host renders the screen. |
| "A/B test which popup variant a user sees" | ⚠ partial. Amply chooses *which* action fires (per-campaign), can target on Custom Properties and event history (Amply SDK 0.6.1+). **Traffic splitting is not generally available — don't offer it.** | Host assigns the bucket (typically a coin-flip persisted in storage + pushed as a Custom Property) and renders both variants. |
| "Send a push notification / email" | ❌ Not Amply. | Use a push provider / email provider. Amply can deeplink users to a screen *after* they open the app. |
| "Throttle prompts / rate-limit asks" | ✅ Repeat Rules + Frequency Limits on the campaign. | Implement the deeplink target. |
| "Trigger an in-app action based on user history" — incl. "hasn't done X for N days" | ✅ built-in on Amply SDK 0.6.1+: audience rules target event history directly — counts, and **how long ago an event first/last happened** ("not in the last 7 days" includes never), with event property filters — alongside Custom Properties, combined with a triggering event. | Fire the events. **Don't add `last_x_at` / `x_count` properties for this** — they duplicate what the SDK already records. (Counter properties only for fleets below SDK 0.6.1 or derived state.) |

In `autopilot`, write one paragraph at the top of the audit: "Your stated goal `<X>` maps onto Amply as follows: Amply will <Y>, your app must <Z>." If any element of the goal lands in the ❌ column, surface that as the first item of the audit. The integration may still be worth doing for the parts Amply *can* do, but the team needs to know upfront where they'll need their own infrastructure.

In `interactive`, present the table to the human and ask "does this match what you want Amply for?" before continuing.

### Phase 0.6 — Anonymous feedback (opt-in)

Ask the developer **once**, with a single `AskUserQuestion`. Default to no; never pressure. Set `feedbackConsent`.

> "Mind if I send Amply one anonymous signal when this integration finishes, so the team can improve this skill? It contains **no code and nothing personal** — only the platform, the mode (autopilot/interactive), how many phases and checkpoints completed, how many troubleshooting loops happened, an optional 1–5 rating, and the skill version. It's sent to Amply once, only on success. Yes / No."

- **No** (default): set `feedbackConsent = no`. Generate nothing, count nothing for transmission, and skip Phase 9 entirely.
- **Yes**: set `feedbackConsent = yes`. From here on, increment `frictionRounds` whenever a verification checkpoint fails and you loop back to fix it (this is the only "sentiment" signal — a counter, never read from the conversation).

In `autopilot` with no human present, treat consent as **no** unless the run was explicitly started with feedback enabled.

### Phase 0.7 — Pre-approve Amply network calls (Claude Code only)

Later phases may run one or two `curl`s to Amply hosts: the opt-in telemetry POST in Phase 9 (`api.amply.tools`), and — only if a phase ever falls back to fetching public docs over HTTP — a GET to `docs.amply.tools`. On Claude Code each un-approved `curl` interrupts the run with a permission prompt. Pre-approve them **once, here**, so the integration flows uninterrupted.

**Only on Claude Code.** Detect it by the presence of a `.claude/` directory (or `CLAUDE_*` env / the host being Claude Code). On Codex, Gemini, Copilot, or any other host, **skip this phase silently** — their permission models differ and there is nothing to write.

Add the allow-rules to **`.claude/settings.local.json`** (developer-local, git-ignored) — never the team-shared `.claude/settings.json`, and never a global user file. Write `.claude/settings.local.json` if it does not exist.

The rules to ensure are present under `permissions.allow`:

- `Bash(curl -s https://docs.amply.tools *)` — always (cheap, harmless; covers the docs-fallback GET).
- `Bash(curl -s -X POST https://api.amply.tools/v1/skill-telemetry *)` — **only if `feedbackConsent == yes`.** If consent is `no`, do not add the telemetry rule; Phase 9 never fires, so there is nothing to approve.

**Idempotency is mandatory.** Read the existing `.claude/settings.local.json`, parse it, and add only the rules not already present (exact-string match against the `permissions.allow` array). If a rule is already there, leave it. Never duplicate an entry, never reorder or drop unrelated rules, and preserve the rest of the file untouched. If the file exists but isn't valid JSON, do **not** clobber it — skip this phase and note it in the audit.

The trailing ` *` (space then `*`) is required: Claude Code matches `Bash(...)` rules as a prefix glob where `*` spans the remaining arguments, newlines, and the line-continuation backslashes of the multi-line `curl`. A rule without the trailing wildcard won't match the real command and the prompt will still fire.

This phase writes config only — it never sends anything. The telemetry POST itself remains gated behind `feedbackConsent` and only runs in Phase 9.

### Phase 1 — Discovery + version gating

Identify the primary platform, package manager, and navigation library. See `references/platform-detection.md`. **Stop and warn** if the project fails any version gate (RN < 0.79, RN New Architecture not enabled, Expo SDK < 53, Android `minSdk` < 24 for RN target / < 21 for KMP, iOS deployment target < 15.1 for RN target / < 14.1 for KMP). Also record the **Amply SDK floor**: pin the version the cheatsheets' install snippets use on new integrations. Two capability floors matter for campaigns: **0.6.1+** for event-history audience targeting and **0.12.0+** for Mini-app actions — event-history audience targeting only matches apps running 0.6.1+, and devices on older SDK builds silently don't match those campaigns (not a build failure; a capability floor — see `references/platform-detection.md` §5). Echo the detected stack back as one block; ask once: "is this right?"

**For RN projects: identify the flavour precisely** — Pure Bare RN, Bare RN + Expo Modules, Expo Prebuild Workflow, or Expo Managed. The check is `git ls-files ios/ android/`: hand-managed native folders → "no prebuild ever", regardless of whether `expo` is in `package.json`. This single distinction drives whether `expo prebuild` is safe to run. (No `app.json` plugin entry is needed for Amply in any flavour — since SDK 0.2.12 the config plugin is a no-op; autolinking registers the module.)

### Phase 1b — Amply app resolution

After Phase 1 has detected `platform`, `bundleId`, and a project name, resolve the Amply application **once**, here, before any wrapper or key work in later phases.

**Every platform needs all three values** — `appId`, `apiKeyPublic` and `apiKeySecret`. The SDK signs requests on the device with the secret, so it is required on React Native / Expo too: since RN SDK 0.12.1 `initialize` rejects a config with any key missing, and Amply does not start.

**There are two paths, and you must check which one you are on rather than assume.** Provisioning over MCP is newer than the campaign tools: the server may not expose it, it needs a permission (`apps:write`) the user may not have granted, and only an organization administrator can use the creating half. Look at the tool list — if `application_create` is there, take **path A**; otherwise take **path B**. Never guess, and never tell the user an automatic option exists before you have seen the tool.

#### Path A — the MCP provisions it

Nothing leaves the editor. Read before writing, so a re-run resolves to what already exists instead of registering duplicates:

1. `projects_list` — reuse the project if one fits. Create with `project_create` only when none does: plans cap how many projects an organization may have, and the refusal is a plan limit, not a bug.
2. `applications_list` — an application is unique per `bundleId` + `platform`. If the pair is already registered, reuse it and read its keys with `api_keys_list` instead of registering again.
3. `application_create` — returns the `appId` **and** the first key pair in one call. `bundleId` must match `PRODUCT_BUNDLE_IDENTIFIER` exactly. `platform` is **case-sensitive**: `iOS` or `Android`, not `ios`/`IOS`.
4. **One application per platform.** A React Native or Expo app that ships both stores needs **two** `application_create` calls with the same `bundleId` and different `platform`, and Phase 5 wires the pair matching each platform. Sharing one pair across both is wrong even though it appears to work.

Two things that look like failures and are not: re-registering an existing `bundleId` + `platform` is **refused rather than duplicated** — that is the guard working, so read the existing application instead of retrying; and a freshly created key ingests events immediately but **campaign delivery only begins once the project's first campaign is activated**, so an empty campaign list is not a broken key.

If a create is refused because the user is not an organization administrator, **fall through to path B** and say so plainly. Retrying will not help and no other tool grants it.

#### Path B — the Amply admin UI

The MCP on this connection cannot provision, so the values come from the user. Where each comes from:

1. **Sign up or log in** at https://app.amply.tools — the organization is created with the account, and that email owns it.
2. **Create a project**, or pick an existing one.
3. **Register the application** under the project, with the `bundleId` matching `PRODUCT_BUNDLE_IDENTIFIER` exactly and the right platform. The admin returns an `appId` (a UUID, **not** the bundleId) plus the first API key.
4. **iOS and Android are two separate applications with two separate key pairs**, same as path A.

The `apiKeySecret` stays readable in the admin — the application's API-keys tab masks it on screen but the copy button yields the real value. **Do not tell the user it is shown only once, and do not have them mint a new key just to recover it.** Minting a new key leaves the previous one live, so a needless mint is an orphan credential the team has to clean up.

#### Both paths

Record one `amplyApps` entry per shipped platform and carry them into Phase 5. Also note the **project name and application name** for each, and whether it was created now or reused — that is what lets a later run tell an existing application from a missing one.

**In `interactive` mode**: on path B, ask for the values and wait — this is the one place the run genuinely cannot proceed on a default. On path A, registering the application needs no confirmation, but **creating a new project does**: it consumes one of the organization's allowance, so name the project you would reuse and let the user say whether to reuse it or add one.

**In `autopilot` mode** the Mode contract forbids the question.

* On **path A** you do not need to ask — the user authorized this when they granted the permission. Prefer reusing an existing project over creating one, and log every object you created in the audit so the team can find it.
* On **path B** no default can invent a real key. Do not halt: the wrapper, the deeplink wiring and the audit are all still worth producing. Write the env entries with values that are **obviously unfilled** — `AMPLY_APP_ID=<REQUIRED: see amply-audit.md § Blocked>` — never a plausible-looking fake, which would let the app initialize against nothing and report into the void. Record it as the run's **single blocking item at the top of the audit**, name the values this platform needs and where to get them, and say that Phase 7 cannot pass without them rather than reporting a green finish.
* Never create an Amply account, never generate a password, and never write credentials into the audit or the repository.

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
- Free-form timestamps (sub-second precision, raw event timestamps) → skip. `*_at` properties are for **state the events can't carry** — a date that comes from outside the app's events (`trial_ends_at` from RevenueCat) or happened before the SDK did. The recency of anything the app fires as an event (last paywall view, last session, last purchase) is an **event-date condition**, never a `last_x_at` property.

**Before proposing any Custom Property for a targeting rule, check whether event history already expresses it** (Amply SDK 0.6.1+, see `references/who-when-what-audit.md` § Who): how many times an event happened (six comparison ops, plus `at least once` / `never`), and **when it first or last happened** — `more than N days ago`, `not in the last N days` (includes never), `less than N days ago`, or before/after a date — narrowed by event property filters (all must match). "Hasn't opened the paywall in 7 days", "logged a workout in the last 3 days", "first purchase over a month ago" all need **zero** new properties. Mind the trigger-event trap: a condition on the *same* event as the trigger always sees the current occurrence. Propose Custom Properties from `references/custom-properties.md` only for state events can't carry (`subscription_status`, `trial_ends_at`, `onboarding_completed`, `locale`, …). `*_count` counters remain the fallback for fleets below SDK 0.6.1 and for derived state that isn't a single event (see `references/custom-properties.md` § Counter properties).

**Phase 3 gap check** — before producing § 6 (Who/When/What):

1. **Property-write ↔ event gap** — for every `*_changed` / `*_updated` event detected in Phase 2, verify a parallel property-write exists. If not, add to audit § 9.1 as Observation: "Event `X_changed` fires but no parallel property-write found; Amply campaigns targeting on `X` won't see the change."
2. **Mutable-baseline one-shot writes** — for every property-write whose key matches the mutable baseline (`subscription_status`, `plan`, `is_premium`, `total_purchases`, …) but is written at only one site (init/login), add to audit § 9.2.
3. **3rd-party bridge gaps** — for every detected 3rd-party SDK use (RC purchase, Superwall register, …) without an app-side track call in proximity, add to audit § 9.3 with the suggested wiring from `references/third-party-event-bridges.md`.

Per Scope discipline, these are **observations**, not action items. Interactive mode may offer to draft the bridges; autopilot only records.

### Phase 4 — Who / When / What readiness audit

For each candidate campaign, walk Amply's campaign model — see `references/who-when-what-audit.md`:

- **Who** — list device properties (country, OS / app version, install date — the first time Amply ran on the device), Custom Properties, event-history conditions (Amply SDK 0.6.1+ — event counts, first/last-occurrence dates, event property filters) and campaign history (seen / last seen another campaign) needed; mark which are populated vs missing (for event conditions: does the app actually fire the event?). All conditions are AND — there is no OR.
- **When** — list triggering event(s); flag whether **Event Param** rules are needed (e.g. `Purchase` filtered by `currency = "USD"`); record required keys/types. Note Repeat Rules and Frequency Limits required.
- **What** — `Mini-app` (Amply Studio screen drawn by the SDK, 0.12.0+), `Deeplink`, or `RateReview`. Reject push notifications, email/SMS and other cross-channel sends — Amply is in-app only. A Deeplink (and a Mini-app's *open deep link* button) can carry **template variables** the SDK fills in on the device — `{@campaign.id}`, `{@custom.pet_name}` and so on, Amply SDK 0.13.0+ — so "which campaign sent this user" or a property value reaches the app's router without app code (`references/deeplink-wiring.md` → *Template variables*).

Save findings as `amply-audit.md` (template: `references/audit-template.md`). This is a **suggestion document**, not a prescription.

### Phase 5 — Wrapper implementation

Use the templates in `references/wrapper-patterns.md`. Generate / patch wrapper code; preserve existing event shape; add the **platform-correct Amply call**:

- **RN/Expo** — `await Amply.track({ name, properties })` (object payload).
- **iOS Swift** — `amply.track(event: "...", properties: [...])` on the held instance.
- **Android Kotlin** — `amply.track(event = "...", properties = mapOf(...))` on the held instance.
- **KMP** — same as platform target; instance constructed in shared init.

For a **gate-able moment** (the app must wait on a campaign action before proceeding — e.g. a rewarded ad before Save/Export), use `trackGated` instead of `track` and branch on the returned decision:

- **RN/Expo** — `const decision = await Amply.trackGated(event, properties)` — never rejects; check `decision.outcome === 'proceed'` / `'cancelled'`. Register the presenter at startup: `await Amply.registerGate(baseUrl, presenter, { onAbort, timeoutMs })`.
- **iOS Swift** — `let decision = await amply.trackGated(event: "...", properties: [...])`. Match with `if case .proceed = decision` / `decision is GateDecision.Cancelled`. Register at startup: `amply.registerGate(baseUrl: ..., presenter: presenter, onAbort: .cancel, timeoutMs: 60_000)`.
- **Android/KMP Kotlin** — `val decision = amply.trackGated(event = "...", properties = mapOf(...))` (suspend). Check `decision is GateDecision.Proceed` / `GateDecision.Cancelled`. Register at startup: `amply.registerGate(baseUrl, presenter, onAbort = AbortPolicy.Cancel, timeoutMs = 60_000)`.

Per-platform signatures are in `references/sdk-cheatsheet-*.md`. Use only the methods listed there — anything else you recall is a mis-recollection.

**On native platforms (Amply SDK 0.9.0+), every registration returns a `ListenerToken` and withdrawal takes that token, not the listener object.** Keep the token wherever you keep the listener; a listener left installed after its owner is gone keeps that owner reachable for the life of the process. The RN JS API is unaffected. See *Withdrawing a listener* in each native cheatsheet.

Initialise Amply in the right place using **the platform-correct API** (see SDK cheatsheets):

- RN/Expo: `await Amply.initialize({ appId, apiKeyPublic, apiKeySecret, debug? })` (static-style module). **`apiKeySecret` is required** — without it `initialize` rejects with `AmplyConfigError` and Amply never starts.
- iOS: `let amply = Amply(config: AmplyConfig(appId:, apiKeyPublic:, apiKeySecret:, defaultConfig: nil))` — **`apiKeySecret` is required**; strong reference held by app.
- Android: `val amply = Amply(config = AmplyConfig(appId, apiKeyPublic, apiKeySecret, defaultConfig = null), application = this)` — **`apiKeySecret` is required**; held on `Application`. Or use the `amplyConfig { api { ... } }` builder DSL.

Pull keys from env / build config. **Refuse** to write keys inline — even if the project's own precedent hard-codes other vendors' keys (RevenueCat / Amplitude / etc.) inline. For projects with no existing env-loading pipeline, do one of: (a) suggest adding `react-native-config` / `EXPO_PUBLIC_*` / `BuildConfig` field, and write the Amply call against it with a clear TODO at the call-site; (b) document the choice prominently in the audit and let the user wire env loading on their own next pass. Never silently inline an Amply key just because the project does it elsewhere — `apiKeySecret` in particular must be treated as a real secret.

**Source of the keys:** by the time Phase 5 runs, Phase 1b has already collected the `amplyApps` entries from the Amply admin. Use them as-is — the right entry for the platform being wired, and the secret only where the platform requires it. Never re-derive or guess them here, and never commit them: they belong in the project's ignored env file.

If `credentialsBlocked` is `true` (autopilot could not ask), still generate the initialization code — it is correct and reviewable — but leave the env entries at their `<REQUIRED: …>` markers, and do not report Phase 5 as verified. The code is right; the credentials are missing, and those are different claims.

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

Run the build **yourself** — per the *Build & verify yourself* contract above, the compile / `pod install` / Gradle sync is never handed to the user; only the on-screen visual confirmation ("UI work needs eyes") is. Print exact steps to fire a test event and confirm it lands in the Amply admin panel. List remaining human-review TODOs (non-trivial wrapper merges, design questions, env-config that needs ops, consent-flow changes). If the user asks for a commit, prepare one — never auto-commit.

**Platform-specific verification checklist** (the RN flavour matters — see `references/platform-detection.md` §2).

**Always read `package.json` → `scripts.ios` / `scripts.android` first** and prefer whatever the project already uses (`yarn ios`, `yarn dev:ios`, `fastlane ios beta`, `eas build --local`, etc.). The canonical commands below are **fallbacks** for when the project has no run script — or sanity references when the existing script looks legacy / inconsistent with the project's flavour. **It is normal** for a project to have a legacy `react-native run-ios` script on iOS and a modern `expo run:android` script on Android (one was added years ago, the other recently). Don't "fix" the script as part of the Amply integration — that's a separate refactor.

- **Pure Bare RN (Flavour A)** — canonical fallback: `npx react-native run-ios` / `run-android`.
- **Bare RN + Expo Modules (Flavour B)** — canonical fallback: `npx expo run:ios` / `run:android`. They wrap Expo Modules autolinking + `pod install` + dev build. **DO NOT** run `npx expo prebuild` — `ios/` and `android/` are hand-managed and committed; `prebuild` would wipe them. **DO NOT** add the Amply config plugin to `app.json` — it's a no-op in every flavour (see the Common Mistakes row). **DO NOT** manually `cd ios && pod install` as a first step; the run script does it.
- **Expo Prebuild Workflow (Flavour C)** — no `app.json` plugin entry needed (since SDK 0.2.12 the Amply config plugin is a no-op; autolinking registers the module). Run `npx expo prebuild --clean` (regenerates `ios/` and `android/` and wires the module in via autolinking), then the project run script. `prebuild` itself is still mandatory: without it there are no up-to-date native projects and `Amply.initialize` rejects with "native module not found".
- **Expo Managed (Flavour D)** — no plugin entry needed either; build via `eas build -p ios` / `-p android` (prebuild + autolinking run in EAS cloud).
- **Native iOS (Swift, no RN)** — `pod install` (CocoaPods) or `xcodebuild -resolvePackageDependencies` (SPM). Verify the resolved version actually landed: CocoaPods → `AmplySDK` at the pinned version in `Podfile.lock`; SPM → both `Package.resolved` *and* the `SourcePackages/checkouts/amply-sdk-ios` tag (a stale binary-target cache keeps the old `.xcframework` even when the pin looks right). For a version *bump*, follow the cheatsheet's "Upgrading the SDK version" and the cross-platform note below.
- **Native Android (Kotlin, no RN)** — Gradle sync; verify the *resolved* version with `./gradlew :app:dependencyInsight --dependency tools.amply:sdk-android` (not just the declared literal — a force/BOM can override it). For a version *bump*, see the cheatsheet's "Upgrading the SDK version" and the cross-platform note below.
- **All platforms** — full build; verify the Amply module logs `[Amply.Sdk]` lines at debug log level. Then confirm a test event lands in the Amply admin panel.

**Two checks, and only one of them is yours.** The `[Amply.Sdk]` log lines you can read yourself — do that, and treat their absence as a failure. Whether the event actually *arrived* is visible only in the admin panel, and no MCP tool exposes raw events or session payloads, so you cannot check it: `statistics_active_users` reports daily totals, not "did my test event land". Print the steps, ask the human to look, and **do not record Phase 7 as passed until they say it arrived.** Reporting a green finish because the build compiled is how an integration ships that reports nothing — the exact failure this phase exists to catch.

**Version bumps (any platform).** The per-flavour checks above confirm the SDK is *present*; a **version change** has its own failure mode and is **not** done when the manifest pin is edited. On every platform a dependency cache — SwiftPM `SourcePackages`, CocoaPods, Gradle `~/.gradle/caches`, npm `node_modules` + Metro — can keep serving the **old** binary while the pin *looks* correct, and for a shipped app a pin edit that's never rebuilt + re-released changes nothing users run. So after any bump: **(1)** force a real re-resolve / re-fetch — don't trust an incremental IDE sync or a human "Resolve Package Versions" click; **(2)** verify the *resolved* version at both the manifest **and** the fetched / native layer; **(3)** rebuild and, for a shipped app, re-archive / upload; **(4) confirm at runtime** that the running build reports the expected `sdkVersionNormalized` in its session payload (Amply admin) — the one check identical on every platform, and the only one that catches a stale binary or a JS-vs-native mismatch the build can't. Per-platform resolve + verify commands: each `references/sdk-cheatsheet-<platform>.md` → **"Upgrading the SDK version"**. (SDK ≤ 0.5.0 hard-coded `sdkVersionNormalized` to `1.0.0`, so the runtime assertion is only meaningful for builds ≥ 0.5.1; below that, fall back to the per-platform resolved-version check.)

### Phase 8 — What's next (activation)

Run this **once, only after Phase 7 verification passes** (a test event has landed in the admin panel). The integration itself is done; this step turns "SDK installed" into "first campaign live," while the context is fresh. **Only offer capabilities that exist today** — in particular do **not** promise A/B variant splitting; Amply does not split traffic (see Phase 0.5), and that surface isn't available.

**`interactive` mode** — present one short `AskUserQuestion` menu, skippable with a single reply:

- **Create your first campaign now** — author it in **Draft** and let the user activate after review.
  - If the **Amply MCP is connected**, call `campaign_create` — there are no templates, so author the campaign in full from the Who/When/What candidates already in the Phase 4 audit. Read the server's campaign targeting reference resource first for the vocabulary, and `references/amply-mcp.md` for the payload traps (`snake_case` keys, the required `triggering.limit`, and targeting being one flat all-must-match list). **Targeting over MCP now reaches everything the admin has** — country, application, app version, OS version, the app version at install, custom properties, install date, and event history — and a trigger carries its **event parameter filters**, so a `CustomPropertyChanged` campaign filtered on `key` and `newValue` is expressible here rather than only in the admin. Check the tool schema rather than this list if the two ever disagree; the server is right.
    **`campaign_create` always produces a Draft.** `campaign_update` exists, but it **replaces the campaign in full** and returns it to Draft, and there is still no clone and no delete — so a draft created by mistake has to be removed by hand in the user's campaign list. Get the payload right on the first call: state the intended audience and trigger back to the user in one line before sending it.
    **When the campaign's What is a Mini-app**, build it over MCP first — `mini_app_create` from a one-line brief the user confirms, show them `editor_url`, `mini_app_publish`, then `campaign_create` with `type: "miniApp"` and the returned `campaign_content`. Pipeline, surface choice and design rules: `references/mini-app-authoring.md`.
  - If the **MCP is not connected**, point the user to the admin UI (`app.amply.tools`) and build the campaign from the Who/When/What candidates already in the Phase 4 audit (`amply-audit.md`) + `references/who-when-what-audit.md`.
- **Done** — end the session.

**`autopilot` mode** — do **not** prompt (the Mode contract forbids questions). Instead append a one-line recommendation to the audit: the single best-fit campaign for this app (its audience, trigger and content, concretely) the team can create in one MCP call or in the admin. A recommendation, not an action taken.

### Phase 9 — Anonymous feedback delivery (opt-in)

Run this **only** on a successful finish **and** only if `feedbackConsent == yes`. Send exactly once.

1. If `telemetrySent` is already true, do nothing (re-entry guard).
2. Generate `sessionId` once — a random UUID v4. Do not regenerate on a retry.
3. Map the skill's `platform`/`rnFlavour` to the wire value: `iOS`→`ios`, `Android`→`android`, `KMP`→`kmp`, RN→`expo` when `rnFlavour` is an Expo flavour (`BareExpoB`/`ManagedD`) else `react-native`.
4. Send one POST (a single `curl`; on Claude Code Phase 0.7 already pre-approved it, so no prompt fires — on other hosts it may prompt once):

   ```bash
   curl -s -X POST https://api.amply.tools/v1/skill-telemetry \
     -H 'Content-Type: application/json' \
     -H 'X-Skill-Token: amply-skill-integration' \
     -d '{
       "session_id": "<sessionId>",
       "platform": "<ios|android|react-native|expo|kmp>",
       "mode": "<autopilot|interactive>",
       "phases_completed": <count of phasesCompleted>,
       "checkpoints_passed": <count of checkpointsPassed>,
       "friction_rounds": <frictionRounds>,
       "rating": <1-5; omit this field entirely if the user gave no rating>,
       "skill_version": "<this skill version>"
     }'
   ```
5. Set `telemetrySent = true`. Ignore the HTTP response — never retry, never surface an error. The integration is already complete; this is a fire-after-success ping.

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
| Adding `"@amplytools/react-native-amply-sdk"` to `app.json` → `expo.plugins` — **any flavour**. | Not needed since SDK 0.2.12: the config plugin is a no-op pass-through; RN autolinking (`react-native.config.js`) registers the module everywhere, including during `prebuild`. Harmless if already present (the SDK prints a removal notice during `prebuild`) — remove the entry when you next touch `app.json`. |
| Initializing without `apiKeySecret` — on **any** platform, RN included. | Required everywhere: native `AmplyConfig` won't build without it (plus `defaultConfig` on iOS / Android / KMP), and RN `initialize` rejects (0.12.1+) or crashed (earlier). |
| Using `Amply.initialize(...)` on Swift / Kotlin / KMP. | RN/Expo only. Native uses instance constructors `Amply(config:)`. |
| Inventing API methods (`AmplySDK.shared.foo()`, `setDeeplinkHandler { ... }`, `AmplySDK.initialize(context, "API_KEY")`). | Use only methods documented in the platform cheatsheet. |
| Calling Amply SDK from many places instead of a wrapper. | Route through the existing analytics wrapper; fan out from there. |
| Hard-coding `appId` / `apiKeyPublic`. | Pull from `.env`, `Info.plist`, `BuildConfig`, `local.properties`. |
| Using array / nested-object Custom Property values; using DateTime on RN. | Native: `String` / `Number` / `Boolean` / `DateTime` only. RN: `string` / `number` / `boolean` only. |
| Wrapping Amply in a runtime consent gate. | Amply is a first-party product-feature SDK, not tracking analytics — consent gates are defensive over-engineering. If a user shouldn't see Amply campaigns, don't construct the SDK for them. See Phase 2.5. |
| Skipping Phase 4 because the user is in a hurry. | At minimum produce a 5-line gap list — even a short audit pays back. |
| Renaming the app's existing events to PascalCase. | Keep existing names. Translate inside the wrapper for the Amply call only. |
| Forgetting strong references — listener garbage-collected. | Listeners and the Amply instance must be retained explicitly on Swift / Kotlin. |
| Firing `track` / `setCustomProperties` before init finishes (init not `await`ed). | The first events race the SDK construction and are dropped. Initialise (and `await` it on RN/Expo) **before** any `track`; see Phase 5.5. |
| Calling `setUserId` after the first `track` of a session. | Early events land on the anonymous profile and never re-attribute. Set the user id at session start / right after login, before the first wrapper `track`. |
| Registering the deeplink listener too late (after first frame / inside a screen). | A cold-start deeplink fires before the listener exists and is lost. Register once at app startup, globally — not per-screen (see Phase 6 listener-placement note). |
| Editing a published mini-app and stopping there. | A campaign shows the version it was given. Re-publish, then `campaign_update` the campaign to the new `campaign_content`. |
| Promising push, email, cross-channel sends, or arbitrary native UI drawn by Amply. | Actions are `Mini-app` (what Amply Studio can build, SDK 0.12.0+), `Deeplink` and `RateReview`. Anything Studio can't build is a host screen behind a Deeplink. |
| Adding a `last_x_at` / `x_count` Custom Property for "hasn't done X in N days" / "did X N times". | Use the built-in event conditions (`last happened not in the last N days`, counts) — the SDK already records the history. Properties only for state events can't carry. |
| Putting "last happened more than N days ago" on the **same** event as the trigger. | The trigger occurrence is recorded first, so it always reads "just now". Put the recency on a different event (e.g. trigger `SessionStarted`, condition on `SessionFinished` or the core value event). |
| Writing an audience with OR. | Targeting is AND-only. Split into two campaigns. |
| Assuming Install Date is the app install date. | It is when Amply first ran on the device. For an app that added Amply recently, "installed more than 30 days ago" matches nobody for 30 days. |

## Feedback

If the skill gets something wrong or is missing a vendor / framework, see `CONTRIBUTING.md`.
