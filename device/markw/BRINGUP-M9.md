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

- **[A] lk2nd keeps itself and boots the image after it.** lk2nd's
  documented install path writes lk2nd to `boot`; its own fastboot then
  writes a `fastboot flash boot` image after its 512 KiB, and at boot it
  loads the Android boot image it finds there. Check this in the pinned
  source (tag commit `24d3f25`, `lk2nd/` partition handling) before P3, and
  note the exact offset and the image size limit (64 MiB minus 512 KiB; the
  oma19 image is 15.6 MiB).
- **[A] Stopping autoboot.** lk2nd stays in its fastboot menu when a volume
  key is held at power-on. Which key, and that it works from a cold boot
  with the Linux image present, is checked at P1 (RAM-booted lk2nd shows the
  same menu) and again after P3.
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
| flashed image fails | lk2nd starts, Linux doesn't | hold the lk2nd key at power-on, `fastboot flash boot previous.img` |
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
- **Also:** RAM-boot lk2nd and note which key holds its menu (§3).
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
| Identifiers leaking into the repo | logs gitignored; serial and the eMMC CID never printed into tracked files | `tools/pr-check` over the test output |

Every guard fails closed: an unknown value, a missing tool or an unexpected
answer is a refusal, not a warning.

## 8. Open questions before M10

1. lk2nd's exact image offset and its fastboot `flash boot` behavior in the
   pinned source (§3).
2. The key that holds lk2nd's menu from a cold boot (P1).
3. Whether MIUI's `userdata` is encrypted (FDE); it does not change the plan
   (P4 reformats it) but `fastboot erase` vs `format` in §4.2 depends on what
   MIUI's first boot accepts.
4. A watchdog/pstore story for an installed boot with no laptop attached:
   today a crash falls back to MIUI through aboot; after P3 it falls back to
   lk2nd, which then boots Linux again. A boot loop must end at lk2nd's menu,
   not loop forever (count boots in `userdata`, or rely on the owner's key
   hold).
