<!-- SPDX-License-Identifier: MIT -->
# Redmi 4 Prime (markw) bring-up notes

Findings from real hardware, newest first. Plan: [ENGINEERING-PLAN.md](ENGINEERING-PLAN.md); first-light runbook: [BRINGUP-M1.md](BRINGUP-M1.md).

## 2026-11-01: power key bounce, idle power, s2idle (7.1.3-msm8953-oma2)

- **The power key bounces.** Held, `pm8941_pwrkey` reports a release and a
  new press about 20 ms apart (the DT debounce is 15625 us). Hyprland
  passes both on, so omamobile-keys locked the phone on the false release
  and the hold never reached the system menu. omamobile-shell 0.2.21
  voids a release followed by a press within 80 ms. A raised PMIC
  debounce in the DT would also work; not tried.
- **Idle wakeups with the panel off**, per second: `sugov:0` 435 (schedutil
  switching the clock about 90 times a second, as cpufreq-dt reports a
  1 ms transition latency and the rate limit was 1.5 ms), quickshell
  about 63-107, `rcu_preempt` about 95, SD writeback kworkers about 80.
  A 20 ms schedutil rate limit (device-markw 0.1.5) cut sugov to 15 and
  the switches to 5. Idle sits at 652.8 MHz either way.
- **Omarchy turns Wi-Fi power save off** in
  `/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf`. NetworkManager
  reads `/etc` after `/usr/lib`, so a `/usr/lib` drop-in can't override it;
  device-markw 0.1.4 ships `/etc/.../zz-omamobile-wifi-powersave.conf`.
  wcn36xx with power save: ping averages about 50 ms, SSH and pacman fine.
- **The idle cycle kept the panel on for about 5 minutes** (screensaver
  animation at 150 s, lock at 300 s, blank 10 s later). `shell.json`
  `"idle": {"screensaver": 0, "lock": 60}` is read live, without a shell
  restart.
- **s2idle works on oma2:** every `pm_test` stage passes, a real s2idle
  wakes on the PMIC RTC alarm (IRQ 71) and on the power key (IRQ 68),
  and 10 of 10 soak cycles passed. wcn36xx logs `ERROR SMD_EVENT (312) not
  supported` at each suspend, harmless so far. The first attempt, on
  oma1, never resumed and rebooted into MIUI with an empty pstore; neither
  the lockup detectors nor a lit panel reproduce it. Details:
  [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).
- **A crash loses its ramoops record**: the reboot goes to MIUI from the
  eMMC, and the record is gone when the probe boots again.

## 2026-10-28: Wi-Fi from the package, Bluetooth, keyboard after screen-off (7.1.3-msm8953)

- **Wi-Fi needs no hand steps on a new card.** The probe DTB leaves WCNSS
  `okay`, and `omamobile-markw-firmware` (device-markw 0.1.2) copies the
  Pronto firmware and this phone's `WCNSS_qcom_wlan_nv.bin` before udev
  loads the drivers. Nothing in the image blacklists the WCNSS modules. The
  hand-made bring-up blacklist is out of `/etc/modprobe.d` (kept as
  `/var/tmp/omamobile-wcnss-bringup.conf.disabled`), and `wlan0` connects
  at every boot.
- **The firmware copy, tested on the phone:** the root has no `cmp`, so
  `--check` first reported every file as changed; it now compares with
  `sha256sum`. Only `a506_zap.elf` was missing. One run copied it, and a
  second run and the unit under systemd copied nothing.
- **Bluetooth comes up with Wi-Fi.** `btqcomsmd` binds the WCNSS `bluetooth`
  SMD node, giving `hci0` (manufacturer 0x001d, HCI version 0x08: 4.2).
  `bluetoothd` is active, the controller powers on, and rfkill blocks
  nothing. A 12 s scan saw 5 devices (counted only). The public address
  isn't a known shared firmware default; whether it stays the same across
  boots is not yet checked. Pairing is not yet tested.
- **The floating show-keyboard button was gone after the screen went off
  and on.** The lock folds squeekboard, the button stayed only after a
  fold by its own tap, and the lock's focus change cleared it.
  omamobile-shell 0.2.19 keeps it after any fold, until another app takes
  focus. Confirmed by the owner, also after a restart.
- **The keyboard over the lock after the screensaver:** omamobile-omarchy
  0.1.8 (patches 0006 and 0007) turns squeekboard back on and unfolds it,
  also when a touch locks through the idle service. Both apply with
  `--fuzz=0` on Omarchy 4.0.6-1 and are applied on the phone, but haven't
  been tried with the screensaver yet.

