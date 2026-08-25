#!/usr/bin/bash
# Attach one file to a GitHub release, in parts if it has to be.
#
#   upload-release-asset.sh <release-tag> <file>
#
# A release asset must be under 2 GiB. A live ISO of a desktop image is
# 3-5, and the phone's archive is already 1.8, so the limit is not a
# hypothetical: the first release to reach the upload step lost four
# finished ISOs to HTTP 422. Anything over the limit is attached as
# <name>.partNN alongside a <name>-PARTS note saying how to put it back
# together; anything under is attached as itself, with no reassembly to
# explain. The checksum files uploaded next to these always cover the
# whole file, so verifying a reassembly is the same gesture as verifying
# a download.
#
# gh, not an upload action: actions that address a release by id PATCH it
# as they attach, which publishes drafts (see build-installer.yml).

set -euo pipefail

TAG="${1:?release tag}"
FILE="${2:?file to attach}"

# Overridable so the split path can be exercised without a 2 GiB file
LIMIT="${ASSET_LIMIT_BYTES:-$((2 * 1024 * 1024 * 1024))}"
# Comfortably under, so the parts stay valid if the limit is ever
# measured in decimal GB somewhere in the chain
PART_SIZE="${ASSET_PART_SIZE:-1900M}"

size="$(stat -c %s "${FILE}")"
name="$(basename "${FILE}")"

if ((size < LIMIT)); then
    # --clobber: re-running a failed or partial release run has to be
    # able to replace what an earlier attempt attached
    gh release upload "${TAG}" "${FILE}" --clobber
    echo "attached ${name} (${size} bytes)"
    exit 0
fi

echo "${name} is ${size} bytes, over the ${LIMIT}-byte asset limit; splitting"
rm -f "${FILE}".part??
split --bytes="${PART_SIZE}" --numeric-suffixes=1 --suffix-length=2 \
    "${FILE}" "${FILE}.part"

parts=("${FILE}".part??)
printf 'cat %s.part?? > %s\n' "${name}" "${name}" > "${FILE}-PARTS"

gh release upload "${TAG}" "${parts[@]}" "${FILE}-PARTS" --clobber
echo "attached ${name} as ${#parts[@]} parts"
