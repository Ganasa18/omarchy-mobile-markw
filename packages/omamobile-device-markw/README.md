# omamobile-device-markw

Omarchy Mobile's first userspace package for the Xiaomi Redmi 4 Prime (codename markw, Snapdragon 625 / MSM8953). It keeps desktop tools away from the eMMC, holds the USB address, gives pacman the `[omamobile]` repository, and tells the shell the panel's output scale. Since 0.1.21 it boots the modem idle at startup, on RAM copies of its NV and with mobile data off: a modem that never boots never lets RPM shut XO down, so s2idle can't reach VDD minimization (`device/markw/BRINGUP-SUSPEND.md`, runbooks N-S). Since 0.1.22 it starts ModemManager after the modem, so the quick settings tile can turn mobile data on, and a sleep hook takes `rmnet_ipa0` down before a suspend when no data link is on it (runbooks U and V). It does not start the charger, the GPU firmware, mobile data (the tile does), or a camera.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Makes every eMMC node and the microSD card's whole-disk node inaccessible and hidden from desktop tools, matched by card type (`MMC`, `SD`) rather than by `mmcblk` number. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. Same file as the Pixel packages |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press opens Omarchy's menu instead of powering off. Same drop-in as the Pixel 7 Pro |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-markw.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason; `bootloader` reaches fastboot through the PM8953 PON. Same bytes as the Pixel 7 Pro package; the test checks |
| `vendor/omamobile-markw-modem`, `vendor/systemd/system/omamobile-markw-modem.service` | `/usr/lib/omamobile`, `/usr/lib/systemd/system` (enabled) | Loads `qcom_q6v5_mss` and starts the modem's remoteproc after `omamobile-markw-rmtfs.service` has copied the NV to RAM; leaves a running modem alone; skipped without rmtfs. ModemManager isn't started |
| `vendor/modprobe.d/omamobile-markw-modem.conf` | `/usr/lib/modprobe.d` | Keeps `qcom_q6v5_mss` from autoloading before rmtfs is ready |
| `vendor/systemd/system/ModemManager.service.d/10-omamobile-markw.conf` | `/usr/lib/systemd/system/ModemManager.service.d` (ModemManager enabled) | ModemManager at boot, after the modem unit. It connects nothing: NetworkManager's gsm profile does, with its autoconnect following the tile |
| `vendor/omamobile-markw-sleep` | `/usr/lib/systemd/system-sleep/omamobile-markw` | Before a suspend, takes `rmnet_ipa0` down when no data link (`qmapmux0.0`) is on it. ModemManager leaves it up after a disconnect, and while it is up ipa2-lite keeps the IPA clock on, so XO stays on: about 30-50 mA asleep instead of about 11 mA |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/markw/device.conf`; `MONITOR_SCALE` is read by `omamobile-setup-user` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: Wi-Fi/Bluetooth (WCNSS firmware), the GPU zap firmware, audio, the charger and sensors. Each comes with its own runbook in `device/markw/ENGINEERING-PLAN.md`.
