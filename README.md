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
- `io.missioncenter.MissionCenter`

Because of the overwrite, new Bluefin Brewfile additions do not appear here
automatically — diff against
`projectbluefin/common:system_files/bluefin/usr/share/ublue-os/homebrew/`
occasionally. The base's `brew-preinstall` mechanism (network-installing CLI
tools at first login) is removed in the build; its `system-cli` tools are
already present in the image as RPMs (or, for starship, a binary Bluefin
bakes from upstream), so brew was only shadowing them in `PATH`, while
`bluefinctl` and the `chairlift` cask are dropped.

Note that removing a preinstall entry uninstalls the app from users'
systems; apps installed before the preinstall migration (or by the user) are
never removed automatically. The `Validate Flatpaks` workflow checks every
entry against Flathub on PRs, and fails on end-of-life or renamed apps.

## GNOME Shell extensions

Most extensions come from Fedora RPMs, or from the Bluefin base, which vendors
several as git submodules pinned to branches matching the shell it ships — the
build deliberately does not install Fedora's RPMs for those, so the base's
copies survive (see the note in [build.sh](build_files/build.sh)).

Two extensions Fedora does not package are vendored here the same way, under
[extensions/](extensions/):

| Extension | Upstream fork | Why vendored |
| --- | --- | --- |
| Weather or Not | [gitlab.gnome.org/lorbus](https://gitlab.gnome.org/lorbus/gnome-shell-extension-weather-or-not) | dropped from Fedora after F43 |
| NekoTorch | [gitlab.com/lorbus42](https://gitlab.com/lorbus42/NekoTorch) | only packaged in a COPR targeting shell 48 |
| Tiling Shell | [domferr/tilingshell](https://github.com/domferr/tilingshell) (upstream, tag `18.0-candidate`) | not in Fedora; only third-party COPRs |

Tiling Shell ships TypeScript, so it is compiled by
[build_pre.sh](build_files/build_pre.sh) in a separate `build-pre` container
stage; only its output is copied into the image, keeping the Node toolchain
out entirely.

Clone with `--recurse-submodules`. Bump them with
`git submodule update --remote`; every enabled extension must declare support
for the shell version the image ships, which the build enforces.

Which extensions are on by default is the `ENABLED_EXTENSIONS` list in
[build.sh](build_files/build.sh), rendered into
`zz2-bluespin-extensions.gschema.override` at build time. `screen-rotate` is
added on `bluespin-surface` only; everything else is the same across variants.
Bluefin's `blur-my-shell`, `dash-to-dock`, `gsconnect` and `logomenu` are
deliberately left off, as are `nekotorch`, `tilingshell`, `just-perfection`
and the Fedora default (GNOME Classic) set — all shipped, none enabled.

GSettings overrides **replace** the key rather than merging, so that list
restates Bluefin's defaults — new extensions Bluefin enables upstream will not
appear here automatically.

## Building locally

Requires `just` and `podman`.

```bash
just build bluespin            # or bluespin-dx / bluespin-surface
just rechunk bluespin          # optional: split into update-friendly layers
```

CI builds all three variants daily and on every push to `main`
(see [`.github/workflows/build.yml`](.github/workflows/build.yml)).

## ISOs

Live installer ISOs are built with
[Titanoboa](https://github.com/ublue-os/titanoboa) directly from the
published images — the same mechanism Bluefin and Bazzite use. Trigger the
[`Build Bluespin ISOs`](.github/workflows/build-iso.yml) workflow from the
Actions tab; it produces one ISO per variant (with checksums) as workflow
artifacts.
