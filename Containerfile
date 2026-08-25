# The one Containerfile for every bluespin image, as a layered family:
#
#   base (Fedora Silverblue) -> bluespin -> dx
#                                        -> surface
#                                        -> fp5 (aarch64)
#
# Every platform is built per Fedora branch; the branch's base comes in as
# BASE_IMAGE from bluespin.env (digests pinned in one place, Renovate
# tracks them; deliberately no default here, so a pin cannot drift between
# two files). `just build <platform> <branch>` selects the platform's stage
# with --target.
#
# The variants are thin deltas ON TOP of the bluespin image: locally they
# build FROM the bluespin stage in this file; in CI (on main) they build
# FROM the pushed bluespin image by digest via BLUESPIN_IMAGE, so a
# variant build never rebuilds the bluespin content. (What ships is then
# rechunked per image for small client updates -- see build-image.yml.)
ARG BASE_IMAGE
ARG BLUESPIN_IMAGE=bluespin

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files
COPY /files /files
COPY /kmods /kmods
COPY /devices /devices
COPY /cosign.pub /cosign.pub

# Base Image
FROM ${BASE_IMAGE} AS base
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:latest
# quay.io/centos-bootc/centos-bootc:stream10

# Everything that installs tooling in order to BUILD something -- the
# v4l2loopback module (gcc, kernel-devel) and the surface vmlinuz re-signing
# (sbsigntools) -- happens in throwaway stages, so no shipping image ever
# carries build tooling, not even as an install-then-remove. Two flavors,
# one per kernel: the stock builder FROMs the same base as the bluespin
# image, so it builds against the very kernel that image ships; the surface
# builder resolves the surface kernel from the COPR, and surface.sh asserts
# both sides agreed. Only the stage a --target actually needs is built.
#
# secureboot_key: optional, and mounted ONLY here -- the private key never
# touches a stage that ships. When `just build` passes it (CI does, from the
# SECUREBOOT_KEY repo secret), the module -- and on surface the kernel image
# -- is signed with our MOK key; without it the build still works and warns.
# required=false keeps keyless local builds building.
FROM base AS kernel-builder-stock

ARG IMAGE_NAME=bluespin
ARG V4L2LOOPBACK_VERSION

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=secureboot_key,required=false \
    /ctx/build_files/kernel-builder.sh

FROM base AS kernel-builder-surface

ARG IMAGE_NAME=bluespin-surface
ARG V4L2LOOPBACK_VERSION

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=secureboot_key,required=false \
    /ctx/build_files/kernel-builder.sh

# The bluespin layer: the image of that name itself, and everything the
# variants share -- see build_files/build.sh.
FROM base AS bluespin

ARG IMAGE_NAME=bluespin
ARG FEDORA_BRANCH

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=kernel-builder-stock,source=/out,target=/kernel-out \
    /ctx/build_files/build.sh

RUN bootc container lint

# The developer variant: dx.sh's tooling, then the variant finishing
# (identity, per-platform desktop and extensions, cleanup).
FROM ${BLUESPIN_IMAGE} AS dx

ARG IMAGE_NAME=bluespin-dx
ARG FEDORA_BRANCH

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/dx.sh && \
    /ctx/build_files/variant-finish.sh bluespin-dx

RUN bootc container lint

# The surface variant: the surface kernel and its friends (surface.sh,
# consuming the surface kernel-builder), then the same finishing.
FROM ${BLUESPIN_IMAGE} AS surface

ARG IMAGE_NAME=bluespin-surface
ARG FEDORA_BRANCH

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=kernel-builder-surface,source=/out,target=/kernel-out \
    /ctx/build_files/surface.sh && \
    /ctx/build_files/variant-finish.sh bluespin-surface

RUN bootc container lint

# The phone variant: Fairphone 5 (SC7280/QCM6490, aarch64) -- the device
# layer from pocketblue plus the mobile shell, layered on the very same
# bluespin image as dx and surface. The bluespin.env base pins are
# multi-arch OCI indexes, so the same digest serves this architecture;
# build with `just build bluespin-fp5 45 arm64` (or natively on arm64).
FROM ${BLUESPIN_IMAGE} AS fp5

ARG IMAGE_NAME=bluespin-fp5
ARG FEDORA_BRANCH

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/fp5.sh && \
    /ctx/build_files/variant-finish.sh bluespin-fp5

RUN bootc container lint
