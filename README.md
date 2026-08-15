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

## Flatpak curation

Flatpaks are shipped as [flatpak preinstall](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall)
entries under [files/usr/share/flatpak/preinstall.d/](files/usr/share/flatpak/preinstall.d/)
(common + extra on all variants, dx apps on `bluespin-dx` only) — the same
mechanism current Bluefin uses. The optional `full-desktop` set installs via
`ujust bbrew` from [full-desktop.Brewfile](files/usr/share/ublue-os/homebrew/full-desktop.Brewfile).

The set was forked from Bluefin's defaults (Nov 2025, commit `1b24cf5`) and is
curated independently. Current Bluefin preinstalls only Bazaar, so the
preinstall set here is purely additive on top of the base. Bluefin's former
defaults live on in its `system-flatpaks*.Brewfile` files; since bluespin
preinstalls everything it wants, it ships `system-flatpaks.Brewfile` only as
an empty stub (masking the base's copy so `ujust install-system-flatpaks`
stays a working no-op), removes the base's dx Brewfile in the build, and
keeps `full-desktop.Brewfile` as the single opt-in catalog. Deliberately
excluded from Bluefin's current sets:

- `org.mozilla.firefox` — Firefox is installed as an RPM instead
- `org.gnome.Papers`, `org.gnome.SimpleScan` — installed as RPMs instead
- `io.missioncenter.MissionCenter`

Because of the overwrite, new Bluefin Brewfile additions do not appear here
automatically — diff against
`projectbluefin/common:system_files/bluefin/usr/share/ublue-os/homebrew/`
occasionally. The base's `brew-preinstall` mechanism (network-installing CLI
tools at first login) is removed in the build; its `system-cli` tools are
baked as RPMs instead, while `bluefinctl` and the `chairlift` cask are
dropped.

Note that removing a preinstall entry uninstalls the app from users'
systems; apps installed before the preinstall migration (or by the user) are
never removed automatically. The `Validate Flatpaks` workflow checks every
entry against Flathub on PRs, and fails on end-of-life or renamed apps.

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
