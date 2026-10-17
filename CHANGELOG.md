# Changelog

All notable changes to `amply-integration` are documented here. Format follows [keepachangelog.com](https://keepachangelog.com/en/1.1.0/); versioning is [SemVer](https://semver.org/spec/v2.0.0.html).

## [0.16.0] — Unreleased

### Added
- **Every campaign gets a goal** (`SKILL.md` Phase 0.5 / Phase 4 / Phase 8 / *Common mistakes*, `references/who-when-what-audit.md` → *Goal*, `references/audit-template.md`). A primary goal plus up to 4 secondaries, each with a window — in-app nudges 1–24 h, winback 1–3 d, trial → paid up to 30 d. A property change (entitlement became `true`) is a goal with no purchase event; several SKUs are one goal with the goal-only `one of` operator; a What's New campaign targets "`X` has never happened" so any later `X` is a first use. Goals are computed by Amply from events the app already sends — no SDK floor, no app release. Every use-case recipe now names its goal.
- **Campaign attribution in the app** (`references/campaign-attribution.md`, new). Put `amply_campaign_id` / `amply_campaign_name` on the purchase event — from the deeplink handler's `info` or `{@campaign.id}` / `{@campaign.name}` in the link, else `getLastCampaignTouch(withinMs)` (**SDK 0.15.0+**) for purchases made elsewhere — and send the same event to Amply and to the app's own analytics. Forward `CampaignShown` / `CampaignResolved` (both carry `campaignName` on **SDK 0.15.0+**) from the app's **existing** system-events listener: on native the SDK keeps one, and a second registration replaces it.
- **Show after** (`references/who-when-what-audit.md` → *Show after*, `SKILL.md` Phase 4). A 0–3 s pause between the trigger and the show (**SDK 0.15.0+**; older SDKs show immediately), with its rules in one paragraph: re-checked before showing, dropped rather than queued, no impression for a dropped show, ignored by `trackGated`.
- **MCP** (`references/amply-mcp.md`): `goals_list`, `goal_create`, `goal_update`; `goals` on `campaign_create` / `campaign_update` / `campaign_get` (omitting it on update keeps the goals; `{}` clears them); `conversions` per bound goal in `campaign_statistics` (non-exclusive — never add campaigns up); `triggering.delay_ms` (0–3000, steps of 100).
- `getLastCampaignTouch` in all four cheatsheets (**SDK 0.15.0+**); `campaignName` and the *Show after* `Skipped*` results in `references/system-events.md` (**SDK 0.15.0+**).

### Fixed
- **The iOS system-events snippet named a method that does not exist** (`references/sdk-cheatsheet-ios.md`). It showed `onSystemEvent(...)`; the protocol declares `onEvent(event: EventInterface)`.

## [0.15.0] — 2026-10-16

### Added
- **App language** (`SKILL.md` Phase 5, platform cheatsheets, *Common mistakes*). Apps that pick their language themselves (in-app switcher, i18next / JS translations) call `setAppLanguage(tag)` — RN `Amply.setAppLanguage(i18n.language)` wired to `languageChanged`, native `setAppLanguage(tag:)` / `appLanguage` in `AmplyConfig` — so sheets, stories and mini-apps show the matching translation and the **App language** targeting rule works (Amply SDK 0.14.0+). Any tag form works (`pt-BR`, `pt_BR`, `zh-Hant`).

## [0.14.0] — 2026-10-16

### Added
- **Build Mini-apps over MCP** (`references/mini-app-authoring.md`, new). With the Amply MCP connected, an agent builds a bottom sheet, card, story or full-screen flow from a plain description (`mini_app_create`), edits it by id (`mini_app_update`), publishes it (`mini_app_publish`) and attaches it to a draft campaign — no admin round trip. The page covers the pipeline, which surface fits which ask, what makes the result look like the app, action order, editing a mini-app built by hand, and the traps (a campaign keeps the version it was given). The exact vocabulary stays on the server (`amply://mini-app/authoring-reference`).
- Mini-app tools in the MCP table (`references/amply-mcp.md`), a Phase 8 path for a Mini-app What, and build-a-mini-app triggers in the description ("make a bottom sheet", "сделай шторку", "сделай сторис", …).
- What makes a generated mini-app look designed (`references/mini-app-authoring.md`): what the platform cannot do is stated up front, "a screen" means full screen, brand colours are given for light and dark, a full screen pins its call to action in `footer` (content scrolls under it and fades out), and the server's *Design rules* are read before writing.

### Changed
- `type: "miniApp"` campaigns take `content` straight from `mini_app_publish`; the "the MCP cannot author or publish a Studio document" caveat is gone from `amply-mcp.md` and `who-when-what-audit.md`.

## [0.13.2] — 2026-10-16

### Added
- **Template variables in campaign links** (`SKILL.md` Phase 3 What, `references/deeplink-wiring.md`, `references/amply-mcp.md`). A Deeplink — or a Mini-app's open-deep-link button — can carry `{@campaign.id|name|type}`, `{@custom.<key>}`, `{@device.…}` and `{@triggeredEvent.…}`, filled in by the SDK on the device (Amply SDK 0.13.0+; older app versions do not receive such a campaign). Values are percent-encoded, a missing value becomes empty, tokens never go in the scheme or host.

### Changed
- **Install pins bumped to 0.13.0** (native and RN `^0.13.0`). The 0.13.0 CocoaPods spec declares iOS 15.0 (Xcode 27 no longer builds for 14.0); React Native already required 15.1.

## [0.13.1] — 2026-10-15

### Fixed
- **The skill installs again with `npx skills add`.** 0.13.0's description contained a colon followed by a space, which strict YAML parsers read as a nested mapping; the `skills` CLI skipped the file and reported "No valid skills found". The description is unchanged apart from that punctuation.

## [0.13.0] — 2026-10-15

### Fixed
- **React Native needs `apiKeySecret` too** (`SKILL.md` Phase 1b / Phase 5 / Common mistakes, `references/sdk-cheatsheet-rn.md`). The skill said the secret was optional and unused on RN. Since RN SDK 0.12.1 `initialize` rejects a config with any key missing and Amply does not start (earlier versions crashed in the native config builder). Integrations that followed the old text shipped without Amply.
- **"Hasn't done X for N days" is a built-in event condition, not a property** (`SKILL.md` Phase 0.5 / Phase 3, `references/who-when-what-audit.md`, `references/custom-properties.md`, `references/property-writes.md`). The baseline catalogue proposed `last_paywall_view_at` and the reactivation recipe prescribed a `last_session_at` property, which taught agents to ask for app changes the SDK already covers. New *Recency recipes* table maps common asks to `first/last happened` conditions, including "…or never".
- **The trigger-event trap is documented.** The triggering occurrence is recorded before the audience is evaluated, so "last happened more than N days ago" on the trigger event never matches and counts include the current occurrence.
- **Install Date / App Install Version are when Amply first ran on the device**, not the app install — for an app that added Amply later, "installed more than 30 days ago" matches nobody for 30 days. The catalogue's `install_date` / `app_version_at_install` rows now say when an app-set copy is still worth it.
- **No OR in targeting**: the RateReview recipe's "… OR `nps_score >= 9`" was not expressible; the recipes no longer use `AppOpened` (which the skill elsewhere tells agents to drop in favour of `SessionStarted`).
- **MCP reference matches the live tools** (`references/amply-mcp.md`, `references/system-events.md`): `campaign_get` output can be carried straight back into `campaign_update`; `triggering.limit` is omitted for no limit; trigger parameter filters work over MCP, so the `CustomPropertyChanged` recipe no longer sends agents to the admin; relative `install_date` `greater` means older.

### Added
- **Mini-app action** (`SKILL.md`, `references/who-when-what-audit.md`, `references/amply-mcp.md`). The skill said Amply draws no UI and has two actions; there are three. A Mini-app is a sheet, card, full screen or story built in Amply Studio and drawn by the SDK (0.12.0+), with button actions (record event, open deep link, request review, save answers as properties, navigate, close). The MCP attaches a published Studio document but cannot author one.
- **Campaign history condition** (seen / first seen / last seen another campaign) in Who.
- **Campaign-design triggers** in the description ("design a campaign", "campaign targeting", "who should see it", Russian equivalents) and a *Designing a condition* checklist: event history first, a Custom Property only for state events can't carry, a missing property makes a condition false.
- `CampaignResolved` in the system-events table; `campaign_statistics` semantics in the MCP table.

### Changed
- **Install pins bumped to 0.12.0** (native) **and ^0.12.1** (RN); capability floors: 0.6.1 event history, 0.12.0 Mini-apps.

## [0.12.0] — 2026-07-30

### Changed
- **Native listener registration takes a token as of Amply SDK 0.9.0** (`references/sdk-cheatsheet-ios.md`, `-android.md`, `-kmp.md`, `SKILL.md`). Every registration — deeplink, system events, log, gate — now returns a `ListenerToken`, and withdrawal takes that token instead of the listener object. Each native cheatsheet gains a *Withdrawing a listener* section covering who actually has to withdraw (anything shorter-lived than the process), where to do it on iOS (the host's explicit teardown hook, **not** `deinit`, which will not run while the SDK holds the reference), and that reclamation after withdrawal is garbage-collected rather than immediate — so a test must not assert prompt deallocation. `unregisterGate` is new: before it, a gate registered by a host that went away parked the next gated call on that URL for the whole fail-open timeout, with nothing on screen.
- **Install pins bumped to `0.9.0`** in all four cheatsheets. The native examples do not compile against 0.8.x. The 0.6.1 event-history floor is unchanged and satisfied by 0.9.0.
- **The Amply MCP is now hosted by Amply, and the skill talks to it over HTTP with OAuth** (`references/amply-mcp.md` rewritten, `SKILL.md` Phase 0). There is nothing to install and no local process: `claude mcp add --transport http amply https://api.amply.tools/mcp`, then the user runs `/mcp` and approves in a browser. The previous local npm server is retired — its endpoint returns 404 and every published version is deprecated, so a skill run that followed the old instructions could not connect at all. The reference now also documents detection ("listed" is not "usable" — an unapproved server answers every call with an authorization error), the tool names, and the errors worth handling.
- **Phase 1b now has two paths and checks which one it is on** (`SKILL.md`, `references/audit-template.md`). Where the server exposes provisioning and the user granted the permission for it, the skill registers the project and application and reads the keys itself, and the integration never leaves the editor. Where it does not — the tools are newer than the campaign ones, need their own permission, and the creating half needs an organization administrator — it asks the user and says where each value comes from. The skill checks the tool list rather than assuming, because an absent tool means any of those three things and the fallback is the same in all of them. Either way it now asks only for what the platform uses: the secret key is required on native iOS/Android/KMP and unused on React Native, which the previous text ignored. Both paths treat iOS and Android as two applications with two key pairs, and neither wires placeholder keys — an integration built on placeholders compiles, runs, and silently reports nothing.
- **Phase 8 authors the first campaign in full rather than from a template** (`SKILL.md`). Campaign templates were a feature of the old server and have no successor, so the phase now calls `campaign_create` directly and points at the server's own targeting reference for the vocabulary.

### Fixed
- **The React Native pin note no longer undersells 0.9.0** (`references/sdk-cheatsheet-rn.md`). 0.9.0 fixes a use-after-free that crashed the app on every JS bundle reload in development. The note now says so, and says plainly that **the JS API is unchanged** — the fix lives entirely in the native bridge — so an RN integrator has a reason to upgrade and nothing to migrate.
- **The skill no longer claims an API key secret can be seen only once** (`SKILL.md` Phase 1b). It stays readable in the admin — the keys tab masks it on screen but the copy button yields the real value. The old warning pushed users to mint a replacement key to "recover" a secret they already had, and because minting leaves the previous key live, each needless mint left an orphan credential behind.
- **The `CustomPropertyChanged` campaign recipe no longer sends agents to the MCP** (`references/system-events.md`). What makes that trigger useful is its Event Param filters, and `campaign_create` cannot express them — it accepts an event name and type and nothing else. A campaign built over MCP would fire on *every* property change the app reports rather than the one named, which is worse than no campaign. The recipe now says to author it in the admin.

### Removed
- **Sixteen tool names that no longer exist** were dropped from the skill and are listed once, explicitly, as do-not-call: the authentication set (`amply_login` / `amply_logout` / `amply_status` / `amply_whoami` / `amply_signup`), the provisioning set (`amply_ensure_app`, `amply_create_project`, `amply_list_applications`, `amply_find_application`, `amply_get_application`, `amply_create_application`, `amply_create_api_key`), and the campaign set (`amply_update_campaign`, `amply_describe_targeting`, `amply_set_campaign_state`, `amply_create_campaign_from_template`). Naming them is deliberate: an agent that has seen an older copy of this skill will otherwise keep reaching for them.
- **The autonomous account-creation path is gone.** The skill previously offered, as its autopilot default, to sign a user up with a generated email and password and log those credentials into the audit file. The tool behind it no longer exists, and the behaviour should not come back in another form.

### Security
- **The skill now states the one thing revoking a connection does not undo** (`references/amply-mcp.md`). Disconnecting invalidates the connection and its tokens; it does not invalidate an SDK API key obtained through it, which keeps working until someone deletes it in Amply. So the guidance is to mint a key only when the integration needs one and to prefer reading an application's existing keys over adding another — a spare key is a long-lived credential nobody is tracking.

### Fixed
- **The Android system-events snippet named a method that does not exist** (`references/sdk-cheatsheet-android.md`). It showed `override fun onSystemEvent(...)`; the interface declares `onEvent(event: EventInterface)`. An agent following it wrote code that does not compile. Caught while updating the same file for 0.9.0.

## [0.10.2] — 2026-07-26

### Fixed
- **`track` vs `trackEvent` on React Native no longer reads as a contradiction** (`references/sdk-cheatsheet-rn.md`). The RN API table listed only `Amply.track({ name, properties? })`, while a note a few lines below announced that `trackEvent` had been "removed" — so an agent reading the cheatsheet would conclude `Amply.trackEvent` does not exist, then find it exported by the installed package and either distrust the cheatsheet or rewrite working call sites. The table now carries both: `track` (object payload) as the canonical form to write in new code, and `trackEvent(event, properties?)` as its positional alias — same behaviour, same shape as `trackGated` — with an explicit "leave existing call sites alone". The Common Mistakes entry about positional arguments now names which of the two accepts them instead of calling the shape unsupported.

### Removed
- **Pre-0.5.0 migration notes dropped** from `SKILL.md`, all four platform cheatsheets, and `references/wrapper-patterns.md`. They described an SDK entry point that no released integration path ever exposed, so they only ever added noise for readers who could not have used it — and were the source of the `trackEvent` contradiction above. The gate API (`trackGated` + `registerGate`) is documented on its own terms; `SKILL.md` now closes that section by pointing at the per-platform cheatsheets as the only authority for method names.

## [0.10.1] — 2026-07-19

### Fixed
- **Expo config plugin guidance corrected** (`references/sdk-cheatsheet-rn.md`, `SKILL.md` flavour instructions + Common Mistakes): the skill still instructed Expo Prebuild / Expo Managed integrations to add `"@amplytools/react-native-amply-sdk"` to `app.json` → `expo.plugins`, while the plugin has been a documented no-op since SDK 0.2.12 — React Native autolinking (`react-native.config.js`) registers the native module in every flavour, including during `expo prebuild`. Integrators following the skill then saw the SDK's own "you can safely remove this plugin" notice on every prebuild. The skill now says: no plugin entry in any flavour; an existing entry is harmless — remove it when next touching `app.json`; `prebuild` itself remains mandatory for Flavour C (it regenerates the native projects where autolinking runs).

## [0.10.0] — 2026-07-18

### Added
- **Event-history targeting (Amply SDK 0.6.1+)** — campaign audience rules now target events directly, and the skill's Who-model documentation gains it as a third targeting source alongside Device properties and Custom Properties (`references/who-when-what-audit.md`): occurrence counts (`how many times`: `exactly` / `not exactly` / `more than` / `fewer than` / `at least` / `at most`, plus `has happened` (ever) / `has never happened`), `first occurrence` / `last occurrence` dates — relative (`more than N days ago` with an "…or never" variant, `within the last N days`) and absolute (`before` / `after` a date, whole UTC days) — and event property filters (equals / not-equals for text, plus greater / less for numbers) applying to both counts and dates. Up to 20 event conditions per campaign; only apps running Amply SDK 0.6.1+ match; history starts at install; evaluated on-device, offline.
- **Amply SDK floor axis** in Phase 1 discovery (`SKILL.md`, `references/platform-detection.md` §5, audit template §1): the skill now records the project's pinned Amply SDK version as a capability floor — devices below 0.6.1 silently don't match event-condition campaigns (not a build failure).
- **Third-party bridge pitch strengthened** (`references/third-party-event-bridges.md`): a forwarded event is now an audience condition too, not just a trigger — e.g. *"`Purchase` happened at least 2 times"*, *"first `PaywallShown` more than 7 days ago"*.

### Changed
- **Counter Custom Properties reframed as the fallback, not the pattern** (`references/custom-properties.md`, `SKILL.md` Phase 3, `references/property-writes.md`, `references/event-naming.md`, audit template): "user fired event X N times" is built-in targeting on Amply SDK 0.6.1+; `*_count` counters remain correct for fleets with older installed builds and for derived state that isn't a single event. The `CustomPropertyChanged` guidance (property-change triggering) is unrelated and unchanged.
- **MCP catalog reconciled with `@amplytools/amply-mcp`** (`references/amply-mcp.md`): added the missing `amply_list_campaigns`, `amply_get_campaign`, `amply_set_campaign_state`, and `amply_create_campaign_from_template` rows (the tools SKILL.md Phase 8 already relies on); `amply_create_campaign` / `amply_describe_targeting` rows now describe event-history targeting slots.
- **SDK install pins bumped to 0.6.1** in all four platform cheatsheets (Gradle coordinates, SPM `from:`, CocoaPods constraint, npm version), each with a one-line 0.6.1-floor callout. Gate-API sections keep their accurate "(SDK 0.5.0+)" headings.
- README distribution section updated to the current model: plugin installs via the `amply-tools/claude-plugins` catalog repo; the plugin subtree holds real copies regenerated by `scripts/sync-plugin.sh` (no root `marketplace.json`, no symlinks).

## [0.9.0] — 2026-06-10

### Added
- **SDK version-upgrade gate (all platforms)** — a new cross-platform "Version bumps (any platform)" note in Phase 7 plus an "Upgrading the SDK version" section in every platform cheatsheet (iOS SPM **and** CocoaPods, Android / Gradle, React Native, KMP). Changing a version pin does **not** take effect until a forced re-resolve: every platform has a dependency cache (SwiftPM `SourcePackages`, CocoaPods, Gradle `~/.gradle/caches`, npm `node_modules` + Metro) that keeps serving the old binary while the pin *looks* correct, and a pin edit that's never rebuilt + re-released changes nothing users run. Per platform the skill now forces a real re-resolve / re-fetch (never deferring to an incremental IDE sync or the human's "Resolve Package Versions" click), verifies the **resolved** version at both the manifest and the fetched / native layer (SPM checkout tag, `Podfile.lock`, Gradle `dependencyInsight`, RN JS + native both), rebuilds + re-ships, and — the one check identical on every platform — confirms the running build reports the expected `sdkVersionNormalized` in its session. RN's two-layer (JS vs native) mismatch and Android's forced / BOM override are called out explicitly.

### Changed
- Phase 7 verification no longer cites a stale pinned iOS version; the "Resolve Package Versions" Xcode-UI action is reclassified as an agent-run CLI resolve, and the Android check now asserts the *resolved* version (`dependencyInsight`) rather than the declared literal.

## [0.8.0] — 2026-06-03

### Changed
- **Plugin marketplace moved to a dedicated catalog repo** to remove install-command confusion. The Claude Code marketplace now lives at `amply-tools/claude-plugins` (marketplace name `amply`) and references this repo's plugin via a `git-subdir` source. New install commands:
  - `/plugin marketplace add amply-tools/claude-plugins` (registers Amply's plugin catalog — installs nothing)
  - `/plugin install amply-integration@amply` (installs the skill)
  The previous form (`/plugin marketplace add amply-tools/sdk-skill`) read like it was installing the skill; the catalog repo makes step 1 clearly "add Amply's catalog". The `npx skills add amply-tools/sdk-skill` path is unchanged.
- **Plugin subtree now holds real file copies, not symlinks.** A cross-repo `git-subdir` sparse clone can't follow symlinks into the repo root, so `plugins/amply-integration/skills/amply-integration/` contains real copies of `SKILL.md` + `references/`, regenerated from the canonical root by `scripts/sync-plugin.sh`. `scripts/sync-plugin.sh --check` is a release gate that fails on drift. The root `SKILL.md` remains the single source of truth.

### Removed
- `.claude-plugin/marketplace.json` from this repo (the catalog moved to `amply-tools/claude-plugins`).

## [0.7.0] — 2026-06-02

### Added
- **Claude Code plugin distribution** — the repo now doubles as a single-plugin Claude Code marketplace: `.claude-plugin/marketplace.json` at the root plus `plugins/amply-integration/` (its own `.claude-plugin/plugin.json`, with the skill symlinked from the canonical root `SKILL.md` + `references/` so there is a single source of truth). Install with `/plugin marketplace add amply-tools/sdk-skill` then `/plugin install amply-integration@amply`. The existing `npx skills add` path is unchanged — verified the `skills` CLI still reports "Found 1 skill" with the plugin tree present (default and `--full-depth` scans).
- **Multi-CLI install table in the README** — one-line install rows for Claude Code, Codex CLI, GitHub Copilot CLI, and Gemini CLI via the `skills` CLI's `-a <agent>` flag, plus the Claude Code plugin-marketplace one-liner.
- **Phase 0.7 — Pre-approve Amply network calls (Claude Code only)** — idempotently adds `curl` allow-rules to `.claude/settings.local.json` so later phases don't interrupt the run with permission prompts: a `docs.amply.tools` GET pattern always, and the `api.amply.tools/v1/skill-telemetry` POST pattern only when `feedbackConsent == yes`. Skipped silently on non-Claude-Code hosts. New `curlPreApproved` state variable.
- **Opt-in anonymous telemetry** (Phase 0.6 consent + Phase 9 delivery) — single anonymous success signal, off by default; no code or PII, only platform/mode/phase-counts/friction/rating/version/random id. (Shipped to `main` after the 0.6.0 tag; logged here as it lands in this release.)

### Changed
- README install section reorganised around the multi-CLI table + plugin one-liner; the old per-host prose blocks are folded into a compact "Manual install" table.

## [0.6.0] — 2026-05-30

### Added
- **State the skill carries** — an explicit silent-state variable table (mode, platform, RN flavour, app id, env block, wrapper strategy, phases completed, checkpoints passed), so the multi-phase workflow never leaves state implicit and never silently overwrites a value on conflict.
- **Phase 8 — What's next (activation)** — after verification, offer one skippable next step: create the first campaign via the Amply MCP (template-matched to the integration), or finish. Autopilot logs a one-line recommendation instead of prompting.
- Three high-frequency **Common mistakes** rows: firing `track` before init is awaited, `setUserId` after the first event of a session, and registering the deeplink listener too late (cold-start loss).
- `references/system-events.md` now points at the `deeplink-on-property-change` MCP template by name (pairs with `@amplytools/amply-mcp@0.4.0`).

### Changed
- Global **Build & verify yourself** contract: the skill runs builds / installs / scheme checks itself rather than asking the user to "try building," with a narrow human-action whitelist.
- Explicit **Context7-vs-MCP tool boundary** in Phase 0 and both MCP reference files (Context7 for SDK reference, MCP for account automation — never crossed).

## [0.5.0] — 2026-05-29

### Added
- Documented the SDK 0.5.0 gate API (`trackGated` + `registerGate`) across `SKILL.md` and the platform cheatsheets — awaiting a campaign action's outcome before the app proceeds.

## [0.3.0] — 2026-05-28

### Changed
- Coordinated with `@amplytools/amply-mcp@0.3.0`: documentation refreshed to drop `amply_bootstrap_for_app` (removed from the MCP in 0.3.0; the skill's runtime path already used `amply_ensure_app` since 0.2.0) and to document the three new MCP authoring tools available to agents: `amply_create_campaign`, `amply_update_campaign`, `amply_describe_targeting`.

## [0.2.0] — 2026-05-25

### Added

- **Mode switch** — `autopilot` vs `interactive`, resolved once at the top of the run (message arg / env var `AMPLY_SKILL_MODE` / one-time prompt). Every multi-option phase decision consults this single value.
- **Phase 1b "Amply app resolution"** — calls `amply_ensure_app` once after platform detection and produces the `envBlock` that Phase 5 consumes. Handles four statuses: `created`, `reused`, `reused_new_key`, `conflict_cross_project`.
- **Scope discipline rule** — explicit meta-rule in SKILL.md: the skill integrates Amply, does not refactor unrelated analytics or fix bugs. Items split between `## 8. Required for Amply to work` (prescriptive) and `## 9. Observations` (neutral).
- **Three-class detect** in Phase 2 — track-events, property-writes, and 3rd-party SDK uses are recognised separately with separate decision trees and audit tables.
- **Events decision tree** in `references/event-naming.md` — first-match-wins ordered rules: skip-system-overlap → skip-property-change-event → skip-pii → skip-high-cardinality → skip-bi-only → high-leverage → default-keep. Each audit row records both Decision and Why.
- **`references/system-events.md`** — the 7 SDK-fired system events + overlap aliases (`session_start` / `app_open` → `SessionStarted`, etc.).
- **`references/property-writes.md`** — full property-write decision tree with per-vendor alias table (Mixpanel `.people.set`, Amplitude `setUserProperties`, Segment `identify`, Firebase `setUserProperty`, …).
- **`references/third-party-event-bridges.md`** — RevenueCat / Superwall / Adjust / Sentry detection with suggested-bridge wiring. Per Scope discipline, autopilot only observes; interactive may offer to draft.

### Changed

- Phase 5 no longer discovers keys; consumes the pre-resolved `envBlock` from Phase 1b.
- `references/amply-mcp.md` tool table updated for `amply_find_application` (read) and `amply_ensure_app` (idempotent primary entry).
- `references/audit-template.md` restructured — events table grows `Decision` + `Why` columns; new tables for user-property writes and Mode-pinned decisions; `## 8 Required` separated from `## 9 Observations` with sub-sections for property-write↔event gaps, mutable-baseline one-shots, 3rd-party bridge gaps, unique-value verification.
- `references/analytics-detection.md` adds property-write greps (Mixpanel `.people.set`, Amplitude `setUserProperty`, Segment `.identify(_, traits)`, etc.) and 3rd-party SDK greps (`Purchases.shared.purchase`, `Superwall.shared.register`, `Adjust.trackEvent`, …).

### Deprecated

- `amply_bootstrap_for_app` — now a thin wrapper around `amply_ensure_app({ ..., mintNewKey: true })`. Will be removed in a future release; use `amply_ensure_app` directly.

### Fixed

- Re-running the skill against an already-integrated project no longer mints duplicate API keys silently. `amply_ensure_app` defaults to `mintNewKey: false`; mint-on-reuse is now opt-in or explicit (autopilot logs the decision; interactive asks).

## [0.1.0] — 2026-05-15

Initial release. Skill scaffold authored, codex-reviewed twice, source-of-truth pass against the SDK source code, **two Phase D field trials against a real RN + Expo project complete**. Thirteen skill-level gaps surfaced and patched in-session. See `CONTRIBUTING.md` Review log for details.

### Added

- `SKILL.md` — 9-phase workflow with tool-neutral prose for Claude Code + Codex parity.
- `references/sdk-cheatsheet-rn.md` — `@amplytools/react-native-amply-sdk` reference.
- `references/sdk-cheatsheet-ios.md` — `AmplySDK` (Swift) reference.
- `references/sdk-cheatsheet-android.md` — `tools.amply:sdk-android` reference.
- `references/sdk-cheatsheet-kmp.md` — `tools.amply:sdk-kmp` reference.
- `references/platform-detection.md` — discovery + version gates.
- `references/analytics-detection.md` — 25+ vendor fingerprints (Firebase, Amplitude, Mixpanel, Segment, PostHog, Heap, Datadog RUM, …).
- `references/wrapper-patterns.md` — wrapper templates (TS / Swift / Kotlin / KMP) with consent gating.
- `references/custom-properties.md` — recommended properties catalogue + counter pattern.
- `references/event-naming.md` — PascalCase events, snake_case property keys; translate inside the wrapper.
- `references/deeplink-wiring.md` — six listener patterns (React Navigation, expo-router, SwiftUI, UIKit, Compose, Jetpack Navigation).
- `references/consent-and-privacy.md` — ATT / GDPR / CCPA gating + PII rules.
- `references/lifecycle-and-state.md` — strong-reference and init-ordering rules per platform.
- `references/who-when-what-audit.md` — Amply campaign-model readiness checklist.
- `references/audit-template.md` — skeleton for `amply-audit.md` output.
- `references/codex-tools.md` — Claude Code → Codex tool-name mapping.
- `CONTRIBUTING.md` — feedback loop, RED/GREEN/REFACTOR cycle, review log.

### Pending

- Phase D validation across the seven canonical pressure scenarios.
- Public repo at `github.com/amply-tools/sdk-skill`.
- agentskills.io registry submission.
