<!-- SPDX-License-Identifier: MIT -->
# Redmi 4 Prime (markw): Arch Linux from the microSD card

Status (2026-10-26): **tools written and tested offline; no root image built
for markw yet; nothing booted on a phone.** Do M1 ([BRINGUP-M1.md](BRINGUP-M1.md))
first: this runbook assumes lk2nd and the M1 probe have already reached SSH.

The phone boots tethered: every boot is `fastboot boot lk2nd`, then `fastboot
boot` this image from lk2nd. Nothing is flashed. The eMMC stays read-only;
only the card's root partition, picked by its file system UUID, is writable.

## How it fits together

```text
tools/markw-kernel        pmOS kernel package -> KDIR (Image.gz, DTB, modules, modules tarball)
tools/build-packages      [omamobile] repository, out/repo (needs a signing key in keys/)
DEVICE=markw KERNEL_OUT=KDIR tools/build-rootfs
                          out/omamobile-rootfs-V-aarch64.img.zst (+ .sha256, .MANIFEST)
tools/build-markw-sd      owner's answers + new UUID -> markw-sd.img, root-uuid
(write markw-sd.img to the card: balenaEtcher, Rufus, or dd)
tools/build-markw-probe --root-uuid UUID
                          boot.img: initramfs switches to Arch on that partition
fastboot boot lk2nd-msm8953.img ; fastboot boot boot.img
```

In the initramfs (`device/markw/initramfs/init`): the guard sets every eMMC
node read-only, leaves the card's whole disk writable but removes its node,
and leaves only the partition carrying the UUID writable. `boot_arch` waits
up to 20 s for it, runs `e2fsck -p`, grows the file system once to the
partition (`omamobile.noresize` skips), mounts it, checks for systemd,
re-checks the guard, then `switch_root`s. Any failure leaves the initramfs
with SSH up at 172.16.42.1. `omamobile.initramfs` on the command line keeps
every disk read-only and stays there.

In Arch, `omamobile-device-markw` keeps the eMMC nodes inaccessible (matched
by card type, not `mmcblk` number), configures usb0, and gives the shell
`MONITOR_SCALE=2` (540x960 logical). `[omamobile]`'s Mesa now carries
Gallium freedreno for the Adreno 506 (pkgrel 1.5); without the GPU zap
firmware the session renders with llvmpipe, which M5 replaces.

## Offline build

```sh
# 1. Kernel (on a Linux file system: modules differ only in case)
tools/markw-kernel --out ~/android/markw/kernel

# 2. Packages and root image (Linux host with Docker and qemu-user binfmt,
#    keys/ for signing, Omarchy's keyring in /usr/share/pacman/keyrings)
tools/build-packages packages/omamobile-device-markw packages/omamobile-shell
tools/build-packages mesa          # hours under qemu; or --import a prebuilt
DEVICE=markw KERNEL_OUT=~/android/markw/kernel tools/build-rootfs

# 3. Card image (asks for the owner's user, password, host name, time zone, key)
tools/build-markw-sd --rootfs out/omamobile-rootfs-V-aarch64.img.zst \
  --out ~/android/markw/sd --card-size 29G

# 4. Boot image for that card
tools/build-markw-probe --kernel ~/android/markw/kernel/Image.gz \
  --dtb ~/android/markw/kernel/dtbs/qcom/msm8953-xiaomi-markw.dtb \
  --modules ~/android/markw/kernel/lib/modules/7.1.3-msm8953 \
  --ssh-key ~/.ssh/id_ed25519.pub --mkbootimg mkbootimg/mkbootimg.py \
  --root-uuid "$(cat ~/android/markw/sd/root-uuid)" --out ~/android/markw/boot-sd
```

Verified offline on 2026-10-26: `markw-kernel` from
`linux-postmarketos-qcom-msm8953-7.1.3-r2` (12 MB modules tarball; refuses a
case-insensitive output directory); `build-markw-sd` on a small test root
(MBR partition from 1 MiB spanning `--card-size`, new UUID, `firstboot.conf`
mode 0600 and `authorized_keys` inside, `e2fsck -fn` clean);
`build-markw-probe --root-uuid` (the initramfs carries the UUID,
`resize2fs`, `dumpe2fs`, `e2fsck`, `blkid`, `switch_root`; `init` parses in
busybox ash); `tests/markw-probe`, `tests/boot-method` and the device
package's `test/all` pass on Linux. Not yet done: a real markw root image.

## Runbook (needs the human; one step at a time)

Before step 1: M1 passed; the card holds nothing you need (it is
overwritten); `markw-sd.img` written to it and its checksum noted.

