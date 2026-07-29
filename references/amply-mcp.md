# Amply MCP — reference

Amply hosts its MCP server. There is nothing to install and no local process — point the client
at a URL and the user approves access in a browser.

```bash
claude mcp add --transport http amply https://api.amply.tools/mcp
```

The user then runs `/mcp`, authenticates, and approves. Any client that supports a remote MCP
server over HTTP takes the same URL.

**Never add an MCP server without explicit consent** — same rule as Context7, autopilot included.

**Scope boundary:** this MCP is for backend operations — projects, campaigns, analytics, prices.
It is **not** a source of SDK reference. Code snippets and API signatures come from Context7 or
the bundled `sdk-cheatsheet-*.md`, never from a backend round-trip.

## Detecting whether it is usable

```bash
claude mcp list | grep -i amply      # Codex CLI: codex mcp list
```

Listed is not the same as usable. A connected-but-unapproved server answers every tool call with
an authorization error. Treat that as **not usable**: ask the user to run `/mcp` and approve,
then continue. Do not attempt a workaround.

Cheapest positive check: call `amply_ping`. It needs no permission, so a `"pong"` proves the
connection and the approval both.

## What it can and cannot do

Read this before planning a phase around it — the gaps decide the shape of the work.

**Can:** read projects; list, read, create, activate and stop campaigns; read active-user and
per-campaign analytics; manage product prices, price batches and custom price indexes.

**Cannot — these need the Amply admin UI:**

* **Create a project, register an application, or produce API keys.** There is no provisioning
  tool. `appId`, `apiKeyPublic` and `apiKeySecret` must come from the user.
* **Edit a campaign.** There is no update tool. A wrong draft cannot be corrected, only replaced
  by another draft, which leaves litter in the customer's campaign list. Get it right once.
* **Target on custom properties, install date, or event history.** On create, only `country`,
  `application`, `app_version` and `os_version` are accepted; anything else is refused outright.
* **Filter a trigger on event parameters.** The triggering event carries a name and a type only —
  see the traps below, because this one fails quietly rather than loudly.
* **List the applications inside a project**, so an application UUID also has to come from the
  user.

## Tools

Names are `snake_case`. Only the connection check keeps the `amply_` prefix.

| Tool | Notes |
| --- | --- |
| `amply_ping` | Connection check, no permission needed. |
| `projects_list` | `{items: [{id, name}]}`. |
| `campaigns_list` | `project_id`, optional `search`, `limit` 1–100. |
| `campaign_get` | The campaign as stored. |
| `campaign_create` | Always a **draft**. See the payload traps below. |
| `campaign_activate` | Publishes a draft. Refused at the plan's active-campaign limit. |
| `campaign_stop` | Stops a live campaign. Cannot return it to draft — neither can the admin. |
| `statistics_active_users` | Daily or monthly, per project, range ≤ 366 days. |
| `campaign_statistics` | Impressions and resolutions for one campaign. |
| `price_*` (16 tools) | Price management. Needs that plan feature; the price-index tools need it as a separate addition. Each starts from an `application_id` the MCP cannot look up. |

Tool visibility follows the permissions the user granted, not their plan — price tools appear even
when the plan lacks the feature, and refuse when called.

## `campaign_create` — payload traps

Each of these produces a confusing error rather than a clear one.

* Keys are **`snake_case`**: `project_id`, `app_version`, `repeat_type`, `compare_type`. Unknown
  keys are **refused**, not ignored, so a camelCase key is a hard error.
* Operators are `snake_case` too: `greater_or_equal`, `not_equal`, `is_set`.
* `triggering.limit` is **required** even with no limit — pass `"limit": {}`.
* `limit`/`limit_type` and `interval`/`interval_dimension` are **pairs**; half a pair is rejected.
* Targeting is a **flat list of conditions, all of which must match** — not OR-ed groups. Two
  `country` conditions therefore match nobody. Express a range as two conditions
  (`app_version >= 1.4.0` and `app_version < 1.5.0`).
* **Event parameter filters are dropped in silence.** This is the one trap that does not
  announce itself: unknown *top-level* keys are refused with an error, but the triggering event
  accepts only a name and a type — any parameter filter you attach is discarded and the campaign
  is created without it. Nothing in the response says so. The campaign then triggers on *every*
  occurrence of that event name, so a filter you believed narrowed the audience did nothing. Any
  campaign whose correctness depends on a parameter filter must be authored in the admin UI.
* `campaign_get` returns a different casing from what `campaign_create` accepts, so a
  read-modify-write round trip needs hand translation. With no update tool, prefer getting it
  right once over iterating.

The server publishes a **campaign targeting reference** as an MCP resource
(`amply://campaign/targeting-reference`), with worked examples. Read that rather than guessing the
vocabulary — and note that it states the same limits as this page, so if the two ever disagree, the
server is right and this page is stale.

## Authorization

OAuth in the browser. Approval is a single allow-or-decline over whatever the client asked for —
not a permission-by-permission choice. The user revokes under **Profile settings → Connected
apps** in the Amply admin.

Never ask for the user's Amply password. Never write credentials into the repository or the audit
log.

## Errors worth handling

| Symptom | Meaning |
| --- | --- |
| Authorization error on every call | Connected but not approved — user runs `/mcp` and approves. |
| A tool is missing from the list | The granted permissions do not cover it. Ask the user to reconnect. |
| "Requires the price management feature" | Plan gate, not a bug. Stop; do not retry. |
| Plan limit on activate | The organization is at its active-campaign cap. Leave it a draft and say so. |
| Unknown-key or refused-targeting error | A payload trap above. Fix the shape; do not retry unchanged. |

## The retired local package

Amply used to publish `@amplytools/amply-mcp` on npm — a local stdio server that signed in with
an email and password and could register applications and mint keys. **It is retired, every
version is deprecated, and its endpoint returns 404.**

If a project still has it configured, remove it, connect to the hosted server, and tell the user
to delete `~/.amply/credentials.json` — it holds a live sign-in token.

None of these exist any more; do not call them: `amply_login`, `amply_logout`, `amply_status`,
`amply_whoami`, `amply_signup`, `amply_ensure_app`, `amply_create_project`,
`amply_list_applications`, `amply_find_application`, `amply_get_application`,
`amply_create_application`, `amply_create_api_key`, `amply_update_campaign`,
`amply_describe_targeting`, `amply_set_campaign_state`, `amply_create_campaign_from_template`.
