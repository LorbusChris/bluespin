# Memory pressure: swap, a box for VS Code, and the OOM killers

What bluespin does when a session outgrows RAM, and why. Implemented in
[build_files/build.sh](../build_files/build.sh) (every platform) and
[build_files/dx.sh](../build_files/dx.sh) (the VS Code box); the
per-machine swap file is `ujust setup-swapfile`
([60-custom.just](../files/usr/share/bluespin/just/60-custom.just)).

## The incident

A 64 GB bluespin-dx workstation, October 2026, running VS Code with a large
C/C++ workspace, several agent sessions and builds in the integrated
terminal:

- systemd recorded the VS Code cgroup peaking at 46-54 GB, plus 4-7 GB of
  swap, in nearly every session for a week.
- Fedora's swap is one 8 GB zram device and nothing else. Once it was full
  the kernel had only the file cache left to evict -- the binaries of the
  desktop itself -- and the machine thrashed: input lag of seconds,
  gnome-shell marked unresponsive, two power-key presses ignored, a hard
  power-off.
- The kernel OOM killer never fired: it acts when an allocation fails, and
  the swap made sure one never quite did. systemd-oomd fired twice in a
  month, each time killing all of VS Code, and not at all in the worst
  incident: its trigger is app.slice spending 80% of a ten-second window
  with every task stalled, for 20 s running.

## What Fedora, Bluefin and Bazzite do

Checked on 2026-10-18 against the installed Fedora 44 packages and the
`ublue-os/bluefin` and `ublue-os/bazzite` trees.

