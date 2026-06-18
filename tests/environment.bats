#!/usr/bin/env bats

# Tests for the environment hook, run via the buildkite/plugin-tester image
# (`docker-compose run --rm tests`). Drives the hook through its branches with
# ASPECT_WORKFLOWS_RUNNER_* env vars.
#
# `rosetta` is stubbed with a hand-rolled script placed on PATH rather than via
# bats-mock's `stub`: bats-mock derives an env-var prefix from the uppercased
# command name (ROSETTA_STUB_RUN, …), which Apple's Rosetta 2 runtime intercepts
# and aborts when the suite runs under Docker Desktop on Apple Silicon. A PATH
# stub is portable across both real Linux CI agents and Apple Silicon dev hosts.

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  HOOK="${PWD}/hooks/environment"

  # Redirect the system bazelrc write to a temp file so tests don't need root.
  BAZELRC_OUT="$(mktemp)"
  export ASPECT_WORKFLOWS_PLUGIN_SYSTEM_BAZELRC="${BAZELRC_OUT}"

  # Isolate cross-step env propagation to a temp file.
  BUILDKITE_ENV_FILE="$(mktemp)"
  export BUILDKITE_ENV_FILE

  # A bin dir we prepend to PATH for hand-rolled stubs.
  STUB_BIN="$(mktemp -d)"
}

teardown() {
  rm -rf "${BAZELRC_OUT}" "${BUILDKITE_ENV_FILE}" "${STUB_BIN}"
}

# Put a `rosetta` on PATH whose `bazelrc` subcommand prints $1 (default rc text).
stub_rosetta() {
  local rc_content="${1:-build --remote_cache=grpcs://example}"
  cat > "${STUB_BIN}/rosetta" <<EOF
#!/bin/bash
# Args are: bazelrc --config <path>. Emit the rc on stdout.
echo '${rc_content}'
EOF
  chmod +x "${STUB_BIN}/rosetta"
  export PATH="${STUB_BIN}:${PATH}"
}

@test "no-ops when not on an Aspect Workflows runner" {
  run "${HOOK}"

  assert_success
  assert_output --partial "Not an Aspect Workflows runner"
  refute_output --partial "Detected Aspect Workflows runner"
}

@test "logs metadata, writes bazelrc via rosetta on a Workflows runner" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_VERSION="2026.22.39"
  export ASPECT_WORKFLOWS_RUNNER_CLOUD_PROVIDER="aws"
  export ASPECT_WORKFLOWS_RUNNER_HAS_NVME_STORAGE=1
  stub_rosetta "build --remote_cache=grpcs://example"

  run "${HOOK}"

  assert_success
  assert_output --partial "Detected Aspect Workflows runner"
  assert_output --partial "Workflows version: 2026.22.39"
  assert_output --partial "Cloud provider: AWS"
  assert_output --partial "NVMe storage: yes"
  assert_output --partial "Wrote Workflows-tuned bazelrc to ${BAZELRC_OUT}"

  run cat "${BAZELRC_OUT}"
  assert_output --partial "build --remote_cache=grpcs://example"
}

@test "omits unset metadata rows" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_VERSION="2026.22.39"
  stub_rosetta

  run "${HOOK}"

  assert_success
  assert_output --partial "Workflows version: 2026.22.39"
  refute_output --partial "Region:"
  refute_output --partial "Instance type:"
}

@test "waits for warming until the marker file appears" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_WARMING_ENABLED=1
  local marker
  marker="$(mktemp -u)"
  export ASPECT_WORKFLOWS_RUNNER_WARMING_COMPLETE_MARKER_FILE="${marker}"
  stub_rosetta

  # Create the marker shortly after the hook starts polling.
  ( sleep 2; touch "${marker}" ) &

  run "${HOOK}"

  assert_success
  assert_output --partial "Warming is still in progress — waiting..."
  assert_output --partial "Warming completed after"

  rm -f "${marker}"
}

@test "skips the warming wait when the marker already exists" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_WARMING_ENABLED=1
  local marker
  marker="$(mktemp)"
  export ASPECT_WORKFLOWS_RUNNER_WARMING_COMPLETE_MARKER_FILE="${marker}"
  stub_rosetta

  run "${HOOK}"

  assert_success
  refute_output --partial "Warming is still in progress"

  rm -f "${marker}"
}

@test "logs the warmed cache version when published" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_WARMING_ENABLED=1
  local marker version_file
  marker="$(mktemp)"
  version_file="$(mktemp)"
  echo "cache-v123" > "${version_file}"
  export ASPECT_WORKFLOWS_RUNNER_WARMING_COMPLETE_MARKER_FILE="${marker}"
  export ASPECT_WORKFLOWS_RUNNER_WARMING_CACHE_VERSION_FILE="${version_file}"
  stub_rosetta

  run "${HOOK}"

  assert_success
  assert_output --partial "Runner warmed from cache version: cache-v123"

  rm -f "${marker}" "${version_file}"
}

@test "warns when warming enabled but marker var unset" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_WARMING_ENABLED=1
  stub_rosetta

  run "${HOOK}"

  assert_success
  assert_output --partial "ASPECT_WORKFLOWS_RUNNER_WARMING_COMPLETE_MARKER_FILE is not set"
}

@test "marks deprecated and skips bazelrc when rosetta is absent" {
  export ASPECT_WORKFLOWS_RUNNER=1
  # Do not stub rosetta — `command -v rosetta` should miss. Restrict PATH so a
  # real rosetta (if any) on the runner can't satisfy the lookup.
  export PATH="${STUB_BIN}:/usr/bin:/bin"

  run "${HOOK}"

  assert_success
  assert_output --partial "\`rosetta\` is not on PATH"
  refute_output --partial "Wrote Workflows-tuned bazelrc"

  run cat "${BUILDKITE_ENV_FILE}"
  assert_output --partial "ASPECT_WORKFLOWS_BUILDKITE_PLUGIN_DEPRECATED=1"
}

@test "marks deprecated when the runner signals a newer mechanism" {
  export ASPECT_WORKFLOWS_RUNNER=1
  export ASPECT_WORKFLOWS_RUNNER_BAZELRC_GENERATE=1
  stub_rosetta

  run "${HOOK}"

  assert_success
  assert_output --partial "is out of date"
  # Still falls back to rosetta in this version.
  assert_output --partial "Wrote Workflows-tuned bazelrc"

  run cat "${BUILDKITE_ENV_FILE}"
  assert_output --partial "ASPECT_WORKFLOWS_BUILDKITE_PLUGIN_DEPRECATED=1"
}
