# amply-integration

A skill that walks an AI agent through integrating the [Amply](https://amply.tools) SDK into a mobile app — React Native, Expo, iOS / Swift, Android / Kotlin, or Kotlin Multiplatform — end to end. Works with **Claude Code** and **Codex CLI** today, and with any host that follows the [agentskills.io specification](https://agentskills.io/specification).

## What the skill does

When you tell your AI agent something like *"add Amply to this app"*, the skill kicks in and runs nine phases in order:

1. Detect the platform, package manager, and navigation library.
2. Audit the existing analytics layer (Firebase / Amplitude / Mixpanel / Segment / PostHog / 25+ vendors covered).
3. Apply privacy / consent gating so Amply tracking respects the project's existing rules.
4. Map existing events and user properties to Amply's `track()` and Custom Properties surface.
5. Run a Who / When / What readiness audit against Amply's campaign model.
6. Generate (or extend) a thin wrapper so Amply is called from one place.
7. Initialise the SDK with platform-correct API and env-driven keys.
8. Wire the deeplink listener to your navigation stack.
9. Hand off with verification commands.

The output is real code changes plus an `amply-audit.md` report the team can act on later.

## Install

### Recommended — via the `skills` CLI

Works for Claude Code, Codex CLI, Cursor, Windsurf, and any other host the `skills` CLI supports:

```bash
npx skills add amply-tools/sdk-skill
```

Add `-g` to install at the user level instead of project level. See `npx skills --help` for per-agent install (`-a claude-code`, `-a codex`, etc.).

After install, the skill is available in any session — phrases like *"integrate Amply"* or *"add the Amply SDK"* will trigger it.

### Manual — Claude Code (per user)

```bash
git clone https://github.com/amply-tools/sdk-skill.git \
  ~/.claude/skills/amply-integration
```

### Manual — Claude Code (as a plugin)

Drop the folder inside your plugin's `skills/` directory. The plugin loader picks it up automatically.

### Manual — Codex CLI

```bash
git clone https://github.com/amply-tools/sdk-skill.git \
  ~/.agents/skills/amply-integration
```

Codex auto-discovers skills from `~/.agents/skills/`. Verify with `codex --help` that the spec hasn't changed since the last release of this README.

### Other hosts

Anywhere that supports the agentskills.io specification — drop the folder in the host's per-user skills directory. The frontmatter and Markdown body are runtime-agnostic.

## Use it

In your AI agent of choice, point it at the project root and say:

```
integrate Amply into this app
```

The skill takes over from there. It will detect your stack, ask one or two clarifying questions, and walk through phases 1–9. Expect to spend ~30 minutes the first time including code review.

## What this skill does NOT do

- Run Amply campaign queries or admin-panel mutations. It generates client integration code; campaigns are still configured in the Amply admin UI.
- Replace your analytics vendor. Amply runs **alongside** Firebase / Amplitude / Mixpanel / etc.
- Send pushes, emails, or SMS. Amply's only action types are `Deeplink` and `RateReview`.
- Render UI. Any popup, sheet, or paywall you want is rendered by the host app in response to a `Deeplink` action.

## Files

| File | Purpose |
|---|---|
| `SKILL.md` | Main entry point — frontmatter + 9-phase workflow. |
| `CONTRIBUTING.md` | How to give feedback and improve the skill. |
| `LICENSE` | Apache 2.0. |
| `references/sdk-cheatsheet-{rn,ios,android,kmp}.md` | Per-platform copy-paste-correct API reference. |
| `references/analytics-detection.md` | ≥25 analytics-vendor fingerprints. |
| `references/wrapper-patterns.md` | Wrapper templates (TS / Swift / Kotlin / KMP). |
| `references/custom-properties.md` | Recommended Custom Property catalogue. |
| `references/event-naming.md` | Convention guidance + translation pattern. |
| `references/deeplink-wiring.md` | Listener wiring per navigation library. |
| `references/consent-and-privacy.md` | ATT / GDPR / CCPA gating. |
| `references/lifecycle-and-state.md` | Strong-reference and ordering rules per platform. |
| `references/who-when-what-audit.md` | Readiness checklist for Amply's campaign model. |
| `references/audit-template.md` | Skeleton for the `amply-audit.md` output. |
| `references/codex-tools.md` | Tool-name mapping for Codex agents. |
| `references/platform-detection.md` | Heuristics + version gates. |

## Feedback

See `CONTRIBUTING.md`. The fastest way to help is to file a `[scenario]` issue when the skill makes a wrong call in your project — those become test cases.

### Anonymous usage signal (opt-in, off by default)

Near the start, the skill asks once whether it may send a single anonymous signal to Amply when an integration finishes successfully. It is **opt-in** — say no (the default) and nothing is ever sent. If you opt in, exactly one request is sent on success, containing **no code and nothing personal**: the platform, the mode (autopilot/interactive), counts of phases/checkpoints completed, the number of troubleshooting loops, an optional 1–5 rating, the skill version, and a random per-run id. It helps the team see where the skill gets stuck. Decline and the whole step is skipped.

## License

Apache License 2.0 — same as the Amply SDK.