## 2026-10-27: lock screen keys, app switcher and Wi-Fi preparation (7.1.3-msm8953)

- **The power button woke the lock without the keyboard.** After the power
  button turned the screen off and on, the lock's PIN pad worked but tapping
  the field or ABC brought no QWERTY. `omamobile-keys` calls
  `omarchy-shell lock wake`, which only ran `omarchy-system-wake`: the field
  kept its focus but got no new focus-in, so squeekboard was never asked
  back. Patch 0009 now also calls the lock view's `forcePasswordFocus()`
  (omamobile-omarchy 0.1.7). It applies with `--fuzz=0` to the phone's
  Omarchy 4.0.6 (`omamobile-omarchy-patches apply --series` from a scratch
  copy, 14 of 14 applied).
- **Still open: no keyboard on the lock after the screensaver.** A touch on
  the screensaver locks through the idle service (0007,
  `screensaver-wake: user returned`), and Qt then logs
  `QWaylandTextInputv3::enableSurface … Trying to enable … but … is focused`.
  The first lock after boot has no such warning, and QWERTY works there.
  The screensaver also turns `screen-keyboard-enabled` off (0006) and
  depends on `restore_osk` to turn it on again. Not yet known which of the
  two is to blame: the next test starts the screensaver from the laptop and
  logs that key and squeekboard's `Visible` while the owner touches the
  screen. For now the owner unlocks with a PIN (number pad).
- **The unlock type is recorded apart from the secret.** `passwd` alone
  leaves `~/.config/omamobile/credential` at `password`, so the lock opens
  on QWERTY even with a numeric secret. `omamobile-set-pin` records `pin`
  and drops Omarchy's `credential-password` toggle.
- **Closing apps:** swipe up on the dock (the search pill) for recent apps,
  then flick a card up. Summoned over IPC (`omarchy-shell shell summon
  omamobile.switcher '{}'`), the `omamobile-switcher` layer came up with
  no errors.
- **A keyboard folded by the hide button never came back.** squeekboard
  unfolds only on a new focus-in, and a tap on a field that already has
  focus (a terminal) gives none, while the button vanished with the
  keyboard. `omamobile.keyboard` 0.1.1 (omamobile-shell 0.2.18) keeps the
  button in the corner as "show keyboard" until the keyboard unfolds or
  another window takes focus. Confirmed by the owner.
- **Wi-Fi joined but had no internet.** There were two causes:
  - The network was a guest network with a captive portal: every HTTP
    request got a 302 to its login page, and NetworkManager reported
    `portal`.
  - markw's `20-usb-gadget.network` set `Gateway=172.16.42.2` at metric 0,
    which beat Wi-Fi (600, or 20600 while NetworkManager reports a
    portal), and a Windows host shares no internet. The gateway is now a
    `[Route]` at metric 1000 (omamobile-device-markw 0.1.1).
- **`tools/markw-debug fastboot` from Arch:** `systemctl reboot bootloader`
  fails with "Too many arguments" and the phone never reboots. It is now
  `systemctl reboot --reboot-argument=bootloader`.
- **Wi-Fi not yet running.** NetworkManager reports Wi-Fi `missing`.
  - The kernel has `qcom_wcnss_pil`, `wcn36xx`, `wcnss_ctrl` and
    `btqcomsmd` (all modules).
  - The probe DTB disabled `remoteproc@a204000` (Pronto, `qcom,pronto-v3-pil`,
    iris `qcom,wcn3660b`) and has no `firmware-name`, so the driver asks for
    `wcnss.mdt` and wcn36xx for `wlan/prima/WCNSS_qcom_wlan_nv.bin`.
  - The firmware is on the phone: `modem` (mmcblk0p1, vfat) has
    `image/wcnss.mdt` with `wcnss.b00`–`b12`, and `persist` has
    `WCNSS_qcom_wlan_nv.bin`, this phone's calibration (`system`'s copy is
    only a 31-byte link to it). Both partitions were mounted read-only and
    unmounted again, and the files were copied on the phone only, to
    `/usr/lib/firmware/updates/` on the card. They never leave the phone.
  - Bring-up blacklist on the card:
    `/etc/modprobe.d/omamobile-wcnss-bringup.conf` (`qcom_wcnss_pil`,
    `wcn36xx`, `wcnss_ctrl`, `btqcomsmd`).
  - `initramfs/build` now leaves WCNSS `okay`; the modem and LPASS stay
    `disabled`. Built and checked (`a204000 okay`, `4080000` and `c200000`
    `disabled`, touch `4a okay`), not booted yet. The previous probe is
    kept as `probe-m3-prewifi` for rollback.
  - **Result (same day, WCNSS probe, by hand under a dmesg stream):**
    - The node came up `okay` at boot with nothing loaded (the blacklist
      held), and the 7 MiB `wcnss@8e700000` region was reserved.
    - `modprobe qcom_wcnss_pil` gave `Booting fw image wcnss.mdt` and
      `remote processor a204000.remoteproc is now up`, then the
      `WCNSS_CTRL`, `WLAN_CTRL` and `IPCRTR` SMD channels.
    - `modprobe wcnss_ctrl` reported `WCNSS Version 1.5 1.2`, then
      `expected cold boot completion` (a timeout warning: Pronto stayed
      `running`), and the BT and FM channels appeared.
    - `modprobe wcn36xx` reported firmware `WCN v2.0 RadioPhy
      vIris_TSMC_4.0 with 48MHz XO`, API 1.5.1.2, and `wlan0` came up.
    - NetworkManager reports Wi-Fi `enabled` and rfkill doesn't block it.
      A scan found 17 networks on 2.4 and 5 GHz, with no wcn36xx errors.
    - Not yet done: connecting, autoloading at boot (remove the bring-up
      blacklist, one boot), Bluetooth (`btqcomsmd`), and power cycles.