### 1. Card in the laptop: check what was written (read-only)

- **Expect:** one partition, ext4, label `omamobile-root`, the UUID in
  `root-uuid`.
- **Stop:** a different UUID or label. **Risk:** none.

### 2. Card in the phone, RAM-boot lk2nd, then the SD image (affects the screen)

```sh
fastboot boot ~/android/markw/lk2nd-msm8953.img
fastboot boot ~/android/markw/boot-sd/boot.img
```

- **Expect:** USB networking as in M1, then within about a minute
  `omamobile-markw: arch: switching to Arch Linux on /dev/mmcblkNpM` in the
  kernel log, and SSH at 172.16.42.1 answered by Arch's sshd.
- **Stop:** the initramfs reports `no microSD partition`, `cannot mount`,
  `no systemd` or `writable outside the allowlist`; read it over SSH
  (`dmesg | grep omamobile`) before anything else.
- **Rollback:** hold Power (or Volume Down + Power for fastboot); the eMMC
  was never writable. Re-image the card if its file system is damaged.
- **Risk:** low.

### 3. In Arch, read-only checks

```sh
findmnt /                                   # the card partition, rw
for s in /sys/class/block/mmcblk*; do echo "${s##*/} $(cat $s/ro) $(cat $s/device/type 2>/dev/null)"; done
ls -l /dev/mmcblk*                          # eMMC nodes mode 0000
systemctl --failed
journalctl -b -p err | head -50
```

- **Pass:** every eMMC (type `MMC`) node `ro=1`; only the card partition
  writable; first boot ran (`omamobile-firstboot`); the owner can log in.
- **Stop:** any eMMC node `ro=0`.

### 4. Display and touch, read-only (M4 groundwork)

The DTB names the panel `xiaomi,markw-panel` and leaves every touchscreen
node (FT5336 @0x38, maXTouch @0x4a, Goodix @0x5d, Synaptics @0x20)
disabled. lk2nd is expected to rewrite the panel compatible to the panel it
detects (this unit: `mdss,nt35596_ebbg`, driver `panel-mdss-nt35596-ebbg`)
and enable the matching touch node. Check that it did, on this boot path:

```sh
p=/proc/device-tree/soc@0/display-subsystem@1a00000/dsi@1a94000/panel@0
tr '\0' '\n' < $p/compatible
for t in /proc/device-tree/soc@0/i2c@78b7000/touchscreen@*; do
  echo "${t##*/} $(tr '\0' ' ' < $t/compatible) $(tr -d '\0' < $t/status)"; done
lsmod | grep -E 'msm|panel|edt|mxt|goodix|rmi'
ls /sys/class/drm /sys/class/backlight
dmesg | grep -iE 'msm|dsi|panel|mdp|edt|mxt|wled|zap|a5xx|firmware' | head -40
```

- **Pass:** the panel compatible is no longer `xiaomi,markw-panel`; one touch
  node is `okay`; `card0-DSI-1` and a backlight exist.
- **If the panel compatible is unchanged:** lk2nd did not patch the DT on
  this path; record it. M4 then supplies the panel and touch choice itself.
- A missing zap shader only keeps the GPU off (llvmpipe); KMS should not
  depend on it. Record the `msm` messages either way.

### 5. The session (affects the screen)

SDDM autologin starts Omarchy's Hyprland session at scale 2. Expect it to be
slow (llvmpipe) until the GPU milestone. Record what works: panel, touch
(FT5x06 or maXTouch variant), on-screen keyboard, power key.

Record every result, sanitized, in `PROGRESS.md` and `NOTES.md` with the
date and `uname -r`.

## Known gaps

- Booting is tethered to a laptop: lk2nd is never flashed (M9 decides that).
- No Wi-Fi/Bluetooth, GPU acceleration, audio or charging control yet:
  they need the phone's own firmware (WCNSS, zap shader) extracted
  privately, each with its own runbook.
- `tools/build-packages` and `tools/build-rootfs` need a Linux host; on
  Windows that means WSL with Docker Desktop's WSL integration. Its qemu
  binfmt node is named `aarch64` (accepted by `tools/lib/alarm.sh`);
  `ALARM_MIRROR` puts a nearer mirror first. Ubuntu 22.04's Python 3.10
  lacks `tomllib`, so `omamobile-shell`'s call-watch test fails natively
  there, and its key-debounce test fails under qemu.
- `omamobile-shell` depends on `omamobile-apps`, hence on `omacam` (Rust:
  about 40 minutes under qemu on a 16-thread laptop); it can't be left out.
