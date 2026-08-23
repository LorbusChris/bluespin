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

Each platform is built per Fedora branch, and the branch is the tag:
`bluespin:44`, `bluespin-dx:rawhide`. `latest` is an alias for the default
branch (44). 44 builds on Bluefin; 45 and rawhide build on Fedora's own
Silverblue, since Universal Blue publishes nothing above 44, and the build
supplies what that base lacks. Which branches CI builds is the matrix in
[build.yml](.github/workflows/build.yml); the rawhide legs exist to find out
what breaks on the next GNOME before it ships.

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

Mission Center (`io.missioncenter.MissionCenter`) is the system monitor, as
on Bluefin; the `gnome-system-monitor` RPM (which the base merely hides) is
removed. The `nethogs` RPM is installed for Mission Center's per-app network
usage. It has to run without root, which takes file capabilities on the
binary, so `/usr/bin/nethogs` is made executable by `wheel` only — its
members already hold root through sudo, whereas world-executable capabilities
would hand every local account packet capture and unrestricted file reads.
See the note in [build.sh](build_files/build.sh).

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

Every extension we enable comes from a source we control, installed the same
way on every base. The ones Fedora does not package -- or packages behind the
shell we ship -- are vendored as git submodules under
[extensions/](extensions/); on a Bluefin base that replaces the base's own
copies of the same extensions, so one pin serves every branch:

| Extension | Source | Why vendored |
| --- | --- | --- |
| AppIndicator | [ubuntu/gnome-shell-extension-appindicator](https://github.com/ubuntu/gnome-shell-extension-appindicator) | upstream, pinned by us |
| Bazaar Companion | [LorbusChris/bazaar-companion](https://github.com/LorbusChris/bazaar-companion) | not packaged by Fedora |
| Caffeine | [LorbusChris/gnome-shell-extension-caffeine](https://github.com/LorbusChris/gnome-shell-extension-caffeine) | fork declaring the current shell |
| Gradia Capture | [LorbusChris/gradia-capture](https://github.com/LorbusChris/gradia-capture) | not packaged by Fedora |
| Search Light | [LorbusChris/search-light](https://github.com/LorbusChris/search-light) | fork declaring the current shell |
| Weather or Not | [gitlab.gnome.org/lorbus](https://gitlab.gnome.org/lorbus/gnome-shell-extension-weather-or-not) | dropped from Fedora after F43 |
| NekoTorch | [gitlab.com/lorbus42](https://gitlab.com/lorbus42/NekoTorch) | only packaged in a COPR targeting shell 48 |
| Mosaic WM | [CleoMenezesJr/MosaicWM](https://github.com/CleoMenezesJr/MosaicWM), pinned twice (`main` for GNOME 50, `gnome-51` for 51) | not packaged anywhere |
| System Monitor | [gitlab.gnome.org/lorbus](https://gitlab.gnome.org/lorbus/gnome-shell-extensions) | Fedora's build only opens GNOME System Monitor; the fork prefers Mission Center and adds CPU, GPU and disk temperature readouts |

Network Displays comes as an RPM from our own
[lorbus/network-displays](https://copr.fedorainfracloud.org/coprs/lorbus/network-displays/)
COPR, and Screen Rotate is Fedora's `gnome-shell-extension-screen-autorotate`.

What is enabled by default is one table, `enabled_extensions_for_platform`
in [extensions.sh](build_files/extensions.sh), rendered into
`zz2-bluespin-extensions.gschema.override` at build time:

| Enabled on | Extensions |
| --- | --- |
| every platform | AppIndicator, Bazaar Companion, Caffeine, Gradia Capture, Network Displays, Search Light |
| `bluespin`, `bluespin-dx`, `bluespin-surface` | Weather or Not |
| `bluespin-dx` | System Monitor, Mosaic WM |
| `bluespin-surface` | Screen Rotate |

Enabled means successfully enabled: the build fails if an extension of ours
that a platform enables does not declare the shell the image ships (an
extension that does not is silently left off at login); for Fedora's it
warns. Everything vendored is installed on every platform regardless, so an
extension a platform does not enable is one toggle away. Bluefin's
`blur-my-shell`, `dash-to-dock`, `gsconnect` and `logomenu` are deliberately
left off, as are `just-perfection` and the Fedora default (GNOME Classic) set.

System Monitor is GNOME's own top-bar indicator from `gnome-shell-extensions`,
replacing Fedora's `gnome-shell-extension-system-monitor` RPM. The stock
extension hides itself when `org.gnome.SystemMonitor.desktop` is not found,
which on the Bluefin base (where that file is hidden) or here (where the RPM
is gone) means it never shows; the fork looks for Mission Center first.
Upstream renders its `metadata.json` with meson, so the build does the
equivalent substitution itself, declaring the shell the image ships — the
extension's code is identical between upstream's `gnome-50` branch and
`main`, so one pin serves both the 44 and the rawhide legs.

Mosaic WM is the tiling extension, replacing Tiling Shell. It is plain
JavaScript, so it needs no build step. Upstream develops each shell on its
own branch -- `main` declares `["50"]`, `gnome-51` declares `["51"]` -- and
the two have diverged too far for one pin, so both are vendored
(`extensions/mosaicwm` tracks `main`, `extensions/mosaicwm-gnome-51` tracks
`gnome-51`) and the build takes the one for the shell the image ships. A
shell with no pin fails the build.

Clone with `--recurse-submodules`. Bump them with
`git submodule update --remote`.

GSettings overrides **replace** the key rather than merging, so the table
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
just build bluespin            # the default branch; or bluespin-dx / bluespin-surface
just build bluespin-dx rawhide # any platform on any branch in bluespin.env
just rechunk bluespin 44       # optional: split into update-friendly layers
```

Every image comes from the one [Containerfile](Containerfile): the branch's
base is passed in as `BASE_IMAGE` from [bluespin.env](bluespin.env), where the
digests are pinned and Renovate tracks them, and
[build.sh](build_files/build.sh) is the single entry point. It branches on
`IMAGE_NAME` for the platform and detects the base it is on -- a Universal Blue
base already ships uupd, ujust, Homebrew and the flatpak preinstall service,
plain Silverblue gets them from [silverblue_base.sh](build_files/silverblue_base.sh).

CI builds the matrix daily and on every push to `main`
(see [`.github/workflows/build.yml`](.github/workflows/build.yml)).

## ISOs

Live installer ISOs are built with
[Titanoboa](https://github.com/ublue-os/titanoboa) directly from the
published images — the same mechanism Bluefin and Bazzite use. Trigger the
[`Build Bluespin ISOs`](.github/workflows/build-iso.yml) workflow from the
Actions tab; it produces one ISO per variant (with checksums) as workflow
artifacts.
