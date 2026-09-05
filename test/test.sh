#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export SHELL=/bin/zsh
export RESTART_HOME="$HOME/.local/share/restart"
export RESTART_BIN="$HOME/.local/bin/restart"
export RESTART_STATE="$HOME/.local/state/restart"
mkdir -p "$HOME"
printf 'keep-me\n' > "$HOME/.zshrc"

"$ROOT/restart" install >/dev/null
if [ -x "$RESTART_HOME/restart" ] \
  && [ -L "$RESTART_BIN" ] \
  && [ -f "$HOME/.agents/skills/restart/SKILL.md" ] \
  && [ -f "$HOME/.claude/skills/restart/SKILL.md" ]; then
  ok 'installer creates one runtime and both skill links'
else
  bad 'installer layout'
fi

"$ROOT/restart" install >/dev/null
if [ "$(grep -cF '# >>> restart >>>' "$HOME/.zshrc")" -eq 1 ] \
  && grep -qF keep-me "$HOME/.zshrc"; then
  ok 'installer is idempotent and preserves shell config'
else
  bad 'installer duplicated or damaged shell wiring'
fi

if grep -qF '!`restart now`' "$HOME/.agents/skills/restart/SKILL.md" \
  && grep -qF 'CODEX' "$RESTART_HOME/restart" \
  && grep -qF 'CLAUDE_CODE_SESSION_ID' "$RESTART_HOME/restart"; then
  ok 'shared skill and runtime contain both client paths'
else
  bad 'cross-client content'
fi

FAKE_BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/launches"
COUNT="$TEST_ROOT/count"
mkdir -p "$FAKE_BIN"
printf '0\n' > "$COUNT"
: > "$LOG"
cat > "$FAKE_BIN/claude" <<'FAKE_CLAUDE'
#!/bin/sh
printf '%s\n' "$*" >> "$LOG"
n=$(cat "$COUNT")
printf '%s\n' $((n + 1)) > "$COUNT"
if [ "$n" -eq 0 ]; then
  printf '1\tclaude\taaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\trestart\n' > "$AGENT_RESTART_REQUEST"
  exit 129
fi
exit 0
FAKE_CLAUDE
chmod +x "$FAKE_BIN/claude"

PATH="$FAKE_BIN:$PATH" AGENT_RESTART_TESTING=1 LOG="$LOG" COUNT="$COUNT" \
  zsh -fc 'source "$RESTART_HOME/restart"; claude --model sonnet'
if [ "$(sed -n '1p' "$LOG")" = '--model sonnet' ] \
  && [ "$(sed -n '2p' "$LOG")" = '--resume aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' ]; then
  ok 'Claude wrapper resumes the exact requested session'
else
  bad "Claude relaunch args: $(tr '\n' '|' < "$LOG")"
fi

printf '0\n' > "$COUNT"
: > "$LOG"
cat > "$FAKE_BIN/codex" <<'FAKE_CODEX'
#!/bin/sh
[ "${AGENT_RESTART_EXPECT_REGISTRY:-}" != 1 ] || [ -f "$RESTART_STATE/wrappers/$PPID" ] || exit 88
printf '%s\n' "$*" >> "$LOG"
n=$(cat "$COUNT")
printf '%s\n' $((n + 1)) > "$COUNT"
if [ "$n" -eq 0 ]; then
  printf '1\tcodex\t01a03269-1106-7263-837c-61f1b5f0310a\trestart\n' > "$AGENT_RESTART_REQUEST"
  exit 129
fi
exit 0
FAKE_CODEX
chmod +x "$FAKE_BIN/codex"

PATH="$FAKE_BIN:$PATH" AGENT_RESTART_TESTING=1 AGENT_RESTART_EXPECT_REGISTRY=1 LOG="$LOG" COUNT="$COUNT" \
  zsh -fc 'source "$RESTART_HOME/restart"; codex --no-alt-screen'
if grep -q -- '--no-alt-screen' "$LOG" \
  && grep -q -- 'resume 01a03269-1106-7263-837c-61f1b5f0310a' "$LOG"; then
  ok 'Codex wrapper resumes the exact requested session'
else
  bad "Codex relaunch args: $(tr '\n' '|' < "$LOG")"
fi

: > "$LOG"
PATH="$FAKE_BIN:$PATH" LOG="$LOG" COUNT="$COUNT" \
  zsh -fc 'source "$RESTART_HOME/restart"; codex exec hello'
if [ "$(cat "$LOG")" = 'exec hello' ]; then
  ok 'non-interactive Codex subcommands bypass supervision'
else
  bad 'Codex pass-through'
fi

: > "$LOG"
PATH="$FAKE_BIN:$PATH" LOG="$LOG" COUNT="$COUNT" \
  zsh -fc 'codex() { command codex --existing-wrapper "$@"; }; source "$RESTART_HOME/restart"; codex exec hello'
if [ "$(cat "$LOG")" = '--existing-wrapper exec hello' ]; then
  ok 'existing client wrapper behavior is preserved'
else
  bad "existing wrapper lost: $(cat "$LOG")"
fi

REQUEST="$TEST_ROOT/request"
: > "$REQUEST"
sleep 30 &
TARGET=$!
AGENT_RESTART_REQUEST="$REQUEST" \
AGENT_RESTART_TARGET_PID="$TARGET" \
CODEX_SESSION_ID=01a03269-1106-7263-837c-61f1b5f0310a \
  "$RESTART_HOME/restart" now >/dev/null
wait "$TARGET" 2>/dev/null
TARGET_RC=$?
if [ "$TARGET_RC" -eq 129 ] \
  && [ "$(cat "$REQUEST")" = $'1\tcodex\t01a03269-1106-7263-837c-61f1b5f0310a\trestart' ]; then
  ok 'client-side trigger writes session and sends SIGHUP'
else
  bad "trigger request or signal: rc=$TARGET_RC payload=$(cat "$REQUEST")"
fi

PIPE_HOME="$TEST_ROOT/pipe-home"
mkdir -p "$PIPE_HOME"
env -u CODEX_SESSION_ID -u CODEX_THREAD_ID -u CLAUDE_CODE_SESSION_ID \
  -u RESTART_HOME -u RESTART_BIN -u RESTART_STATE \
  HOME="$PIPE_HOME" SHELL=/bin/zsh RESTART_SOURCE_URL="file://$ROOT/restart" \
  sh < "$ROOT/restart" >/dev/null
if [ -x "$PIPE_HOME/.local/share/restart/restart" ] \
  && [ -f "$PIPE_HOME/.agents/skills/restart/SKILL.md" ] \
  && [ -f "$PIPE_HOME/.claude/skills/restart/SKILL.md" ]; then
  ok 'piped one-line installation path works'
else
  bad 'piped installation path'
fi

"$RESTART_HOME/restart" uninstall >/dev/null
if [ ! -e "$RESTART_BIN" ] \
  && [ ! -e "$HOME/.agents/skills/restart" ] \
  && [ ! -e "$HOME/.claude/skills/restart" ] \
  && ! grep -qF '# >>> restart >>>' "$HOME/.zshrc" \
  && grep -qF keep-me "$HOME/.zshrc"; then
  ok 'uninstall removes only restart-owned wiring'
else
  bad 'uninstall cleanup'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
