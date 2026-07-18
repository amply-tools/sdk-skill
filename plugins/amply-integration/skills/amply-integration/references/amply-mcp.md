# Amply MCP — first-class automation for backend ops

The `@amplytools/amply-mcp` server (separate package, installed independently of this skill) lets the agent talk directly to the Amply backend — sign up, log in, create projects, register applications, fetch `apiKeyPublic` + `apiKeySecret`. When this MCP is connected, **the skill can complete a full integration without ever asking the user to open the Amply admin UI** — it is the highest-leverage piece of Phase 0 toolchain after Context7.

**Scope boundary:** this MCP is for account / backend automation only — keys, `appId`, projects, campaigns. It is **not** a source of SDK reference; code snippets and API signatures come from Context7 or the bundled `sdk-cheatsheet-*.md`, never from a backend round-trip.

## Detection (Phase 0)

After the Context7 check, run:

```bash
claude mcp list | grep -i amply
```

(For Codex CLI: `codex mcp list`.)

Expected line if connected:

```
amply: ... ✓ Connected
```

If present, you have access to a known set of tools all prefixed `amply_`. The tools:

| Tool | Use it when |
|---|---|
| `amply_status` | First thing — check whether you're already authenticated. |
| `amply_signup` | The user has no Amply account yet. |
| `amply_login` | The user has an Amply account; you don't have a session. |
| `amply_whoami` | Confirm whose account / org the session belongs to before doing destructive things. |
| `amply_logout` | Done with the session (rare during integration). |
| `amply_list_projects` | You need a `projectId` and don't have one. |
| `amply_create_project` | The user's org has no project, or they want a dedicated one. |
| `amply_list_applications` | You have a `projectId` and want to enumerate apps under it. |
| `amply_find_application` | You have a `bundleId + platform` and want to discover whether it's already registered anywhere in the org (with `projectId` to scope). Pure read. |
| `amply_get_application` | You have an Application UUID and need its metadata. |
| `amply_create_application` | First-time registration of the app. Returns the first API key in the response. |
| `amply_create_api_key` | Need an additional key (key rotation, separate scope). |
| **`amply_ensure_app`** | **Recommended primary entry** — idempotent project + app + key resolution with cross-project conflict guard and explicit `mintNewKey` opt-in. Returns one of `created` / `reused` / `reused_new_key` / `conflict_cross_project`. |
| `amply_list_campaigns` | You have a `projectId` and want to enumerate its campaigns (id, name, type, state per campaign). Read-only. |
| `amply_get_campaign` | You have a campaign id and want its full triggering / targeting / content for inspection. Read-only. |
| `amply_set_campaign_state` | Flip a campaign between `Draft` / `Active` / `Cancel`. Authoring tools always create in Draft; this is how a reviewed campaign goes live (or a live one gets paused — Cancel pauses, never deletes). |
| `amply_create_campaign_from_template` | Create a campaign in Draft from a whitelisted known-good template (`rate-review-after-positive-moment`, `deeplink-on-session-n`, `deeplink-on-property-change`, …) — the safest authoring path when a template fits. |
| `amply_create_campaign` | Create a campaign from a full definition — event property filters via `params`, every-N `repeat`, device / customProperty / event-history targeting (event-count and first/last-occurrence date conditions with per-event property filters; up to 20 event conditions per campaign, matched only by apps on Amply SDK 0.6.1+). Always created in Draft state. |
| `amply_update_campaign` | Edit a campaign in place; top-level replace of provided fields; current state preserved for fields not supplied. |
| `amply_describe_targeting` | Describe the targeting + triggering vocabulary available — slots (device, Custom Property, event count, event date), comparators, and predicate shapes — so agents can discover the campaign-authoring vocabulary before calling `amply_create_campaign`. |

## Removed tools

| Tool | Removed | Notes |
|---|---|---|
| `amply_bootstrap_for_app` | 0.3.0 | Was a thin wrapper around `amply_ensure_app({ ..., mintNewKey: true })`; deprecated in 0.2.0, removed in 0.3.0. Use `amply_ensure_app` directly. |

## If the MCP is NOT connected

Offer to install it. **It's free** and 30 seconds:

```bash
claude mcp add amply -- npx -y @amplytools/amply-mcp
```

After install, the user must restart the agent session for the MCP to register.

