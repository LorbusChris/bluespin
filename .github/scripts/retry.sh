#!/bin/bash
# retry.sh <tries> <pause-seconds> <command...>
#
# Run the command up to <tries> times, sleeping <pause> seconds between
# attempts. For commands whose failures are usually someone else's bad
# minute -- cosign talking to rekor.sigstore.dev, mostly: the public
# Rekor 502s now and then, cosign's own retry gives up after two tries
# seconds apart, and all three bluespin legs of the first main run failed
# in one such window. Three tries thirty seconds apart outlast a gateway
# blip without masking a real outage.
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
