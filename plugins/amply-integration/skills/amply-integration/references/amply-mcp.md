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

**Can, but only on some connections — check the tool list:** register a project or an application
and read or mint its API keys. Provisioning is newer than the campaign tools, needs the
`apps:write` permission, and the creating half additionally requires that the Amply user be an
**organization administrator**. So `application_create` being absent means any of three things, and
the answer is the same in all of them: fall back to asking the user. Never assume it is there.

**Cannot — these need the Amply admin UI:**

* **Delete or clone a campaign.** Neither has a tool. A draft created by mistake stays in the
  customer's campaign list until someone removes it by hand, so it is still worth getting the
  payload right on the first call rather than iterating.

Campaign **authoring and editing** used to be on this list and no longer are: `campaign_update`
exists (a full replace that returns the campaign to Draft), targeting reaches every condition the
admin has, and a trigger carries its event parameter filters. If a tool named here is missing from
your connection, the server predates that change — trust the tool list over this page.

## Tools

Names are `snake_case`. Only the connection check keeps the `amply_` prefix.

| Tool | Notes |
| --- | --- |
| `amply_ping` | Connection check, no permission needed. |
| `projects_list` | `{items: [{id, name}]}`. Read-only. |
| `project_create` | Needs `apps:write` + organization admin. Refused at the plan's project limit. |
| `applications_list` | Under `campaigns:read`, because it is the only source of the application ids `campaign_create` targeting needs. Returns no secret. |
| `application_create` | Needs `apps:write` + admin. Returns the `appId` **and** the first key pair. `platform` is case-sensitive (`iOS` / `Android`); one call per platform; a duplicate `bundleId` + `platform` is refused, not duplicated. |
| `api_keys_list` | Needs `apps:write` — it returns live secrets in plaintext, which is why it is not under a read scope. |
| `api_key_create` | Needs `apps:write` + admin. Mints an **additional** pair; the previous one stays live. |
| `campaigns_list` | `project_id`, optional `search`, `limit` 1–100. |
| `campaign_get` | The campaign as stored. |
| `campaign_create` | Always a **draft**. See the payload traps below. |
| `campaign_update` | **Full replace**, not a patch — omitted fields are cleared, and the campaign returns to Draft. Carry `campaign_get`'s output back (rename `id` → `campaign_id`, drop `state`). |
| `campaign_activate` | Publishes a draft. Refused at the plan's active-campaign limit. |
| `campaign_stop` | Stops a live campaign. Cannot return it to draft — neither can the admin. |
| `statistics_active_users` | Daily or monthly, per project, range ≤ 366 days. |
| `campaign_statistics` | Daily impressions and resolved outcomes for one campaign. A day with no row is a day nothing was recorded (not zero); today's row is still counting. The admin's Statistics tab shows impressions only. |
| `price_*` (16 tools) | Price management. Needs that plan feature; the price-index tools need it as a separate addition. Each starts from an `application_id` the MCP cannot look up. |

Tool visibility follows the permissions the user granted, not their plan — price tools appear even
when the plan lacks the feature, and refuse when called.

## `campaign_create` — payload traps

Each of these produces a confusing error rather than a clear one.

* Keys are **`snake_case`**: `project_id`, `app_version`, `repeat_type`, `compare_type`. Unknown
  keys are **refused**, not ignored, so a camelCase key is a hard error.
* Operators are `snake_case` too: `greater_or_equal`, `not_equal`, `is_set`.
* `triggering.limit`: **omit it** for a campaign with no limit (that is the admin's default). `count` is the total cap per device, `interval` + `interval_dimension` the minimum gap between impressions, `limit` + `limit_type` the per-session or per-device frequency cap.
* `limit`/`limit_type` and `interval`/`interval_dimension` are **pairs**; half a pair is rejected.
* Targeting is a **flat list of conditions, all of which must match** — not OR-ed groups. Two
  `country` conditions therefore match nobody. Express a range as two conditions
  (`app_version >= 1.4.0` and `app_version < 1.5.0`).
* Event **parameter filters work** — pass them as `triggering.event.params`, and the same shape
  is accepted by the `event_count` and `event_date` targeting conditions. Values are always
  strings, whatever `value_type` says: pass `"3"`, not `3`. (Until mid-2026 these were accepted
  and then silently discarded, which made a `CustomPropertyChanged` campaign fire on every
  property the app reported. If you are talking to an older server, check that a filter you sent
  comes back from `campaign_get`.)
* `campaign_get` returns the campaign spelled the way `campaign_update` takes it (`snake_case`):
  to edit, send its `id` as `campaign_id`, drop `state`, and carry every other field back.
* `campaign_update` **replaces the campaign in full** and returns it to Draft — on a live campaign
  that takes it off air until someone activates it again. There is no clone and no delete, so a
  campaign created by mistake has to be removed by hand in the admin.
* `type: "miniApp"` needs `content.documentId` + `content.versionId` of a document already
  **published in Amply Studio** for that project. The MCP cannot list, author or publish Studio
  documents — the screen is built in the admin; the MCP only attaches it. Mini-app campaigns match
  devices on Amply SDK 0.12.0+ only.
* `install_date` in **relative** mode compares the install's *age*: `greater` 30 days = installed
  more than 30 days ago (the tool description's "greater means more recently" holds only for
  absolute dates). Install date is the first time Amply ran on the device, not the app install.

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

**One thing revocation does not undo.** Disconnecting the app invalidates the connection and its
tokens — it does **not** invalidate an SDK API key obtained through it. Such a key keeps working
until someone deletes it in Amply. So mint a key only when the integration actually needs one, and
prefer reading an application's existing keys over adding another: a spare key is a long-lived
credential nobody is tracking.

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

None of these names exist any more; do not call them: `amply_login`, `amply_logout`,
`amply_status`, `amply_whoami`, `amply_signup`, `amply_ensure_app`, `amply_create_project`,
`amply_list_applications`, `amply_find_application`, `amply_get_application`,
`amply_create_application`, `amply_create_api_key`, `amply_update_campaign`,
`amply_describe_targeting`, `amply_set_campaign_state`, `amply_create_campaign_from_template`.

Several of them do have successors under different names — `project_create`, `applications_list`,
`application_create`, `api_key_create` — but the request shapes differ, so port the call rather than
renaming it. There is no successor at all for signing in (the browser does that), for
`amply_ensure_app`'s one-shot behaviour (do the read-then-create steps yourself), for editing a
campaign, or for campaign templates.
