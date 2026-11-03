<!-- SPDX-License-Identifier: MIT -->
# markw: USB OTG host for flashing an ESP32 (runbook)

Goal (PROGRESS.md, "Target lanjutan"): flash and verify firmware on an ESP
board from the phone through an OTG adapter, read its UART, and get the
laptop's USB gadget link back afterwards.

Owner's hardware: a NodeMCU ESP-32S (ESP32-WROOM) and a 6-pin "USB TO TTL"
adapter with a CH340G (SOIC-16, 12 MHz crystal; pins 5V, VCC, 3V3, TXD, RXD,
GND). The adapter has no DTR/RTS, so the ESP32 enters its ROM loader by hand
(hold BOOT, tap EN, release BOOT).

## What is in place (2026-10-28, 7.1.3-msm8953)

- **Role switching is the kernel's own.** `qcom-smbchg` reads the ID pin
  (`smbchg_otg_is_present`), switches DWC3 through its `usb-role-switch` to
  host for an OTG adapter and to device for the laptop, and turns OTG VBUS on
  in host mode while no external power comes in (`smbchg_otg_switch`). The
  probe used to force `dr_mode = "peripheral"` and drop the role switch (M1,
  as flame); `tools/build-markw-probe --usb-role otg` keeps the kernel's
  wiring, still starting as peripheral (`role-switch-default-mode`).
  Built: `~/android/markw/probe-m4-otg` (`dr_mode` unset, role switch yes,
  default peripheral, WCNSS okay). `probe-m3` stays the rollback.
- **CH340 and PL2303 drivers.** The postmarketOS kernel has `cp210x`,
  `ftdi_sio` and `cdc_acm` but not `ch341` or `pl2303`. Both were built from
  `msm8953-mainline/linux` `v7.1.3-r0` with the phone's own
  `/proc/config.gz` (clang, `pahole` for `DEBUG_INFO_BTF_MODULES`, which
  sizes `struct module`; without it the kernel refused them) and installed
  in `/lib/modules/7.1.3-msm8953/updates/`. They load (unsigned: the kernel
  is tainted, `MODULE_SIG_FORCE` is off). A kernel of our own replaces them.
