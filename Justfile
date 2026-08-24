set dotenv-filename := "bluespin.env"
set dotenv-load

export image_name := env_var("IMAGE_NAME")
export repo_organization := env_var("REPO_ORGANIZATION")
export repo_name := env_var("REPO_NAME")
export image_desc := env_var("IMAGE_DESC")
export image_keywords := env_var("IMAGE_KEYWORDS")
export image_logo_url := env_var("IMAGE_LOGO_URL")
export default_fedora_branch := env_var("DEFAULT_FEDORA_BRANCH")
export chunkah_image := env_var("CHUNKAH_IMAGE")

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
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${target_image##*/}")

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

    # Cross-arch builds need qemu-user-static with binfmt registered on an x86
    # host and take hours; CI uses native arm64 runners, where this is a no-op
    # that keeps the recipe honest about what it is producing.
    if [[ -n "${arch}" ]]; then
        PODMAN_BUILD_ARGS+=("--arch" "${arch}")
    fi

    podman build "${PODMAN_BUILD_ARGS[@]}" .

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
