# Changelog

All notable changes to `amply-integration` are documented here. Format follows [keepachangelog.com](https://keepachangelog.com/en/1.1.0/); versioning is [SemVer](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — Unreleased

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

## [0.1.0] — Unreleased

Initial draft. Skill scaffold authored, codex-reviewed twice, source-of-truth pass against the SDK source code, **two Phase D field trials against a real RN + Expo project complete**. Thirteen skill-level gaps surfaced and patched in-session. See `CONTRIBUTING.md` Review log for details. Still pending: Phase D scenarios 2–7, install validation on a clean machine, public repo creation.

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
