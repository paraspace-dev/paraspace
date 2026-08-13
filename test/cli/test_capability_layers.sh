#!/usr/bin/env bash
# CLI-tier tests for the bundled Void capability layers. Package installation
# is an image/e2e concern; these run their workspace hooks against throwaway homes.
# shellcheck disable=SC2016  # generated fake scripts expand when they run

capability_repo() { cd "$(dirname "$PARA")/.." && pwd; }

test_git_layer_clones_and_converges() {
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
    PARA_PROJECT_NAME=acme PARA_HOSTNAME=host1 \
    bash "$repo/layers/git/hooks/provision" >/dev/null 2>&1

  assert test -f "$shared/git/ssh/id_ed25519.pub" || return 1
  assert_contains "$(cat "$shared/git/ssh/id_ed25519.pub")" "para-acme-host1" \
    "the key names its project and machine" || return 1
  assert test -d "$home/app/.git" || return 1
  assert_eq "TOKEN=one" "$(cat "$home/app/.env")" "the host env reached the clone" || return 1
  assert_eq "git:before" "$(cat "$root/points")" "the layer opened its hook point" || return 1
  assert_contains "$(cat "$root/git-calls")" "--branch main" "the branch reached git clone" || return 1

  env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
    PARA_SHARED="$shared" PARA_ORIGIN=https://example.com/acme/app.git \
    PARA_CLONE_DIR=app PARA_CLONE_BRANCH=main PARA_HOST_ENV="$host_env" \
    PARA_RUN_HOOK="$fake/run-hook" PARA_NAME=feat GIT_CALLS="$root/git-calls" \
    POINT_CALLS="$root/points" bash "$repo/layers/git/hooks/provision" >/dev/null 2>&1
  assert_eq 1 "$(wc -l < "$root/git-calls" | tr -d ' ')" "a second provision did not clone again" || return 1
  assert_eq 2 "$(wc -l < "$root/points" | tr -d ' ')" "the integration point converges every time"
}

test_docker_layer_boots_only_a_compose_clone() {
  # Both halves of "only": it boots a clone that has a Compose file, and it is a
  # no-op for the two shapes that have none, which is what lets a project vendor
  # this mod without a Compose stack.
  local repo root fake calls points
  repo="$(capability_repo)"; root="$(scratch)"; fake="$root/bin"; calls="$root/docker-calls"
  points="$root/points"
  mkdir -p "$fake"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$DOCKER_CALLS"' > "$fake/docker"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$POINT_CALLS"' \
    > "$fake/run-hook"
  chmod +x "$fake/docker" "$fake/run-hook"
  a_docker_boot() { # a_docker_boot <home>
    env HOME="$1" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
      PARA_CLONE_DIR=app DOCKER_CALLS="$calls" POINT_CALLS="$points" \
      PARA_RUN_HOOK="$fake/run-hook" \
      bash "$repo/layers/docker/hooks/boot" >/dev/null 2>&1
  }

  mkdir -p "$root/no-clone"
  a_docker_boot "$root/no-clone" || return 1
  assert test ! -e "$calls" || return 1

  mkdir -p "$root/no-compose/app"
  a_docker_boot "$root/no-compose" || return 1
  assert test ! -e "$calls" || return 1

  mkdir -p "$root/stack/app"; : > "$root/stack/app/compose.yaml"
  a_docker_boot "$root/stack" || return 1
  assert_eq "compose up -d --wait --wait-timeout 300" "$(cat "$calls")" \
    "the compose boot waits for readiness" || return 1
  assert_eq 3 "$(wc -l < "$points" | tr -d ' ')" \
    "the hook point opens on every boot, stack or no stack" || return 1
  assert_eq "docker:boot:after" "$(tail -n1 "$points")" \
    "and it is the layer's own point that opened"
}

test_git_layer_trusts_the_ssh_host_it_will_clone_from() {
  # The ssh:// path, which the https test above never reaches: the origin's host
  # and its port both have to survive into ssh-keyscan, or git clone stops at
  # host key verification and the hook misreads that as an unauthorized key.
  local repo root home shared fake
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"
  mkdir -p "$home" "$shared" "$fake"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1" = clone ]; then dest="${@: -1}"; mkdir -p "$dest/.git"; fi' > "$fake/git"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake/run-hook"
  # -F never knows the host, so every run reaches ssh-keyscan; -f still has to
  # leave a keypair behind, since the hook links both halves into ~/.ssh.
  printf '%s\n' '#!/usr/bin/env bash' \
    'case " $* " in *" -F "*) exit 1 ;; esac' \
    'while [ "$#" -gt 0 ]; do' \
    '  if [ "$1" = -f ]; then : > "$2"; printf "ssh-ed25519 AAAA test\n" > "$2.pub"; fi' \
    '  shift' \
    'done' > "$fake/ssh-keygen"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$SCAN_CALLS"' > "$fake/ssh-keyscan"
  chmod +x "$fake/git" "$fake/run-hook" "$fake/ssh-keygen" "$fake/ssh-keyscan"

  a_git_provision() { # a_git_provision <origin> <home>
    env HOME="$2" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
      PARA_SHARED="$shared" PARA_ORIGIN="$1" PARA_CLONE_DIR=app \
      PARA_HOST_ENV="$root/absent.env" PARA_RUN_HOOK="$fake/run-hook" \
      PARA_NAME=feat PARA_PROJECT_NAME=acme SCAN_CALLS="$root/scan-calls" \
      bash "$repo/layers/git/hooks/provision" >/dev/null 2>&1
  }

  mkdir -p "$root/scp"
  a_git_provision git@github.com:acme/app.git "$root/scp" || return 1
  assert_eq "-H -p 22 github.com" "$(cat "$root/scan-calls")" \
    "the scp-like origin is scanned on the default port" || return 1

  rm -f "$root/scan-calls"; mkdir -p "$root/url"
  a_git_provision ssh://git@git.example.com:2222/acme/app.git "$root/url" || return 1
  assert_eq "-H -p 2222 git.example.com" "$(cat "$root/scan-calls")" \
    "and an ssh:// origin keeps the port it names"
}

