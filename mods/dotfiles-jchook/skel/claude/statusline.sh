#!/usr/bin/env bash
set -euo pipefail
# para: Claude Code status line — a persistent, always-visible tag telling you
# which workspace this claude instance is in, even when the TUI is full-screen.
#
# Keys off the container hostname (para-<name>), so it works no matter how
# claude was launched — `para claude`, or `claude` inside `para sh`. Claude pipes
# a JSON blob on stdin we have no use for, so drain it and read the hostname.
cat >/dev/null 2>&1 || true

ws="$(hostname 2>/dev/null || true)"; ws="${ws#para-}"
[ -n "$ws" ] || ws="workspace"

# A stable color per workspace name, so several open at once read as different
# colors at a glance and not just as different text. 31–36 are the ANSI colors
# and +60 is each one's bright twin — twelve to collide in.
hash="$(printf '%s' "$ws" | cksum)"; hash="${hash%% *}"
color=$(( hash % 6 + 31 ))
if [ $(( hash / 6 % 2 )) -eq 1 ]; then color=$(( color + 60 )); fi

# Branch of whatever repo claude is running in (its cwd is the workspace clone).
branch="$(git branch --show-current 2>/dev/null || true)"

printf '\033[1;%sm▉ %s\033[0m' "$color" "$ws"
if [ -n "$branch" ]; then printf ' \033[2m⎇ %s\033[0m' "$branch"; fi
