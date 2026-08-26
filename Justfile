set dotenv-filename := "bluespin.env"
set dotenv-load

export image_name := env_var("IMAGE_NAME")
export repo_organization := env_var("REPO_ORGANIZATION")
export repo_name := env_var("REPO_NAME")
export image_desc := env_var("IMAGE_DESC")
export image_keywords := env_var("IMAGE_KEYWORDS")
export image_logo_url := env_var("IMAGE_LOGO_URL")
export default_fedora_branch := env_var("DEFAULT_FEDORA_BRANCH")
export next_fedora_branch := env_var("NEXT_FEDORA_BRANCH")
export chunkah_image := env_var("CHUNKAH_IMAGE")

# Flashable disk images (bluespin-fp5 only). env() rather than env_var() so a
# local run works without editing bluespin.env. The default image ref derives
# from REPO_ORGANIZATION rather than hardcoding an owner: on a fork, a
# hardcoded ref would silently pull and flash upstream's published image
# instead of the operator's own build.
export disk_device := env("DISK_DEVICE", "fairphone-fp5")
export disk_image_ref := env("DISK_IMAGE_REF", "ghcr.io/" + lowercase(repo_organization) + "/bluespin-fp5:45")
export image_builder_image := env_var("IMAGE_BUILDER_IMAGE")
# NOT pocketblue's release setting of `-mmt=1 -md=1500m`: a 1500 MB LZMA2
# dictionary needs an order of magnitude more RAM to compress, single-threaded,
# and would thrash a hosted runner. The unused partition space is zeros and
# compresses to nothing either way, so the archive tracks content size.
# The flashable archive: LZMA2 as 7z used to do it, in a tar so the
# flash scripts keep their mode and the raw images keep their holes.
# Both are overridable together -- e.g. "zstd -19 -T0 --long=27" with
# "tar.zst" -- for a faster build at a slightly larger archive.
export disk_archive_compressor := env("DISK_ARCHIVE_COMPRESSOR", "xz -9 -T0")
export disk_archive_ext := env("DISK_ARCHIVE_EXT", "tar.xz")

