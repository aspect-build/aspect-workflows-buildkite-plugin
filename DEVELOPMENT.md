# Development

## Layout

| Path | What |
|---|---|
| `hooks/pre-command` | Entry point. Guards on the runner, logs metadata, waits for warming, writes `/etc/bazel.bazelrc` via `rosetta`, and emits the deprecation signal. Runs as `pre-command` (after checkout, before the step command) because `rosetta bazelrc` reads the workspace's `.bazelversion`. Ports `setupOnWorkflowsRunner` from `aspect-build/setup-aspect`. |
| `lib/shared.bash` | Logging, the deprecation signal, cross-step env propagation (`$BUILDKITE_ENV_FILE`), and the runner-metadata table. |
| `plugin.yml` | The plugin's public contract (name/description/author, `requirements`, config schema). |
| `tests/` | BATS tests, run via the `buildkite/plugin-tester` Docker image. |
| `.buildkite/pipeline.yml` | This plugin's own CI: tests, linter, shellcheck. |
| `.github/workflows/` | Weekly tagging and the manual release workflow (+ their `release_*.sh` helpers). See [Releasing](#releasing). |

## Test

The test suite runs in the [`buildkite/plugin-tester`](https://github.com/buildkite-plugins/buildkite-plugin-tester)
image, which provides BATS plus the `bats-support`/`bats-assert`/`bats-mock`
helpers (`stub`/`unstub`, `assert_output`, …):

```sh
docker-compose run --rm tests
```

The tests redirect the `/etc/bazel.bazelrc` write to a temp file (via the
`ASPECT_WORKFLOWS_PLUGIN_SYSTEM_BAZELRC` override) so they don't need root, and
stub `rosetta` to drive the hook through each branch.

## Lint

Locally, run shellcheck over the shell sources:

```sh
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable hooks/pre-command lib/*.bash
```

CI additionally runs the [Buildkite plugin linter](https://github.com/buildkite-plugins/plugin-linter-buildkite-plugin)
against `plugin.yml`.

## Releasing

This plugin is referenced by commit SHA, not tag (see the README). It uses two
tiers of tags, both matching aspect-build/aspect-cli's scheme:

| | Tag | Workflow | Trigger | GitHub Release? |
|---|---|---|---|---|
| **Weekly** | `YYYY.VV` (e.g. `2026.22`) | `weekly_tag.yaml` | cron + push to main | no |
| **Release** | `vYYYY.VV.N` (e.g. `v2026.22.3`) | `tag_release.yaml` | manual `workflow_dispatch` | yes |

Across both tiers: **pin to the commit SHA, not the tag.** Tags are mutable.

**Weekly tags** are dated pointers for discoverability. `weekly_tag.yaml` runs on
a Monday cron **and** on every push to `main`; each run no-ops if the week's tag
already exists or if `main` hasn't advanced since the last `YYYY.VV` tag — so a
quiet repo gets at most one tag per week, only when something shipped.

**Releases** are cut manually from the Actions tab (`tag_release.yaml`) when you
want richer, changelog-bearing notes. The release version is `vYYYY.VV.N`: the
current weekly tag plus the number of commits since it (`release_version.sh`,
derived via `git describe`). The notes lead with a copy-paste plugin-pin snippet
pinned to the released SHA (`release_notes.sh`), followed by GitHub's
auto-generated changelog. Before the first weekly tag exists, `release_version.sh`
falls back to this week's `YYYY.VV.0`.
