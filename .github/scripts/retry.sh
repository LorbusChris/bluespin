#!/bin/bash
# retry.sh <tries> <pause-seconds> <command...>
#
# Run the command up to <tries> times, sleeping <pause> seconds between
# attempts. For commands whose failures are usually someone else's bad
# minute -- cosign talking to rekor.sigstore.dev, mostly, whose own retry
# gives up after two tries seconds apart. Three tries thirty seconds
# apart outlast a gateway blip without masking a real outage. (What this
# canNOT fix: a deterministic rejection. The 2026-08-25 attest failures
# retried identically forever because the payload itself was too big --
# see the Generate SBOM step in build-image.yml.)
set -uo pipefail

tries=$1
pause=$2
shift 2

for ((attempt = 1; attempt <= tries; attempt++)); do
    "$@" && exit 0
    if ((attempt < tries)); then
        echo "attempt ${attempt}/${tries} failed; retrying in ${pause}s" >&2
        sleep "${pause}"
    fi
done
exit 1
