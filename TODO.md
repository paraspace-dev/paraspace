- [ ] Tests should fail on set -e and explicitly || true when failure is expected (or wrap them in a `expect 1 cmd` or something to expect a specific exit code? This would prevent accidental false-negatives on tests, where they pass by default because someone forgot to check something

- [ ] No more hardcoding claude/tmux -- hooks/run drives `para run` per project

- [ ] Default templates should get slimmed down in some way or be composable so that it's easy to add my handy tooling config without having to duplicate all the template primitives. _common was an attempt but failed for a dumb reason (helpers is needed for relative import -- can just copy it dummy)

- [ ] Minimal template should move to alpine, e.g. alpine-minimal and void-docker-gh. We should use the minimal template to drive tests maybe?

- [ ] Main template should have a plugin that lets users import their own dotfiles or run a callback hook that is local to their machine and settings. This way users can configure their own tmux + nvim config.