## 2026-10-27: M3, Arch from the microSD card (7.1.3-msm8953)

- **Arch boots from the card.** lk2nd, then `probe-m3`, then switch_root
  to the card by UUID. The panel shows systemd's status lines (still the
  lk2nd framebuffer through simplefb, see below), systemd-networkd puts
  `172.16.42.1` on usb0, and SDDM autologs in the user.
- **Windows host:** Arch's usb0 is static (`20-usb-gadget.network`), with
  no DHCP server, so the host needs `172.16.42.2/24` set by hand once
  (admin PowerShell: `New-NetIPAddress -InterfaceAlias '<adapter>'
  -IPAddress 172.16.42.2 -PrefixLength 24`). The initramfs udhcpd hands
  out the same address, so M1 still works.
- **First boot stopped at "Update is Completed":** the image ships
  machine-id `uninitialized`, so systemd-firstboot waited on /dev/console
  (ttyMSM0, unreachable). Fixed with `systemd.firstboot=off` on the probe
  cmdline. omamobile-firstboot does that setup instead.
- **SSH dropped by ufw (`[UFW BLOCK] IN=usb0 … DPT=22`).** The
  postmarketOS kernel has no `xt_hl` or `ip6t_rt` (and warns about
  `limit`), so `ip6tables-restore` fails on `/etc/ufw/before6.rules` and
  every `ufw` command ends in `problem running ufw-init`. Omarchy's
  firewall leaf had already turned ufw on (IPv4 loaded), and firstboot's
  `services and firewall` step failed on its first `ufw` call, before the
  usb0 rule. That step is essential, so firstboot.conf stayed and the
  setup reran at every boot. Neither a `/run` mask of `ufw.service` nor an
  `ExecStartPost` ACCEPT helped: the commands, not the unit, enable ufw.
  Fixes: omamobile-firstboot 0.1.1 allows SSH on usb0 before Omarchy's
  leaves and drops to `IPV6=no` on a kernel without the matches; the card
  was repaired with `IPV6=no`. The real fix is a kernel with them.
