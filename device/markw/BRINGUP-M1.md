<!-- SPDX-License-Identifier: MIT -->
# Redmi 4 Prime (markw): first light

Status (2026-10-27): **steps 1-5 passed on the owner's phone (7.1.3-msm8953);
results in [NOTES.md](NOTES.md).**
Kernel source: postmarketOS `linux-postmarketos-qcom-msm8953-7.1.3-r2`
(built from [msm8953-mainline/linux][kernel] tag `v7.1.3-r0`), release
`7.1.3-msm8953`. Like flame, this probe consumes that package's kernel, DTB
and modules and keeps no kernel worktree. Second stage: [lk2nd][lk2nd],
loaded into RAM with `fastboot boot` and never flashed.

The `ram-only` descriptor is refused by the generic image, flash, push and
installer tools (`tests/boot-method`). Nothing here writes the phone.

## Goal

Boot a kernel and an SSH server entirely from RAM, with the eMMC (user area,
`boot0`, `boot1`) and the microSD card all read-only. Establish that the
boot chain and the recovery path work before any rootfs, display or radio work.

## Sources and facts

- [V, source] `msm8953-xiaomi-markw.dts` (v7.1.3-r0): model `Xiaomi Redmi 4
  Prime`, compatible `xiaomi,markw`, `qcom,msm8953`; `qcom,msm-id = <293 0>`
  (common dtsi), `qcom,board-id = <0x1000b 1>`; ramoops at `0x9ff00000`.
- [V, source] The MSM8953 DT has no APSS watchdog node, so the probe has no
  hardware watchdog. A hung kernel needs the buttons (see Recovery).
- [V, source] USB is a flattened DWC3 at `/soc@0/usb@7000000` with
  `usb-role-switch` driven by the PMI8950 charger; the probe sets
  `dr_mode = "peripheral"` and drops the role switch, as flame does.
- [V, source] The postmarketOS kernel builds DWC3, QUSB2, SDHCI-MSM,
  configfs and devtmpfs in; NCM/ACM functions, `libcomposite`, `qcom-pon`
  and `reboot-mode` are modules. Only those seven go into the initramfs.
- [V, source] lk2nd (commit `fd380ac`) lists markw; its fastboot `boot`
  takes an Android boot image, decompresses a gzip kernel and looks for an
  appended DTB matched by `qcom,msm-id`/`qcom,board-id`. `project/msm8953.mk`
  sets `ABOOT_IGNORE_BOOT_HEADER_ADDRS`: the kernel goes to `0x80000000`
  (2 MiB aligned + `text_offset`), tags/DTB to `0x83400000`, ramdisk to
  `0x83600000`. This kernel's `image_size` is `0x1e60000`, ending at
  `0x81e60000`; the builder refuses a kernel that would reach the DTB.
- [V, PON DT] `pm8953` PON has `mode-bootloader = <0x2>`: `reboot-to
  bootloader` with `qcom-pon` loaded asks the stock bootloader for fastboot.
