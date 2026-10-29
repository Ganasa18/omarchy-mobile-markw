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