- **No readable RTC:** the clock read 1970 in the initramfs (no `rtc0`)
  and 2026-10-18 (systemd's epoch) in Arch. gpg found the keyring key
  "created 8 days in the future", skipped it and the `pacman keyring`
  step failed. The root image now touches `/usr/lib/clock-epoch`; the
  card got one by hand.
- **GUI: GPU firmware was the blocker.** In Arch, msm DRM binds
  (`card0-DSI-1`, `panel_mdss_nt35596_ebbg`, `fb0: msmdrmfb`), but
  without `qcom/a530_pm4.fw` the Adreno 506 never starts. freedreno then
  fails (`get_param … -6`, `fd_pipe_new2: allocation failed`, `egl:
  failed to create dri2 screen`), and Hyprland aborts, both the user
  session and SDDM's greeter compositor, which takes `sddm-greeter-qt6`
  down with it. Every file needed is on the phone's own `system`
  partition (`/etc/firmware`: `a530_pm4.fw`, `a530_pfp.fw`,
  `a506_zap.mdt` and `.b00`-`.b02`). It was mounted `ro,noload` on the
  phone and copied there into `/usr/lib/firmware/updates/qcom/` (zap
  under `msm8953/xiaomi/markw/`), so no blob left the phone. After
  `systemctl restart sddm`: `loaded qcom/a530_pm4.fw from new location`,
  and Hyprland, Quickshell, squeekboard and Omarchy's lock screen came
  up. To do: a provisioning step that copies these (as
  `tools/phone-provision` does for cheetah), never the repo.
- **Touch: this unit has an Atmel maXTouch, not an FT5336.** lk2nd enables
  `touchscreen@38` (`edt,edt-ft5336`) from the panel name, and
  `edt_ft5x06` failed its probe. An I2C trace showed the ID read at 0x38
  NAKed (`ret=-6`) with the supplies on, and `i2cdetect -r 2` found only
  0x4a. The probe DTB now also enables `touchscreen@4a`:
  `atmel_mxt_ts 2-004a: Family: 166 Variant: 7 Firmware V1.0.AB`,
  2160x3840 range (libinput scales it to the panel). Typing on
  squeekboard works. A missing `maxtouch.cfg` is harmless: the chip
  keeps its config in NVM.
- **The USB link drops for a few seconds now and then** once the session
  runs (`dwc3-qcom … remote wakeup not configured`, then `Charger
  error`). Probably the Windows host suspending the idle NCM adapter;
  not yet confirmed. SSH with a retry works around it.
- **Recovery without buttons:** when Arch can't be reached, the probe
  with `fastboot --cmdline '<probe cmdline> omamobile.stay' boot` stays
  in the initramfs: SSH up, eMMC read-only, the card's root partition
  writable for repairs. From there, `reboot-to bootloader` reached stock
  fastboot. A boot dead-man (`multi-user.target` JobTimeout 60 min,
  reboot to the bootloader) now covers a hung Arch boot.
- **Forced restart:** Volume Down + Power for 30-40 s when Arch hangs and
  SSH is gone.

## 2026-10-27: M1 first light, kernel and SSH from RAM (7.1.3-msm8953)

- **Stock state (read-only, adb then fastboot).** Android 6.0.1,
  `verifiedbootstate=orange`; `fastboot oem device-info` reports
  unlocked and critical unlocked. `fastboot getvar unlocked` answers
  empty on this aboot, so the runbook uses `oem device-info`.
- **lk2nd 23.1 RAM-booted** (`fastboot boot`, 360 KiB): `product:
  lk2nd-msm8953`, log `Detected device: Xiaomi Redmi 4 Prime (markw)
  (compatible: xiaomi,markw)`. The cmdline from aboot names the panel
  `qcom,mdss_dsi_nt35596_ebbg_1080p_video`, so this unit is the NT35596
  EBBG variant. lk2nd then reports `Invalid boot image header` and stays
  in fastboot: expected, nothing follows lk2nd on the boot partition
  because it was never flashed. Two `Command timeout error` lines early
  in its log are not explained yet.
- **Probe RAM-booted from lk2nd** (`probe-m1/boot.img`, 17 MiB): the
  Windows 11 host bound the NCM function with its in-box `UsbNcm` driver
  and had `172.16.42.2` about 4 s after `Booting`; the ACM port appeared
  as a COM port; `ssh root@172.16.42.1` worked.
- **Guard:** `mmcblk0`, `mmcblk0boot0/1` and all 49 partitions `ro=1`.
  eMMC HS400, 29.1 GiB; `mmcblk0rpmb` present as a chardev only. No
  microSD inserted (mmc1 host probed, no card).
- **Health:** no oops or panic, pstore empty, UDC `configured`, 8 CPUs,
  MemTotal 2.87 GB (3 GB variant), CPU and GPU zones at 29-31 °C.
  Known MSM8953 messages: `psci: [Firmware Bug]: failed to set PC mode:
  -1`, `cpu cpu0: Failed to set OPP config`.
- **Charger:** `qcom-smbchg … Charger error` at 8.3 s. The USB supply
  reads `online=1` but the battery `Discharging` (capacity 94, 4.23 V,
  health Good) on a laptop port. Charging is M6 work; keep sessions short
  until it is understood.
- **Display:** the screen goes dark once the kernel takes over. Expected:
  the probe carries no display driver (`/sys/class/drm` and `/proc/fb`
  empty), and unused clocks and regulators turn off.
- **Return path:** `reboot-to bootloader` (with `qcom-pon` loaded) reached
  stock fastboot within 2 s; lk2nd is gone, as it lived in RAM only.
  Nothing was written to the phone in this session.
