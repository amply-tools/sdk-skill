# Contributing to `amply-integration`

This skill is shipped at `github.com/amply-tools/sdk-skill` (Apache 2.0). It is read by AI agents (Claude Code, Codex CLI, and any other host that follows the [agentskills.io specification](https://agentskills.io/specification)) and steers them through an Amply SDK integration end-to-end.

We treat the skill **like any other piece of production software**: with versioning, tests, code review, and a public changelog. The "tests" here are pressure scenarios run against the skill — see `superpowers:writing-skills` for the full TDD-for-skills methodology.

## How to give feedback

### Quick fix or correction

If something is wrong (an SDK method doesn't exist, a vendor is missing, a code sample doesn't compile):

1. Open an issue at `github.com/amply-tools/sdk-skill/issues/new` with the title `[fix] <one-line summary>`.
2. Quote the offending block from the skill or a reference file.
3. State what the agent did with that text in your project, and what it should have done.

### "It picked the wrong thing for my project"

If the skill gave you the wrong outcome (wrong SDK, wrong wrapper choice, wrong consent decision), open a `[scenario]` issue:

```
Title:   [scenario] <agent runtime> <platform> — wrong <thing>
Body:
  - Agent runtime:   Claude Code v… / Codex CLI v…
  - Project type:    RN/Expo/Swift/KMP/Kotlin
  - Existing analytics: Mixpanel / Firebase / Segment / …
  - Existing consent:  ATT / UMP / custom / none
  - What I expected the skill to do: …
  - What it actually did: …
  - Transcript / diff (optional but useful): …
```

We use these reports to build new pressure scenarios — see "Pressure scenarios" below.

### "There's a vendor or framework you don't cover"

Open a `[vendor]` issue. Include:

- Vendor / framework name + URL.
- Per-platform package markers (so we can grep for them).
- Per-language call-site patterns.
- Any reason this vendor's events should be **excluded** from the Amply fan-out (e.g. it's BI-only, server-driven, etc.).

We add the entry to `references/analytics-detection.md`.

## How the skill is improved

We follow RED → GREEN → REFACTOR for every change.

### 1. Define the failing test (RED)

A "test" here is a **pressure scenario**: a code-base setup + a prompt that, today, produces the wrong agent behaviour. Capture it in `tests/scenarios/<name>.md` with:

- Project skeleton (or pointer to a public sample repo).
- Prompt the user types.
- The exact wrong behaviour observed.

We do not ship the change until we can reproduce the failure on a fresh machine.

### 2. Patch the skill (GREEN)

Edit `SKILL.md` or the relevant `references/*.md`. Keep the body of `SKILL.md` under ~500 words; push detail into references. Re-run the same prompt against the patched skill (under both Claude Code and Codex CLI) until the agent behaves correctly.

### 3. Look for new loopholes (REFACTOR)

Often, plugging one rationalisation opens up another (the agent finds a new excuse not to follow the skill). Run the scenario again with the patched skill, look for the next loophole, plug it. Repeat until the skill is bulletproof for that scenario.

### 4. Write down what you learned

Append a row to `CHANGELOG.md` and (for non-trivial changes) a paragraph to the Review log below. Future contributors need to know **why** a particular sentence is in the skill — otherwise it gets pruned during a future "tidy up" and the regression returns.

## Pressure scenarios — the canonical set

We maintain at least these scenarios, in `tests/scenarios/`:

1. **RN-bare-mixpanel-with-att** — RN bare project, Mixpanel + ATT consent.
2. **expo-firebase-ump** — Expo managed, Firebase Analytics + UMP consent.
3. **swiftui-firebase-no-consent** — SwiftUI app, Firebase Analytics, no consent framework yet.
4. **uikit-amplitude-onetrust** — UIKit / Storyboards, Amplitude, OneTrust.
5. **android-compose-revenuecat-no-analytics** — Compose app, RevenueCat for billing, no other analytics — tests that the skill still proposes a wrapper.
6. **kmp-shared-no-analytics** — Pure KMP shared module, two thin platform shells.
7. **monorepo-mixed** — Yarn workspace with one RN target + one Swift target — tests platform disambiguation.

Adding a scenario is the most common way to contribute meaningful improvements.

## Release process

1. Bump the version field in `SKILL.md` frontmatter (semver: `<major>.<minor>.<patch>`).
2. Update `CHANGELOG.md`.
3. Tag the release (`v0.x.y`).
4. Push. The Anthropic skills marketplace pulls from the tag; Codex skills users update via `git pull` or whatever package manager their setup uses.

## Coding style for skill files

- Markdown only. No HTML. No images that aren't already next to the source-of-truth (`landing/docs/amply-capabilities-reference.md`).
- Use `❌` / `✅` to mark "wrong" / "right" code blocks — agents key off these.
- Code blocks must be copy-paste-correct against the SDK source. We treat the SDK source — not these examples — as the source of truth.
- Avoid first-person voice in the skill body. Write to the agent: "do X", "check Y".

## Review log

| Date | Reviewer | Surface | Outcome |
|---|---|---|---|
| 2026-05-10 | codex (review #1) | `PLAN.md` v0 | Surfaced 14 issues — `Amply.initialize` only on RN; deeplink platform-correct signatures; SDK version gates; RN custom-prop type narrowness; missing Who/When/What audit phase; missing Privacy/Consent and Lifecycle phases; expanded vendor list; per-language grep patterns; "always extend existing wrapper" was too broad; tool-neutral prose in main workflow. Folded into PLAN.md and SKILL.md before publish. |
| 2026-05-10 | codex (review #2) | full skill folder | Surfaced 10 more issues — phase-count framing inconsistency; PLAN said `SKILL.md` was ≤500 words but it isn't (relaxed wording instead of trimming); RN wrapper accepted `unknown` and cast to scalar — added `coerceForRn` helper that drops arrays/objects and converts `Date`→epoch ms; iOS / SwiftUI sample hard-coded `"..."` placeholders even after the no-hardcode rule — switched to `Bundle.main` reads; SwiftUI deeplink sample read `@StateObject` from `init` — restructured around an `AppEnvironment` holder; Compose sample used `navController` before declaration — captured via `LaunchedEffect`; KMP cheatsheet flagged as inferred-from-samples (capabilities reference doesn't spell out `expect/actual` shapes); `audit-template.md` no-auto-stage clarified; tool-name framing trimmed in `SKILL.md`; added vendors AppMetrica, Flurry, Matomo, CleverTap, MoEngage, WebEngage, Pendo, FullStory. |
| 2026-05-10 | source-of-truth pass | actual SDK source files (`react-native-sdk/src/`, `multiplatform-library-template/library/src/`, `samples/ios-spm-sample/`) | Cross-checked the cheatsheets against the real Kotlin/Swift/TS source. Three material corrections: (1) `AmplyConfig` on iOS / Android / KMP requires `apiKeySecret` and `defaultConfig` — every native init example was missing both, fixed. (2) RN cheatsheet was missing `getRecentEvents`, `getDataSetSnapshot`, `removeAllListeners`, `systemEvents.addListener` aliases — added; `getCustomProperty` return type clarified to `string \| number \| boolean \| null`. (3) Custom Property limits documented (RN: keys ≤ 32 chars + values ≤ 255 chars; native: keys ≤ 255 chars). Also: KMP iOS init clarified — Kotlin/Native Swift bridge maps `initialize` → `doInitialize`. **Added Phase 0 (Context7 MCP)** so the skill prefers live `docs.amply.tools` over the bundled cheatsheets when available, and offers to install Context7 when missing — see `references/context7-mcp.md`. |
| 2026-05-12 | Amply MCP shipped (companion package) | Amply MCP (separate npm package `@amplytools/amply-mcp`) | Implemented a local stdio MCP server backed by the Symfony GraphQL admin API. 12 tools (signup / login / logout / whoami / list+create projects / list+get+create applications / create api key / bootstrap_for_app). One-shot `amply_bootstrap_for_app` returns a ready-to-paste `.env.local` block including `appId` (bundleId) + `apiKeyPublic` + `apiKeySecret`. Skill changes: `SKILL.md` Phase 0 now checks both Context7 AND Amply MCP; Phase 5 mentions `amply_bootstrap_for_app` as the canonical key source when the MCP is connected; new `references/amply-mcp.md` documents tools, error codes, autonomous-mode policy, and the one-shot flow. Codex review #1 of the MCP plan caught 25 contract / security / SDK issues; all folded before the v1 build. Codex review #2 of the actual code pending overnight. Public release path coordinated alongside the skill's. |
| 2026-05-12 | field trial #2 follow-ups | RN+Expo Flavour B project | Two user-reported corrections during verification setup: (a) **Build script discovery** — skill mandated `yarn expo run:ios` for Flavour B but real Flavour-B projects commonly ship legacy `react-native run-ios` scripts (especially when the codebase predates Expo Modules adoption) and the two scripts may be mixed within one project (`yarn ios` legacy, `yarn android` modern). Fix: SKILL.md Phase 7 + `sdk-cheatsheet-rn.md` now say "**read `package.json` scripts first, prefer existing**; `expo run:` is canonical fallback only". Don't normalise the script during integration. (b) **Env-file semantics** — clarified explicitly that `.env.local` only reads `EXPO_PUBLIC_*` into the RN runtime (Metro inlines them at bundle time); non-prefixed vars (e.g. `SENTRY_AUTH_TOKEN`) are build-time only. The skill's wrapper templates already use `EXPO_PUBLIC_AMPLY_*` correctly; no patch needed, but worth surfacing in the env-handling note in Phase 5. |
| 2026-05-11 | field trial #2 (GREEN verification + new RED) | RN+Expo Flavour B project, follow-up branch | Re-ran skill end-to-end against the same project on a fresh branch with the updated skill. **All seven major fixes from trial #1 held green**: Flavour B correctly detected via `git ls-files`; `app.json` left untouched (verified with `git diff`); no `expo prebuild`; Pattern A.1 with `getStateFromPath` used; sync wrapper signature preserved across 163 call sites; RevenueCat-driven Custom Properties seeded; Context7 autonomous-mode branch followed (no MCP install). 5 new gaps surfaced and patched: (a) **iOS New-Arch grep paths** — agent couldn't find where to check `RCT_NEW_ARCH_ENABLED`; added explicit order `Podfile.properties.json` → `Podfile` ENV → `package.json` script. (b) **Array-valued user-property recipe** — `custom-properties.md` said "arrays not supported" without a deterministic transformation; added three recipes (CSV / first-value / drop+counter) with TS implementation. (c) **Pattern A.1 pre-flight** — sample assumed `NavigationContainer` already had a `ref`; added explicit "add `createNavigationContainerRef` first" pre-flight step. (d) **Consent default re-framed** — "yes for identifier events" was stricter than the existing analytics stack of most apps; rewrote `consent-and-privacy.md` to "**match the project's posture, don't unilaterally tighten**" with a 4-row table mapping existing-stack posture → Amply behaviour. (e) **Flavour B sub-case** — projects that author their own Expo Modules (`modules/expo-foo/`) — added a paragraph clarifying the integration path is unchanged. Verification on a real device deferred (Phase 7 explicitly hands off to user, ~10 minutes Pod-install + Xcode compile required). |
| 2026-05-11 | field trial #1 follow-up | Bare RN + Expo Modules (Flavour B) project | User flagged a CRITICAL skill gap surfaced by the trial: the skill conflated "Expo bare workflow" with "Bare RN + Expo Modules". They are different — the latter has hand-managed `ios/` and `android/` committed to git, and **`expo prebuild` would wipe them**. The trial agent added the Amply config plugin to `app.json` (a no-op in Flavour B) and the skill's Phase 7 checklist actively recommended `prebuild --clean` for "Expo bare". Fixed: `platform-detection.md` §2 now distinguishes four flavours (Pure Bare RN, **Bare RN + Expo Modules**, Expo Prebuild Workflow, Expo Managed) with explicit `git ls-files ios/ android/` heuristic for B-vs-C; `SKILL.md` Phase 1 mandates the flavour check; Phase 7 checklist split per flavour; Common Mistakes table now flags `prebuild` against Flavour B and superfluous `app.json` plugin entries against Flavour A/B; `sdk-cheatsheet-rn.md` install section made conditional on flavour. |
| 2026-05-11 | field trial #1 (Phase D RED) | RN bare 0.81 + Expo 54 project (Amplitude + Sentry + Adjust + RevenueCat, ATT-only consent) | Sub-agent ran the skill end-to-end against a real project on a fresh integration branch. Eight gaps surfaced and patched same session: (1) Context7 had no autonomous-mode branch — added "do not install MCP without explicit opt-in" path. (2) iOS deployment target gate was 13.0 in `platform-detection.md` but the published `AmplyReactNative.podspec@0.1.0` requires 15.1 — fixed gate. (3) RN `DataSetType` union in published 0.2.9 doesn't include `@custom` — removed `@custom` example from RN cheatsheet; documented the published union explicitly. (4) RN `apiKeySecret` was documented as absent — clarified as `optional, not absent`. (5) Wrapper template was async-only, breaking projects with sync Amplitude/Firebase wrappers — added rule "inherit existing wrapper's signature, fire-and-forget Amply if sync". (6) Deeplink Pattern A assumed a single "Promo" target — added Pattern A.1 with `getStateFromPath` + `getActionFromState` to re-use existing `linking.config`. (7) Phase 5 didn't warn that projects with no env-loading pipeline need explicit guidance — added (a)/(b) branch. (8) Phase 7 missing Expo-bare `prebuild --clean` checkbox — added platform-specific verification checklist. Also: mixed-mode typed wrapper guidance in Phase 2 (don't refactor call sites during integration). |

When you run a review, append a row here.
