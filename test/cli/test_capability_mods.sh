#!/usr/bin/env bash
# CLI-tier tests for the bundled Void capability mods. Package installation is
# an image/e2e concern; these run their workspace hooks against throwaway homes.
# shellcheck disable=SC2016  # generated fake scripts expand when they run

capability_repo() { cd "$(dirname "$PARA")/.." && pwd; }

test_git_mod_clones_and_converges() {
  local repo root home shared fake host_env
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"; host_env="$root/host.env"
  mkdir -p "$home" "$shared" "$fake"
  printf 'TOKEN=one\n' > "$host_env"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$GIT_CALLS"' \
    'if [ "$1" = clone ]; then dest="${@: -1}"; mkdir -p "$dest/.git"; fi' \
    > "$fake/git"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$POINT_CALLS"' \
    > "$fake/run-hook"
  chmod +x "$fake/git" "$fake/run-hook"

  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_SHARED="$shared" PARA_ORIGIN=https://example.com/acme/app.git \
    PARA_CLONE_DIR=app PARA_CLONE_BRANCH=main PARA_HOST_ENV="$host_env" \
    PARA_RUN_HOOK="$fake/run-hook" PARA_NAME=feat GIT_CALLS="$root/git-calls" \
    POINT_CALLS="$root/points" PARA_GIT_NAME=Acme PARA_GIT_EMAIL=dev@example.com \
    bash "$repo/mods/git/hooks/provision" >/dev/null 2>&1

  assert test -f "$shared/git/ssh/id_ed25519.pub" || return 1
  assert test -d "$home/app/.git" || return 1
  assert_eq "TOKEN=one" "$(cat "$home/app/.env")" "the host env reached the clone" || return 1
  assert_eq "git:before" "$(cat "$root/points")" "the mod opened its hook point" || return 1
  assert_contains "$(cat "$root/git-calls")" "--branch main" "the branch reached git clone" || return 1

  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_SHARED="$shared" PARA_ORIGIN=https://example.com/acme/app.git \
    PARA_CLONE_DIR=app PARA_CLONE_BRANCH=main PARA_HOST_ENV="$host_env" \
    PARA_RUN_HOOK="$fake/run-hook" PARA_NAME=feat GIT_CALLS="$root/git-calls" \
    POINT_CALLS="$root/points" bash "$repo/mods/git/hooks/provision" >/dev/null 2>&1
  assert_eq 1 "$(wc -l < "$root/git-calls" | tr -d ' ')" "a second provision did not clone again" || return 1
  assert_eq 2 "$(wc -l < "$root/points" | tr -d ' ')" "the integration point converges every time"
}

test_docker_mod_boots_only_a_compose_clone() {
  local repo root home fake
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"; fake="$root/bin"
  mkdir -p "$home/app" "$fake"
  : > "$home/app/compose.yaml"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" > "$DOCKER_CALLS"' > "$fake/docker"
  chmod +x "$fake/docker"
  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_CLONE_DIR=app DOCKER_CALLS="$root/docker-calls" \
    bash "$repo/mods/docker/hooks/boot" >/dev/null 2>&1
  assert_eq "compose up -d --wait --wait-timeout 300" "$(cat "$root/docker-calls")" \
    "the compose boot waits for readiness"
}

test_gh_mod_authorizes_a_git_key_once() {
  local repo root home shared fake
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"
  mkdir -p "$home/.ssh" "$shared" "$fake"
  printf 'ssh-ed25519 test\n' > "$home/.ssh/id_ed25519.pub"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$GH_CALLS"' \
    'exit 0' > "$fake/gh"
  chmod +x "$fake/gh"
  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_SHARED="$shared" PARA_GH_AUTH=1 PARA_ORIGIN=git@github.com:acme/app.git \
    GH_CALLS="$root/gh-calls" bash "$repo/mods/gh/hooks/git:before" >/dev/null 2>&1
  assert test -f "$shared/gh/.key-authorized" || return 1
  assert test -L "$home/.config/gh" || return 1
  local before; before="$(wc -l < "$root/gh-calls" | tr -d ' ')"
  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_SHARED="$shared" PARA_GH_AUTH=1 PARA_ORIGIN=git@github.com:acme/app.git \
    GH_CALLS="$root/gh-calls" bash "$repo/mods/gh/hooks/git:before" >/dev/null 2>&1
  assert_eq "$before" "$(wc -l < "$root/gh-calls" | tr -d ' ')" \
    "the authorization marker prevents another GitHub call"
}
