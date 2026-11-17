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

| Prerequisite | State (2026-11-17) |
| --- | --- |
| Port at least 90 % (owner's gate) | about 86 % |
| M3-M8 evidence | display, GPU, touch, Wi-Fi, BT, audio, mobile data, charger, sensors in the BRINGUP docs. Still open: auto-suspend enabled at boot after a day's soak, a data-on sleep (AA), charger R2, 20 boot cycles on the current kernel |
| Approved amendment to the non-A/B safety policy (§2) | not yet: needs the owner's explicit approval of §2 |
| Restore rehearsal (§6 P1, then P7) | not yet |
| No open critical risk | open: a hang in a long sleep is not yet ruled out (BRINGUP-SUSPEND) |

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

The owner gives up MIUI's user data (agreed: OS on eMMC `userdata`, the
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
- **Initramfs changes (code, offline):** a new `BOOT_METHOD=lk2nd-emmc` in
  `device.conf` and an `EMMC_RW="userdata"` allowlist (the Pixel `UFS_RW` is
  untouched). `init` then finds the root by the UUID packed at build time
  **and** checks that its block device is the eMMC partition whose
  `PARTNAME` is `userdata` (by `/sys/class/block/*/uevent`, never by
  `mmcblkN`: the eMMC was mmcblk0 on oma18 and mmcblk1 on oma19). Every other
  eMMC partition and `boot0`/`boot1` get `blockdev --setro` as today. A UUID
  found anywhere else stops the boot with a message rather than mounting it.
  The microSD path (`ram-only`) stays as it is.

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

The transaction (`tools/markw-install update`, future):

1. Build the new image with `tools/build-markw-probe --root-uuid <userdata
   UUID>`; record its SHA-256 and kernel release.
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

### P2. Installer, offline

- **Run:** `tools/markw-install` with its tests (§7) in WSL; `--dry-run`
  against a fake fastboot and a loop-file eMMC.
- **Expect:** every negative test refuses, dry run prints the exact
  commands and writes nothing.
- **Stop:** any test fails. **Risk:** none (no phone).

### P3. lk2nd into `boot` (M10, write)

- **Run:** stock fastboot, `fastboot flash boot lk2nd-msm8953.img` (pinned
  SHA-256), `fastboot reboot`.
- **Expect:** lk2nd's menu (no Linux image yet).
- **Stop:** no lk2nd within 30 s. **Rollback:** §4.2 steps 1-2.
  **Risk:** medium.

### P4. Format `userdata` (M10, write, MIUI data lost)

- **Run:** RAM-boot the probe with `EMMC_RW=userdata`; the installer checks
  `PARTNAME=userdata`, its size, that nothing is mounted, then
  `mkfs.ext4 -L omamobile-root`; record the UUID.
- **Stop:** any check fails. **Rollback:** §4.2 step 3. **Risk:** medium.

### P5. Root filesystem copy (M10)

- **Run:** `rsync -aHAX` of the microSD root to `userdata`, with `fstab`
  and the machine's identity files left as they are on the SD.
- **Expect:** `rsync` exits 0; a second run copies nothing.
- **Rollback:** reformat (P4). **Risk:** low.

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
   partition of 16 MiB or more as ext2 (§3), ext4 ones included. Checked
   without a write at P1 (`fastboot continue` on a RAM-loaded lk2nd, then
   its log): it must skip them all and fall through, not hang.
2. **Whether a late key reaches lk2nd's menu** after stock aboot (§3).
   Convenience only; the stock-fastboot route always works.
3. Whether MIUI's `userdata` is encrypted (FDE); it does not change the plan
   (P4 reformats it) but `fastboot erase` vs `format` in §4.2 depends on what
   MIUI's first boot accepts.
4. **A boot loop with no laptop.** After P3, a Linux crash and watchdog
   reset boots Linux again through lk2nd, forever. Options: the initramfs
   counts failed boots on `userdata` and, after three, reboots with the
   `bootloader` reason, which lk2nd turns into its fastboot (§3; stock aboot
   may take that reason first, [A]); or rely on the owner's key hold.
   Decide before P6.