import "tools/disk_images.just"

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# Build one platform on one Fedora branch: `just build bluespin-dx rawhide`.
#
# The branch is the image tag. Its base comes from bluespin.env
# (FEDORA_<BRANCH>_BASE_IMAGE, digest-pinned there and nowhere else) and goes to
# the one Containerfile as BASE_IMAGE; build.sh branches on IMAGE_NAME for the
# platform and detects the base it landed on.
# arch: only for cross-arch platforms; empty means the host arch, which is what
# every amd64 platform wants.
build $target_image=image_name $fedora_branch=default_fedora_branch $arch="":
    #!/usr/bin/env bash
    set -euox pipefail

    tag="${fedora_branch}"
    base_var="FEDORA_${fedora_branch^^}_BASE_IMAGE"
    base="${!base_var:-}"
    if [[ -z "${base}" ]]; then
        echo "no base image for Fedora ${fedora_branch}: set ${base_var} in bluespin.env" >&2
        exit 1
    fi

    BUILD_ARGS=()
    LABELS=()

    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${base}")
    BUILD_ARGS+=("--build-arg" "FEDORA_BRANCH=${fedora_branch}")

    # The platform is a Containerfile stage (the stages set their own
    # IMAGE_NAME; passing it as a build-arg would mislabel the shared
    # bluespin layer inside a variant build).
    case "${target_image##*/}" in
        bluespin) BUILD_ARGS+=("--target" "bluespin") ;;
        bluespin-dx) BUILD_ARGS+=("--target" "dx") ;;
        bluespin-surface) BUILD_ARGS+=("--target" "surface") ;;
        bluespin-fp5) BUILD_ARGS+=("--target" "fp5") ;;
        *)
            echo "no Containerfile stage for platform '${target_image##*/}'" >&2
            exit 1
            ;;
    esac

    # CI (pushes on main) builds the variants FROM the just-pushed bluespin
    # image; locally and on PRs the variants chain from the bluespin stage
    # in the Containerfile instead.
    if [[ -n "${BLUESPIN_IMAGE:-}" ]]; then
        BUILD_ARGS+=("--build-arg" "BLUESPIN_IMAGE=${BLUESPIN_IMAGE}")
    fi

    # The out-of-tree module's own version, for modinfo and dmesg. Upstream's
    # Makefile derives it with `git describe`, which cannot work inside the
    # build: the submodule's .git is a gitlink into this repo's .git/modules,
    # and neither is in the build context.
    BUILD_ARGS+=("--build-arg" \
        "V4L2LOOPBACK_VERSION=$(git -C kmods/v4l2loopback describe --tags --always --dirty 2>/dev/null || echo snapshot)")

    # Optional Secure Boot signing key for the surface kernel (CI stages it
    # from the SECUREBOOT_KEY repo secret; see build.sh). Absent means an
    # unsigned build that warns.
    if [[ -n "${SECUREBOOT_KEY_FILE:-}" ]]; then
        BUILD_ARGS+=("--secret" "id=secureboot_key,src=${SECUREBOOT_KEY_FILE}")
    fi

    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/{{ repo_organization }}/{{ repo_name }}/${GIT_SHA}/README.md")
        LABELS+=("--label" "org.opencontainers.image.documentation=https://raw.githubusercontent.com/{{ repo_organization }}/{{ repo_name }}/${GIT_SHA}/README.md")
        LABELS+=("--label" "org.opencontainers.image.source=https://github.com/{{ repo_organization }}/{{ repo_name }}/blob/${GIT_SHA}/Containerfile")
        LABELS+=("--label" "org.opencontainers.image.url=https://github.com/{{ repo_organization }}/{{ repo_name }}/tree/${GIT_SHA}")
        LABELS+=("--label" "org.opencontainers.image.version=${fedora_branch}.$(date +%Y%m%d)-${GIT_SHA}")
    fi

    # Image metadata for https://artifacthub.io/ - This is optional but is highly recommended so we all can get a index of all the custom images
    # The metadata by itself is not going to do anything, you choose if you want your image to be on ArtifactHub or not.
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "io.artifacthub.package.keywords={{ image_keywords }}")
    LABELS+=("--label" "io.artifacthub.package.logo-url={{ image_logo_url }}")
    LABELS+=("--label" "io.artifacthub.package.prerelease=false")
    LABELS+=("--label" "containers.bootc=1")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.description={{ image_desc }}")
    LABELS+=("--label" "org.opencontainers.image.title=${target_image##*/}")
    LABELS+=("--label" "org.opencontainers.image.vendor={{ repo_organization }}")

    # This actually builds the image!
    PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --pull=newer --tag "${target_image}:${tag}" --file Containerfile)

    # NO_CACHE=1 forces a full rebuild. Podman's layer cache keys on neither
    # bind-mounted context content nor secrets, so a cached layer can lie
    # about both (see README); local verification builds want this. CI runs
    # on fresh runners and never needs it.
    if [[ -n "${NO_CACHE:-}" ]]; then
        PODMAN_BUILD_ARGS+=("--no-cache")
    fi

    # Cross-arch builds need qemu-user-static with binfmt registered on an x86
    # host and take hours; CI uses native arm64 runners, where this is a no-op
    # that keeps the recipe honest about what it is producing.
    if [[ -n "${arch}" ]]; then
        PODMAN_BUILD_ARGS+=("--arch" "${arch}")
    fi

    podman build "${PODMAN_BUILD_ARGS[@]}" .