- **Userspace.** `esptool` 5.5.0, `picocom` 3.1 and `python-pyserial` from
  Arch Linux ARM `extra`; `<user>` is in `uucp`. pacman needed
  `--disable-sandbox` (owner's go): this kernel has no Landlock, so pacman 7
  can't sandbox its downloader and every download fails. Arduino:
  `arduino-cli` 1.5.1 (`extra`) with Espressif's `esp32:esp32` core for
  `<user>` (its index URL in `~/.arduino15`; the core ships linux-arm64
  Xtensa toolchains).
- **A second link.** SSH on `wlan0` from `<lan>/24` only (ufw rule
  "omamobile ssh over home wifi"; key login only), host key pinned on the
  laptop. With the cable out for the ESP, the phone stays reachable at its
  Wi-Fi address.

## Runbook

Every step is the owner's call. Stop at the first failed Pass and roll back.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Read-only: Wi-Fi SSH answers (`ssh -o UserKnownHostsFile=~/.ssh/known_hosts_markw root@<lan-ip> true`), battery above 50 % | both | either fails | — | none |
| 1 | Restart into the OTG probe: `tools/markw-debug -y fastboot`, then `tools/markw-debug --probe ~/android/markw/probe-m4-otg/boot.img -y boot` (laptop cable in) | Arch up; USB SSH answers; `/sys/class/usb_role/*/role` = `device`; extcon `USB=1 USB-HOST=0` | no USB SSH within 3 min (check Wi-Fi SSH first) | `tools/markw-debug -y fastboot`, then boot `probe-m3`; hung: hold Volume Down + Power 30-40 s (MIUI) | low |
| 2 | Unplug the laptop, wait 10 s, plug it back (gadget re-binds after a role change) | USB SSH back within 30 s | not back in 60 s | Wi-Fi SSH: `systemctl restart systemd-networkd`; else step 1's rollback | low |
| 3 | Start a log over Wi-Fi (`dmesg -w`), unplug the laptop, plug the OTG adapter with nothing on it | role `host`, extcon `USB-HOST=1`, `otg-vbus` enabled, an xHCI root hub in `lsusb` | no role change, or any smbchg/dwc3 error | unplug the adapter; laptop cable back (role `device`) | low |
| 4 | CH340G alone on the OTG adapter (jumper on 3V3, nothing wired) | `ch341-uart converter now attached to ttyUSB0`; adapter LED on | no `ttyUSB0`; VBUS drops; phone reboots | unplug | low |
| 5 | Wire the ESP32: adapter TXD to RX0 (GPIO3), RXD to TX0 (GPIO1), GND to GND, 5V to 5V. Hold BOOT, tap EN, release BOOT. `esptool --port /dev/ttyUSB0 --baud 115200 chip-id` (read-only) | chip ESP32, a MAC (don't paste it anywhere) | no sync after two tries (check TX/RX crossing, BOOT sequence) | unplug | low |
| 6 | Flash a test firmware: MicroPython for ESP32 (micropython.org, generic ESP32), `esptool --port /dev/ttyUSB0 --baud 115200 erase-flash`, then `write-flash 0x1000 <file>.bin`, BOOT sequence before each | `Hash of data verified` | any write error | re-run the same step; the ESP's ROM loader can't be bricked by this | low (ESP only) |
| 7 | UART: tap EN, `picocom -b 115200 /dev/ttyUSB0`, then `print("hello from markw")` at the REPL (exit: Ctrl-A Ctrl-X) | MicroPython banner and the echo | nothing after EN | check RX/TX; unplug | none |
| 7b | Arduino: as `<user>`, `arduino-cli compile --fqbn esp32:esp32:esp32 <sketch>` (a blink plus `Serial.println`), BOOT sequence, `arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 <sketch>`, then picocom as step 7 | `Hash of data verified`; the sketch's lines at 115200 | compile or upload error | flash MicroPython again (step 6) if wanted | low (ESP only) |
| 8 | Unplug the OTG adapter, plug the laptop | role `device`, USB SSH back | not back in 60 s | as step 2 | low |

Results go here and in NOTES.md, with the date and `uname -r`.

## Results

**2026-10-28, 7.1.3-msm8953, `probe-m4-otg`:**

- **Step 0: pass.** Wi-Fi SSH answered; battery at 88 %, charging.
- **Step 1: pass** (`./DEBUGING_RUN.sh --otg --restart`). The role was
  `device`, extcon read `USB=1 USB-HOST=0`, DWC3 was in device mode, and
  the gadget was bound.
- **Step 2: pass.** USB SSH came back about 5 s after the cable was plugged
  in again.
- **Steps 3 and 4: pass** (the owner plugged the adapter with the CH340G
  already on it):
  - the role went to `host`, extcon read `USB=0 USB-HOST=1`, and
    `otg-vbus` was enabled;
  - `1a86:7523` enumerated and `ch341` autoloaded as `ttyUSB0`.
- **Step 5: not passed.**
  - The ESP32 was in a boot loop: `rst:0x10 (RTCWDT_RTC_RESET),
    boot:0x13 (SPI_FAST_FLASH_BOOT)`, read clearly over the adapter. So the
    ESP-to-phone direction works.
  - With BOOT held, esptool synced once and then failed at "Detecting chip
    type". After that the chip answered nothing.
  - Suspects: the NodeMCU's own, unpowered USB-UART loading RX0, or the
    adapter's jumper not on 3V3.
  - Next try: the board's own USB port through the OTG adapter (CP2102 or
    CH340C; both drivers are on the phone), which also gives auto-reset.
- **After the adapter was unplugged** (the kernel log over Wi-Fi shows
  `ch341` disconnected and both xHCI buses deregistered cleanly), Wi-Fi SSH
  dropped. The phone then answered nothing: no Wi-Fi, USB, adb or fastboot.
  Not yet known whether it hung on leaving host mode or only lost Wi-Fi.
  Check `journalctl -b -1` after the next boot.
- **The hang (2026-10-29, read from boot -1's journal).**
  - The boot didn't hang at the unplug: it ran on for two hours. It hung at
    7274 s, in a burst of fast role changes while cables were swapped:
    host up (7272.69), host removed (7273.65), `usb0` gadget back (7273.79),
    host up again 0.5 s later (7274.28).
  - The log ends at `hub 2-0:1.0: 1 port detected`, with no oops. The
    owner saw a frozen lock screen until a held power key.
  - Earlier bursts (7037-7038 s, 7239 s) survived.
  - Reading: `qcom-smbchg` acts on every ID-pin/VBUS change at once
    (`smbchg_detect_work` sets the role directly, with no debounce), so a
    plug that bounces flips DWC3 between host and device within
    milliseconds. One switch landing mid-teardown hangs the bus, most
    likely a register access with the controller's clocks or PHY off: no
    panic, nothing logged.
  - No lockup detector and no watchdog driver in this kernel, so the phone
    stays frozen. `panic=10` is set, so it wasn't a panic.
  - `qcom-smbchg` and the DWC3 core are built in, so the fix needs our own
    kernel: debounce the role decision in `smbchg_detect_work` (act only
    on a state stable for a few hundred milliseconds), plus `QCOM_WDT` and
    the lockup and hung-task detectors.
  - Until then, use `probe-m4-otg` only for OTG sessions (`probe-m3`
    stays the default), swap cables in one firm motion, and wait about
    5 s between unplug and plug.

**2026-11-03, 7.1.3-msm8953-oma3 (`probe-m9k-oma3`, role-change debounce
patch 0001), the board's own USB port through the OTG adapter, from Flash
(omamobile-flash 0.1.4).** Unattended by the laptop: the cable was out
and Wi-Fi SSH was off, so there is no kernel log, only the owner's photos.

- **Plug: pass.** No hang. The board was powered from the phone (its LED
  on), and Flash listed `ttyUSB0 · CP210x` by itself.
- **Upload: not passed.** The blink upload (esptool 5.4.0 at PlatformIO's
  default 460800 baud) connected to the chip (ESP32-D0WD-V3, revision
  3.1) and read its eFuses. Then it warned "Detected crystal freq
  15.55 MHz is quite different to normalized freq 26 MHz", uploaded the
  stub and failed with "Failed to start stub flasher. There was no
  response". The 2026-10-28 CH340G run also synced once and then lost the
  chip. Suspects: the board browning out on the phone's OTG VBUS, or the
  speed. Next try: `upload_speed = 115200`, then a powered OTG hub.
- **Flash froze** (Hyprland's "Application Not Responding"; its Terminate
  did nothing) while the board stayed plugged in. Its log replaced the
  whole line list for every line, and a board in a reset loop prints fast.
  Fixed in omamobile-flash 0.1.6 (batched appends to a ListModel), not
  yet installed. The battery read 89 % at 05:37, 88 % at 05:39 and 83 % at
  05:44 (the percentage is an estimate), with the board on OTG power.
- **After unplug: the laptop link did not come back.** The owner unplugged
  the board and plugged the laptop in. Windows showed "USB device not
  recognized" (Device Manager: "Unknown USB Device (Device Descriptor
  Request Failed)"), so something pulled D+ up but the controller never
  answered enumeration. There was no USB network adapter, and the phone
  answered no ping, adb or fastboot. Either the phone hung or DWC3 was left
  half switched between host and device; the owner reported it stuck "as
  before".
- **The previous boot's journal (read after a held power key, MIUI and
  fastboot back to oma3): no hang.** The phone ran on and shut down
  cleanly from the held key (8239 s). Two separate faults:
  - **Out of memory.** `cp210x` attached at 7146 s, and the board
    re-enumerated once 0.3 s later (a reset). Flash, the board's quickshell
    process, grew to 1.87 GB anonymous RSS. The 1.4 GB zram swap filled,
    and at 7637 s the kernel OOM killer killed it, the only OOM kill of the
    boot. The phone was slow and swapping before that: that was the
    unresponsive window and the fast battery drain. omamobile-flash 0.1.6
    caps the log in a ListModel instead of building a new array per line.
  - **The gadget link died after leaving host mode.** At unplug (7615.6 s)
    `USB role host -> none` came 0.5 s later (the debounce), the xHCI buses
    deregistered, and xHCI logged "host not responding to stop endpoint
    command" (7620.9 s). The gadget came back by itself: `usb0` gained
    carrier at 7639.33 s. Then `USB role none -> device` at 7640.26 s, and
    `usb0` lost carrier at 7640.28 s, for good. A replug at 8110-8113 s
    (`device -> none -> device`) brought nothing back either: that was the
    laptop's "Device Descriptor Request Failed". So it is the late
    `none -> device` switch, landing on a gadget that is already up, that
    leaves DWC3's device side dead. Whether the memory pressure (a
    20 s-late role decision) made it worse is not known.
- Next: OTG only with Wi-Fi SSH on and `dmesg -w` streamed to the laptop
  (BRINGUP-KERNEL.md step 5), and Flash 0.1.6 first. Look at what
  `qcom-smbchg`'s `none -> device` does to a DWC3 that already runs the
  gadget (a role set that should be a no-op); `omamobile-usb-rescue`-style
  recovery (rebinding the UDC) can be tried over Wi-Fi when it happens.
