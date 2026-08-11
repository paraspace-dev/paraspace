#!/usr/bin/env bash
# CLI-tier coverage for the shared host/guest helper primitives.
# shellcheck disable=SC2016  # command bodies expand in their child bash, not here

helpers_repo() { cd "$(dirname "$PARA")/.." && pwd; }

test_set_parafile_var_respects_existing_assignment_forms() {
  local root p form before
  root="$(helpers_repo)"
  for form in 'PARA_ROUTES=8080' 'PARA_ROUTES=""' ': "${PARA_ROUTES:=3000}"' 'PARA_ROUTES="${PARA_ROUTES-4000}"'; do
    p="$(a_project "$form")"; before="$(cat "$p/.paraspace/Parafile")"
    assert env PARA_PROJECT_DIR="$p" PARA_HELPERS="$root/libexec/helpers" bash -c \
      '. "$PARA_HELPERS"; set_parafile_var_if_not_set PARA_ROUTES 9000' || return 1
    assert_eq "$before" "$(cat "$p/.paraspace/Parafile")" "existing form wins: $form" || return 1
  done
}

test_set_parafile_var_ignores_comments_and_similar_names_and_escapes() {
  local root p value resolved
  root="$(helpers_repo)"; p="$(a_project '# PARA_ROUTES=8080' 'PARA_ROUTE=7000')"
  value="one two'\"\$three"
  assert env PARA_PROJECT_DIR="$p" PARA_HELPERS="$root/libexec/helpers" VALUE="$value" bash -c \
    '. "$PARA_HELPERS"; set_parafile_var_if_not_set PARA_ROUTES "$VALUE"' || return 1
  resolved="$(env -i bash -c '. "$1"; printf "%s" "$PARA_ROUTES"' bash "$p/.paraspace/Parafile")"
  assert_eq "$value" "$resolved" "the appended assignment round-trips through bash" || return 1
  assert_eq 1 "$(grep -c '^PARA_ROUTES=' "$p/.paraspace/Parafile")" "exactly one declaration"
}

test_set_parafile_var_rejects_bad_names_and_missing_parafiles() {
  local root p
  root="$(helpers_repo)"; p="$(scratch)"
  assert_fails env PARA_PROJECT_DIR="$p" PARA_HELPERS="$root/libexec/helpers" bash -c \
    '. "$PARA_HELPERS"; set_parafile_var_if_not_set ROUTES 80' || return 1
  assert_fails env PARA_PROJECT_DIR="$p" PARA_HELPERS="$root/libexec/helpers" bash -c \
    '. "$PARA_HELPERS"; set_parafile_var_if_not_set PARA_bad 80' || return 1
  assert_fails env PARA_PROJECT_DIR="$p" PARA_HELPERS="$root/libexec/helpers" bash -c \
    '. "$PARA_HELPERS"; set_parafile_var_if_not_set PARA_ROUTES 80'
}

test_xbps_install_skips_an_all_installed_set() {
  local root fake calls
  root="$(helpers_repo)"; fake="$(scratch)"; calls="$fake/calls"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake/xbps-query"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "$XBPS_CALLS"' > "$fake/xbps-install"
  chmod +x "$fake/xbps-query" "$fake/xbps-install"
  assert env PATH="$fake:$PATH" XBPS_CALLS="$calls" PARA_HELPERS="$root/libexec/helpers" bash -c \
    '. "$PARA_HELPERS"; xbps_install git openssh' || return 1
  assert test ! -e "$calls"
}

test_xbps_install_batches_only_missing_packages() {
  local root fake calls
  root="$(helpers_repo)"; fake="$(scratch)"; calls="$fake/calls"
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1" != git ]' > "$fake/xbps-query"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "$XBPS_CALLS"' > "$fake/xbps-install"
  chmod +x "$fake/xbps-query" "$fake/xbps-install"
  assert env PATH="$fake:$PATH" XBPS_CALLS="$calls" PARA_HELPERS="$root/libexec/helpers" bash -c \
    '. "$PARA_HELPERS"; xbps_install git openssh git' || return 1
  assert_eq '-Sy git git' "$(cat "$calls")" "one transaction containing only missing arguments" || return 1
  assert_eq 1 "$(wc -l < "$calls" | tr -d ' ')" "one xbps-install invocation"
}
