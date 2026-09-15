# Bundled agent configuration

Configuration carried to every machine devbox provisions, for both agent
harnesses. Nothing here is installed by default: the bundle is written only
when the Claude Code or Codex module is selected.

## Status

Structure only. The contents are not yet defined, and no manifest module
installs the bundle yet.

## Layout

| Path | Harness | Holds | Installed to |
|---|---|---|---|
| `claude/.claude-plugin/plugin.json` | Claude Code | plugin manifest | — |
| `claude/commands/` | Claude Code | slash commands, one `.md` per command | `~/.claude/plugins/devbox/commands/` |
| `claude/skills/` | Claude Code | skills, one directory per skill with a `SKILL.md` | `~/.claude/plugins/devbox/skills/` |
| `claude/agents/` | Claude Code | subagent definitions, one `.md` each | `~/.claude/plugins/devbox/agents/` |
| `claude/hooks/hooks.json` | Claude Code | PreToolUse, PostToolUse and Stop hooks | `~/.claude/plugins/devbox/hooks/` |
| `claude/rules/` | Claude Code | rule files referenced from `CLAUDE.md` | `~/.claude/rules/` |
| `codex/AGENTS.md` | Codex | project and global instructions | `~/.codex/AGENTS.md` |
| `codex/prompts/` | Codex | custom prompts, one `.md` per prompt | `~/.codex/prompts/` |
| `codex/rules/` | Codex | rule files included from `AGENTS.md` | `~/.codex/rules/` |
| `codex/hooks/` | Codex | `notify` handlers referenced from `config.toml` | `~/.codex/hooks/` |

## Adding content

1. Drop the file into the directory for its harness and kind.
2. Keep one concern per file; both harnesses load these as plain Markdown.
3. Anything that applies to both harnesses belongs in `claude/rules/` and is
   mirrored into `codex/rules/`, not duplicated by hand.
