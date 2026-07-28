#!/usr/bin/env bash
# para: Claude Code status line — a persistent, always-visible tag telling you
# which workspace this claude instance is in, even when the TUI is full-screen.
#
# Keys off the container hostname (para-<name>), so it works no matter how
# claude was launched — `para claude`, or `claude` inside `para sh`. Claude
# pipes a JSON blob on stdin (session/model/context info); we don't need it, so
# just drain it (claude closes stdin after writing) and key off the hostname.
cat >/dev/null 2>&1 || true

ws="$(hostname 2>/dev/null)"; ws="${ws#para-}"
[ -n "$ws" ] || ws="workspace"

# Stable, distinct color per workspace name (char-sum → palette index) so ws1
# and ws2 read as different colors at a glance, not just different text.
sum=0
for ((i = 0; i < ${#ws}; i++)); do printf -v o '%d' "'${ws:i:1}"; sum=$((sum + o)); done
palette=(31 32 33 34 35 36 91 92 93 94 95 96)
c="${palette[sum % ${#palette[@]}]}"

# Branch of whatever repo claude is running in (its cwd is the workspace clone).
branch="$(git branch --show-current 2>/dev/null || true)"

printf '\033[1;%sm▉ %s\033[0m' "$c" "$ws"
[ -n "$branch" ] && printf ' \033[2m⎇ %s\033[0m' "$branch"
