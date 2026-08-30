# Desktop defaults: what bluespin takes from Bluefin, and what it leaves

The Bluefin base configures the desktop through its `zz0` gschema override and
a set of dconf files. The Fedora Silverblue bases do not, so before this review
the f44 images had Bluefin's desktop and the f45/rawhide images had Fedora's.

Every setting is reviewed here against Fedora's actual default, and either
taken or left alone. **What is not taken is as deliberate as what is** — and on
the Bluefin base, "Fedora" means the key is actively stripped from `zz0`,
because an override we do not write cannot un-set one Bluefin already wrote.

Implemented in [build_files/desktop.sh](../build_files/desktop.sh); the
enabled-extension table lives in
[build_files/extensions.sh](../build_files/extensions.sh).

Decisions marked **?** are still open.

## A. Desktop defaults

| # | Setting | Fedora | Bluefin | Decision |
|---|---|---|---|---|
| 1 | Monospace font | `Adwaita Mono 11` | `JetBrains Mono 11` | Bluefin *(needs #56)* |
| 2 | Font antialiasing | `grayscale` | `rgba` (subpixel) | Bluefin |
| 3 | Titlebar font | `Adwaita Sans Bold 11` | `Adwaita Sans Bold 12 @wght=700` | Bluefin |
| 4 | Accent colour | `blue` | `slate` | Fedora |
| 5 | Hot corners | on | off | Fedora |
| 6 | Weekday in clock | off | on | Bluefin · Fedora on fp5 |
| 7 | Numlock at boot | off | on | Bluefin · Fedora on fp5 |
| 8 | Power button | suspends | asks | Bluefin · Fedora on fp5 |
| 9 | App-unresponsive timeout | 5 s | 20 s | Bluefin |
| 10 | File chooser sorting | mixed | folders first | Bluefin |
| 11 | Titlebar buttons | close only | minimise, maximise, close | Bluefin · Fedora on fp5 |
| 12 | Show desktop | unbound | `Super+D` | Bluefin |
| 13 | Alt+Tab | switches apps | switches windows (`Super+Tab` = apps) | Bluefin |
| 14 | Input source switch | `Super+Space` | `Shift+Super+Space` | Bluefin |
| 15 | Unmaximize | `Super+Down` + `Alt+F5` | `Super+Down` only | Bluefin |
| 16 | Terminal shortcut | unbound | `Ctrl+Alt+T`, `Ctrl+Alt+Return` | Bluefin, wired to `ptyxis` |
| 17 | Files shortcut | unbound | `Super+E` | Bluefin |
| 18 | Search Light | no shortcut, upstream look | `Super+Space` + custom look | shortcut only |
| 19 | Wallpaper | Fedora day/night set | Bluefin branded set | Fedora |
| 20 | Background colours | Fedora blue | black / white | Fedora |
| 21 | Dash favourites | Firefox, Calendar, Files, Software, Text Editor, Calculator | Readymade, Firefox, Thunderbird, Files, Bazaar, Software, Code | **ours** (below) |
| 22 | Search providers | all installed answer | Bazaar + Calculator only | Fedora |
| 23 | App-grid folders | flat grid (GNOME upstream ships none) | 9 folders, 4 dead | **ours**: 8 category-driven (below) |
| 24 | Ptyxis theme | always dark | follows system | Fedora |
| 25 | Ptyxis restore session | reopens tabs | fresh window | Bluefin |
| 26 | Ptyxis restore size | remembers | default size | Bluefin |
| 27 | Ptyxis audible bell | beeps | silent | Fedora |
| 28 | Ptyxis palette | GNOME default | `catppuccin-dynamic` file | **Catppuccin Mocha**, bundled (below) |
| 29 | Nautilus → Terminal | **already built in** | configures an obsolete extension | moot — nothing to do |

### 21. Dash favourites, in order

Neither stock list works here: Bluefin's names Readymade (not on Flathub at
all — it is Fyra Labs' ISO installer), Code (dx only) and
`org.mozilla.Thunderbird` (Flathub carries two Mozilla-published Thunderbirds;
we preinstall the lowercase `org.mozilla.thunderbird`), and both lists name
`org.gnome.Software`, which this image removes. GNOME silently drops
favourites whose desktop file is missing, so the stock lists leave a dash of
three icons.

| Position | App | Comes from |
| --- | --- | --- |
| 1 | Firefox | RPM (`org.mozilla.firefox.desktop`) |
| 2 | Thunderbird | preinstalled flatpak (`org.mozilla.thunderbird`) |
| 3 | Files | RPM (`org.gnome.Nautilus`) |
| 4 | Bazaar | preinstalled flatpak |
| 5 | Calendar | preinstalled flatpak |
| 6 | Calculator | preinstalled flatpak |
| 7 | Text Editor | preinstalled flatpak |
| 8 | Code | RPM, **bluespin-dx only** |

### 23. App-grid folders

GNOME upstream's own default is an empty `folder-children` — a flat grid, no
folders — so folders are entirely our addition, not something we inherit.
Bluefin's nine are hardcoded app lists: `YaST` and `Pardus` are never defined
at all (other distributions' system tools), `Wine` and `GamingUtilities` name
apps this image does not ship, and their `Utilities`/`Development` lists are
mostly apps we do not have.

Ours are category-driven, so they populate from whatever is installed and stay
correct as the app set changes. Names come from GNOME's own `.directory`
files, which carry 84-118 translations each. All eight are defined on every
platform: GNOME hides a folder with no matching apps, so an empty one costs
nothing and files a user's later install for free.

| Folder | Label | Populated by | From our set today |
| --- | --- | --- | --- |
| Utilities | Utilities | `X-GNOME-Utilities` + named | Flatseal, Warehouse, Extension Manager, Ignition, Refine, Smile, Disk Utility |
| Graphics | Graphics | `Graphics` | GIMP, Inkscape, Pinta, Loupe, Gradia |
| Office | Office | `Office` | LibreOffice, Calendar, Contacts, Planify, Papers |
| Internet | Internet | `Network` | Firefox, Thunderbird, Fractal, Dino, Signal, Dialect, Connections |
| Multimedia | Sound & Video | `AudioVideo` | Amberol, Shortwave, Podcasts, Showtime, Snapshot, EarTag, Sound Recorder |
| System | System Tools | `System` | Mission Center, Firmware, Logs, Disk Usage, firewall-config |
| Games | Games | `Game` | empty until a user opts in (Steam, Cartridges and Bottles are in the catalogs); empty folders stay invisible |
| Development | Programming | `Development`, `IDE` + named | dx: Ghidra, Arduino IDE, Podman Desktop, D-Spy, Code, virt-manager |

### 28. The Ptyxis palette

Bluefin's `catppuccin-dynamic` is not a Ptyxis built-in: Ptyxis bundles
Catppuccin Latte, Frappé, Macchiato and Mocha as four flat palettes, and the
"dynamic" one is a file pairing Latte (light) with Mocha (dark) so the
terminal follows the system style.

We use the **bundled Catppuccin Mocha** instead, because #24 keeps the
terminal always dark — the light half could never appear, and the dark half
of Bluefin's file is byte-identical to the bundled Mocha. That also avoids
the file's limitation: Ptyxis reads palettes from the user's data directory
only, with no system-wide path, so a shipped palette has to travel through
`/etc/skel` and reaches only accounts created after installation. A bundled
palette works for every user immediately.

If #24 ever flips to follow the system, revisit this: the light half becomes
visible, and the file (with its `/etc/skel` caveat) earns its keep.

Palette identifiers are the bundled file's stem — `gnome.palette` is the
schema default `gnome`, so Mocha is `Catppuccin Mocha`. If that ever stops
matching, Ptyxis silently falls back to its default palette.

### 29. Nautilus "Open in Console" — already native

Nautilus 50/51 ships this itself: the context-menu action
`view.current-directory-console`, with `Ctrl+.` as its shortcut. It launches
whichever app registers `Categories=TerminalEmulator`, and Ptyxis is the only
one on every platform — so it already opens Ptyxis in the right directory,
with nothing installed or configured.

`nautilus-open-any-terminal`, which Bluefin's override configures with four
keys, is the pre-GNOME-46 answer to this. It is not packaged in any Fedora
branch and is not installed on the Bluefin base either, so those four keys
are inert there as well as here.

## B. Hardware

| # | Item | Fedora (without) | Bluefin (with) | Decision |
|---|---|---|---|---|
| 30+31 | `ublue-os-udev-rules` | controllers/keys work partially; apps and flatpaks often cannot reach them | non-root access for controllers, VR, Wooting/ZSA, U2F/Titan, Framework 16, Arduino, SuperDrive | **yes** — COPR package, owns the rules on every base |
| 32 | `ddcutil` | no external-monitor brightness control | DDC/CI brightness + input switching | yes |
| 33 | `openrgb-udev-rules` | OpenRGB needs root | RGB control as your user | yes |
| 34 | `input-remapper` | no remapping tool | remap keys/buttons/gamepads | yes |
| 35 | `solaar-udev` | Solaar cannot manage receivers | Logitech Unifying management | yes |
| 36 | `ykpers` | generic FIDO rules only | YubiKey personalisation | yes |
| 37 | `bcache-tools` | no bcache userspace | bcache SSD caching usable | yes |
| 38 | `alsa-tools-firmware` | some pro-audio cards mute | firmware loaders present | yes |
| 39 | `oversteer-udev` | wheels need manual rules | racing wheel support | yes — in the ublue COPR after all, not just Fedora |

## C. Shell and login cosmetics

| # | Item | Fedora (without) | Bluefin (with) | Decision |
|---|---|---|---|---|
| 40 | `bling` | plain shell | aliases + shell integrations | eza+ugrep installed everywhere, **no aliases**; no integrations |
| 41 | fastfetch config | plain login | system summary, **with Bluefin logos** | no — the motd's SSH status block covers it |
| 42 | motd tips | plain login | rotating tips line | **yes, ours — shipped**: `/usr/libexec/bluespin-motd` + `/usr/share/bluespin/motd/tips.txt`, run from profile.d |

### 40. What bling actually does, and what we take

`/usr/share/ublue-os/bling/bling.sh` is **opt-in on Bluefin too** — nothing
sources it until a user runs `ujust bluefin-cli`, which appends the source
line to their `~/.bashrc`. It does five things:

1. **Aliases that shadow standard commands**: `ls`, `grep`, `egrep`, `fgrep`,
   `xzgrep`, `xzegrep`, `xzfgrep`, `cat`.
2. **Aliases that do not**: `ll`, `l.`, `l1`.
3. **Shell integrations**, evaluated at every shell start: `direnv hook`,
   `starship init`, `zoxide init`, `mise activate`, and `bash-preexec`.
4. **Atuin** setup, present but commented out upstream.
5. A `BLING_SOURCED` guard so sourcing twice does not break atuin.

bluespin installs **eza** and **ugrep** as ordinary Fedora packages on every
platform and ships **no aliases at all** — no `bling.sh`, no shell
integrations, and nothing that changes what any command name means. A
command that works in a terminal here works the same over ssh, in a
container, and in someone else's shell. Call the tools by name: `eza`, and
`ug` (or `ug -Q` for interactive query mode).

### 40a–42. Prompt, fastfetch, motd

- **Starship (40a): yes — wired.** Pinned + hashed upstream binary
  (`build_files/starship.sh`), Renovate bumps the version and the build
  prints the new hashes to paste; bash-only init
  (`files/etc/profile.d/95-bluespin-starship.sh`). A COPR build may replace
  the binary fetch later.
- **fastfetch (41): no.** It is a decorative system-info panel; everything
  useful it would show at an SSH login (image:tag, kernel, uptime, disk) is
  four lines the motd script prints itself. Not worth a package and a config.
- **motd (42): yes, ours — shipped.** One script,
  `/usr/libexec/bluespin-motd`: local shells get a short banner + one random
  tip, first shell of the session only; SSH logins always get it plus a
  compact status block (kernel, uptime, /sysroot usage). Honours
  `~/.config/no-show-user-motd` via the profile.d hook, toggled by
  `ujust toggle-user-motd`.

### 61. ujust — the RPM dropped, the library vendored

Originally three stale recipes in the `ublue-os-just` RPM were stubbed and
awk-stripped at build time. Superseded: bluespin no longer installs the RPM
at all. The pieces it keeps are vendored under `files/` (from
ublue-os/packages, Apache-2.0) and installed to **`/usr/share/bluespin/just`**
— curation instead of subtraction. Kept: `ujust`/`ugum`, the helper
libraries, bash completion (only), `00-default` (minus ublue's
`enroll-secure-boot-key`), `10-update`, `15-luks`, `20-clean` (minus the
Homebrew block), `30-distrobox` with `distrobox.ini` (minus the
zenity-dependent DaVinci installer and the `apps.ini` NVIDIA-container
recipe), and our `60-custom`. Left behind: `40-nvidia`/`50-akmods` files,
zsh/fish completions, ublue's motd hook and tips (replaced by ours). uupd
stays, from the COPR; `just` and `gum` are Fedora packages.

## D. First-boot hooks

All of these call `/usr/lib/ublue/setup-services/libsetup.sh`, run by
`ublue-system-setup.service` — **unowned files Bluefin's build drops in, not an
RPM**. Taking any of 43–46 means vendoring that runner too, so they share one
cost.

| # | Item | Fedora (without) | Bluefin (with) | Decision |
|---|---|---|---|---|
| 43 | Theming hook | — | sets the Logo-menu icon | no |
| 44 | gnupg hook | manual `gpg-agent.conf` | GPG smartcards work out of the box | **no — obsolete**: measured on F44, `gpgconf` already reports `/usr/libexec/scdaemon`; the hook was a shim for the F43 path move, and smartcards work with no config |
| 45 | Framework hooks | stock kernel args | per-CPU/BIOS kargs | Fedora — measured a no-op on the actual hardware |
| 46 | Tailscale | not installed | RPM + operator hook | **yes — shipped**: vendor repo file vendored disabled (enabled per transaction), `tailscaled` enabled, operator via explicit `ujust tailscale-operator` |
| 47 | Firefox prefs | blocklist-respecting defaults | forces past Mozilla's GPU blocklist | Fedora (drop) |
| 48 | Bazaar override | may not see our /etc-defined Flathub | reads `host-etc` | **yes** |

## E. Fedora defaults to remove

Installed on the Silverblue legs, already absent on the Bluefin base.

| # | Package | Fedora (keep) | Bluefin (remove) | Decision |
|---|---|---|---|---|
| 49 | `fedora-third-party` + `fedora-flathub-remote` | filtered Flathub can shadow ours | conflict gone | **removed**; no Fedora remote at all — Flathub is the one source |
| 50 | `fedora-workstation-repositories` | one-toggle Chrome/PyCharm repos | gone | removed |
| 51 | `fedora-bookmarks` | Fedora bookmarks in browsers | gone | removed |
| 52 | `fedora-chromium-config` | Fedora's Chromium defaults | gone | removed (+ -gnome subpackage) |
| 53 | `yelp` | app Help links open | Help links dead | keep |
| 54 | video thumbnailers | ships THREE (totem, gst, ours) | removes totem | **gst-thumbnailers only** — totem AND ffmpegthumbnailer dropped; gst decodes via ffmpeg (`gstreamer1-plugin-libav`) |
| 55 | `gnome-shell-extension-background-logo` | Fedora watermark on desktop | no watermark | removed |

## F. Packages

Package additions and removals are decisions in their own right, never a
side effect of a setting.

| # | Item | Fedora (without) | Bluefin (with) | Decision |
|---|---|---|---|---|
| 56 | `jetbrains-mono-fonts` | #1 silently inert | font applies | keep (installed everywhere) |
| 57 | `Ctrl+Shift+Esc` → Mission Center | unbound | opens Mission Center | yes |
| 58 | `it.mijorus.smile` flatpak | not installed | emoji picker installed | yes |
| 59 | Smile shortcuts | unbound | `Super+.` and `Ctrl+Alt+Space` | both |

## G. Flatpak tiers (2026-08-25)

Two tiers, decided app by app (the full per-app history is in the session
log; the files are the authority):

- **System, preinstalled on every platform**:
  [desktop.preinstall](../files/usr/share/flatpak/preinstall.d/desktop.preinstall)
  — the old bluespin/bluespin-extra/bluespin-dx preinstall split is
  dissolved. Preinstall tracks its entries, so apps that left the system
  tier are uninstalled from existing installations on the next preinstall
  run; the ones promoted into it keep their installs (tracking is per-ref).
- **Opt-in, per-user, on any platform**:
  [extra.list](../files/usr/share/bluespin/flatpaks/extra.list) (general
  desktop) and [dx.list](../files/usr/share/bluespin/flatpaks/dx.list)
  (developer GUIs), via `ujust install-flatpaks <set>` /
  `ujust remove-flatpaks <set>` — user scope on purpose: no root, and the
  OS-level set stays untouched. uupd updates both scopes. The old
  full-desktop catalog was absorbed into these two.
- Notable singles: Fractal is the preinstalled Matrix client (Element is in
  dx); Dino is preinstalled for XMPP; Planify covers the notes slot;
  Iotas and Buffer were dropped outright; Piper ships in extra **with**
  `libratbag-ratbagd` on the host (the daemon it needs — flipping 58f's
  earlier "no"); Chatty is in dx as a flatpak, with `mmsd-tng` +
  `purple-mm-sms` in the dx base and the RPM variant parked for FP5.

## Applied as defect fixes, not decisions

- `gnome-software` and `gnome-software-rpm-ostree` are removed on every image:
  uupd owns updates, and the rpm-ostree plugin made GNOME Software a second
  updater driving the same deployment.
- `os-release` identifies the image as bluespin rather than as whatever the
  base was. `ID` deliberately stays `fedora`, because dnf's copr plugin builds
  its chroot name from `$ID-$VERSION_ID`; Fedora's own convention is to
  distinguish in `VARIANT_ID`, which is what Workstation does.
- `uupd.timer` is enabled at build: the RPM ships no preset, so the one
  updater never actually ran on any earlier build.
- `ostree` and `ostree-libs` are required at **2026.4 or newer**. 2026.3, which
  the base ships, rejects static deltas it should accept
  ([ostree#3635](https://github.com/ostreedev/ostree/issues/3635)), so Flathub
  apps failed to update on every run;
  [ostree#3645](https://github.com/ostreedev/ostree/pull/3645) reverts it. The
  build asks for that version and enables `updates-testing` only while the
  ordinary repos cannot answer, so once the update is promoted it resolves from
  `updates` by itself — there is no pin to drop and no day the build has to be
  touched. The gate can be deleted whenever; by then it does nothing. The
  revert reopens
  [GHSA-7cgc-gp99-6jmm](https://github.com/ostreedev/ostree/security/advisories/GHSA-7cgc-gp99-6jmm),
  a medium-severity decompression-bomb DoS, as it does for every F44 machine
  once 2026.4 is stable.
- `distrobox` and `powerstat` are explicit packages: both used to arrive
  only as weak dependencies (uupd's and ublue-os-just's Recommends), which
  the ujust vendoring would otherwise have silently dropped.
- The Secure Boot enrolment recipe is `ujust enroll-secureboot-key` — the
  `bluespin` infix went with ublue's identically-purposed recipe, which is
  no longer shipped alongside it.
