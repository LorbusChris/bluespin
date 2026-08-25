#!/bin/bash
# Finish a variant layer on top of the bluespin image: stamp the variant's
# identity, regenerate the per-platform desktop defaults and extension set
# (the bluespin layer wrote the defaults), and prune what the layer's dnf
# work left in /var. Everything platform-specific that is not the variant's
# own hardware or tooling script lives here, so the variant layers stay
# thin deltas over the shared bluespin layers.
set -xeuo pipefail

platform=$1

# shellcheck source=build_files/identity.sh
source /ctx/build_files/identity.sh
# shellcheck source=build_files/extensions.sh
source /ctx/build_files/extensions.sh
# shellcheck source=build_files/desktop.sh
source /ctx/build_files/desktop.sh
# shellcheck source=build_files/silverblue_base.sh
source /ctx/build_files/silverblue_base.sh

set_image_identity "${platform}"

mapfile -t ENABLED_EXTENSIONS < <(enabled_extensions_for_platform "${platform}")
assert_enabled_extensions "${ENABLED_EXTENSIONS[@]}"
write_enabled_extensions_override "${ENABLED_EXTENSIONS[@]}"

write_desktop_defaults "${platform}"

cleanup_silverblue_image
