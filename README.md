# bluespin

Custom [bootc](https://bootc-dev.github.io/bootc/) images based on
[Bluefin](https://projectbluefin.io/), built with the
[Universal Blue](https://universal-blue.org/) tooling.

## Variants

| Image | Purpose |
| --- | --- |
| `ghcr.io/lorbuschris/bluespin` | Base: Bluefin plus extra GNOME apps and shell extensions |
| `ghcr.io/lorbuschris/bluespin-dx` | Adds the developer layer ([dx.sh](build_files/dx.sh)) plus packaging tools |
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
| Mosaic WM | [CleoMenezesJr/MosaicWM](https://github.com/CleoMenezesJr/MosaicWM) | not packaged anywhere |

Mosaic WM is the tiling extension, replacing Tiling Shell. It is plain
JavaScript, so it needs no build step. Upstream declares `shell-version`
`["50"]`. It ships disabled everywhere, and its shell coverage is tracked in
the GNOME compatibility report each image workflow publishes rather than
asserted at build time — it patches window
management internals via `InjectionManager`, which is not something to declare
compatible with a newer shell without running it.

Clone with `--recurse-submodules`. Bump them with
`git submodule update --remote`; every enabled extension must declare support
for the shell version the image ships, which the build enforces.

Which extensions are on by default is the `ENABLED_EXTENSIONS` list in
[build.sh](build_files/build.sh), rendered into
`zz2-bluespin-extensions.gschema.override` at build time. `screen-rotate` is
added on `bluespin-surface` only; everything else is the same across variants.
Bluefin's `blur-my-shell`, `dash-to-dock`, `gsconnect` and `logomenu` are
deliberately left off, as are `nekotorch`, `mosaicwm`, `just-perfection`
and the Fedora default (GNOME Classic) set — all shipped, none enabled.

GSettings overrides **replace** the key rather than merging, so that list
restates Bluefin's defaults — new extensions Bluefin enables upstream will not
appear here automatically.

## Trash launcher

[trash.desktop](files/usr/share/applications/trash.desktop) adds a "Trash"
entry to the app grid that opens `trash:///` in Files. Its name and comment
are the strings of GTK's own sidebar Trash entry, so the build localises it
from the image's `gtk40` catalogs with
[desktop-translations.py](build_files/desktop-translations.py) rather than
keeping a copy of the translations here.

## The developer layer

All variants build on `ghcr.io/ublue-os/bluefin`, not `bluefin-dx`, so the two
non-dx images do not carry developer tooling — that alone is roughly half the
uncompressed size. [dx.sh](build_files/dx.sh) re-creates Bluefin's dx layer for
`bluespin-dx` only: virtualisation, incus/LXC, Cockpit, podman extras, tracing
tools, ROCm and VS Code.

**Docker is deliberately omitted** — no `docker-ce`, no `docker.socket`, and
none of its docker-in-docker plumbing. Podman is in the base and
`podman.socket` is enabled.

Two units come with it, since neither exists on the non-dx base:
`libvirt-workaround.service` relabels libvirt's `/var` directories at boot
(a bootc image has no `/var`, so they come up without the SELinux contexts
the RPM would have applied), and `bluespin-dx-groups.service` adds wheel
members to `libvirt` and `incus-admin`.

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
