#!/usr/bin/env bash
# Fetch prebuilt artifacts that are not produced by this repo (u-boot), each
# pinned to a sha256 so a third-party release is verified rather than trusted.
# Ported from pocketblue's tools/postprocess/download-extra.sh.

set -uexo pipefail

file_list=$1

download_file() {
    name=$1
    url=$2
    checksum=$3

    curl -fL --retry 3 "${url}" -o "out/${name}"
    echo "${checksum}  out/${name}" | sha256sum --check
}

while IFS= read -r line; do
    # shellcheck disable=SC2206  # deliberate word splitting: name url sha256
    args=($line)
    download_file "${args[0]}" "${args[1]}" "${args[2]}"
done < "$file_list"