- [A] Stock Xiaomi aboot accepts `fastboot boot lk2nd.img` on an unlocked
  bootloader (lk2nd's documented test path). Unverified on this unit.

## Offline build (done 2026-10-26)

```sh
# Kernel package, unpacked anywhere (public GPL package, not a vendor blob)
curl -LO https://mirror.postmarketos.org/postmarketos/master/aarch64/linux-postmarketos-qcom-msm8953-7.1.3-r2.apk
mkdir k && tar -xzf linux-postmarketos-qcom-msm8953-7.1.3-r2.apk -C k
git clone --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg

tools/build-markw-probe --kernel k/boot/vmlinuz \
  --dtb k/boot/dtbs/qcom/msm8953-xiaomi-markw.dtb \
  --modules k/usr/lib/modules/7.1.3-msm8953 \
  --ssh-key ~/.ssh/id_ed25519.pub --mkbootimg mkbootimg/mkbootimg.py \
  --out ~/android/markw-probe-1
```

Result: `boot.img` 17 MiB, header v0, page size 2048, kernel = `Image.gz`
with the 67 KiB DTB appended (verified with `unpack_bootimg.py`: the kernel
blob ends with the DTB, and the gzip stream decompresses to an ARM64 Image).
In the DTB: USB `dr_mode=peripheral`, no `usb-role-switch`, remoteprocs
`4080000` (modem), `a204000` (WCNSS) and `c200000` (LPASS) disabled.
Initramfs: `init`, a static aarch64 `reboot-to`, the seven modules in
dependency order, the public key, and no firmware. Two builds give the same
DTB; the initramfs differs by file timestamps only (as with flame's builder).

On Windows hosts the builder needs an LF checkout and Docker Desktop; from
Git Bash run it with `MSYS2_ARG_CONV_EXCL=/src`.

Ready on the owner's laptop (2026-10-26, outside the repository):
`~/android/markw/lk2nd-msm8953.img`, lk2nd release 23.1 (tag commit
`24d3f25`), SHA-256 `2170c90c…3cfa`; it lists markw and carries the
`xiaomi,markw` DT, and its `msm8953.mk` and load addresses match the
pinned commit's. `~/android/markw/probe-m1/`, built with the owner's own
public key (`boot.img` SHA-256 in its `SHA256SUMS`). `tools/markw-kernel`
now produces the kernel inputs from the pinned package.

## Runbook (needs the human; one step at a time)

Before step 1 the owner confirms: bootloader unlocked; battery above 50 %;
Volume Down + Power reaches stock fastboot; an lk2nd image for
`lk2nd-msm8953` from the pinned commit (built, or a release with its
checksum recorded); no microSD card inserted for M1.

### 1. Identify the phone in stock fastboot (read-only)

```sh
fastboot devices
fastboot getvar product
fastboot getvar unlocked     # empty on this aboot
fastboot oem device-info     # "Device unlocked: true"
```

- **Expect:** one device, product `markw`, unlocked `yes` (or
  `Device unlocked: true` from `oem device-info`).
- **Stop:** any other product, locked, or two devices attached.
- **Rollback:** none needed. **Risk:** none.

### 2. RAM-boot lk2nd (affects the screen; announce first)

```sh
fastboot boot ~/android/markw/lk2nd-msm8953.img
fastboot devices          # now answered by lk2nd
fastboot oem log && fastboot get_staged lk2nd.log
```

- **Expect:** the screen shows lk2nd's fastboot menu; `lk2nd.log` names
  markw (`xiaomi,markw` / `msm8953-xiaomi-markw`).
- **Stop:** no lk2nd screen within 30 s, or a different device detected.
- **Rollback:** hold Volume Down + Power to restart into stock fastboot;
  nothing was written. **Risk:** low.

### 3. RAM-boot the probe from lk2nd

```sh
fastboot boot ~/android/markw/probe-m1/boot.img
```

- **Expect:** within about 30 s the host sees a USB NCM interface and an ACM
  port (`Redmi 4 Prime (Omarchy Mobile)`), and gets `172.16.42.2`.
- **Pass:** `ssh root@172.16.42.1` works.
- **Stop:** no USB within 60 s. Do not retry blindly.
- **Rollback:** the probe returns to the bootloader by itself 90 s after
  USB drops; otherwise hold Power (duration unknown on this unit, record
  it) or Volume Down + Power. Nothing was written. **Risk:** low.

### 4. Read-only checks over SSH

```sh
uname -r                                  # 7.1.3-msm8953
cat /proc/cmdline
for s in /sys/class/block/mmcblk*; do echo "${s##*/} $(cat $s/ro)"; done   # all 1
cat /sys/class/udc/*/state                # configured
dmesg | grep -iE 'oops|panic|bug:|mmc0|dwc3|qcom-pon' | head -40
ls /sys/fs/pstore
```

- **Pass:** every `mmcblk*` reads `ro=1`; no oops; UDC configured.
- **Stop:** any block device with `ro=0`, any oops. Copy the log first.
- Record results (sanitized: no serials, no CID, no partition contents) in
  `PROGRESS.md` and a new `NOTES.md`, with the date and `uname -r`.

### 5. Return to fastboot

```sh
ssh root@172.16.42.1 reboot-to bootloader
```

- **Expect:** stock fastboot (lk2nd is gone; it was only in RAM).
- **Stop:** the phone boots MIUI instead: `qcom-pon` did not load; record it.
- **Risk:** low.

## Not in M1

No rootfs switch, no microSD write, no display or GPU driver work, no
firmware, no remote processors, no radios. Those are M3-M6 in
[ENGINEERING-PLAN.md](ENGINEERING-PLAN.md).

[kernel]: https://github.com/msm8953-mainline/linux/tree/v7.1.3-r0
[lk2nd]: https://github.com/msm8916-mainline/lk2nd
