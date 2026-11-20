# markw M9: persistent-install design

**Status (2026-11-19): M10 P5 passed.** The last verified session reached
`graphical.target` on ext4 eMMC `userdata` with the oma19 probe loaded
into RAM. Installed `boot` still contains P3, whose normal boot uses
the microSD root. P6 (permanent eMMC-root boot) and P7 (restore rehearsal)
are pending. The tracked descriptor remains `BOOT_METHOD=ram-only`.

M9 established the writable-partition allowlist, the boot chain and
rollback, and the installer's negative tests ([ENGINEERING-PLAN](ENGINEERING-PLAN.md)
§9.4, §21 M9). Hardware writes belong to the gated M10 runbook and
require the owner's go for each step.

Evidence tags as in [BRINGUP-M1](BRINGUP-M1.md): **[V]** verified on this
phone or in pinned source, **[A]** assumption still to check.

## 1. Gate

Nothing in §6 past step P2 runs until all of these hold:

| Prerequisite | State (2026-11-19) |
| --- | --- |
| Port at least 90 % (owner's gate) | about 90 % (2026-11-19; was 89 %, then 86 %). The last point is the systemd audit closed: all four findings fixed or ruled out, the last the idle shell's 60 Hz call-card animation (omamobile-shell 0.2.45, NOTES). The weights are estimates, so this is at the gate, not past it. Still open: earpiece, headphone and volume limits; the ESP32 upload |
| M3-M8 evidence | display, GPU, touch, Wi-Fi, BT, audio, mobile data, charger (R2 passed 2026-11-17), sensors in the BRINGUP docs. The overnight data-on sleep (AA) passed 2026-11-19 with modemmanager 1.24.2-2.3: 11 h 50 min, vmin 97 %, about 12 mA, no crash (BRINGUP-SUSPEND CE). Auto-suspend is enabled at boot from device-markw 0.1.28 (installed 2026-11-19). Cold boots: 4 of 4 passed 2026-11-19 (the owner cut the plan's ten to four, next to ten warm reboots passed 2026-11-18; BRINGUP-KERNEL), with auto-suspend active at every boot |
| Approved amendment to the non-A/B safety policy (§2) | approved by the owner 2026-11-19, as written in §2: `boot` and `userdata` only, each write still gated step by step |
| Restore rehearsal (§6 P1, then P7) | P1 (no write) passed 2026-11-17; P7 after the install |
| No open critical risk | a hang in a long sleep: closed 2026-11-19. A 19 h auto-suspend (2026-11-18) and an 11 h 50 min one on the fixed stack (device-markw 0.1.27, modemmanager 1.24.2-2.3) both woke cleanly on Power |

Checks before P3 (2026-11-19, read-only):

- MIUI's data: the owner keeps none of it (apps or files), and Linux could
  not read it anyway (FDE, §8 question 3).
- The NV backup is current: the sha256 of `modemst1`, `modemst2`, `fsg`,
  `fsc`, `sec` and `persist`, read by `PARTNAME` with all six `ro=1`, match
  the newest set (taken after the P1 MIUI boot, 2026-11-17) in both its
  phone and laptop sums, so no MIUI boot has changed them since.

## 2. Writable-partition allowlist (policy amendment)

**Approved by the owner on 2026-11-19**, for markw only and as written
below. The approval doesn't start the install: each step from P3 on still
waits for the owner's go.

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

**What changes for the owner after P3, until P6:** MIUI no longer boots, and
the phone has no Linux image in `boot` yet, so a power-on without the
laptop stops in lk2nd's menu (it finds no `/extlinux` and no image). Every
boot until P6 is the laptop's `fastboot boot` of the microSD probe, as
today; stock fastboot (Volume Down + Power) is unchanged. So P3 to P6 are
best run in one sitting.

Runbook (prepared 2026-11-19, not run). One write, at P3.6; everything
before it is read-only or on the laptop.

| Step | Where | Run | Expect / Pass | Stop | Risk |
| --- | --- | --- | --- | --- | --- |
| P3.0 open the gate | laptop | `BOOT_METHOD=lk2nd-emmc` in `device/markw/device.conf` and the package's copy (device-markw 0.1.32); `tests/boot-method` expects markw refused by `install-phone`, `images`, `flash`, `push` as `unsupported BOOT_METHOD=lk2nd-emmc`; run `tests/markw-install`, `tests/boot-method`, the package tests; commit | all pass; only `tools/markw-install` writes | any test fails | none (no phone) |
| P3.1 phone state | Linux (microSD root) | battery (`upower`), `ro` of all 49 eMMC partitions, no `/extlinux` on the card, NV sums (done 2026-11-19, §1) | battery 50 % or more on the cable; all `ro=1`; no `/extlinux` | any one fails | low (reads) |
| P3.2 backups and pin | laptop | `tools/markw-install check` (no phone in fastboot) | `backups: 20261117T003912Z (boot), 20261117T030058Z-after-miui (NV)`, `check passed` | any refusal | none |
| P3.3 stock fastboot | phone | `tools/markw-debug fastboot` from Linux, or Volume Down + Power from off (**the screen shows fastboot**) | `fastboot getvar product`: `markw`; `partition-size:lk2nd` empty (stock) | no fastboot in 60 s: Power hold, boot the probe as usual | low |
| P3.4 check with the phone | laptop | `tools/markw-install check` | `phone: markw, stock fastboot`, `check passed` | any refusal | none |
| P3.5 dry run | laptop | `tools/markw-install --dry-run lk2nd` | prints exactly one line, `DRY: fastboot flash boot …/lk2nd-msm8953.img` | anything else printed | none |
| **P3.6 the write** | laptop | `tools/markw-install lk2nd` (`--battery-checked` if fastboot can't read the voltage); the owner types `markw` | fastboot `OKAY` for `boot`, `done: 'fastboot reboot' shows lk2nd's menu` | an error from fastboot: **do not reboot**; stay in stock fastboot and run §4.2 step 2 (MIUI's `boot.img` back) | **medium** |
| P3.7 first lk2nd boot | phone | `fastboot reboot` | lk2nd's menu within 30 s; `fastboot getvar partition-size:lk2nd` `0x80000`; `fastboot oem log` saved to `logs/` (the ext4 scan, §8 question 1) | no lk2nd in 30 s: Volume Down + Power (stock fastboot), §4.2 steps 1-2 | medium |
| P3.8 back to Linux, verify | lk2nd fastboot, then Linux | `fastboot boot out/markw/probe-oma19/boot.img` (RAM, microSD root as today); then read-only: the first 368656 bytes of `boot` (by `PARTNAME`) hash to the lk2nd pin; all 49 eMMC partitions still `ro=1` | Omarchy from the microSD; the hash matches | a mismatch: stock fastboot, flash lk2nd again (P3.6) or §4.2 | low |

**Result (2026-11-19, `7.1.3-msm8953-oma19`): failed at P3.7, rolled
back.** P3.0-P3.5 passed (gate opened in device-markw 0.1.32; backups and
the lk2nd pin checked; stock fastboot; the dry run printed the one write).
P3.6 wrote lk2nd 23.1 into `boot` (`Sending` and `Writing` OKAY). Then:

- `fastboot reboot`, and a cold boot on Power alone: the Mi logo stayed,
  and the fastboot that answered was stock aboot's (`kernel: lk`, no
  `partition-size:lk2nd`, `oem log` an unknown command), drawn without its
  fastboot screen. lk2nd never reached its menu.
- With lk2nd in `boot`, a RAM boot of the same lk2nd also failed, twice:
  `Booting FAILED (Status read failed (Too many links))`, a black screen
  and no USB device for over a minute. The same RAM path had worked at P1
  and at every cold boot before P3.
- Rollback: stock fastboot (Volume Down + Power), `fastboot flash boot
  install-backup/20261117T003912Z/boot.img` (both sums checked first; only
  `boot` written, `userdata` kept). The RAM path then worked at once and
  Omarchy came up from the microSD; `boot` hashes as the backup, all 49
  eMMC partitions `ro=1`. MIUI was not booted, so the NV set is unchanged.
- Bootloader: `Device unlocked: true`, `critical unlocked: true`.

So lk2nd fails, wherever it is loaded from, while `boot` starts with lk2nd.
Not yet known why: the bytes from 512 KiB on (where lk2nd looks for the
Linux image) are the same before and after P3, leftover MIUI kernel with
no Android header; only the first 368 KiB changed. Before another P3: read
lk2nd 23.1's start-up handling of `boot` in the source, and consider
writing `boot` so lk2nd never meets MIUI's leftovers (the remainder
cleared, or lk2nd and the Linux image in one write). Also found: fastboot
reports `battery-voltage` in µV (4050000), so `charged()` in
`tools/markw-install`, which reads mV, passes at any charge (fixed in
device-markw 0.1.33, which also closed the gate again).

Analysis (offline, the same day). The evidence doesn't separate two
causes:

- **H1, aboot or lk2nd fails on the flashed image.** Against it:
  postmarketOS's markw page installs exactly this way (`fastboot flash boot
  lk2nd.img`), and the markw dts is in lk2nd 23.1 (`devices.md`). The only
  header difference from MIUI's image is a separate QCDT (`dt_size` 8192
  against 0); magic, addresses and page size match.
- **H2, a stale `bootloader` reboot reason.** P3.3 reached stock fastboot
  through `systemctl reboot --reboot-argument=bootloader`. After P3.6,
  `fastboot reboot` was answered by stock fastboot again within about 2 s,
  too fast for any image to have run, and a Power-only cold boot also
  stayed in fastboot, behind the Mi logo. lk2nd's LK scrubs the reason
  when it reads it (`platform/msm_shared/reboot.c`), but Xiaomi's aboot is
  closed, and the postmarketOS markw page warns that `adb reboot {target}`
  with lk2nd installed loops. The RAM failures are confounded: they came
  before the owner's accidental Mi Recovery boot (a kernel that would reset
  the reason), and the RAM path worked after it, so the rollback may not
  have been what fixed it.

A retry that tests H2 without changing anything else: reach stock fastboot
by keys only (Volume Down + Power from a power-off, no reboot argument from
Linux), write lk2nd, and leave fastboot with `fastboot continue` or a power
hold. It needs the owner's go and reopening the gate.

**Retry (2026-11-19, owner's go): fails the same way; H1 holds.** To rule
out MIUI's leftovers as well, `boot` got one image: lk2nd 23.1 (pinned
hash), zeros to 512 KiB, then the oma19 microSD probe (its `SHA256SUMS`
hash), 16873472 bytes, written once from stock fastboot by hand (the
installer has no such command; the gate stayed `ram-only`). lk2nd thus
found a valid Android image where it looks for Linux.

- A `systemctl poweroff` with the cable in powered the phone straight
  back on into MIUI (`boot` still held MIUI's image), so MIUI ran once:
  check the NV set against the backup before more modem work.
- Stock fastboot reached by `adb reboot bootloader`; the image written
  (OKAY); `fastboot continue` (OKAY): the FASTBOOT screen stayed, the USB
  device went away, and no SSH within 5 minutes.
- Power held, then a Power-only boot: stock fastboot again after 136 s
  (`oem log` unknown, no `partition-size:lk2nd`).
- **The decisive one, no reboot reason at all:** cable out, Power held
  until off, Power alone: the Mi logo stayed. H2 is out.

So on this markw, lk2nd 23.1 does not come up when stock aboot loads it
from `boot`, whatever follows it, while the same file loaded by `fastboot
boot` always does.

Afterwards: MIUI's `boot.img` written back (both sums checked), Omarchy up
through the laptop, `boot` hashes as the backup, all eMMC partitions
`ro=1`. Against the 2026-11-17 NV set, MIUI's run changed `modemst1`,
`modemst2` and `persist` (`fsg`, `fsc`, `sec` unchanged), so a fresh
read-only set was taken: `20261119T141617Z-after-miui`, phone and laptop
sums agreeing on all six. The laptop RAM boot remains the working route.

**Rollback at any point:** Volume Down + Power gives stock fastboot whatever
`boot` holds; `fastboot flash boot install-backup/20261117T003912Z/boot.img`
puts MIUI's boot image back (§4.2 step 2), and MIUI boots, its `userdata`
untouched until P4.

#### P3 diagnosis (2026-11-19, offline)

- **[V, capture]** In the P0 stock `aboot.img`, the eMMC loader enters its
  QCDT branch at `0x8f62aa1c` when `dt_size` is nonzero. It calls the
  table validator (`0x8f61933c`) and selector (`0x8f619408`), then returns
  an error at `0x8f62ae08` if selection fails. Normal boot can then fall
  back to stock fastboot (`0x8f62efac`). The RAM loader calls the same
  validator and selector through `0x8f62c35c`, then tries the appended-DTB
  scanner at `0x8f62c8c4` on failure. The eMMC loader reaches that scanner
  at `0x8f62a9d4` when `dt_size` is zero.
- **[V, image]** Pinned lk2nd 23.1 has a QCDT v2 at image offset `0x58000`
  with nine entries within the table bounds. Its MSM8953 entries have
  variant low bytes `0x44`, `0x45` or `0x46`. The stock selector compares
  that byte against the hardware variant. The Markw pair is `0x1000b/1`
  on MSM8953 (`293`), as in [BRINGUP-M1](BRINGUP-M1.md). That pair is in
  the contiguous appended list at kernel offset `0x52484`. The stock
  scanner reads the list start (`0x4cff4`) at kernel offset `0x2c`.
  MIUI's backed-up image uses appended DTBs (`dt_size = 0`).
- **[A]** This makes QCDT selection failure the leading explanation for
  P3. No live aboot trace confirms which error occurred. A stale Mi or
  fastboot splash can outlast a USB state change. Check USB enumeration
  and fastboot variables to identify the loader, then SSH and PID 1 to
  confirm Linux reached the installed root.

**Test candidate.** Set `dt_size` to zero, remove the 8192-byte QCDT at
`0x58000`, and retain the `SEANDROIDENFORCE` footer. Recompute the legacy
SHA-1 image ID from the kernel, ramdisk and empty second stage, each
followed by its four-byte little-endian size. The ARM payload, appended
DTBs, ramdisk and load addresses are byte-identical. The offline build is
`out/markw/probe-lk2nd-appended-dtb/lk2nd-msm8953.img`, 360464 bytes,
SHA-256 `4084b1818b54c63014c44c6ccf68e2844c9efab3b35579b1bfb20588a51fa1b8`.

| Step | Run | Pass / stop | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Identify the stage, read-only | `fastboot devices`; for one device, `fastboot getvar product` and `fastboot getvar partition-size:lk2nd`. If USB NCM is up, `tools/phone-ssh --fresh 'uname -r; cat /proc/1/comm'` | Stock `markw` is the candidate's starting point. Stop on no USB response, a different product or multiple devices. `systemd` confirms the real root | None | Low |
| Candidate RAM trial, after the owner's go | From stock fastboot, `fastboot boot out/markw/probe-lk2nd-appended-dtb/lk2nd-msm8953.img`. Once lk2nd is confirmed, separately approve `fastboot boot out/markw/probe-oma19/boot.img` | lk2nd enumerates, then `7.1.3-msm8953-oma19` reaches `systemd` from microSD. Stop at the first missing transition or if it stays in initramfs | Return to the pinned original RAM boot after approval | Low |
| Candidate eMMC trial, still gated | Follow the stock-fastboot preflight and P3 commands below | Cold boot reaches lk2nd, then Omarchy from microSD. Stop before P4 if the installer or rollback is unavailable, or if any transition fails | Use the approved `restore-boot` command and verify the restored image | Medium |

The installer still pins the original image and the descriptor is
`ram-only`. Direct stock-aboot boot of mainline is a separate option. The
oma19 image already uses the appended Markw DTB layout, but the handoff
and recovery without lk2nd would need separate validation.

**RAM trial, first stage (2026-11-19, owner's go).** From a running
`7.1.3-msm8953-oma19` system, one reboot reached stock fastboot
(`product: markw`, no `partition-size:lk2nd`). Stock fastboot accepted the
candidate (`Sending` and `Booting` OKAY). It then enumerated as
`lk2nd-msm8953` with `partition-size:lk2nd = 0x80000` and
`partition-size:boot = 0x3f80000`. This confirms stock aboot's RAM path
can load the repacked image with `dt_size = 0`.

**RAM trial, Linux handoff (2026-11-19, owner's separate go).** The
SHA-256-checked oma19 probe booted from lk2nd's fastboot (`Sending` and
`Booting` OKAY). A fresh USB SSH session confirmed `7.1.3-msm8953-oma19`,
PID 1 `systemd`, active `graphical.target`, and an ext4 root on an SD
device. All 49 eMMC partitions were read-only. The two-stage RAM trial
passed.

**Cold boot candidate (laptop only).**
`out/markw/probe-lk2nd-appended-dtb/boot-p3-microsd.img` is 16873472 bytes,
SHA-256 `4449558c89092b78df4fe67769d6766c8c05517c31669e921f39773045ba948d`.
Checked byte for byte: RAM-tested lk2nd at offset 0, zero padding to
512 KiB, then the same `probe-oma19/boot.img` with the microSD root.
The P0 rollback `boot.img` matches both recorded checksum lists.

**P3 write and rollback, gated.** `tools/markw-install p3-test IMG` accepts
only the SHA-256 above. `restore-boot` restores the checked P0 `boot.img`
without an erase. Both require stock Markw fastboot, verified backup
sets, the battery check and the typed codename. Both use the canonical
P0 backup set `20261117T003912Z`. Each verifies a temporary local copy of
the image before issuing one `flash boot` to the checked USB device. They
return with the phone still in fastboot.

1. Confirm the microSD root has no `/extlinux`, battery is at least 50%
   on the cable, eMMC partitions are read-only, and installer `check`
   passes. With the owner's go, enter stock fastboot. Stop if the
   product or loader changes or the link drops. **Risk:** low.
2. With the checked-in descriptor, run `tools/markw-install --dry-run
   p3-test out/markw/probe-lk2nd-appended-dtb/boot-p3-microsd.img`
   and `tools/markw-install --dry-run restore-boot`. Each must print
   exactly one `flash boot` targeting the intended image, with P0's
   `20261117T003912Z/boot.img` as the rollback. If battery
   voltage is unavailable, add `--battery-checked` after the owner
   confirms charge. **Risk:** none.
3. After approval for this write, create a temporary descriptor with the
   line `BOOT_METHOD=lk2nd-emmc` and pass it as `MARKW_DEVICE_CONF` only
   for each separately approved `p3-test` or `restore-boot` invocation.
   Keep the checked-in descriptor `ram-only`.
   The owner types `markw`. Expect fastboot `OKAY`; on any write error,
   stay in stock fastboot and get approval for `restore-boot` with the
   same temporary descriptor. **Risk:** medium.
4. With separate approval, power off from stock fastboot, then use Power
   only with the cable disconnected. Reconnect USB for evidence. Expect
   oma19 with `systemd`, `graphical.target` and ext4 root on SD. Resolve
   `boot` by `PARTNAME=boot` on the MMC disk and verify the SHA-256 of
   its first 16873472 bytes against the pin above. Stop if the image or
   runtime differs, the Mi logo persists, or stock fastboot comes back.
   Rollback: enter stock fastboot and use `restore-boot` with the temporary
   descriptor after approval. To verify without starting MIUI, load the
   pinned original lk2nd and the microSD probe in RAM after separate
   approvals. Hash the full read-only MMC `boot` and compare it to P0.
   **Risk:** medium. A pass here is required before P4.

**Live preflight (2026-11-19, owner's go).** oma19 was running with
`systemd`, no `/extlinux` on the microSD root, battery at 100%, and the
read-only eMMC `boot` matching P0. One reboot reached stock `markw`
fastboot. Both installer dry runs passed with the tracked `ram-only`
descriptor. Each printed one `flash boot`, for the pinned P3 image and
the canonical P0 rollback image respectively. The phone stayed in stock
fastboot until the owner approved the write.

**P3 write (2026-11-19, owner confirmed `markw`).** The gated `p3-test`
invocation checked the pinned image and P0 backup, then sent and wrote
`boot` once (`Sending` and `Writing` OKAY). Stock fastboot still reported
`product: markw` afterwards. The host fastboot printed an AVB footer
copy warning because the stock partition-size query supplied no value.
No host reboot command was issued.

**P3 cold boot passed (2026-11-19, `7.1.3-msm8953-oma19`).** After the
owner booted the phone with the combined image installed, a fresh USB
SSH session reached `systemd` and active `graphical.target` on
`xiaomi,markw`. Root was ext4 on microSD and all 49 eMMC partitions were
read-only. The SHA-256 of the first 16873472 bytes of eMMC `boot`, found
by `PARTNAME` and device type, matched the P3 image. The host sent no
RAM boot image after the P3 write. This verifies the `aboot` → installed
lk2nd → installed oma19 chain with the repacked image. P4–P7 have yet
to run.

### P4. Format `userdata` (M10, write, MIUI data lost)

- **Preflight (2026-11-19, `7.1.3-msm8953-oma19`):** P3 image still
  matches eMMC `boot`. The SD root uses 20177637376 bytes and has no
  `/extlinux`. `userdata` was identified by `PARTNAME` on eMMC, is
  26301931008 bytes, and has no mounts. All 49 eMMC partitions are
  read-only. Charge was 87%, charging. Installer `check` passed for the
  original lk2nd pin and both backup sets. No P4 write has run.
- **Check before writing:** with approval, enter stock fastboot and
  verify product `markw`, the stock loader, and the `userdata` size.
  Run `tools/markw-install --dry-run format`. Expect a single
  `format:ext4 userdata` operation. Stop on a missing or unexpected
  answer. **Risk:** low (reboot and reads).
- **Dry run result (2026-11-19, owner's go):** one reboot from oma19
  reached stock fastboot; battery was 88%. Fastboot reported `userdata`
  as ext4 and 26301931008 bytes, matching Linux. The closed-gate dry run
  printed exactly one `format:ext4 userdata`. The host SDK's `mke2fs`
  also generated a sparse ext4 test file offline at that logical size
  rounded down to a 4 KiB boundary. No phone storage was changed.
- **Run after explicit approval to erase MIUI data:** from stock
  fastboot, `tools/markw-install format` (`fastboot format:ext4 userdata`),
  with the temporary descriptor and the owner typing `markw`. Expect
  successful formatting. Stop on any error; keep the known-good P3
  `boot` image available for recovery. **Risk:** medium (data loss).
- **Format result (2026-11-19, owner confirmed `markw`):** the installer
  issued one `format:ext4 userdata` against the confirmed stock Markw
  target. `mke2fs` built the ext4 image with 6421369 4 KiB blocks;
  fastboot reported `Sending` and `Writing` OKAY. The device stayed in
  stock fastboot until the owner approved a reboot.
- **Verify:** with separate boot approval, start the installed P3
  microSD probe. `tools/markw-install uuid` reads the new ext4 UUID by
  `PARTNAME` and device type into `logs/markw-install/userdata-uuid`.
  Stop if the running OS or partition check differs from the plan.
- **Readback passed (2026-11-19, `7.1.3-msm8953-oma19`):** one approved
  stock-fastboot reboot reached `systemd` and active `graphical.target`
  from the installed P3 image. On the MMC `PARTNAME=userdata`, `blkid -p`
  reported ext4 and the same UUID as `mke2fs`. The UUID was kept in
  `logs/markw-install/userdata-uuid`. `userdata` was unmounted, all 49
  eMMC partitions were read-only, and the eMMC `boot` prefix still
  matched P3. The live root remains on microSD.
- **Then:** build the eMMC image, `tools/build-markw-probe … --root-uuid
  <that UUID> --root-on emmc`.
- **[A]** Stock aboot supports `format` (it answers `partition-type` and
  `partition-size`); if it doesn't, lk2nd's fastboot (the same Qualcomm
  code) does, and `userdata` is not split by lk2nd.
- **Stop:** any check fails. **Rollback:** §4.2 step 3. **Risk:** medium.

### P5. Root filesystem copy (M10)

- **Prepared on the laptop (2026-11-19):**
  `out/markw/probe-oma19-emmc/boot.img`, 17571840 bytes, SHA-256
  `9a7b4dd319ec4324abdf30349d99e179433344fb53add7cc7c5605cc35b1634f`.
  Its kernel and appended DTB are byte-identical to P3. The new
  initramfs contains the verified P4 eMMC UUID, current storage guard
  and AArch64 `rsync`. No microSD-root UUID is embedded. Installer and
  storage-guard tests passed on offline fixtures.
- **Run:** from lk2nd's fastboot, `fastboot boot` the eMMC image: with an
  empty `userdata` its initramfs finds no systemd and stays, SSH up, with
  `userdata` writable. Obtain approval for each boot and verify the
  expected kernel, initramfs PID 1, matching UUID and read-only flags on
  the other eMMC partitions. Stop if any check fails. **Risk:** low.
- **Entering lk2nd fastboot with P3 installed (2026-11-19):** stock
  fastboot accepted the repacked lk2nd in RAM, then Omarchy oma19 came
  back with `systemd` and active `graphical.target`. No lk2nd USB fastboot
  interface appeared and the P5 image was never sent. This is consistent
  with lk2nd's normal autoboot finding the valid P3 image. To interrupt
  it, use a normal restart and hold Volume Down only after the first
  splash or vibration, per the [lk2nd 23.1 usage guide][lk2nd-23-usage].
  Require the lk2nd product and 512 KiB split before sending the probe.
- **Software-only fallback (2026-11-19):** the late key attempt still
  reached P3 on this phone. On the laptop, build the pinned lk2nd 23.1
  source (`e9c8b21735c13dd7ace808b1e35451638f0a0c6d`) with
  `LK2ND_FORCE_FASTBOOT=1`, then repack it with `dt_size = 0` as above.
  `out/markw/probe-lk2nd-force-fastboot/lk2nd-msm8953.img` has SHA-256
  `534f80a2f85e16f87a4678e06b62320adddfc25a6775ec1ce00e6597b7968f37`.
  The appended Markw DTB and compiled fastboot flag were checked
  offline. This is for `fastboot boot` from stock Markw fastboot. Stop
  if it does not enumerate as Markw in lk2nd fastboot. The installed P3
  image stays in `boot` throughout this RAM test.
- **RAM preflight passed (2026-11-19, `7.1.3-msm8953-oma19`, owner's
  go):** one software reboot reached stock Markw fastboot. RAM-loaded
  force-fastboot lk2nd reported Markw and the 512 KiB split. It then
  loaded the P5 probe, which stayed at PID 1 `init` with USB SSH and
  `rsync`. The configured UUID matched the unmounted ext4 `userdata`.
  Of the 49 eMMC partitions, only `userdata` was writable. Both eMMC
  hardware boot areas were read-only and the whole-disk node was absent.
  The running probe is ready for the separately approved copy.
- **Copy after separate approval:** `tools/markw-install copy` checks the
  microSD source with `e2fsck -fn` and mounts it `ro,noload` (no journal
  replay). It refuses a source with `/extlinux` (§3), a destination that
  contains files, or a copy that would consume more than 90% of the
  available destination space. It runs `rsync -aHAX --numeric-ids` and a
  second dry pass that must succeed and find nothing, then syncs and
  unmounts both. The root has no `fstab` entries naming the card. Stop on
  a dirty source, failed copy, failed verification or failed unmount.
  **Risk:** low (writes to the prepared `userdata`).
- **Copy passed (2026-11-19, `7.1.3-msm8953-oma19`, owner's go):**
  `rsync` copied the 19704668 KiB microSD root. The source stayed mounted
  read-only, a second dry pass found nothing to copy, and both filesystems
  were synced and unmounted. Readback found a clean ext4 on `userdata`,
  the expected UUID, a matching SHA-256 for `/usr/lib/systemd/systemd`,
  and 4.6 GiB free excluding reserved blocks. The other eMMC partitions
  stayed read-only. The boot trial from this copied root is pending.

[lk2nd-23-usage]: https://github.com/msm8916-mainline/lk2nd/tree/23.1#usage
- **Size:** the microSD root holds 19 GB on 2026-11-17, 9.5 GB of it the
  owner's Arduino and PlatformIO toolchains; `userdata` is 24.5 GiB, so about
  5 GiB stay free. Moving those toolchains to the card before P5 is the
  owner's call.
- **Expect:** `copy done`; then `tools/markw-install trial IMG` reaches
  systemd as PID 1 and verifies that `/` is the eMMC `userdata` with
  the UUID recorded in the image. The installer accepts the generic
  `lk2nd-msm8953` product only with the Markw board identity and the
  expected split. A boot that never leaves the initramfs or uses the
  microSD root cannot record a passing trial.
- **Trial passed (2026-11-19, `7.1.3-msm8953-oma19`, owner's go):** a
  software reboot from the P5 initramfs reached stock fastboot. The
  force-fastboot lk2nd and the pinned P5 probe were loaded into RAM.
  The first installer readback failed because formatted `findmnt` output
  padded `MAJ:MIN`; raw output fixed the parser. Reading the same
  running boot confirmed PID 1 `systemd`, active `graphical.target`,
  ext4 root on MMC `userdata` with the P4 UUID, and no Oops, BUG or
  kernel panic lines. The boot-try marker cleared. The other eMMC
  partitions and both hardware boot areas remained read-only, and the
  installed `boot` prefix still matched P3. The local trial receipt
  records the verified RAM image after matching the fastboot log to
  the live readback. No flash was issued during P5.
- **Rollback:** format again (P4). **Risk:** low.

### P6. Linux image into `boot` (M10, write)

- **Run:** the §5 transaction steps 3-5 with the image built for the new UUID.
- **Expect:** cold boot to Omarchy from eMMC with no laptop; `phone-smoke`
  passes; all eMMC partitions but `userdata` still `ro=1`; the microSD
  card mounted read-write at `/mnt/sd` with `/mnt/sd/data` owned by the
  owner (`omamobile-markw-sd-storage`, device-markw 0.1.31: it mounts the
  card's ext4 partition only when the root is not on the card, and leaves
  the old microSD root on it as the §5 way back).
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
3. ~~Whether MIUI's `userdata` is encrypted (FDE).~~ Answered 2026-11-19,
   read-only from Linux: yes. `blkid -p` finds no filesystem, there is no
   ext4 magic at byte 1080, and the last 16 KiB hold Android's crypto
   footer (magic 0xD0B5B1C4, version 1.3). Its key is bound to the
   keymaster and the owner's PIN, so Linux cannot read MIUI's files; a copy
   of them would have to come from a MIUI boot (then a fresh modem backup,
   §4.1). P4 reformats it; a restore that MIUI rejects after `fastboot
   erase` is retried with `fastboot format`.
4. ~~A boot loop with no laptop.~~ Decided: the initramfs's three-try
   count (§3). Still [A]: whether stock aboot honours the `bootloader`
   reason from Linux (it did for `tools/markw-debug fastboot` on 2026-11-17,
   from the RAM-booted chain).