| | Fedora | Bluefin | Bazzite | bluespin |
| --- | --- | --- | --- | --- |
| zram size | `min(ram, 8192)`: all of RAM up to 8 GB, a flat 8 GB above ([F34 change](https://fedoraproject.org/wiki/Changes/Scale_ZRAM_to_full_memory_size), aimed at installing on small machines; the cap is not explained) | Fedora's | desktop images: `min(ram / 2, 16384)` | `min(max(ram / 2, min(ram, 8192)), 16384)`: Fedora's curve up to 16 GB of RAM, half of RAM above, capped at 16 GB -- 4/8/8/16/16 GB for 4/8/16/32/64 GB machines |
| zram compression | lzo-rle (kernel default) | Fedora's | zstd | zstd: markedly better on heap-shaped memory (the lzo-rle ratio measured on this workload was 2.5:1) for CPU a desktop has to spare |
| `vm.page-cluster` | 3 (8-page swap read-ahead) | Fedora's | Deck image 0, desktop images 3 | 0: read-ahead buys nothing on zram and little on NVMe, and evicts what is still needed |
| `vm.swappiness` | 60 | Fedora's | Deck image 180 (with watermark and dirty-bytes tweaks), desktop images 60 | 100: idle heaps go to zram before the file cache that keeps the desktop responsive; not 180 because the evidence for it is anecdotal and a disk file sits behind zram here |
| disk swap | none since F33 | none | none | on request: `ujust setup-swapfile [SIZE]` (default 32G) |
| systemd-oomd | per-slice pressure kill at 80% for 20 s, [raised from 50% in 2023](https://pagure.io/fedora-workstation/issue/358); swap-based kill removed in F37 | Fedora's | Fedora's | Fedora's (see below) |
| per-app memory limits | none | none | none | VS Code boxed on dx (see below) |

## 1. Swap sized for the machine

Files: [zram-generator.conf](../files/etc/systemd/zram-generator.conf),
[60-bluespin-swap.conf](../files/usr/lib/sysctl.d/60-bluespin-swap.conf),
[var-swap-swapfile.swap](../files/usr/lib/systemd/system/var-swap-swapfile.swap).

The zram file is the main file in `/etc` rather than a `/usr/lib` drop-in
because the phone's device layer ships its own main file (`ram * 2`) over
it; a drop-in would override that one too. The phone keeps its zram and
gets the sysctls.

`ujust setup-swapfile` creates `/var/swap/swapfile` in its own btrfs
subvolume (a swap file pins its extents, so the subvolume holding it can
never be snapshotted, and that restriction should not land on `/var`
itself). The swap unit ships enabled on every platform at priority 10
behind zram's 100, gated on `ConditionPathExists`, so it is inert until
the file exists and the image carries no per-machine state. No SELinux
relabelling: systemd activates swap through `swapon`, which transitions to
`fsadm_t`, a domain the policy leaves unconfined for files.

Swap alone only moves the wall. What keeps the desktop usable is the next
layer.

## 2. VS Code in a memory box (bluespin-dx)

Electron moves VS Code's main process into a systemd scope of its own,
`app-com.microsoft.VSCode-<pid>.scope`, and everything it spawns afterwards
lands there: extension hosts, language servers and indexers, agent
sessions, integrated terminals and whatever runs in them. gnome-shell's
launch scope, `app-gnome-com.microsoft.VSCode-<pid>.scope`, keeps the
Chromium plumbing: zygotes, the GPU process, one renderer per window.

systemd applies drop-ins to such transient scopes by dash-truncated name,
so two directories under `/usr/lib/systemd/user/` box them, in percent of
physical RAM:

| Scope | `MemoryMax` | `MemorySwapMax` | At the wall |
| --- | --- | --- | --- |
| `app-com.microsoft.VSCode-*` | 75% | 10% | the kernel reclaims the scope's own pages into swap and, once the allowance is spent, kills the single largest process inside -- an indexer, one agent session -- and VS Code lives on |
| `app-gnome-com.microsoft.VSCode-*` | 25% | 5% | a runaway renderer dies alone; VS Code offers to reload that window |

Both set `OOMPolicy=continue`. Without it the user manager's default,
`stop`, answers the kernel's one kill by terminating the whole scope: all
of VS Code and every session in it. Tested on the workstation: a hog in a
200 MB scope took a sibling `sleep` down with it under `stop`, and left it
running under `continue`.

There is deliberately no `MemoryHigh`. The cgroup documentation describes
its throttling as something for an external monitor to act on, and the
monitor on a Fedora desktop is systemd-oomd, whose action is to kill the
whole cgroup: a soft limit that keeps VS Code stalled for minutes would
invite exactly what the box exists to prevent. `memory.max` already
reclaims before it kills, and the swap allowance bounds how long that
reclaim can thrash inside the box.

A running VS Code picks the box up on `systemctl --user daemon-reload`;
`systemctl --user show 'app-com.microsoft.VSCode-*.scope' -p MemoryMax`
shows it. The percentages are deliberate: 75% of 64 GB leaves 16 GB for
the shell, the browser and containers; 75% of 16 GB leaves 4. Toolbox and
podman containers are not inside the box (libpod scopes under `user.slice`)
and neither is Firefox; both are candidates for the same treatment if they
turn out to need it. dx.sh asserts the desktop file id the directories are
named after, because the scope names follow it and VS Code renamed it from
`code.desktop` in its autumn 2026 releases.

Files:
[app-com.microsoft.VSCode-.scope.d](../files/usr/lib/systemd/user/app-com.microsoft.VSCode-.scope.d/90-bluespin-memory-cap.conf),
[app-gnome-com.microsoft.VSCode-.scope.d](../files/usr/lib/systemd/user/app-gnome-com.microsoft.VSCode-.scope.d/90-bluespin-memory-cap.conf).

## 3. systemd-oomd: kept at Fedora's 80%

Fedora's per-slice default lets oomd kill the worst app cgroup once
`app.slice` reports more than 80% *full* memory-stall pressure for 20 s.
Fedora raised that from 50% in 2023 after the lower value killed Evolution,
Firefox and whole sessions on an 8 GB machine during ordinary compiles, and
it removed the swap-based kill in F37 because Fedora's swap is small. The
workstation's freeze shows 80% can go unreached in a thrash -- but nothing
measured says 60% would have fired either, and a lower limit makes oomd
likelier to answer a confined thrash inside the VS Code box by killing all
of VS Code. The box and the swap are the measured fixes; the limit stays
where Fedora put it. A machine that wants it lower can drop
`ManagedOOMMemoryPressureLimit=60%` under `[Slice]` into
`/etc/systemd/user/app.slice.d/*.conf`; `oomctl` shows the limit in effect.

## Overriding on a machine

All of it is drop-ins and defaults, so the usual rules apply: a file of the
same name under `/etc/systemd/user/<dir>/` replaces the shipped drop-in,
`/etc/systemd/zram-generator.conf` is yours to edit (bootc keeps local edits
across updates), and a higher-numbered `/etc/sysctl.d/*.conf` wins over
`60-bluespin-swap.conf`.