# Layer the container-native ISO contract onto a built image, for
# Titanoboa to turn into a live installer ISO: Anaconda, the livesys
# session, an initramfs that can boot a squashfs, and iso.yaml itself.
#
#   just live-image ghcr.io/lorbuschris/bluespin:45 bluespin 45
#
# base_ref is the image to layer on, platform names the family member it
# belongs to, and the branch decides what an install will track -- the
# channel alias for that branch, so a machine installed from stable's
# media follows stable across the next Fedora branch by itself. Tags
# out_tag, which CI sets to the ref it publishes the media image under.
#
# This is install media in container form: the installer belongs here,
# not in an image whose only job is to update an existing system.
[group('Build')]
live-image $base_ref $platform=image_name $branch=default_fedora_branch $out_tag="":
    #!/usr/bin/env bash
    set -euox pipefail

    # The channel this medium installs, from the same table the tags use
    case "${branch}" in
        "${DEFAULT_FEDORA_BRANCH}") channel=latest ;;
        "${NEXT_FEDORA_BRANCH}") channel=next ;;
        rawhide) channel=rolling ;;
        *) channel="${branch}" ;;
    esac
    install_ref="ghcr.io/${REPO_ORGANIZATION,,}/${platform}:${channel}"

    # The ISO's volume label, which its own boot entries name back and
    # which titanoboa names the file after. Volume IDs cap at 32 chars.
    iso_label="${platform}-${branch}"

    tag="${out_tag:-localhost/${platform}-live:${branch}}"

    podman build \
        --target live \
        --build-arg "LIVE_BASE_IMAGE=${base_ref}" \
        --build-arg "IMAGE_NAME=${platform}" \
        --build-arg "INSTALL_REF=${install_ref}" \
        --build-arg "ISO_LABEL=${iso_label}" \
        --tag "${tag}" \
        .

