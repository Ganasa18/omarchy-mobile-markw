<!-- SPDX-License-Identifier: MIT -->
# markw: our own kernel (runbook)

Status: built on the laptop (2026-10-29), not booted yet. Release
`7.1.3-msm8953-oma1`.

## Why

postmarketOS's kernel package (`7.1.3-msm8953`) got the port to Omarchy,
but three things need a kernel of our own:

- **USB OTG froze the phone** (BRINGUP-OTG.md, 2026-10-29): `qcom-smbchg`
  switches the DWC3 role on every bounce of the ID pin and VBUS. The patch
  `0001-power-supply-qcom-smbchg-debounce-USB-role-changes` acts only after
  500 ms of quiet, and logs `USB role X -> Y`.
- **A hang leaves no trace and no way back.** The kernel has no lockup
  detector and no watchdog driver. `markw.config` turns soft and hard
  lockups into panics, so `panic=10` reboots and ramoops keeps the trace.
  Hung tasks are only reported, because a slow microSD can block writers.
  The APSS watchdog (`0x0b017000` on the sibling msm8937) needs a new DT
  node: it waits for a separate boot (one change per boot).
- **pacman needs `--disable-sandbox`** without Landlock. Landlock is now on
  (already in `CONFIG_LSM`).

It also builds `ch341` and `pl2303` itself, so the hand-built copies in
`/lib/modules/7.1.3-msm8953/updates/` are no longer needed for this release.
Debug info is off; nothing on the phone reads it.

## Build (laptop only)

```sh
tools/build-markw-kernel --config markw-config.gz \
  --source linux-v7.1.3-r0.tar.gz --out ~/android/markw/kernel-oma1
```

`--config` is the phone's own `/proc/config.gz` under postmarketOS's
kernel. The source tarball is pinned by SHA-256. The tool checks that every
`markw.config` value survived `olddefconfig`.

The probe is the same initramfs with this kernel:

```sh
K=~/android/markw/kernel-oma1
tools/build-markw-probe --kernel $K/Image.gz \
  --dtb $K/dtbs/qcom/msm8953-xiaomi-markw.dtb \
  --modules $K/lib/modules/7.1.3-msm8953-oma1 \
  --ssh-key ~/.ssh/id_ed25519.pub --mkbootimg ~/mkbootimg/mkbootimg.py \
  --root-uuid <ROOT-UUID> --usb-role otg --out ~/android/markw/probe-m5-oma1
```

## Runbook

Every step is the owner's call. Stop at the first failed Pass. The eMMC is
never written: the probe boots from RAM, and the only write is a new module
directory on the microSD root.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Read-only, on the laptop: the build's `SOURCE`, `config` and `modules-*.tar.zst` exist; `grep -c '' modules.order` is close to postmarketOS's | all present | anything missing | — | none |
| 1 | Copy the modules to the running phone (postmarketOS kernel): `tools/phone-ssh 'tar -C /usr/lib/modules --zstd -xf -' < $K/modules-7.1.3-msm8953-oma1.tar.zst`, then `depmod 7.1.3-msm8953-oma1` | `/usr/lib/modules/7.1.3-msm8953-oma1/modules.dep` exists; the running kernel's directory untouched | tar or depmod errors | `rm -rf /usr/lib/modules/7.1.3-msm8953-oma1` | low |
| 2 | Boot the new probe with the laptop cable in: `MARKW_PROBE=~/android/markw/probe-m5-oma1/boot.img ./DEBUGING_RUN.sh --restart` | USB SSH answers; `uname -r` is `7.1.3-msm8953-oma1`; the lock screen shows | no USB SSH in 3 min (check Wi-Fi SSH) | hold Power about 10 s (it boots MIUI), then `./DEBUGING_RUN.sh` (probe-m3) | low |
| 3 | Read-only checks: `cat /sys/kernel/security/lsm` names `landlock`; `cat /proc/sys/kernel/softlockup_panic /proc/sys/kernel/hardlockup_panic` are 1; Wi-Fi up, GPU devfreq moving, `dmesg -l err,warn` against the old boot | all match; no new errors | a driver missing or a new error | step 2's rollback | none |
| 4 | pacman with its sandbox: `pacman -Sy` (refreshes the package lists only) | downloads succeed without `--disable-sandbox` | Landlock errors | keep `--disable-sandbox` for now | none |
| 5 | OTG with a log over Wi-Fi (`dmesg -w`): unplug the laptop, plug the OTG adapter with the CH340G, wait, unplug, plug the laptop | `USB role device -> host`, `ttyUSB0`, `USB role host -> device`, USB SSH back; one role line per plug | two role lines for one plug, or a hang | if hung: hold Power, then fastboot and probe-m3 first, and read `/sys/fs/pstore` | low |
| 6 | Deliberate bounce: wiggle the OTG plug in and out quickly a few times, then leave it in | at most one `USB role` line per settled state; no hang | a hang | as step 5 | medium |

