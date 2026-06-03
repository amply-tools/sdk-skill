# Changelog

All notable changes to `amply-integration` are documented here. Format follows [keepachangelog.com](https://keepachangelog.com/en/1.1.0/); versioning is [SemVer](https://semver.org/spec/v2.0.0.html).

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
- Documented the SDK 0.5.0 gate API (`trackGated` + `registerGate`) across `SKILL.md` and the platform cheatsheets; the removed callback-continuation API (`trackEvent(..., onProceed, onCancel)` / `registerCampaignPresenter`) is called out as a breaking change.

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