# Split the image for smaller updates (New)!
rechunk $target_image=image_name $tag=default_fedora_branch:
    #!/usr/bin/env bash
    set -xeuo pipefail

    # You may run into space issues on github runners as we are making a
    # complete copy of the image, which likely has no shared layers, unless your
    # base image is also using chunkah
    CHUNKAH_CONFIG_FILE="$(mktemp)"

    # You may omit the current directory here if you are confident that you
    # won't run out of space on /tmp for your image
    CHUNKAH_OUTPUT_DIR="$(mktemp -d ./"${target_image##*/}"_chunkah_XXXXXX)"

    trap 'rm -f "${CHUNKAH_CONFIG_FILE}"; rm -rf "${CHUNKAH_OUTPUT_DIR}"' EXIT
    podman inspect "${target_image}:${tag}" > "${CHUNKAH_CONFIG_FILE}"

    podman run --rm \
      --mount=type=image,src="${target_image}:${tag}",target=/chunkah \
      -v "${CHUNKAH_CONFIG_FILE}:/chunkah-config.json:ro,Z" \
      -v "${CHUNKAH_OUTPUT_DIR}:/run/out:Z" \
      "${chunkah_image}" \
      build \
      --verbose \
      --compressed \
      --max-layers 128 \
      --prune /sysroot/ \
      --label ostree.commit- --label ostree.final-diffid- \
      --config /chunkah-config.json \
      --output oci:/run/out/chunked

    CHUNKED_IMAGE="$(podman pull "oci:${CHUNKAH_OUTPUT_DIR}/chunked")"
    podman tag "${CHUNKED_IMAGE}" "${target_image}:${tag}"

# Split the image for smaller updates (Classical)!
ostree-rechunk $target_image=image_name $tag=default_fedora_branch:
    #!/usr/bin/env bash
    set -xeuo pipefail

    # Use the already-built local image to avoid pulling from a remote registry
    RPM_OSTREE_CHUNKER_IMAGE="localhost/${target_image}:${tag}"

    RPM_OSTREE_OUTPUT_DIR="$(mktemp -d ./"${target_image##*/}"_rpm-ostree_XXXXXX)"

    # rpm-ostree needs scratch space under /var/tmp, which our image cleanup
    # strips; mount host scratch space there instead of relying on the image
    RPM_OSTREE_TMP_DIR="$(mktemp -d ./"${target_image##*/}"_rpm-ostree-tmp_XXXXXX)"

    trap 'rm -rf "${RPM_OSTREE_OUTPUT_DIR}" "${RPM_OSTREE_TMP_DIR}"' EXIT

    podman run --rm \
      --pull=never \
      --mount=type=image,src="${target_image}:${tag}",target=/rpm-ostree \
      --privileged \
      -v "${RPM_OSTREE_OUTPUT_DIR}:/run/out:Z" \
      -v "${RPM_OSTREE_TMP_DIR}:/var/tmp:Z" \
      --entrypoint /usr/bin/rpm-ostree \
      "${RPM_OSTREE_CHUNKER_IMAGE}" \
      compose build-chunked-oci \
      --max-layers 127 \
      --format-version=2 \
      --bootc \
      --rootfs /rpm-ostree \
      --output oci-archive:/run/out/"${target_image##*/}.oci"

    CHUNKED_IMAGE="$(podman pull oci-archive:"${RPM_OSTREE_OUTPUT_DIR}/${target_image##*/}.oci")"
    podman tag "${CHUNKED_IMAGE}" "${target_image}:${tag}"

# Generate Tags: the branch, dated, and with the commit; the default branch
# additionally carries `latest` and the undated set it always had, so nothing
# that follows `bluespin:latest` or `bluespin:<date>` changes. Non-default
# branches never get a bare date tag -- the legs build the same day.
[group('Utility')]
generate-build-tags $target_image=image_name $fedora_branch=default_fedora_branch:
    #!/usr/bin/env bash
    set -eou pipefail

    DATE=$(date +%Y%m%d)
    GIT_SHA=""
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
    fi

    BUILD_TAGS=("${fedora_branch}" "${fedora_branch}-${DATE}")
    if [[ -n "${GIT_SHA}" ]]; then
        BUILD_TAGS+=("${fedora_branch}-${DATE}-${GIT_SHA}")
    fi

    if [[ "${fedora_branch}" == "{{ default_fedora_branch }}" ]]; then
        BUILD_TAGS+=("latest" "latest-${DATE}" "${DATE}")
        if [[ -n "${GIT_SHA}" ]]; then
            BUILD_TAGS+=("latest-${GIT_SHA}" "latest-${DATE}-${GIT_SHA}" "${DATE}-${GIT_SHA}")
        fi
    fi

    # The other channel aliases: next is the branched pre-release's,
    # rolling is rawhide's. Only latest owns the bare date tag.
    if [[ "${fedora_branch}" == "{{ next_fedora_branch }}" ]]; then
        BUILD_TAGS+=("next" "next-${DATE}")
        if [[ -n "${GIT_SHA}" ]]; then
            BUILD_TAGS+=("next-${GIT_SHA}" "next-${DATE}-${GIT_SHA}")
        fi
    fi
    if [[ "${fedora_branch}" == "rawhide" ]]; then
        BUILD_TAGS+=("rolling" "rolling-${DATE}")
        if [[ -n "${GIT_SHA}" ]]; then
            BUILD_TAGS+=("rolling-${GIT_SHA}" "rolling-${DATE}-${GIT_SHA}")
        fi
    fi

    echo "${BUILD_TAGS[@]}"

# Tag Images
[group('Utility')]
tag-images $target_image=image_name $tag=default_fedora_branch tags="":
    #!/usr/bin/env bash
    set -eoux pipefail

    # Get Image, and untag
    IMAGE=$(podman inspect ${target_image}:${tag} | jq -r .[].Id)
    podman untag ${IMAGE}

    # Tag Image
    for tag in {{ tags }}; do
        podman tag $IMAGE "${target_image}:${tag}"
    done

    # Show Images
    podman images

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