Results go here and in NOTES.md, with the date and `uname -r`.

## Results

**2026-10-29, build `7.1.3-msm8953-oma1`** (Alpine clang 20.1.8, 21 min on
the laptop's WSL, 2.7 GB with the source tree):

- **Step 0: pass.** 818 modules against postmarketOS's 816: the same set
  plus `ch341` and `pl2303`. `Image.gz` 10.7 MB (12.3 MB with postmarketOS's
  debug-info build). Probe `~/android/markw/probe-m5-oma1` (OTG role) built.
- Two first tries failed and the tool now covers both: Kconfig 7.1 takes
  numbers for `BOOTPARAM_SOFTLOCKUP_PANIC` and `BOOTPARAM_HUNG_TASK_PANIC`
  (the fragment check caught it), and the module signing key needs the
  `openssl` command.

**2026-10-29, on the phone, `7.1.3-msm8953-oma1`:**

- **Step 1: pass.** Modules unpacked to `/usr/lib/modules/7.1.3-msm8953-oma1`;
  `depmod` clean; postmarketOS's directory untouched.
- **Step 2: pass** (`MARKW_PROBE=…/probe-m5-oma1/boot.img ./DEBUGING_RUN.sh
  --restart`). USB SSH answered, and Hyprland and the lock screen came up.
- **Step 3: pass.**
  - The LSM list includes `landlock`.
  - `softlockup_panic=1`, `hardlockup_panic=1`, `watchdog_thresh=10`.
  - Wi-Fi was up, the GPU ran at 650 MHz, and the USB role was `device`.
  - No failed units.
  - The only WARNING is `pclk0_clk_src: rcg didn't update its
    configuration` while `panel_mdss_nt35596_ebbg` loads, already seen under
    postmarketOS's kernel (taint `W`).
- **Step 4: pass.** `pacman -Sy` on a throwaway copy of the database
  downloaded every repository with the sandbox on (no `--disable-sandbox`).

## oma3: the light sensor fix and the watchdog

Release `7.1.3-msm8953-oma3` adds two patches to oma2's two:

- `0003-iio-light-ltr501-wait-for-the-start-up-time-after-power-on`: the
  driver enables the sensor's supplies and reads the part ID at once, but
  the LTR-559 needs 100 ms after power-on. This is the likely reason it
  stays unbound at every boot (NOTES.md, 2026-11-02, sensors), while a bind
  by hand later works. `omamobile-markw-light.service` stays in the package
  until oma3 has bound the sensor at several boots in a row; it does nothing
  when the driver already owns the device.
- `0004-arm64-dts-qcom-msm8953-add-the-APSS-watchdog-disabled`: upstream
  MSM8953 has no watchdog node. Its siblings MSM8937 and MSM8917 describe
  the APSS watchdog at `0x0b017000` with
  `"qcom,apss-wdt-qcs404", "qcom,kpss-wdt"`, sleep clock, no interrupts; the
  node is copied with `status = "disabled"`. Whether this firmware lets
  Linux run that block is unknown, so it is enabled only in a boot of its
  own (step 3), by editing the probe's DTB.

`markw.config` adds `CONFIG_WATCHDOG=y` and `CONFIG_QCOM_WDT=m`: with the
node disabled the module never loads.

```sh
tools/build-markw-kernel --config markw-config.gz \
  --source linux-v7.1.3-r0.tar.gz --out ~/android/markw/kernel-oma3
```

### Runbook (oma3)

Same rules as above: the owner's call at each step, stop at the first failed
Pass, RAM boots only, the eMMC is never written.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Read-only, on the laptop: `SOURCE` lists patches 0001-0004; `config` has `CONFIG_QCOM_WDT=m`; `fdtget $K/dtbs/qcom/msm8953-xiaomi-markw.dtb /soc@0/watchdog@b017000 status` is `disabled` | all match | anything else | — | none |
| 1 | Copy the modules to the running phone and `depmod 7.1.3-msm8953-oma3` (as step 1 above) | `modules.dep` exists; other module directories untouched | tar or depmod errors | `rm -rf /usr/lib/modules/7.1.3-msm8953-oma3` | low |
| 2 | Boot `probe-m9-oma3` (node disabled) with the laptop cable in | `uname -r` is `7.1.3-msm8953-oma3`; `/sys/bus/i2c/devices/0-0023/driver` exists and `journalctl -b -u omamobile-markw-light` shows no bind; sound, sensors and Wi-Fi as under oma2; no `/dev/watchdog*` | no USB SSH in 3 min, or a driver missing | hold Power about 10 s, then the oma2 probe (`probe-m8-audio`) | low |
| 3 | Boot `probe-m9w-oma3`, whose DTB has the node enabled (`fdtput -t s markw.dtb /soc@0/watchdog@b017000 status okay`), with `dmesg -w` streamed over Wi-Fi | `qcom_wdt` probes; `/sys/class/watchdog/watchdog0/identity` and `timeout` read; `state` is `inactive`; the phone stays up 10 min | a hang or reset during boot, or an abort in the log | hold Power, then the step 2 probe | medium |
| 4 | Bite test, announced first: `systemd-run --unit=x-wdt-bite sh -c 'exec 3>/dev/watchdog0; sleep 600'` (opens the watchdog and never pets it) | the phone resets about `timeout` seconds later | no reset after `timeout` + 30 s: the block doesn't bite; stop the unit (it closes without the magic character, so note the state) | the phone boots MIUI or lk2nd; then the step 3 probe | medium |
| 5 | systemd pets it: a drop-in with `RuntimeWatchdogSec=30s`, then `systemctl daemon-reexec` | `systemctl show -p RuntimeWatchdogUSec` is 30 s; `state` is `active`; up for 1 h with no reset | an unexpected reset | remove the drop-in, reboot | low |

After step 5 the node is enabled in the markw DTS (a patch of its own),
`omamobile-device-markw` ships the drop-in, and the module is no longer a
separate step.

### Results (oma3)

**2026-11-02, build `7.1.3-msm8953-oma3`** (laptop only, no phone):

- **Step 0: pass.** `SOURCE` lists 0001-0004; the config has
  `CONFIG_WATCHDOG=y`, `CONFIG_QCOM_WDT=m`; 820 modules, `qcom-wdt.ko` among
  them. Against oma2's DTB the only changes are the watchdog node
  (`status = "disabled"`) and the speaker route from patch 0002 (until now
  added by the probe builder, which leaves a DTB that has it alone).
- `checkpatch --strict` is clean on 0003 and 0004. `dt-validate` did not
  run: `dtschema` would not install in the container. The node is the one
  MSM8937 and MSM8917 already carry upstream.
- Probes: `probe-m9-oma3` (node disabled, boot.img sha256 `26e547d9…`) and
  `probe-m9w-oma3` (node enabled, `37f42c3e…`); their initramfs contents are
  identical, only the DTB's watchdog status differs.

**2026-11-02, on the phone, `7.1.3-msm8953-oma3`:**

- **Step 1: pass.** Modules unpacked (checksum matched, 820 modules),
  `depmod` clean, oma2's directory untouched.
- **Step 2: pass** (`probe-m9-oma3`). USB SSH answered; system `running`, no
  failed units.
  - The kernel bound the LTR-559 itself: it registered as `iio:device1`,
    before the BMI120's `iio:device2` at 12.08 s, while
    `omamobile-markw-light` started at 16.09 s and exited in 46 ms without
    binding. Under oma2 that unit had to bind it at every boot. It read lux
    1, proximity 26.
  - The compass and accelerometer came up as before; Wi-Fi connected; the
    sound card, PipeWire and WirePlumber up; GPU devfreq at 19.2-650 MHz.
  - No `/dev/watchdog*`, as expected with the node disabled; no new errors
    against oma2 (the ASoC "widget overwritten" and maxtouch.cfg lines are
    old).

**2026-11-07, on the phone, `7.1.3-msm8953-oma6`:**

- **Step 3: pass** (`probe-m13-oma6-wdt`: oma6's kernel and modules, the
  DTB with patch 0009's 150 mA and the watchdog node's `status` set to
  `okay` by `fdtput`; the `dtc` diff against the running DTB is that one
  line). `qcom_wdt` bound `b017000.watchdog` by itself (module alias from
  the DT) and `/dev/watchdog` and `/dev/watchdog0` appeared within about
  50 s of boot. The `watchdog0` sysfs attributes (`identity`, `timeout`,
  `state`) are missing: `CONFIG_WATCHDOG_SYSFS` is off. systemd's
  `RuntimeWatchdogUSec` is 0, so nothing opens it. The touch controller
  is the Atmel maXTouch; the `edt_ft5x06` probe failure in the log is
  the other candidate driver and happened on the boot before too.
- Up 10.2 h on that boot with the driver bound and nothing opening the
  device: no reset, no new errors (the venus firmware and OPP lines are
  old). Step 3 holds well past its 10 min.
- **Step 4: fail, stop condition** (owner's go). A detached unit opened
  `/dev/watchdog0`, set 30 s (`WDIOC_SETTIMEOUT`, read back 30) and never
  petted it: the phone was still up 2.5 min later, SSH answering, with no
  watchdog message in the kernel log. The unit was stopped and the device
  disarmed with a magic close (`V`). So writes from Linux don't arm a
  bite on this phone: the likeliest reason is that the secure world owns
  the APSS watchdog on MSM8953, as downstream's `msm_watchdog` runs it
  through TrustZone; not checked further. The node stays `disabled`
  (patch 0004 unchanged) and step 5 (systemd petting it) is moot; the
  soft and hard lockup detectors with `panic=10` remain the hang net.

## oma19: ten warm reboots (2026-11-18)

Owner's go, cable in, attended. Each cycle: `./DEBUGING_RUN.sh --restart
--probe out/markw/probe-oma19/boot.img` (Arch `systemctl reboot
--reboot-argument=bootloader`, stock fastboot, lk2nd and the probe in RAM),
SSH, 45 s to settle, then a read-only check. Stop conditions: an `Oops:`,
`Internal error`, panic, `BUG:`, ext4 or MMC error, any eMMC partition
not `ro=1`, a failed unit, the wrong kernel, or a WARNING other than the
accepted `pclk0_clk_src` one.

- **10 of 10 passed** on `7.1.3-msm8953-oma19`: 102-107 s from the reboot
  command to SSH, SSH at about 72 s of uptime, `is-system-running`
  `running`, no failed unit, ModemManager active, every eMMC partition
  `ro=1`, no Oops, panic or storage error.
- The `pclk0_clk_src: rcg didn't update its configuration` pair (taint
  512) came on 4 of the 10 boots (cycles 3, 4, 8, 10) and on none of the
  others: it is intermittent, the panel came up either way. No other
  WARNING.
- Two false stops on the way, both from the check, not the phone: a
  case-insensitive "oops" matched `ramoops` (cycle 1), and the pclk0
  pair was not yet allowed (cycle 3).
- Wi-Fi read `unavailable` throughout: NetworkManager's Wi-Fi switch was
  off (rfkill soft block, kept across reboots), set before the test.
- Still to do: ten attended cold boots (power off, Power key), which need
  the owner's hands.

## oma19: ten cold boots, runbook (prepared 2026-11-19)

Nothing is flashed on markw, so Power alone boots MIUI, and a MIUI boot
rewrites the modem NV (`modemst1/2`, `persist`), which would need a fresh
backup. Each cold boot therefore goes through stock fastboot by hand:
full power-off, then Volume Down + Power, then lk2nd and the probe in
RAM as before. This also tests `systemctl poweroff` on markw for the
first time, and the first boots with device-markw 0.1.28 (auto-suspend
enabled at boot).

Risk: low (RAM-only, no eMMC write). Attended, cable in for the checks.

Each cycle (the laptop script stops at the first failure):

1. Laptop: `systemctl poweroff` (armed 3 s ahead), then waits until SSH
   is gone. **Stop** if SSH still answers 2 min later.
2. Owner: when the screen is dark, unplug the cable (a cable left in can
   start the stock charger mode), wait until the phone is fully off,
   hold **Volume Down + Power** until the fastboot screen, plug back in.
   **Stop** if the screen hangs lit after poweroff: hold Power about 15 s
   to force it off, and report.
3. Laptop: `./DEBUGING_RUN.sh --probe out/markw/probe-oma19/boot.img`
   (fastboot -> lk2nd -> probe). **Stop** if the phone came up in MIUI
   instead: take a fresh NV backup before any radio work.
4. Laptop: SSH, 45 s to settle, then the warm-reboot check (no `Oops:`,
   panic, `BUG:`, ext4 or MMC error; every eMMC partition `ro=1`; no
   failed unit; `running`; kernel `7.1.3-msm8953-oma19`; no WARNING but
   the accepted pclk0 pair), plus `omamobile-autosuspend` active.

Expect: the screen goes dark within about 10 s of step 1; from fastboot
to SSH about 75-105 s.
Rollback: none needed; Volume Down + Power reaches fastboot from any
state, and Power alone still boots MIUI (then back up the NV).
Logs: `logs/markw-coldboots-1119/` (summary, cycle logs, dmesg per boot).

### Results (2026-11-19): 4 of 4 passed; the owner cut the run to 4

The owner decided 4 cold boots are enough next to the ten warm reboots,
so the run stopped after cycle 4 (the plan's ten is reduced by the
owner's decision, not by a failure).

- **4 of 4 passed** on `7.1.3-msm8953-oma19`, device-markw 0.1.28,
  modemmanager 1.24.2-2.3: SSH at about 71 s of uptime, `running`, no
  failed unit, ModemManager active, every eMMC partition `ro=1`, no
  Oops, panic or storage error. `omamobile-autosuspend` was active at
  every boot, the first proof that 0.1.28 enables it.
- `systemctl poweroff` works on markw: each time SSH was gone within
  seconds, and the previous boot's journal ends in `Reached target System
  Power Off`, `systemd-shutdown` syncing and sending SIGTERM. No charger
  mode and no MIUI boot, so the modem NV was not touched.
- The pclk0 pair came on 3 of the 4 boots (cycles 1, 3, 4); no other
  WARNING.
- Two waits ran out (cycle 2, 15 min each) before the phone reached
  fastboot by hand. Those were the timeout for the owner's step, not the
  phone; cycle 2 then passed once it was in fastboot.
