# markw M9: persistent-install design

**Status (2026-11-17):** design only. **No persistent write happens in this
milestone** ([ENGINEERING-PLAN](ENGINEERING-PLAN.md) §9.4, §21 M9). The phone
still boots RAM-only (`BOOT_METHOD=ram-only`, lk2nd and the probe both loaded
by `fastboot boot`), and every eMMC partition stays `ro=1`. This document
gives the M9 deliverables: the exact writable-partition allowlist, the boot
chain, the way back to MIUI, the kernel-update transaction and rollback, and
the installer's threat model and negative tests. It also gives a gated
runbook, whose write steps belong to M10 and need the owner's go.

Evidence tags as in [BRINGUP-M1](BRINGUP-M1.md): **[V]** verified on this
phone or in pinned source, **[A]** assumption still to check.

## 1. Gate

Nothing in §6 past step P2 runs until all of these hold:

| Prerequisite | State (2026-11-19) |
| --- | --- |
| Port at least 90 % (owner's gate) | about 89 % (2026-11-19; was 86 %) |
| M3-M8 evidence | display, GPU, touch, Wi-Fi, BT, audio, mobile data, charger (R2 passed 2026-11-17), sensors in the BRINGUP docs. The overnight data-on sleep (AA) passed 2026-11-19 with modemmanager 1.24.2-2.3: 11 h 50 min, vmin 97 %, about 12 mA, no crash (BRINGUP-SUSPEND CE). Auto-suspend is enabled at boot from device-markw 0.1.28 (installed 2026-11-19; not booted with it yet). Cold boots: 4 of 4 passed 2026-11-19 (the owner cut the plan's ten to four, next to ten warm reboots passed 2026-11-18; BRINGUP-KERNEL), with auto-suspend active at every boot |
| Approved amendment to the non-A/B safety policy (§2) | not yet: needs the owner's explicit approval of §2 |
| Restore rehearsal (§6 P1, then P7) | P1 (no write) passed 2026-11-17; P7 after the install |
| No open critical risk | a hang in a long sleep: closed 2026-11-19. A 19 h auto-suspend (2026-11-18) and an 11 h 50 min one on the fixed stack (device-markw 0.1.27, modemmanager 1.24.2-2.3) both woke cleanly on Power |

## 2. Writable-partition allowlist (policy amendment)

The repository rule is "never an unsuffixed flash". markw has no A/B slots,
so a persistent install cannot follow it. The proposed amendment for this
device only:

| Partition | eMMC index | Size | Who writes it | When |
| --- | --- | --- | --- | --- |
| `boot` | p21 | 64 MiB | stock fastboot, once (lk2nd); lk2nd's fastboot afterwards (Linux image after lk2nd) | install, kernel update, restore |
| `userdata` | p49 | 25083.5 MiB | the RAM-booted installer (`mkfs.ext4`, rootfs copy); the installed OS at run time | install; always mounted read-write afterwards |

**Nothing else, ever.** The 47 other partitions stay `ro=1` from the
initramfs on, Linux mounts none of them, and no tool takes a partition name
from its arguments. In particular these are never written: `aboot`,
`abootbak`, `sbl1*`, `rpm*`, `tz*`, `devcfg*`, `cmnlib*`, `keymaster*`,
`lksecapp*` (boot chain: a bad write needs EDL), `modem`, `modemst1`,
`modemst2`, `fsg`, `fsc`, `sec`, `persist` (radio calibration and IMEI: the
off-repo backup in `~/android/reference/markw/modem-backup/` is the only
copy), `devinfo` (unlock state), `recovery`, `system`, `cust`, `cache`,
`splash`, `dsp`, `mdtp`, `oem`.

`recovery`, `system`, `cust` and `cache` stay MIUI's, so the restore in §4
needs only `boot` and a reformat of `userdata`. `cache` (256 MiB) was
considered as an ext2 `/boot` for lk2nd's extlinux loader and rejected for
now: it widens the allowlist by one partition for a convenience (boot
entries) that the laptop-driven update in §5 already gives.

The owner means to move to Omarchy for good and does not need MIUI's data
(2026-11-17): MIUI stays only as a known-good system to fall back to (its
modem stack, and a phone that boots without lk2nd), so §4 keeps the image
and the rehearsal but not the data. The owner gives up MIUI's user data (agreed: OS on eMMC `userdata`, the
microSD as extra storage). MIUI's apps and files on the phone are lost at P4
unless the owner copies them off first.

## 3. Boot chain once installed

```text
Xiaomi aboot (stock, unlocked; never written)
  -> boot p21, offset 0: lk2nd 23.1 (368 KiB)                  [written once]
  -> boot p21, offset 512 KiB: Linux Android boot image          [kernel updates]
       kernel + markw.dtb + initramfs (device/markw/initramfs/init)
  -> initramfs: storage guard, then root = ext4 on userdata by UUID
  -> switch_root to Arch Linux ARM; modules from /usr/lib/modules on userdata
```

Read in the pinned source (tag `23.1`, tag object `24d3f25`, commit
`e9c8b217`; checkout outside the repository):

- **[V, source] lk2nd keeps itself and boots the image after it.**
  `lk2nd/project/lk2nd.mk` sets `LK2ND_PARTITION_BASE=boot`,
  `LK2ND_PARTITION_SIZE=512*1024`, and `lk2nd/device/2nd/partition.c`
  splits `boot` in lk2nd's own partition table into a virtual `lk2nd` (the
  first 512 KiB) and a `boot` that starts at 512 KiB. So lk2nd's `fastboot
  flash boot` writes from 512 KiB on, and its Android boot reads from there.
  This holds for a RAM-booted lk2nd too (the split happens at init, whatever
  loaded it), which gives the rollback in §5 a fixed path. The image limit
  is 64 MiB minus 512 KiB (oma19's is 15.6 MiB). lk2nd 23.1 is 368 KiB.
- **[V, source] Boot order: extlinux first, on any disk.** Unless a key or
  reboot reason asks for fastboot or recovery, `lk2nd_boot()`
  (`lk2nd/boot/boot.c`) tries every leaf partition of at least 16 MiB on
  every block device, the microSD included, mounts it with LK's ext2 driver
  and boots `/extlinux/extlinux.conf` if it finds one; only then does it
  fall back to the Android image at 512 KiB. Two consequences:
  - a card or partition with `/extlinux/extlinux.conf` takes the boot ahead
    of the installed image. That is a recovery route (a prepared microSD
    boots without a laptop) and a threat (§7): neither the eMMC root nor the
    microSD root may carry an `/extlinux/` directory;
  - LK's ext2 driver logs the superblock's incompatible features but does
    not refuse them (`lib/fs/ext2/ext2.c`), so it will try to read the ext4
    `userdata` root (and today's ext4 microSD root) with extents it does not
    understand. It should simply find no config, but that is untested
    (open question 1).
- **[V, source] Keys and reboot reasons, in lk2nd** (`app/aboot/aboot.c`,
  as in Qualcomm's aboot): Volume Down gives fastboot, Volume Up gives
  recovery (it skips `lk2nd_boot()` and boots the `recovery` partition,
  which stays MIUI's recovery), both together reboot to the emergency
  download mode. A `bootloader` reboot reason gives fastboot, and an lk2nd
  panic reboots in fastboot mode (`PANIC_REBOOT_MODE=FASTBOOT_MODE`).
- **[A] Stock aboot reads the same keys first.** Volume Down + Power from
  off lands in *stock* fastboot, before lk2nd runs. Whether a key pressed
  later (after the stock splash) reaches lk2nd's menu is checked after P3.
  It is not needed for recovery: from stock fastboot, `fastboot boot
  lk2nd-msm8953.img` always gives a RAM-loaded lk2nd with the same split,
  and that is the path §5 relies on.
- **[V] Recovery buttons.** Volume Down + Power reaches stock fastboot
  ([BRINGUP-M1](BRINGUP-M1.md) §1) whatever `boot` holds, because aboot is
  never written. That is the floor every failure in §5 lands on.
- **Initramfs (written 2026-11-17, `tests/markw-probe`).** The descriptor
  stays `ram-only` until the gate opens; the eMMC root is a build option,
  `tools/build-markw-probe --root-uuid UUID --root-on emmc`, which packs
  `/etc/omamobile-emmc-root` instead of `/etc/omamobile-sd-root` (both
  packed: neither is used, every disk stays read-only). The build records
  `root-on` beside the image, and `tools/markw-install` takes only an
  `emmc` image. In this mode `init`'s guard allows:
  - the eMMC (type MMC) partition whose `PARTNAME` is `userdata` **and**
    whose file system carries the packed UUID: found by name and type, never
    by `mmcblkN` (the eMMC was mmcblk1 at P0 and mmcblk0 after P1);
  - that partition's whole disk, because the kernel refuses writes to a
    partition of a read-only disk. Its node is removed, as the Pixel guard
    does for `/dev/sda`, and in Arch `10-omamobile-storage.rules` (already
    in device-markw) gives every eMMC node mode 0000 and hides it from
    udisks. Root on the phone could still `mknod` the disk; no tool does.
    This is the one deviation from "never allow a whole disk"
    (ENGINEERING-PLAN §10), and the same one the Pixel path makes;
  - the microSD card whole, as storage (its node kept).

  Every other eMMC partition, `boot0` and `boot1` (whole disks of type MMC
  with no partitions) get `blockdev --setro` as today; a card partition
  named `userdata` with the UUID is storage, never the root; a `userdata`
  with another UUID leaves the whole eMMC read-only and boots nothing. The
  microSD-root mode is unchanged.
- **Boot-loop guard (open question 4, decided).** In the eMMC mode the
  initramfs counts a try in `/var/lib/omamobile/boot-tries` on the root
  before each switch and drops a runtime unit into `/run/systemd/system`
  (as it does for the 60 min deadman) that removes the count once
  `graphical.target` is reached. At three uncleared tries it stays in the
  initramfs with SSH up; with no USB host its keeper reboots to the
  bootloader after 90 s, where stock fastboot waits. A count that isn't a
  number counts as three.

## 4. The way back to MIUI

### 4.1 What must exist before any write

A read-only backup set, taken from the RAM-booted Linux (the eMMC is `ro=1`
there) into `~/android/reference/markw/install-backup/<UTC>/`, never into the
repository:

- `boot.img` (p21, the original MIUI boot image, 64 MiB raw),
- `recovery.img` (p22), `aboot.img`, `abootbak.img`, `devinfo.img`,
  `splash.img` (reference only: never restored by a script),
- the GPT (first 34 and last 33 sectors of the eMMC) and the
  `/sys/class/block/*/uevent` listing,
- `SHA256SUMS` computed on the phone and again on the laptop; the set counts
  only when both match.

The NV set (`modemst1`, `modemst2`, `fsg`, `fsc`, `sec`, `persist`) already
exists and is refreshed after every MIUI boot (the rule in AGENTS.md).

### 4.2 Restore (rehearsed at P7)

1. Volume Down + Power: stock fastboot. `fastboot getvar product` must say
   `markw`.
2. `fastboot flash boot install-backup/<UTC>/boot.img` (lk2nd and Linux are
   gone in one write).
3. `fastboot erase userdata` (or `fastboot format userdata`): MIUI cannot
   read an ext4 Linux root and would loop; an empty `userdata` makes it set
   up a fresh one.
4. `fastboot reboot`: MIUI's first-boot setup.
5. Afterwards: a fresh NV backup (MIUI's modem stack has run).

Expected: MIUI boots as on 2026-11-15. `system`, `recovery` and the firmware
were never written, so they need nothing.

**Last resort, not scripted:** Xiaomi's fastboot ROM for markw. Its flash
scripts write many partitions; read the script before use, and never run a
variant that writes `persist`, `modemst*` or `fsg` without comparing against
the NV backup first.

## 5. Kernel update and rollback

**Phase 1 (the first install): updates only from the laptop, through
lk2nd's fastboot.** The installed Linux never gets `boot` writable: its
guard allows `userdata` alone, so a bug or a bad command on the phone
cannot touch the boot chain.

The transaction (`tools/markw-install trial IMG`, then `commit IMG`; steps 2 and 6 by hand for now):

1. Build the new image with `tools/build-markw-probe --root-uuid <userdata
   UUID> --root-on emmc`; it records its SHA-256, kernel release and root.
2. Push the new modules to `/usr/lib/modules/<release>` on the running
   phone, next to the current release's (as `bin/omamobile push` does); the
   old release's modules stay.
3. **Trial boot in RAM:** reboot to lk2nd's fastboot, `fastboot boot
   new.img`. Nothing is written yet.
4. **Commit only after success:** the trial boot must reach
   `omamobile-boot-success` (USB network, SSH, session) and pass
   `tools/phone-smoke`. Then, from lk2nd's fastboot: `fastboot flash boot
   new.img`, which lk2nd writes after itself.
5. **Verify:** boot the flashed image (cold), then read p21 from 512 KiB on
   for the image's length read-only and compare SHA-256 with step 1.
6. Keep the previous image and its checksum on the laptop and in
   `/var/lib/omamobile/boot/previous.img` on `userdata`; delete the
   release before that one, and its modules.

**Rollback:**

| Failure | What the owner sees | Way back |
| --- | --- | --- |
| trial boot (step 3) fails | a hang, or a reboot into the current image | nothing was written: Power hold; lk2nd boots the current image |
| flashed image fails | lk2nd starts, Linux doesn't | Volume Down + Power (stock fastboot), `fastboot boot lk2nd-msm8953.img` (RAM), then `fastboot flash boot previous.img`, which the RAM lk2nd writes from 512 KiB |
| write interrupted at step 4 | lk2nd intact, image damaged | same as above |
| lk2nd itself damaged | no lk2nd menu | Volume Down + Power (stock fastboot), `fastboot flash boot lk2nd.img`, then the image |
| `userdata` root damaged | initramfs stops at root | RAM-boot the probe with the microSD root (today's path), `fsck`/restore from the laptop |

**Phase 2 (later, separately reviewed):** an on-phone update that makes
`boot` writable from Linux for one transaction only. Not part of this
design.

## 6. Gated runbook

Read-only first. P0-P2 fit M9; P3-P7 are M10 and need the §1 gate and the
owner's explicit go for each step.

### P0. Read-only backup (§4.1)

- **Run:** RAM-booted probe as today; on the phone, `dd` of each listed
  partition by `PARTNAME` to `/dev/stdout`, streamed over SSH to the laptop;
  checksums on both sides.
- **Expect:** sizes match §2 (boot 64 MiB, recovery 64 MiB, aboot 1 MiB);
  both sums agree.
- **Stop:** any `dd` error, a size mismatch, a partition that resolves to a
  different index than in this document.
- **Rollback:** none needed (reads only). **Risk:** low.

**Result (2026-11-17, `7.1.3-msm8953-oma19`): passed.** Set
`install-backup/20261117T003912Z` (off-repo): `boot` 64 MiB, `recovery` 64
MiB, `aboot`, `abootbak`, `devinfo` 1 MiB each, `splash` 20 MiB, both GPT
copies (`EFI PART` signature) and the 49-row partition listing. Phone and
laptop SHA-256 files agree on all eight. `boot.img` is MIUI's own (Android
header v0, page 2048, a 20.1 MB kernel, Qualcomm `androidboot.*` cmdline,
no lk2nd string), `aboot` and `abootbak` are identical, and all 49 eMMC
partitions still read `ro=1` afterwards. Over Git Bash the shared SSH
connection (`OMAMOBILE_SSH_SHARE=1`) fails to pass its descriptors and
every stream comes back empty: run P0 with a connection per stream.

### P1. No-write rehearsal of the way back

- **Run:** Volume Down + Power; `fastboot boot install-backup/<UTC>/boot.img`
  (the original MIUI boot image, in RAM only).
- **Expect:** MIUI boots normally. Then a fresh NV backup (MIUI ran).
- **Also (open question 1):** from stock fastboot, `fastboot boot
  lk2nd-msm8953.img`, then `fastboot continue`: lk2nd's autoboot scans the
  ext4 microSD root and the eMMC partitions (reads only: `lib/fs/ext2/ext2.c`
  has no write code), finds no extlinux and no image at
  512 KiB, and should return to its fastboot. `fastboot oem log` and
  `fastboot get_staged` keep its log. **Stop:** no fastboot answer within
  60 s (Power hold, MIUI boots).
- **Stop:** MIUI does not boot from the backup image: the backup is not good,
  and no write may happen.
- **Rollback:** power hold; MIUI boots from flash anyway. **Risk:** low.

**Result (2026-11-17): passed.** No write anywhere; the eMMC read `ro=1`
on all 49 partitions after the return to Linux.

- Stock fastboot reached from Linux with `tools/markw-debug fastboot`
  (`product: markw`, no `lk2nd` partition: the stock bootloader).
- lk2nd 23.1 (SHA-256 checked) RAM-booted; on the phone it reports
  `partition-size:lk2nd` 0x80000 and `partition-size:boot` 0x3f80000:
  **[V, phone]** the 512 KiB split of §3.
- `fastboot continue`: the USB link went away and did not come back, and
  the screen stayed on lk2nd with its menu answering the volume keys, so
  the autoboot scan of the ext4 microSD root and the eMMC partitions did
  not hang (open question 1). In the source, `cmd_continue()` stops
  fastboot before `lk2nd_boot()`, and when no image is found the
  `continue` path does not restart it, so a failed `continue` always looks
  like this; its log is lost with the USB. The menu's **Bootloader** entry
  took the phone to stock fastboot.
- `fastboot boot install-backup/20261117T003912Z/boot.img` (SHA-256
  matching both sums files): MIUI booted to `sys.boot_completed=1`
  (MIUI V10.2.2.0, its 3.18 kernel). **The way back works with this
  image.**
- Back to oma19 with `DEBUGING_RUN.sh --probe out/markw/probe-oma19/boot.img`.
  NV backup `20261117T030058Z-after-miui`, all six sums matching on both
  sides: `modemst1`, `modemst2`, `fsg`, `fsc` and `sec` identical to the
  2026-11-15 set, `persist` changed (MIUI writes it at boot).
- The eMMC was `mmcblk1` at P0 and `mmcblk0` after this boot: the
  renumbering in §7 happens between consecutive boots.

### P2. Installer, offline

- **Run:** `tools/markw-install` with its tests (§7) in WSL; `--dry-run`
  against a fake fastboot and a fake phone.
- **Expect:** every negative test refuses, dry run prints the exact
  commands and writes nothing.
- **Stop:** any test fails. **Risk:** none (no phone).

**Result (2026-11-17): passed.** `tools/markw-install` (check, lk2nd,
trial, commit, verify, restore) and `tests/markw-install`, 42 tests in WSL
against a fake fastboot, a fake phone over SSH (a fake sysfs and `/dev`)
and synthetic backups. Every refusal of §7 refuses before any write: the
`ram-only` descriptor (all writes; `--dry-run` only prints), a wrong or
empty product, two phones or none, an lk2nd with another split, a changed
lk2nd, an unknown or low battery, a missing or changed MIUI `boot.img`,
sums that disagree, a backed-up `boot.img` holding lk2nd, a changed NV
set, a wrong typed codename, `commit` with no passed `trial` (or a trial of
another image, or one that booted another kernel or an Oops), an image
changed after its build or too big for `boot` after lk2nd, `restore`
through lk2nd (which would write MIUI's image at 512 KiB), and `verify`
against a `boot` partition on the microSD. The tool holds exactly two
fastboot writes, `flash boot` and `erase userdata`, both with constant
names. P4 (format `userdata`) and P5 (root copy) are not in the tool yet:
they need the initramfs's `EMMC_RW` first, and refuse by not existing.

### P3. lk2nd into `boot` (M10, write)

- **Run:** stock fastboot, `fastboot flash boot lk2nd-msm8953.img` (pinned
  SHA-256), `fastboot reboot`.
- **Expect:** lk2nd's menu (no Linux image yet).
- **Stop:** no lk2nd within 30 s. **Rollback:** §4.2 steps 1-2.
  **Risk:** medium.

### P4. Format `userdata` (M10, write, MIUI data lost)

- **Run:** stock fastboot, `tools/markw-install format` (`fastboot
  format:ext4 userdata`); then RAM-boot today's microSD probe and
  `tools/markw-install uuid`, which reads the new file system's UUID
  read-only (by `PARTNAME` and type) into `logs/markw-install/userdata-uuid`.
- **Then:** build the eMMC image, `tools/build-markw-probe … --root-uuid
  <that UUID> --root-on emmc`.
- **[A]** Stock aboot supports `format` (it answers `partition-type` and
  `partition-size`); if it doesn't, lk2nd's fastboot (the same Qualcomm
  code) does, and `userdata` is not split by lk2nd.
- **Stop:** any check fails. **Rollback:** §4.2 step 3. **Risk:** medium.

### P5. Root filesystem copy (M10)

- **Run:** from lk2nd's fastboot, `fastboot boot` the eMMC image: with an
  empty `userdata` its initramfs finds no systemd and stays, SSH up, with
  `userdata` writable. Then `tools/markw-install copy`: on the phone it
  mounts the microSD root read-only (the card's ext4 partition with
  systemd), refuses an `/extlinux` there (§3), refuses a `userdata` that is
  not empty or would be more than 90 % full, runs `rsync -aHAX
  --numeric-ids` and a second dry pass that must find nothing. The root has
  no `fstab` entries (the initramfs mounts it), so nothing in it names the
  card.
- **Size:** the microSD root holds 19 GB on 2026-11-17, 9.5 GB of it the
  owner's Arduino and PlatformIO toolchains; `userdata` is 24.5 GiB, so about
  5 GiB stay free. Moving those toolchains to the card before P5 is the
  owner's call.
- **Expect:** `copy done`; then `tools/markw-install trial IMG` reaches
  systemd as PID 1 (an initramfs answering with the same kernel release
  fails the trial).
- **Rollback:** format again (P4). **Risk:** low.

### P6. Linux image into `boot` (M10, write)

- **Run:** the §5 transaction steps 3-5 with the image built for the new UUID.
- **Expect:** cold boot to Omarchy from eMMC with no laptop; `phone-smoke`
  passes; all eMMC partitions but `userdata` still `ro=1`.
- **Rollback:** §5 table. **Risk:** medium.

### P7. Restore rehearsal (M10, write)

- **Run:** §4.2 in full, MIUI boots, then reinstall (P3-P6).
- **Expect:** MIUI first-boot setup; NV checksums unchanged against the
  pre-install set, apart from what MIUI's modem stack writes (refresh the
  backup).
- **Risk:** medium. Only after P7 passes is the install declared done.

## 7. Installer threat model and negative tests

| Threat | Guard | Negative test (must refuse) |
| --- | --- | --- |
| Wrong phone | `fastboot getvar product` = `markw` and the descriptor's `CODENAME`; the owner types the codename | product `flame`, empty product, two devices attached |
| Wrong partition | partition names are constants in the tool (`boot`, `userdata`); no argument or variable names one | an env var or argument naming `aboot`, `modem`, `persist`; a patched constant (test greps the tool for other `fastboot flash` targets) |
| Stock vs lk2nd fastboot confusion | kernel updates require lk2nd's fastboot (its own `getvar` variables); the lk2nd write requires stock fastboot | `update` against stock fastboot; `install-lk2nd` against lk2nd |
| `mmcblkN` renumbering (seen: oma18 vs oma19) | resolve by `PARTNAME` and size, never by index | `userdata` at an unexpected size; `PARTNAME` missing; the microSD offered as `userdata` |
| Unverified or oversized image | SHA-256 against the build record; size under 64 MiB minus 512 KiB | a changed byte; an image over the limit |
| No way back | refuse unless the §4.1 set exists and both checksum files agree | missing `boot.img`; mismatched sums |
| Low battery or power loss mid-write | refuse under 50 %, cable required for P3-P6 | battery 40 %; no charger |
| Mounted or busy target | refuse if `userdata` is mounted or in use | a mounted fake target |
| A silent partial run | `set -euo pipefail`, every step logs to `logs/`, a write step re-reads and verifies | a fake fastboot that fails half way: tool stops, nothing after it runs |
| A stray `/extlinux/extlinux.conf` (a microSD, or the root itself) takes the boot ahead of the installed image (§3) | the rootfs build and the installer refuse a root with `/extlinux/`; the installed image is the only boot entry | a root image with `/extlinux/extlinux.conf`; a second card offered as the install source |
| A write through lk2nd's fastboot to a partition other than `boot` (lk2nd's fastboot writes any partition, as Qualcomm's aboot does) | the tool's only lk2nd write is `fastboot flash boot`; no raw `fastboot` passthrough | the grep test above also covers the update path |
| Identifiers leaking into the repo | logs gitignored; serial and the eMMC CID never printed into tracked files | `tools/pr-check` over the test output |

Every guard fails closed: an unknown value, a missing tool or an unexpected
answer is a refusal, not a warning.

## 8. Open questions before M10

1. **LK's ext2 driver on ext4 partitions.** lk2nd's autoboot mounts every
   partition of 16 MiB or more as ext2 (§3), ext4 ones included. P1 showed
   the scan does not hang (the menu still answered), but not what it read:
   its log went with the USB. The full answer comes after P3, when the
   autoboot runs for real with ext4 on `userdata` and the image at 512 KiB
   (`fastboot oem log` from the menu's fastboot afterwards).
2. **Whether a late key reaches lk2nd's menu** after stock aboot (§3).
   Convenience only; the stock-fastboot route always works.
3. Whether MIUI's `userdata` is encrypted (FDE). Low priority: the owner
   does not keep MIUI's data, P4 reformats it, and a restore that MIUI
   rejects after `fastboot erase` is retried with `fastboot format`.
4. ~~A boot loop with no laptop.~~ Decided: the initramfs's three-try
   count (§3). Still [A]: whether stock aboot honours the `bootloader`
   reason from Linux (it did for `tools/markw-debug fastboot` on 2026-11-17,
   from the RAM-booted chain).