test_git_layer_points_a_github_origin_at_key_settings() {
  # The authorize pause prints where the key goes, but only GitHub has a URL
  # the layer knows; any other host gets just the key.
  local repo root home shared fake out
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"; out="$root/out"
  mkdir -p "$home" "$shared" "$fake"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$fake/git"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake/run-hook"
  printf '%s\n' '#!/usr/bin/env bash' \
    'case " $* " in *" -F "*) exit 1 ;; esac' \
    'while [ "$#" -gt 0 ]; do' \
    '  if [ "$1" = -f ]; then : > "$2"; printf "ssh-ed25519 AAAA test\n" > "$2.pub"; fi' \
    '  shift' \
    'done' > "$fake/ssh-keygen"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake/ssh-keyscan"
  chmod +x "$fake"/*

  a_failed_provision() { # a_failed_provision <origin>
    env HOME="$home" PATH="$fake:$PATH" PARA_HELPERS="$repo/libexec/helpers" \
      PARA_SHARED="$shared" PARA_ORIGIN="$1" PARA_CLONE_DIR=app \
      PARA_HOST_ENV="$root/absent.env" PARA_RUN_HOOK="$fake/run-hook" \
      PARA_NAME=feat PARA_PROJECT_NAME=acme PARA_NONINTERACTIVE=1 \
      bash "$repo/layers/git/hooks/provision" >/dev/null 2>"$out" || true
  }

  a_failed_provision git@github.com:acme/app.git
  assert_contains "$(cat "$out")" "https://github.com/settings/keys" \
    "a GitHub origin prints the key settings URL" || return 1
  a_failed_provision git@git.example.com:acme/app.git
  assert_not_contains "$(cat "$out")" "settings/keys" \
    "another host does not get GitHub's URL"
}

a_gh_hook() { # a_gh_hook <hook> <repo> <home> <shared> <fake> <calls>
  env HOME="$3" PATH="$5:$PATH" PARA_HELPERS="$2/libexec/helpers" \
    PARA_LAYER_DIR="$2/layers/gh" PARA_SHARED="$4" PARA_GH_AUTH=1 \
    PARA_ORIGIN=git@github.com:acme/app.git GH_CALLS="$6" \
    bash "$2/layers/gh/hooks/$1" >/dev/null 2>&1
}

test_gh_layer_authorizes_a_git_key_once() {
  local repo root home shared fake calls
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"; calls="$root/gh-calls"
  mkdir -p "$home/.ssh" "$shared" "$fake"
  printf 'ssh-ed25519 test\n' > "$home/.ssh/id_ed25519.pub"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$GH_CALLS"' \
    'exit 0' > "$fake/gh"
  chmod +x "$fake/gh"
  a_gh_hook git:before "$repo" "$home" "$shared" "$fake" "$calls"
  assert test -f "$shared/gh/.key-authorized" || return 1
  assert test -L "$home/.config/gh" || return 1
  assert_contains "$(cat "$calls")" "ssh-key add" "the key was uploaded" || return 1
  local before; before="$(wc -l < "$calls" | tr -d ' ')"
  a_gh_hook git:before "$repo" "$home" "$shared" "$fake" "$calls"
  assert_eq "$before" "$(wc -l < "$calls" | tr -d ' ')" \
    "the authorization marker prevents another GitHub call"
}

test_gh_layer_never_adds_a_key_github_already_holds() {
  # The re-run path after you delete the marker, or authorize by hand: GitHub
  # rejects the duplicate, so an add there would fail the hook forever.
  local repo root home shared fake calls
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"; calls="$root/gh-calls"
  mkdir -p "$home/.ssh" "$shared" "$fake"
  printf 'ssh-ed25519 AAAAKEY para\n' > "$home/.ssh/id_ed25519.pub"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$GH_CALLS"' \
    'if [ "$2" = list ]; then echo "para  ssh-ed25519 AAAAKEY  authentication"; fi' \
    'if [ "$2" = add ]; then exit 1; fi' > "$fake/gh"
  chmod +x "$fake/gh"
  a_gh_hook git:before "$repo" "$home" "$shared" "$fake" "$calls"
  assert test -f "$shared/gh/.key-authorized" || return 1
  assert_not_contains "$(cat "$calls")" "ssh-key add" "the key already there is not re-added"
}

test_gh_layer_shares_its_config_without_the_git_layer() {
  # The link is the layer's own provision hook, so a project that clones itself
  # still gets one gh login for every workspace.
  local repo root home shared fake
  repo="$(capability_repo)"; root="$(scratch)"; home="$root/home"
  shared="$root/shared"; fake="$root/bin"
  mkdir -p "$home/.config/gh" "$shared" "$fake"
  printf 'stale\n' > "$home/.config/gh/hosts.yml"
  a_gh_hook provision "$repo" "$home" "$shared" "$fake" "$root/gh-calls" || return 1
  assert test -L "$home/.config/gh" || return 1
  assert test -d "$shared/gh"
}
