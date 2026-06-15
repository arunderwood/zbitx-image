# Inspecting the reference image

This recipe exists to **recreate** the maintainer's hand-crafted official
zBitx v2 image. When a feature is missing or a behavior differs, the fastest
way to find ground truth is to open the reference image and read what the
maintainer actually shipped — the exact package versions, config files,
systemd units, overlays, and `config.txt` knobs — rather than guessing.

This doc is the procedure for doing that on the Windows + WSL development box.
A helper script, [`scripts/inspect-reference-image.sh`](../scripts/inspect-reference-image.sh),
automates it.

## Why WSL, and why read-only

- The image's root filesystem is **ext4**, which Windows cannot mount
  natively. The WSL2 `Debian` distro is a real Linux kernel and can
  loop-mount it. (We use `Debian`, not the default `Ubuntu`, to match the
  rest of this box's tooling — see the project memory.)
- Everything here is **strictly read-only**: the loop device is attached
  `--read-only`, and both partitions are mounted `-o ro`. The reference
  image is the artifact under test; it must never be mutated. The script
  also refuses to recover the ext4 journal (`norecovery`), so no write can
  reach the image even indirectly.

## Prerequisites

- The compressed reference image at
  `C:\Users\daniel\Downloads\zbitxv2.img.gz` (the maintainer's official
  build), downloaded from
  <https://drive.google.com/file/d/12lLTpae5ElLt63cgGeuNRREixa-01yyV/view>.
  Override the location with `ZBITX_REF_GZ=/mnt/c/...` if it moves.
- The WSL2 `Debian` distro (runs as root, passwordless sudo).
- **~30 GB of free space in the WSL filesystem.** The image is captured
  from an expanded SD card: the rootfs partition is ~29.5 GB and the
  `.gz` decompresses to a full ~30 GB raw image. The loop mount needs the
  *complete* image present — a partially-decompressed file fails to mount
  with `EXT4-fs: bad geometry ... exceeds size of device`.

## Quick start

Run the helper from the **PowerShell** tool (the Git-Bash-backed Bash tool
mangles `/mnt/c/...` paths and nested quoting when calling `wsl`):

```powershell
$s = "/mnt/c/Users/daniel/checkouts/zbitxv2-image/scripts/inspect-reference-image.sh"
wsl -d Debian -u root -- bash $s up       # decompress (first run only) + mount RO
wsl -d Debian -u root -- bash $s status   # show what's mounted
wsl -d Debian -u root -- bash $s down     # unmount + detach the loop device
```

After `up`, the partitions are readable at:

| Mount point      | Partition    | Filesystem | Holds                                  |
| ---------------- | ------------ | ---------- | -------------------------------------- |
| `/mnt/ref-boot`  | `…p1` (256M) | FAT32      | `config.txt`, `cmdline.txt`, DTBs, overlays, kernel |
| `/mnt/ref-root`  | `…p2` (~29G) | ext4       | the full root filesystem               |

The first `up` decompresses the image into `/root/zbitx-ref/zbitxv2.img`
(a few minutes — it writes ~30 GB). That file is **kept** so later `up`/`down`
cycles are instant. Delete it to reclaim disk:
`wsl -d Debian -u root -- rm /root/zbitx-ref/zbitxv2.img`.

> **The `Debian` distro self-terminates when idle and drops the mount.** A
> bare/empty listing usually means the mount vanished, not that the file is
> missing. Just re-run `up` — it is idempotent and re-attaches in seconds
> once the image is already decompressed.

## Reading it

Once mounted, inspect with ordinary tools. Bundle reads into one `wsl`
invocation so an idle-timeout can't drop the mount mid-session:

```powershell
# What OS/release did the maintainer ship?
wsl -d Debian -u root -- cat /mnt/ref-root/etc/os-release

# The boot knobs (audio, overlays, hardware enables)
wsl -d Debian -u root -- cat /mnt/ref-boot/config.txt

# Exact installed package versions, to diff against our package list
wsl -d Debian -u root -- bash -c "dpkg-query -W -f='\${Package}\t\${Version}\n' --admindir=/mnt/ref-root/var/lib/dpkg | sort"

# Which services are enabled at boot?
wsl -d Debian -u root -- ls -la /mnt/ref-root/etc/systemd/system/multi-user.target.wants

# Find a specific config / overlay / unit
wsl -d Debian -u root -- bash -c "grep -rn 'hw=' /mnt/ref-root/home /mnt/ref-root/etc 2>/dev/null"
```

The sBitx application and the maintainer's customizations live under
`/mnt/ref-root/home/` (the radio runs the app from the first user's home).

> **Note on the base OS:** the reference rootfs reports
> `Raspbian GNU/Linux 10 (buster)` — 32-bit Raspbian, the platform upstream
> zbitxv2 was developed against. This recipe deliberately rebuilds on
> arm64 Bookworm instead (see [bookworm-patches.md](bookworm-patches.md)),
> so expect package versions, paths, and some config to differ. Use the
> reference for *intent* (which knob, which service, which file), then
> translate to the Bookworm equivalent rather than copying verbatim.

## Cleanup

```powershell
wsl -d Debian -u root -- bash $s down     # unmount + detach
```

`down` leaves the decompressed `.img` in place. If you are finished with the
reference for good and want the ~30 GB back:

```powershell
wsl -d Debian -u root -- rm /root/zbitx-ref/zbitxv2.img
```
