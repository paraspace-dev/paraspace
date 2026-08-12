#!/usr/bin/env bash
# Host-side Docker layer configuration against deterministic Compose JSON,
# driven through `para add docker`, which runs the configure chain.
# shellcheck disable=SC2016  # generated fake scripts expand when they run

docker_config_repo() { cd "$(dirname "$PARA")/.." && pwd; }

fake_compose() { # fake_compose <dir>
  mkdir -p "$1"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1 $2" = "compose version" ]; then exit 0; fi' \
    'if [ "$1 $2 $3 $4" = "compose config --format json" ]; then command cat "$COMPOSE_MODEL"; exit; fi' \
    'exit 1' > "$1/docker"
  chmod +x "$1/docker"
}

docker_add_model() { # docker_add_model <project> <model> <fake>
  a_linked_package "$1"
  env PARA_PROJECT_DIR="$1" COMPOSE_MODEL="$2" PATH="$3:$PATH" "$PARA" add docker 2>&1
}

test_docker_configure_infers_one_apex_route_and_explicit_images() {
  local repo p fake out
  repo="$(docker_config_repo)"; p="$(a_project)"; fake="$(scratch)"; fake_compose "$fake"
  out="$(docker_add_model "$p" "$repo/test/fixtures/compose/single.json" "$fake")" || return 1
  assert_contains "$(cat "$p/.paraspace/env")" 'PARA_PREPULL_IMAGES=example/web:latest' "explicit image inferred" || return 1
  assert_contains "$(cat "$p/.paraspace/env")" 'PARA_ROUTES=8080' "one port uses the apex" || return 1
  assert_not_contains "$(cat "$p/.paraspace/env")" 'worker' "build-only service has no generated image" || return 1
  assert_contains "$out" 'Set PARA_ROUTES' "the additive edit is reported"
}

test_docker_configure_resolves_multiple_routes_and_skips_unsafe_ports() {
  local repo p fake out parafile
  repo="$(docker_config_repo)"; p="$(a_project)"; fake="$(scratch)"; fake_compose "$fake"
  out="$(docker_add_model "$p" "$repo/test/fixtures/compose/multiple.json" "$fake")" || return 1
  parafile="$(cat "$p/.paraspace/env")"
  assert_contains "$parafile" 'PARA_PREPULL_IMAGES=registry.example/app:ready' "resolved duplicate images are removed" || return 1
  assert_eq 1 "$(grep -c '^PARA_PREPULL_IMAGES=' "$p/.paraspace/env")" "one image declaration" || return 1
  assert_contains "$parafile" 'PARA_ROUTES=web-app-http-main:8080\ web-app-8081:8081\ api:4000' "service and port names are DNS-safe" || return 1
  assert_contains "$out" "unpublished or ranged" "ranges/random publishing are explained" || return 1
  assert_contains "$out" "loopback" "loopback is explained" || return 1
  assert_contains "$out" "application protocol is mqtt" "non-HTTP is explained"
}

test_docker_configure_keeps_existing_values_independently_and_is_idempotent() {
  local repo p fake before
  repo="$(docker_config_repo)"; p="$(a_project 'PARA_ROUTES=""')"; fake="$(scratch)"; fake_compose "$fake"
  docker_add_model "$p" "$repo/test/fixtures/compose/single.json" "$fake" >/dev/null || return 1
  before="$(cat "$p/.paraspace/env")"
  docker_add_model "$p" "$repo/test/fixtures/compose/single.json" "$fake" >/dev/null || return 1
  assert_eq "$before" "$(cat "$p/.paraspace/env")" "re-adding creates no duplicate declarations" || return 1
  assert_contains "$before" 'PARA_ROUTES=""' "an empty route remains authoritative" || return 1
  assert_contains "$before" 'PARA_PREPULL_IMAGES=example/web:latest' "the other setting is still inferred"
}

test_docker_configure_skips_all_routes_on_duplicate_normalized_hosts() {
  local repo p fake out
  repo="$(docker_config_repo)"; p="$(a_project)"; fake="$(scratch)"; fake_compose "$fake"
  out="$(docker_add_model "$p" "$repo/test/fixtures/compose/duplicate.json" "$fake")" || return 1
  assert_not_contains "$(cat "$p/.paraspace/env")" 'PARA_ROUTES=' "ambiguous routes are not guessed" || return 1
  assert_contains "$(cat "$p/.paraspace/env")" 'PARA_PREPULL_IMAGES=one:1\ two:2' "image inference is independent" || return 1
  assert_contains "$out" "unique DNS-safe" "the skipped route is explained"
}

test_docker_configure_missing_tools_and_bad_json_are_nonfatal() {
  local repo p empty fake nocompose out
  repo="$(docker_config_repo)"; p="$(a_project)"; empty="$(scratch)"
  out="$(env -i PATH="$empty" PARA_PROJECT_DIR="$p" PARA_LAYER_DIR="$repo/layers/docker" PARA_HELPERS="$repo/libexec/helpers" /bin/bash "$repo/layers/docker/configure" 2>&1)" || return 1
  assert_contains "$out" "Node.js is not available" "missing Node warns" || return 1

  nocompose="$(scratch)"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$nocompose/docker"; chmod +x "$nocompose/docker"
  out="$(PATH="$nocompose:$(dirname "$(command -v node)"):/usr/bin:/bin" PARA_PROJECT_DIR="$p" \
    PARA_LAYER_DIR="$repo/layers/docker" PARA_HELPERS="$repo/libexec/helpers" \
    bash "$repo/layers/docker/configure" 2>&1)" || return 1
  assert_contains "$out" "Docker Compose is not available" "missing Compose warns" || return 1

  fake="$(scratch)"; fake_compose "$fake"
  printf 'not json\n' > "$fake/bad.json"
  out="$(COMPOSE_MODEL="$fake/bad.json" PATH="$fake:$PATH" PARA_PROJECT_DIR="$p" PARA_LAYER_DIR="$repo/layers/docker" PARA_HELPERS="$repo/libexec/helpers" bash "$repo/layers/docker/configure" 2>&1)" || return 1
  assert_contains "$out" "could not be inspected" "malformed Compose output warns" || return 1
  assert_not_contains "$(cat "$p/.paraspace/env")" 'PARA_PREPULL_IMAGES=' "no edit on malformed output"
}