In autonomous mode (sub-agent, batch job, CI) — do **not** install the MCP without explicit consent. Same rule as Context7 in `references/context7-mcp.md`. Fall back to the manual flow: tell the user the values you need (`appId`, `apiKeyPublic`, optional `apiKeySecret`) and where to find them in `app.amply.tools/applications/<bundleId>`, then write the `.env.local` block ourselves once they paste them in.

## How this drives Phase 1b (Amply app resolution) and Phase 5 (Wrapper implementation)

When the MCP is available, Phase 1b owns app resolution and produces the `envBlock` Phase 5 will use.

1. Call `amply_status` — verify session.
2. If not authenticated, ask the user (or, with permission, call `amply_signup` / `amply_login`).
3. Call `amply_ensure_app` with the project's bundleId + platform (detected in Phase 1):

```
amply_ensure_app({
  bundleId: "<bundle-id-from-Info.plist-or-AndroidManifest>",
  name: "<human-readable app name>",
  platform: "<iOS | Android>",
  projectName: "<optional, defaults to oldest project>",
  mintNewKey: false,
  allowDuplicateAcrossProjects: false
})
```

4. The tool returns one of:

```json
// status: "created" — first key returned inline
{
  "status": "created",
  "project": { "id": "...", "name": "..." },
  "application": { ... },
  "firstApiKey": { "public": "...", "secret": "..." },
  "envBlock": "# Amply (iOS). Do not commit.\n..."
}

// status: "reused" — existing app, no key (secrets are not in the list endpoint)
{
  "status": "reused",
  "application": { ... },
  "firstApiKey": null,
  "envBlock": "...<paste from Amply admin>...",
  "hint": "Existing application reused. ... re-invoke with mintNewKey:true ..."
}

// status: "reused_new_key" — opt-in mint of a fresh secret on the existing app
{
  "status": "reused_new_key",
  "firstApiKey": { "public": "...", "secret": "..." },
  "envBlock": "..."
}

// status: "conflict_cross_project" — same bundleId+platform in a different project
{
  "status": "conflict_cross_project",
  "existingApplicationProject": { "id": "...", "name": "..." },
  "hint": "... pass `projectName` matching the existing project, or set `allowDuplicateAcrossProjects: true` ..."
}
```

5. Per Phase 1b in SKILL.md: in `interactive` mode ask the user before minting; in `autopilot`, re-invoke with `mintNewKey: true` on the `reused` branch and log the decision. On `conflict_cross_project`, STOP and surface to the user.
6. Paste `envBlock` into `.env.local` (or the project's equivalent) in Phase 5. For non-Expo projects, adapt the env var prefix to match what the project's wrapper code reads.

Record in `amply-audit.md` under "Toolchain":

```
Amply MCP:    connected — bootstrap via amply_ensure_app
Application:  <bundleId> (<UUID>) under project "<projectName>" (<UUID>)
Keys source:  amply_ensure_app (status=<created|reused|reused_new_key>)
```

## Error codes — what to do

| Code | Meaning | Recovery |
|---|---|---|
| `auth_required` | No session / session expired and refresh failed. | Re-run `amply_login` (or `amply_signup` if new). |
| `invalid_credentials` | Login rejected. | Ask user for correct password, or signup. |
| `conflict` | `bundleId + platform` already registered. | Use `amply_find_application` to discover where, then `amply_ensure_app` with the right `projectName`. |
| `not_found` | Bad UUID, or you don't have access. | Re-list to find the correct id. |
| `validation_error` | Backend rejected input. | The `message` field describes the issue. |
| `access_denied` | Access control denied access. | Verify you're in the right org via `amply_whoami`. |
| `network_error` | Endpoint unreachable. | Check `AMPLY_ENDPOINT` and network. |
| `graphql_error` | Unclassified GraphQL error. | Surface `message` to the user. |
| `internal_error` | Unexpected. | Try once more; if persists, file an issue. |

## Anti-patterns

- ❌ Calling `amply_list_applications` without `projectId` — the backend requires it. Use `amply_find_application` for cross-project search.
- ❌ Caching secrets from list endpoints — they **do not** include secrets. Secrets are only in `applicationCreate` and `apiKeyCreate` mutation responses.
- ❌ Skipping `amply_status` and immediately calling authenticated tools — wastes a network call on a guaranteed `auth_required`.
- ❌ Calling `amply_signup` if `amply_login` would do — accounts are not free to create programmatically in many tenants.
- ❌ Re-running the skill against an already-integrated project and minting a new key on every run. `amply_ensure_app` defaults to `mintNewKey: false` for exactly this reason — only opt in when the user has lost access to the old secret.
