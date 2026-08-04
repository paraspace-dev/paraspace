#!/usr/bin/env bash
# CLI-tier tests for what this package ships to an AGENT rather than to a shell:
# the two `.claude-plugin/` manifests and the `skills/paraspace-setup/` skill.
#
# Why the suite carries them. Every other consumer of this package errors when
# something moves, because a hook dies or para refuses. An agent doesn't. A
# bundled path that stops resolving or a manifest that stops parsing just makes
# it improvise, and the failure surfaces as a worse `.paraspace/` in somebody's
# repo. These are the assertions nothing else here would make.
#
# They read the package's own files ($REPO, exported by test/run) and never write
# inside the checkout. `node` reads the manifests: it is the parser npm and Claude
# Code both use, and this package already needs it.

SKILL_REL=skills/paraspace-setup

# _json <file> <expr>. One field out of a JSON file. The path crosses as an
# argument, and the only thing interpolated into the source is <expr>, which
# every caller here writes as a literal.
_json() { node -p "require(process.argv[1]).$2" "$1"; }

# _pkg_root <para-path>. The package dir that para reads its docs/ and
# templates/ out of. bin/para's pkg_root (and the probe's para_pkg) resolve the
# symlink chain first, and npm installs one, so a dirname of $PARA can name the
# wrong tree.
_pkg_root() {
  node -p 'require("path").resolve(require("fs").realpathSync(process.argv[1]), "../..")' "$1"
}

# ---------------------------------------------------------------- manifests

test_the_plugin_manifest_declares_the_package_version() {
  local pkg plugin
  pkg="$(_json "$REPO/package.json" version)" || return 1
  plugin="$(_json "$REPO/.claude-plugin/plugin.json" version)" || return 1
  # Omit it and Claude Code versions the plugin by git SHA, so every commit to
  # main reads as a new release to everyone who installed it.
  # bin/sync-plugin-version keeps the two equal through `npm version`.
  assert_eq "$pkg" "$plugin" "plugin.json carries package.json's version"
}

test_the_marketplace_points_at_the_shipped_skill() {
  local market="$REPO/.claude-plugin/marketplace.json" name entry src skill files
  # Claude Code keys enabledPlugins and `/plugin` off the marketplace entry's
  # name, so a name that drifts from the manifest's silently changes what a user
  # installs, and what an uninstall then fails to remove.
  name="$(_json "$REPO/.claude-plugin/plugin.json" name)" || return 1
  entry="$(_json "$market" 'plugins[0].name')" || return 1
  assert_eq "$name" "$entry" "the entry is named for the plugin it installs" || return 1
  # `source` is the dir the install copies; without a manifest in it there is no
  # plugin there to install.
  src="$(_json "$market" 'plugins[0].source')" || return 1
  assert test -f "$REPO/${src%/}/.claude-plugin/plugin.json" || return 1
  skill="$(_json "$market" 'plugins[0].skills[0]')" || return 1
  assert test -f "$REPO/${skill#./}/SKILL.md" || return 1
  # And the tarball has to contain both, or the plugin installs empty from npm.
  files="$(_json "$REPO/package.json" 'files.join(" ")')" || return 1
  assert_contains "$files" ".claude-plugin" "the published files include the manifests" || return 1
  assert_contains "$files" "skills" "the published files include the skill"
}

# -------------------------------------------------------------------- skill

test_the_skill_resolves_every_bundled_path_it_names() {
  local dir="$REPO/$SKILL_REL" rel hits
  # ${CLAUDE_SKILL_DIR} is the only substitution that resolves at every install
  # scope. CLAUDE_PLUGIN_ROOT is unset for a skill installed with `npx skills`,
  # and no CLAUDE_* variable reaches a Bash tool call at all, so a path built
  # from it points at /skills/… and the skill's first command dies there.
  hits="$(grep -rl CLAUDE_PLUGIN_ROOT "$dir" 2>/dev/null || true)"
  assert_eq "" "$hits" "nothing in the skill depends on CLAUDE_PLUGIN_ROOT" || return 1
  while IFS= read -r rel; do
    assert test -e "$dir/$rel" || return 1
  done < <(grep -rohE '[$][{]?CLAUDE_SKILL_DIR[}]?/[A-Za-z0-9/._-]+' "$dir" \
             | sed -E 's|[$][{]?CLAUDE_SKILL_DIR[}]?/||' | sort -u)
  # An agent reading a link to a page that isn't there has no way to tell a typo
  # from a file it was not supposed to open, so it guesses instead. The reference
  # pages cross-link each other, so sweep all of them, not just SKILL.md.
  while IFS= read -r rel; do
    assert test -f "$dir/$rel" || return 1
  done < <(grep -rohE 'references/[A-Za-z0-9._-]+\.md' "$dir" | sort -u)
}

test_the_skill_frontmatter_is_what_a_listing_reads() {
  local dir="$REPO/$SKILL_REL" fm desc
  assert_eq "---" "$(head -1 "$dir/SKILL.md")" "SKILL.md opens with frontmatter" || return 1
  fm="$(awk 'NR > 1 && /^---$/ { exit } NR > 1 { print }' "$dir/SKILL.md")"
  assert_contains "$fm" "name: paraspace-setup" "the skill names itself" || return 1
  assert_contains "$fm" "description:" "and says when to trigger" || return 1
  # Claude Code truncates the description at 1536 characters in the skill
  # listing, and the tail is where the "not for" cases live, the half that keeps
  # it from triggering on plain Docker or devcontainer work.
  desc="$(printf '%s' "$fm" | sed -n '/^description:/,$p' | tr -d '\n')"
  assert test "${#desc}" -lt 1536
}

test_the_probe_reports_a_broken_machine_instead_of_failing() {
  # The first command the skill runs. Two things have to hold: a missing or
  # refusing tool is a FINDING, not a failure (an agent reads a non-zero exit as
  # "the survey broke" and starts debugging the probe), and it must name the docs
  # of the para on PATH, since that copy matches the contract it targets.
  local fence pkg out rc=0
  fence="$(a_fenced_backend)"
  pkg="$(_pkg_root "$PARA")" || return 1
  out="$(cd "$(scratch)" && env -u PARA_PROJECT_DIR PATH="$(dirname "$PARA"):$fence:$PATH" \
    bash "$REPO/$SKILL_REL/scripts/para-probe" 2>&1)" || rc=$?
  assert_eq 0 "$rc" "the probe exits zero with every backend refusing" || return 1
  assert_contains "$out" "$pkg/docs" "it locates the installed para's docs" || return 1
  assert_contains "$out" "$pkg/templates" "and its templates"
}

test_the_probe_survives_a_machine_with_no_para_at_all() {
  # No para is the branch with no docs or templates pointer to give the agent, so
  # the install line is the whole report, and a non-zero exit here is what sends
  # an agent debugging the probe rather than reading it.
  local fence out rc=0
  fence="$(a_fenced_backend)"
  # PATH down to the system dirs, so no para on the developer's real PATH can
  # slip in; the fence still answers for incus and caddy.
  out="$(cd "$(scratch)" && env -u PARA_PROJECT_DIR PATH="$fence:/usr/bin:/bin" \
    bash "$REPO/$SKILL_REL/scripts/para-probe" 2>&1)" || rc=$?
  assert_eq 0 "$rc" "the probe exits zero with no para installed" || return 1
  assert_eq MISSING "$(awk '$1 == "para" { print $2 }' <<<"$out")" \
    "the tools section reports para missing" || return 1
  assert_contains "$(grep npm <<<"$out")" "paraspace" "and still says how to install it"
}
