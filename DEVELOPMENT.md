# Development

## Layout

| Path | What |
|---|---|
| `hooks/environment` | Entry point. Guards on the runner, logs metadata, waits for warming, writes `/etc/bazel.bazelrc` via `rosetta`, and emits the deprecation signal. Ports `setupOnWorkflowsRunner` from `aspect-build/setup-aspect`. |
| `lib/shared.bash` | Logging, the deprecation signal, cross-step env propagation (`$BUILDKITE_ENV_FILE`), and the runner-metadata table. |
| `plugin.yml` | The plugin's public contract (name/description/author, `requirements`, config schema). |
| `tests/` | BATS tests, run via the `buildkite/plugin-tester` Docker image. |
| `.buildkite/pipeline.yml` | This plugin's own CI: tests, linter, shellcheck. |

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
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable hooks/environment lib/*.bash
```

CI additionally runs the [Buildkite plugin linter](https://github.com/buildkite-plugins/plugin-linter-buildkite-plugin)
against `plugin.yml`.

## Releasing

This plugin is referenced by commit SHA, not tag (see the README). Weekly
`YYYY.VV` tags are dated pointers for discoverability only — always pin consumers
to a SHA.
