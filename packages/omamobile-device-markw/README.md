# omamobile-device-markw

Omarchy Mobile's first userspace package for the Xiaomi Redmi 4 Prime (codename markw, Snapdragon 625 / MSM8953). It keeps desktop tools away from the eMMC, holds the USB address, gives pacman the `[omamobile]` repository, and tells the shell the panel's output scale. It does not start a remote processor (modem, WCNSS, LPASS), the charger, the GPU firmware, or a camera.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Makes every eMMC node and the microSD card's whole-disk node inaccessible and hidden from desktop tools, matched by card type (`MMC`, `SD`) rather than by `mmcblk` number. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. Same file as the Pixel packages |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press opens Omarchy's menu instead of powering off. Same drop-in as the Pixel 7 Pro |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-markw.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason; `bootloader` reaches fastboot through the PM8953 PON. Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/markw/device.conf`; `MONITOR_SCALE` is read by `omamobile-setup-user` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: Wi-Fi/Bluetooth (WCNSS firmware), the GPU zap firmware, audio, the charger and sensors. Each comes with its own runbook in `device/markw/ENGINEERING-PLAN.md`.
