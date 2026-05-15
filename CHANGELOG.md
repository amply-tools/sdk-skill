# Changelog

All notable changes to `amply-integration` are documented here. Format follows [keepachangelog.com](https://keepachangelog.com/en/1.1.0/); versioning is [SemVer](https://semver.org/spec/v2.0.0.html).

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
