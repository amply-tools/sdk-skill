# Amply MCP — first-class automation for backend ops

The `@amplytools/amply-mcp` server (separate package, installed independently of this skill) lets the agent talk directly to the Amply backend — sign up, log in, create projects, register applications, fetch `apiKeyPublic` + `apiKeySecret`. When this MCP is connected, **the skill can complete a full integration without ever asking the user to open the Amply admin UI** — it is the highest-leverage piece of Phase 0 toolchain after Context7.

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

If present, you have access to a known set of tools all prefixed `amply_`. The 12 v1 tools:

| Tool | Use it when |
|---|---|
| `amply_status` | First thing — check whether you're already authenticated. |
| `amply_signup` | The user has no Amply account yet. |
| `amply_login` | The user has an Amply account; you don't have a session. |
| `amply_whoami` | Confirm whose account / org the session belongs to before doing destructive things. |
| `amply_logout` | Done with the session (rare during integration). |
| `amply_list_projects` | You need a `projectId` and don't have one. |
| `amply_create_project` | The user's org has no project, or they want a dedicated one. |
| `amply_list_applications` | You have a `projectId` and want to check whether the app's `bundleId` is already registered. |
| `amply_get_application` | You have an Application UUID and need its API keys. |
| `amply_create_application` | First-time registration of the app. Returns the first API key in the response. |
| `amply_create_api_key` | Need an additional key (key rotation, separate scope). |
| **`amply_bootstrap_for_app`** | **Recommended one-shot for AI-agent integration** — ensures project + application + first key in one tool call, returns a ready-to-paste `.env.local` block. |

## If the MCP is NOT connected

Offer to install it. **It's free** and 30 seconds:

```bash
claude mcp add amply -- npx -y @amplytools/amply-mcp
```

After install, the user must restart the agent session for the MCP to register.

In autonomous mode (sub-agent, batch job, CI) — do **not** install the MCP without explicit consent. Same rule as Context7 in `references/context7-mcp.md`. Fall back to the manual flow: tell the user the values you need (`appId`, `apiKeyPublic`, optional `apiKeySecret`) and where to find them in `app.amply.tools/applications/<bundleId>`, then write the `.env.local` block ourselves once they paste them in.

## How this changes Phase 5 (Wrapper implementation)

When the MCP is available:

1. Call `amply_status` — verify session.
2. If not authenticated, ask the user (or, with permission, call `amply_signup` / `amply_login`).
3. Call `amply_bootstrap_for_app` with the project's bundleId + platform (detected in Phase 1):

```
amply_bootstrap_for_app({
  bundleId: "<bundle-id-from-Info.plist-or-AndroidManifest>",
  name: "<human-readable app name>",
  platform: "<iOS | Android>",
  projectName: "<optional, defaults to org's first project>"
})
```

4. The tool returns:

```json
{
  "status": "created" | "existing",
  "project": { "id": "...", "name": "..." },
  "application": { "id": "...", "bundleId": "...", "name": "...", "platform": "..." },
  "firstApiKey": { "public": "...", "secret": "..." } | null,
  "envBlock": "# Amply (iOS). Do not commit.\nEXPO_PUBLIC_AMPLY_APP_ID=...\n..."
}
```

5. If `status` is `"existing"` and `firstApiKey` is `null`, call `amply_create_api_key({ applicationId: application.id })` to mint a fresh secret (existing secrets are not returned by list endpoints).
6. Paste `envBlock` into `.env.local` (or the project's equivalent). For non-Expo projects, adapt the env var prefix to match what the project's wrapper code reads.

Record this in `amply-audit.md` under "Toolchain":

```
Amply MCP:    connected — bootstrap via amply_bootstrap_for_app
Application:  <bundleId> (<UUID>) under project "<projectName>" (<UUID>)
Keys source:  amply_bootstrap_for_app (status=<created|existing>)
```

## Error codes — what to do

| Code | Meaning | Recovery |
|---|---|---|
| `auth_required` | No session / session expired and refresh failed. | Re-run `amply_login` (or `amply_signup` if new). |
| `invalid_credentials` | Login rejected. | Ask user for correct password, or signup. |
| `conflict` | `bundleId + platform` already registered. | Use `amply_get_application` / `amply_list_applications` to find the existing one. |
| `not_found` | Bad UUID, or you don't have access. | Re-list to find the correct id. |
| `validation_error` | Backend rejected input. | The `message` field describes the issue. |
| `access_denied` | Access control denied access. | Verify you're in the right org via `amply_whoami`. |
| `network_error` | Endpoint unreachable. | Check `AMPLY_ENDPOINT` and network. |
| `graphql_error` | Unclassified GraphQL error. | Surface `message` to the user. |
| `internal_error` | Unexpected. | Try once more; if persists, file an issue. |

## Anti-patterns

- ❌ Calling `amply_list_applications` without `projectId` — the backend requires it.
- ❌ Caching secrets from `amply_list_applications` — the list endpoint **does not** include secrets. Use `amply_get_application` or `amply_create_application`/`_api_key` responses.
- ❌ Skipping `amply_status` and immediately calling authenticated tools — wastes a network call on a guaranteed `auth_required`.
- ❌ Calling `amply_signup` if `amply_login` would do — accounts are not free to create programmatically in many tenants.
