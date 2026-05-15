# Context7 MCP — first-class source for Amply docs

Amply's public docs live at [docs.amply.tools](https://docs.amply.tools) and are mirrored into the [Context7](https://context7.com) registry. When the host agent has the Context7 MCP server connected, the skill **prefers Context7 lookups over its baked-in cheatsheets** — Context7 reflects whatever the live docs say, while these cheatsheets are a snapshot.

## Phase 0 — toolchain check (the skill's first action)

Run this once at the start of every session, **before** Phase 1.

### Step 1 — Detect Context7

In the same shell the agent runs:

```bash
claude mcp list | grep -i context7
```

For Codex CLI, the equivalent is `codex mcp list` (subcommand may be `codex mcp` — verify with `codex mcp --help` if the spelling has changed since this file was written). For other hosts, follow their MCP-listing command.

A line like `context7: ... ✓ Connected` means the server is wired up. Anything else (`✗ Failed to connect`, no line at all) means it isn't usable.

### Step 2a — Context7 is available

Use it for SDK reference questions:

1. Resolve the library ID once per session:
   - Tool call: `mcp__context7__resolve-library-id` with query `"amply"` (or `"amply.tools"` / `"@amplytools/react-native-amply-sdk"`).
   - Capture the canonical library ID — it usually looks like `amply-tools/sdk` or similar.
2. Pull docs on demand:
   - Tool call: `mcp__context7__get-library-docs` with the library ID.
   - Optionally pass a topic: `"react native initialization"`, `"deeplink listener swift"`, `"custom properties"`, `"who when what targeting"`.
3. Treat the returned content as **authoritative for that session** — newer than the cheatsheets in this skill.
4. If the docs in Context7 disagree with this skill's cheatsheets, follow Context7 and file a `[fix]` issue against the skill so the cheatsheet catches up.

### Step 2b — Context7 is not available

**Two branches, depending on whether a human is in the loop.**

**Human-in-the-loop:** offer to install. **It's free** and takes ~30 seconds.

**Autonomous run (sub-agent, batch job, CI):** do NOT install. Installing an MCP changes the user's environment and shouldn't happen without consent. Log this as a TODO in `amply-skill-trial-log.md` / `amply-audit.md` ("Context7 MCP not connected; install recommended for future runs — see `references/context7-mcp.md`") and proceed using the bundled `references/sdk-cheatsheet-*.md` cheatsheets. The integration still works; the audit just won't reflect the freshest docs.

If you're not sure which branch you're in (your host doesn't surface user-interaction capability), default to autonomous-mode behaviour — never install MCP without an explicit opt-in.

Install command (human-in-the-loop only):

```bash
# Claude Code — recommended
claude mcp add --transport http context7 https://mcp.context7.com/mcp

# Alternative — if HTTP transport isn't preferred
claude mcp add context7 -- npx -y @upstash/context7-mcp
```

For Codex CLI, the canonical install is via the host's `mcp` config. Verify by running `codex mcp add --help` and follow the printed flags. The endpoint to add is the same as above (`https://mcp.context7.com/mcp`).

After installation, ask the user to restart the agent session so the new MCP is picked up. Then continue from Phase 1.

If the user declines the install, fall back to the bundled `references/sdk-cheatsheet-{rn,ios,android,kmp}.md` files. Note in the audit report that the skill ran without Context7 — future re-runs will benefit from installing it.

## What the skill should still NOT do, even with Context7

- Don't replace the entire skill with "ask Context7". The skill's value is the **opinionated workflow** (Phases 1–7 with sub-phases), not a docs lookup loop.
- Don't expose `apiKeySecret` to the user verbatim from the live docs without flagging that the value is a real secret to keep out of source control.
- Don't blindly trust a Context7 result if it materially contradicts what the agent observes in the actual SDK source files in the user's project — when both are present, the project's actual installed SDK version wins.

## When the project ships its own MCP

Some Amply customers may add their own internal MCP that exposes campaign / event metadata. The skill should also check `claude mcp list` for anything matching `amply` (case-insensitive) — if found, surface it to the user as a richer source for Phase 4 (Who/When/What audit), since it can answer "what events / properties are already configured in our admin panel".

## Capturing the result in `amply-audit.md`

```
Toolchain:
  Context7 MCP:        <connected | installed-this-session | declined | unavailable>
  Project-specific MCP: <name + endpoint | none>
  Docs source for this run: <Context7 library:id | bundled cheatsheets | mixed>
```
