#!/usr/bin/env bash
# Emit the release-notes body for a release of this Buildkite plugin. The
# headline content is a copy-paste plugin-pin snippet pinned to the released
# commit SHA — pinning to the immutable SHA (not the mutable tag) is the
# recommended practice; see the README and DEVELOPMENT.md. GitHub appends its
# auto-generated changelog below this body (generate_release_notes: true).
#
# Required env: REPO (owner/name), SHA (full 40-char commit), TAG (e.g. v2026.22.3).

set -o errexit -o nounset -o pipefail

# Buildkite references a plugin as `<owner>/<name>#<ref>`, dropping the
# conventional `-buildkite-plugin` repo suffix. Strip it so the snippet matches
# how the plugin is actually referenced in a pipeline.yml.
plugin_ref="${REPO%-buildkite-plugin}"

cat <<EOF
### Pin this release

Pin to the **commit SHA**, not the tag — tags are mutable, so SHA-pinning is the
recommended way to consume a third-party Buildkite plugin.

\`\`\`yaml
steps:
  - command: bazel test //...
    plugins:
      - ${plugin_ref}#${SHA}: ~ # ${TAG}
\`\`\`
EOF
