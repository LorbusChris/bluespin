# The one Containerfile for every bluespin image.
#
# Which base to build on comes in as BASE_IMAGE: the Bluefin the shipping
# variants (bluespin, bluespin-dx, bluespin-surface) build on, or Fedora's own
# Silverblue for the images Universal Blue publishes no base for (the
# experimental rawhide image today). `just build` supplies it from bluespin.env,
# where the digests are pinned in one place and Renovate tracks them; there is
# deliberately no default here, so a pin cannot drift between two files.
#
# What goes on top is decided in build_files/build.sh, from IMAGE_NAME (the
# variant) and from what the base turns out to provide.
ARG BASE_IMAGE
ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files
COPY /files /files
COPY /extensions /extensions
COPY /cosign.pub /cosign.pub

# Base Image
FROM ${BASE_IMAGE} AS base
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:latest
# quay.io/centos-bootc/centos-bootc:stream10

FROM base

ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh

RUN bootc container lint
