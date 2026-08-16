#!/bin/bash
set -xeuo pipefail

# Anything that needs a toolchain to build runs here, in a throwaway stage, so
# the toolchain never reaches the final image. Output goes to /out, which the
# main build stage bind-mounts at /pre.
OUT=/out
install -d "${OUT}"

# Tiling Shell ships TypeScript sources. Our fork adds the package-lock.json
# upstream does not carry, so npm ci gives a reproducible dependency tree.
dnf -y install nodejs npm glib2-devel

TS_SRC=/tmp/tilingshell
cp -r /ctx/extensions/tilingshell "${TS_SRC}"
cd "${TS_SRC}"
# npm needs a writable HOME; /root points at /var/roothome, which does not
# exist in a container build
export HOME="${TS_SRC}" npm_config_cache="${TS_SRC}/.npm"
npm ci --no-audit --no-fund
npm run build
cp -r "${TS_SRC}/dist" "${OUT}/tilingshell@ferrarodomenico.com"
