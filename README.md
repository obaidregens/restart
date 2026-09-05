# restart

Restart Claude Code or Codex in place and resume the exact live conversation.
The restart itself is local shell work, so it still works when the active model
or provider is unavailable.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/obaidregens/restart/refs/heads/main/restart | sh
```

Open a new terminal after installation.

| Client | Restart command | Needs the model? |
|---|---|---|
| Claude Code | `/restart` | No. The skill's `` !`restart now` `` is expanded client-side. |
| Codex CLI | `!restart` | No. `!` is Codex's client-side shell mode. |
| Codex CLI | `$restart` | Yes. This is the discoverable skill entry point. |

The installer is also the runtime: one downloaded file provides the shell
wrappers, `restart` executable, Claude skill, and Codex skill. It installs the
canonical copy at `~/.local/share/restart/restart`, links it into
`~/.local/bin`, and links one shared `SKILL.md` into both clients.

## Manage

```sh
restart status
restart install       # idempotent repair/update
restart uninstall
```

The shell wrapper supervises only interactive `claude` and `codex` sessions.
Commands such as `claude --print`, `codex exec`, `codex review`, login, update,
and MCP management pass through unchanged.

## How it works

Each wrapper creates a private one-shot request file before launching the CLI.
Claude Code exposes `CLAUDE_CODE_SESSION_ID`; Codex shell mode exposes
`CODEX_SESSION_ID`. The local command writes that exact ID, sends SIGHUP to the
wrapped foreground client, and the supervisor resumes only the requested ID.
Claude receives the private channel directly. Codex shell commands can run in a
pre-existing app-server process, so restart maps the live session's writer lock
back to the exact Codex process and its registered private channel (`lsof` on
macOS, `/proc` on Linux).
An unrelated SIGHUP, a malformed request, or a dead terminal never relaunches.

`agent_restart_loop <client> <launch-function> [args...]` is the small public
shell API for tools that need work between exit and resume. `/use-aws` uses this
hook to change provider settings while leaving restart ownership here.

## Requirements

- macOS or Linux
- zsh or Bash as the interactive shell
- `curl` for one-line installation
- `lsof` on macOS (included with macOS); Linux uses `/proc`

## License

MIT
