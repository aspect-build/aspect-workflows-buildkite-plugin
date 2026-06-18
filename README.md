# Aspect Workflows Buildkite plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that prepares an
[Aspect Workflows](https://docs.aspect.build/workflows) runner so that **raw
`bazel <verb>` calls** — not just `aspect <task>` — route through the runner's
caching infrastructure.

This is the Buildkite counterpart of the
[`aspect-build/setup-aspect`](https://github.com/aspect-build/setup-aspect)
GitHub Action, ported down to just the work that an Aspect Workflows runner
needs.

## Why

On an Aspect Workflows runner, `aspect <task>` already wires itself into the
runner's remote cache, BES backend, and local NVMe disk cache on its own. But
many pipelines mix `aspect build` with a separate bare `bazel build` step, and
without this plugin those bare `bazel` invocations would miss all of that.

The plugin runs in the **`pre-command` hook** — after the repository checkout
(so `rosetta` can read the workspace's `.bazelversion`) and before the step's
command (so the rc is in place before any `bazel` call). It does three things:

1. **Logs the runner's metadata** (version, cloud, region, instance, …) for
   traceability.
2. **Waits for the runner's cache warming to complete.** `aspect <task>` performs
   this wait itself; a raw `bazel` call would otherwise race the still-running
   bootstrap warming — competing for CPU/disk and missing the warmed caches.
3. **Writes `/etc/bazel.bazelrc`** (the first rc Bazel loads) via the
   runner-provided `rosetta bazelrc`, so raw `bazel` picks up the Workflows-tuned
   configuration.

It does **not** install `aspect`, `bazel`, or Bazelisk, and does not wire up any
ephemeral-runner caching or auth — Buildkite runners are expected to be Aspect
Workflows runners, which already ship those. On a non-Workflows runner the plugin
**no-ops gracefully** (logs a skip message and exits 0), so it is safe to leave in
a pipeline that occasionally runs elsewhere.

## Usage

Add the plugin to any step that runs `bazel` directly:

```yaml
steps:
  - command: bazel test //...
    plugins:
      - aspect-build/aspect-workflows#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

`aspect <task>` steps don't need the plugin (they self-configure), but it's
harmless to apply it pipeline-wide.

### Pin to a commit SHA

**Pin to a full-length commit SHA**, not a branch or tag — tags are mutable and
can be repointed at malicious code, so SHA-pinning is the recommended way to
consume third-party plugins. Annotate with the version in a trailing comment for
readability and let Renovate keep the SHA fresh:

```yaml
plugins:
  - aspect-build/aspect-workflows#19a9eb187ad1f1c65c1b6d64a7fc03589041c8ae: ~ # v2026.25.0
```

Find the latest SHA on the [Releases page](https://github.com/aspect-build/aspect-workflows-buildkite-plugin/releases).

## Requirements

- An Aspect Workflows Buildkite runner (sets `ASPECT_WORKFLOWS_RUNNER`). On any
  other agent the plugin no-ops.
- `bash` on the agent. `aspect`, `bazel`, and `rosetta` are provided by the
  Workflows runner image.

## Configuration

None. The plugin's behavior is driven entirely by the runner's
`ASPECT_WORKFLOWS_RUNNER_*` environment variables.

## Deprecation signal

`rosetta` is a legacy mechanism that a future major Aspect Workflows release will
remove. When the runner signals that a newer bazelrc-generation mechanism is
available (`ASPECT_WORKFLOWS_RUNNER_BAZELRC_GENERATE` is set), or when `rosetta`
is missing entirely, the plugin emits a warning and exports
`ASPECT_WORKFLOWS_BUILDKITE_PLUGIN_DEPRECATED=1` (via `$BUILDKITE_ENV_FILE`) so
downstream `aspect <task>` steps can surface the same signal. If you see this,
upgrade the plugin to the latest release.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md). In short:

```sh
docker-compose run --rm tests   # BATS suite via buildkite/plugin-tester
```

CI ([.buildkite/pipeline.yml](.buildkite/pipeline.yml)) runs the tests, the
plugin linter, and shellcheck.

## License

Apache-2.0. See [LICENSE](LICENSE).
