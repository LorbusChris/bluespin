# bluespin

Custom [bootc](https://bootc-dev.github.io/bootc/) images based on
[Bluefin DX](https://projectbluefin.io/), built with the
[Universal Blue](https://universal-blue.org/) tooling.

## Variants

| Image | Purpose |
| --- | --- |
| `ghcr.io/lorbuschris/bluespin` | Base: Bluefin DX plus extra GNOME apps and shell extensions |
| `ghcr.io/lorbuschris/bluespin-dx` | Adds development and packaging tools |
| `ghcr.io/lorbuschris/bluespin-surface` | Replaces the kernel with [linux-surface](https://github.com/linux-surface/linux-surface)'s `kernel-surface` + `iptsd` for Microsoft Surface devices |

## Switching to bluespin

From an existing bootc/atomic Fedora system:

```bash
sudo bootc switch ghcr.io/lorbuschris/bluespin:latest
```

Images are signed with [cosign](https://github.com/sigstore/cosign); the public
key is [`cosign.pub`](cosign.pub). The image ships a
`/etc/containers/policy.json` entry so updates from `ghcr.io/lorbuschris` are
signature-verified on-device. To verify manually:

```bash
cosign verify --key cosign.pub ghcr.io/lorbuschris/bluespin:latest
```

## Building locally

Requires `just` and rootful `podman`.

```bash
just build bluespin            # or bluespin-dx / bluespin-surface
just build-qcow2 localhost/bluespin   # disk image via bootc-image-builder
just build-iso localhost/bluespin-dx  # per-variant Anaconda installer ISO
just run-vm-qcow2 localhost/bluespin  # boot it in a web-based VM
```

CI builds all three variants daily and on every push to `main`
(see [`.github/workflows/build.yml`](.github/workflows/build.yml)).
