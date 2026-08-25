# bluespin

Custom [bootc](https://bootc-dev.github.io/bootc/) desktop images built on
[Fedora Silverblue](https://fedoraproject.org/atomic-desktops/silverblue/),
taking some configuration and plenty of inspiration from
[Bluefin](https://projectbluefin.io/) — without building on it. Everything
layered on top of the base is a recorded decision in this repo; the desktop
ones live in [docs/desktop-defaults.md](docs/desktop-defaults.md).

## Variants

| Image | Purpose |
| --- | --- |
| `ghcr.io/lorbuschris/bluespin` | Fedora Silverblue plus full multimedia, curated GNOME apps, shell extensions and desktop defaults |
| `ghcr.io/lorbuschris/bluespin-dx` | Adds the developer layer ([dx.sh](build_files/dx.sh)): virtualisation, containers, tracing and packaging tools |
| `ghcr.io/lorbuschris/bluespin-surface` | Replaces the kernel with a [linux-surface](https://github.com/linux-surface/linux-surface)-patched kernel + `iptsd`, built in our [@mobility/surface](https://copr.fedorainfracloud.org/coprs/g/mobility/surface/) COPR, for Microsoft Surface devices |

Each platform is built per Fedora branch, and the branch is the tag:
`bluespin:44`, `bluespin-dx:rawhide`. `latest` is an alias for the default
branch (44). Every branch builds on Fedora's own Silverblue; which branches
CI builds is the matrix in [build.yml](.github/workflows/build.yml), and the
rawhide legs exist to find out what breaks on the next GNOME before it
ships.

## What the images carry

- **Full multimedia** from RPMFusion: real `ffmpeg` and `fdk-aac`, VA-API
  hardware decode, HEIC, and aptX for Bluetooth audio. The repos ship
  installed but disabled — enabled only for the build's own transactions.
- **A curated GNOME desktop**: fonts, keybindings, app-grid folders, Ptyxis
  defaults and a per-platform extension set. Every choice against Fedora's
  and Bluefin's defaults is recorded in
  [docs/desktop-defaults.md](docs/desktop-defaults.md).
- **Flatpaks in two tiers**: one preinstalled system set, opt-in per-user
  catalogs for the rest (see below).
- **`ujust`** with a vendored, curated recipe library at
  `/usr/share/bluespin/just` (from
  [ublue-os/packages](https://github.com/ublue-os/packages), Apache-2.0) —
  only recipes that actually work on these images.
- **Updates via [uupd](https://github.com/ublue-os/uupd)** — system image,
  flatpaks in both scopes, distrobox. GNOME Software is removed rather than
  left racing it; `ujust toggle-updates` turns the timer on and off.
- **Shell and login**: the [starship](https://starship.rs/) prompt for bash
  (checksum-pinned upstream binary), and a small motd — banner plus one tip
  in the first shell of a session, kernel/uptime/disk on every SSH login;
  `ujust toggle-user-motd` hides it.
- **Tailscale**, with `tailscaled` enabled but idle until `tailscale up`;
  `ujust tailscale-operator` lets your user drive it without sudo.
- **A signed `v4l2loopback`** virtual camera on every platform and branch,
  built from the vendored submodule in a throwaway Containerfile stage.

## Secure Boot

Two things in these images are signed with bluespin's own MOK key, and one
enrolment covers both:

- **`v4l2loopback`** (the virtual camera OBS and friends use), on every
  platform and branch. It is built from
  [upstream's sources](https://github.com/v4l2loopback/v4l2loopback) —
  vendored as a submodule — against the exact kernel each image ships, and
  signed in the Containerfile's `kernel-builder` stage; the private key is
  only ever mounted into that throwaway stage, never one that ships.
- **The `bluespin-surface` kernel**, whose `vmlinuz` is re-signed after
  coming from our own
  [`@mobility/surface`](https://copr.fedorainfracloud.org/coprs/g/mobility/surface/)
  COPR (COPR can only sign with Red Hat's test keys, which shim rejects).

Enroll the certificate once:

```bash
ujust enroll-secureboot-key   # wraps: sudo mokutil --import /usr/lib/pki/bluespin-secureboot.der
```

mokutil asks for a one-time password; at the next boot, the MOK manager
appears — choose "Enroll MOK" and enter it.

Without enrolling, `bluespin` and `bluespin-dx` still boot normally — their
kernels carry Fedora's own signature, which shim already trusts — and only
the virtual camera stays unavailable. `bluespin-surface` needs the enrolment
to boot with Secure Boot on at all, since its kernel is ours.

Images built without the signing key (a fork's pull request, a local
`just build` without `SECUREBOOT_KEY_FILE`) ship the module unsigned and the
surface kernel with its COPR test-key signature; both say so in the build
log, and both work with Secure Boot disabled.

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

Every published digest additionally carries a **keyless** signature bound to
the build workflow's OIDC identity (Fulcio certificate, logged in Rekor).
On-device verification keeps enforcing the key; the keyless signature exists
so a later switch is a policy change rather than a re-signing campaign. To
verify it:

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/LorbusChris/bluespin/\.github/workflows/build\.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lorbuschris/bluespin:latest
```

## Flatpak curation

Flatpaks come in two tiers. The system set — one
[desktop.preinstall](files/usr/share/flatpak/preinstall.d/desktop.preinstall)
for every platform — ships as [flatpak preinstall](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall)
entries, the same mechanism current Bluefin uses. Everything else is an
opt-in per-user catalog under
[files/usr/share/bluespin/flatpaks/](files/usr/share/bluespin/flatpaks/):
`extra` (general desktop: GNOME Circle and community apps) and `dx`
(developer GUIs), installed with `ujust install-flatpaks <set>` and removed
with `ujust remove-flatpaks <set>` — per-user on purpose, so opting in
needs no root and never touches the OS-level set.

Deliberately excluded from Bluefin's sets:

- `org.mozilla.firefox` — Firefox is installed as an RPM instead

Mission Center (`io.missioncenter.MissionCenter`) is the system monitor, as
on Bluefin; the `gnome-system-monitor` RPM is removed. The `nethogs` RPM is
installed for Mission Center's per-app network usage. It has to run without
root, which takes file capabilities on the binary, so `/usr/bin/nethogs` is
made executable by `wheel` only — its members already hold root through
sudo, whereas world-executable capabilities would hand every local account
packet capture and unrestricted file reads. See the note in
[build.sh](build_files/build.sh).

Note that removing a preinstall entry uninstalls the app from users'
systems; apps installed before the preinstall migration (or by the user) are
never removed automatically. The `Validate Flatpaks` workflow checks every
entry — preinstalls and catalogs — against Flathub on PRs, and fails on
end-of-life or renamed apps.

## GNOME Shell extensions

Every extension we enable comes from a source we control, installed the same
way on every branch. The ones Fedora does not package — or packages behind
the shell we ship — are pinned by repository and exact commit in
[extensions.sh](build_files/extensions.sh) and fetched at build time as
forge tarballs — no git in the build and no submodules to keep in step.
Renovate follows each pin's branch (most are our forks, patched on their
default branch for the GNOME we ship) and also watches each fork's
*upstream*, so a PR appears both when a fork moves and when upstream lands
support for the next GNOME — the moment a fork can be rebased or retired:

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

Screen Rotate ships installed on every platform but is enabled nowhere for
now: Fedora's RPM does not yet declare GNOME 51, and an enabled extension
that cannot load is a warning on every 51 leg.

Enabled means successfully enabled: the build fails if an extension of ours
that a platform enables does not declare the shell the image ships (an
extension that does not is silently left off at login); for Fedora's it
warns. Everything vendored is installed on every platform regardless, so an
extension a platform does not enable is one toggle away. Bluefin's
`blur-my-shell`, `dash-to-dock`, `gsconnect` and `logomenu` are deliberately
left off, as are `just-perfection` and the Fedora default (GNOME Classic)
set. GSettings overrides replace the key rather than merging, so this table
is the complete enabled set.

System Monitor is GNOME's own top-bar indicator from `gnome-shell-extensions`,
replacing Fedora's `gnome-shell-extension-system-monitor` RPM. The stock
extension hides itself when `org.gnome.SystemMonitor.desktop` is not found —
and that RPM is removed here — so it would never show; the fork looks for
Mission Center first. Upstream renders its `metadata.json` with meson, so
the build does the equivalent substitution itself, declaring the shell the
image ships — the extension's code is identical between upstream's
`gnome-50` branch and `main`, so one pin serves both the 44 and the rawhide
legs.

Mosaic WM is the tiling extension, replacing Tiling Shell. It is plain
JavaScript, so it needs no build step. Upstream develops each shell on its
own branch — `main` declares `["50"]`, `gnome-51` declares `["51"]` — and
the two have diverged too far for one pin, so both branches are pinned and
the build fetches the one for the shell the image ships. A shell with no
pin fails the build.

The one submodule left in this repo is the v4l2loopback kernel module under
[kmods/](kmods/) — clone with `--recurse-submodules` to build locally.
Extension pins bump via Renovate, or by editing the commit in
[extensions.sh](build_files/extensions.sh).

## Trash launcher

[trash.desktop](files/usr/share/applications/trash.desktop) adds a "Trash"
entry to the app grid that opens `trash:///` in Files. Its name and comment
are the strings of GTK's own sidebar Trash entry, so the build localises it
from the image's `gtk40` catalogs with
[desktop-translations.py](build_files/desktop-translations.py) rather than
keeping a copy of the translations here.

## The developer layer

The two non-dx images carry no developer tooling — that alone is roughly
half the uncompressed size of a dx image. [dx.sh](build_files/dx.sh) builds
the developer layer for `bluespin-dx` only: virtualisation
(libvirt/qemu/virt-manager), incus/LXC, Cockpit, podman extras, tracing and
perf tools, ROCm, the C toolchain, Fedora packaging tools, VS Code from
Microsoft's repo (shipped disabled, like every external repo here), and the
Kubernetes CLIs — kubectl, helm, k9s, flux, argocd, grype, syft — as
digest-pinned podman functions
([97-bluespin-container-clis.sh](files/etc/profile.d/97-bluespin-container-clis.sh))
rather than installed binaries: nothing on the host, every tool pinned like
the rest of this repo, and a real binary of the same name always wins.

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
just build bluespin              # the default branch; or bluespin-dx / bluespin-surface
just build bluespin-dx rawhide   # any platform on any branch in bluespin.env
NO_CACHE=1 just build bluespin   # force a full rebuild (see the caveat below)
just rechunk bluespin 44         # optional: split into update-friendly layers
```

Every image comes from the one [Containerfile](Containerfile), as a
layered family selected by `--target`:

```
base (Silverblue) → bluespin → dx
                             → surface
```

[build.sh](build_files/build.sh) builds the **bluespin** layer — everything
the platforms share, with
[silverblue_base.sh](build_files/silverblue_base.sh) supplying what a plain
Silverblue base lacks (the updater, ujust, Flathub and the preinstall
service, the multimedia stack). The variants are thin deltas on top:
[dx.sh](build_files/dx.sh) or [surface.sh](build_files/surface.sh), then a
shared [variant-finish.sh](build_files/variant-finish.sh) that stamps the
variant's identity and per-platform desktop/extension set. Two throwaway
**kernel-builder** flavors (stock and surface) do everything that must
install tooling in order to build something — gcc and kernel-devel for the
v4l2loopback module, sbsigntools for the surface vmlinuz — and are the only
stages the Secure Boot key is ever mounted into. The branch's base comes in
as `BASE_IMAGE` from [bluespin.env](bluespin.env), where the digests are
pinned and Renovate tracks them.

Locally and on pull requests a variant build chains from the bluespin stage
inside the Containerfile (self-contained). On pushes to `main`, CI builds
and publishes the bluespin image first and the variant jobs then build
`FROM` that published digest (`BLUESPIN_IMAGE`), so dx and surface never
rebuild the bluespin content
(see [`build.yml`](.github/workflows/build.yml) calling
[`build-image.yml`](.github/workflows/build-image.yml)). Every published
image is then rechunked with [chunkah](https://github.com/coreos/chunkah),
so a client update downloads only the chunks whose packages changed. CI
builds the matrix daily and on every push to `main`.

One local-only caveat: podman keys the build cache on the base image and the
`RUN` command, but **not** on the contents of the `ctx` stage the build
scripts are bind-mounted from, nor on build secrets. A local rebuild can
silently reuse a layer built from older scripts — `NO_CACHE=1` exists for
exactly that. CI runners start cold, so they are unaffected.

## Provenance

Everything in a shipped image that is not from Fedora's own repos:

| Source | What |
| --- | --- |
| RPMFusion (repos shipped disabled) | `ffmpeg`, `fdk-aac`, `libheif-freeworld`, `mesa-va-drivers-freeworld`, `intel-media-driver`, `pipewire-codec-aptx` |
| [ublue-os/packages](https://copr.fedorainfracloud.org/coprs/ublue-os/packages/) COPR | `uupd`, `ublue-os-udev-rules`, `oversteer-udev` |
| [lorbus/network-displays](https://copr.fedorainfracloud.org/coprs/lorbus/network-displays/) COPR | `gnome-network-displays` + extension |
| [lorbus/calls](https://copr.fedorainfracloud.org/coprs/lorbus/calls/) COPR (dx) | `calls` |
| [@mobility/surface](https://copr.fedorainfracloud.org/coprs/g/mobility/surface/) COPR (surface) | the surface `kernel`, `iptsd` |
| packages.microsoft.com (dx, repo shipped disabled) | `code` |
| pkgs.tailscale.com (repo shipped disabled) | `tailscale` |
| Upstream GitHub release, sha256-pinned | `starship` |
| Vendored in this repo | `v4l2loopback` (submodule, built + signed in the kernel-builder stage), the ujust library and recipes |
| Pinned repo + commit, fetched at build | the GNOME Shell extensions ([extensions.sh](build_files/extensions.sh)) |

No third-party repo or COPR is left enabled in a shipped image: each is
enabled for its own transaction and disabled again, so nothing on the
running system resolves against them unless the user turns one on. Flatpaks
all come from Flathub, validated in CI.

## ISOs

Live installer ISOs are built with
[Titanoboa](https://github.com/ublue-os/titanoboa) directly from the
published images — the same mechanism Bluefin and Bazzite use. Trigger the
[`Build Bluespin ISOs`](.github/workflows/build-iso.yml) workflow from the
Actions tab; it produces one ISO per variant (with checksums) as workflow
artifacts.
