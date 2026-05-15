# Tool-name mapping — Claude Code → Codex CLI

The `SKILL.md` body is written with tool-neutral verbs (*open*, *modify*, *grep*, *run shell command*, *dispatch a sub-agent*). When you need an explicit translation between Claude Code tool names and Codex CLI equivalents, use this table.

| Action | Claude Code | Codex CLI |
|---|---|---|
| Read a file | `Read` | `read_file` (file ops via Codex's filesystem MCP) or shell `cat` via the shell tool. |
| Edit a file | `Edit` | `apply_patch` (Codex's patch-apply tool) or shell `sed` / direct file write. |
| Create / overwrite a file | `Write` | `apply_patch` with a new-file diff. |
| Run a shell command | `Bash` | `shell` (Codex's exec tool). |
| List directory | `Bash` (`ls`) | `shell` (`ls`). |
| Search code | `Bash` (`grep` / `rg`) | `shell` (`rg`). |
| Dispatch a sub-agent | `Agent` (with `subagent_type`) | Codex sub-task launch via the orchestration API; or invoke `codex exec` recursively from the `shell` tool. |
| Background / long-running command | `Bash` with `run_in_background` | `shell` with `&` redirected to a log file, then poll. |
| Track tasks | `TaskCreate` / `TaskUpdate` / `TaskList` | Codex maintains its own internal task list — use whatever the active session exposes; otherwise just keep a Markdown todo list in the chat. |

**Skill loading paths** *(verify on a fresh install before relying on these)*:

| Runtime | Per-user skill directory |
|---|---|
| Claude Code | `~/.claude/skills/<skill-name>/` |
| Claude Code (plugin author) | inside the plugin package, alongside `plugin.json` |
| Codex CLI | `~/.agents/skills/<skill-name>/` (per the Codex skill spec) |

If a Codex install lays out skills differently in a future version, update this file and the `Skill Architecture → Cross-tool compatibility` section in `PLAN.md`.

**Behavioural parity:**
- Both runtimes load `SKILL.md` and treat its frontmatter as the matcher.
- Reference files (`references/*.md`) are pulled in only when the body explicitly mentions them.
- Neither runtime executes code from the skill — the agent reads, the user approves, the agent acts via tools.
