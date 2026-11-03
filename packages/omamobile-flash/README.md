<!-- SPDX-License-Identifier: MIT -->
# omamobile-flash

Flash is a small PlatformIO front end for the phone: pick a project, an env
and a port, then build, upload, watch the serial port or clean. It is an
ordinary window, so Hyprland tiles it beside a terminal where the code is
written (an editor, or a coding agent).

```
Flash (quickshell -p /usr/share/omamobile-flash/shell.qml)
  ├─ omamobile-flash projects | dirs | sketch | envs | ports   (JSON for the window)
  ├─ omamobile-flash init DIR BOARD SPEED          (platformio.ini for a sketch)
  ├─ pio run -d DIR -e ENV [-t upload --upload-port PORT | -t clean]
  └─ omamobile-flash monitor PORT BAUD             (pyserial, line by line)
```

- **Projects** are folders under `~` (four levels deep) with a
  `platformio.ini` (`pio`) or an Arduino IDE sketch (`ino`), newest first,
  scanned again each time the list opens. **Browse folders** walks `~`
  (hidden folders left out) to choose any other folder. With no projects,
  the list offers to copy the blink example to `~/proyek/blink`.
- **An Arduino sketch** (a `.ino` and no `platformio.ini`) gets one from
  Flash before it builds: the board is guessed from arduino-cli's `build/`
  folder (else `esp32dev`, and can be changed) and the speed from its
  `Serial.begin()`. It builds the sketch where it is (`src_dir = .`, only
  the sketch's own sources and its `src/`), so the Arduino IDE still opens
  the folder. An existing `platformio.ini` is never replaced.
- **Env** lists the `[env:NAME]` sections, `default_envs` first; the monitor
  speed comes from `monitor_speed` (else 115200).
- **Port** lists `/dev/ttyUSB*` and `/dev/ttyACM*`, named by the adapter's
  USB vendor (CP210x, CH340, FTDI, ESP32 USB), and follows the cable.
- After an upload the Serial tab opens, so the board's first lines show.

PlatformIO Core itself goes into `~/.platformio/penv`, a Python virtualenv
from PyPI, as PlatformIO's own installer does: the window's PlatformIO row
(or `omamobile-flash setup`) installs it, and no system package changes.
A `pio` on PATH (Arch's `platformio-core`) is used when that is missing.
The first build of a platform downloads its toolchain into `~/.platformio`
(about 1-2 GB for espressif32) and is slow on the phone; later builds are
incremental. The ports are group `uucp`, which the installer's user is in.

## Use from a terminal

```sh
omamobile-flash                 # the window
omamobile-flash projects        # what the window lists
omamobile-flash dirs ~/esp      # what the folder browser shows
omamobile-flash sketch ~/esp/hello          # the sketch's .ino, board and speed
omamobile-flash init ~/esp/hello esp32dev   # its platformio.ini
omamobile-flash setup           # PlatformIO into ~/.platformio/penv
omamobile-flash status          # which pio, and its version
omamobile-flash monitor /dev/ttyUSB0 115200
```

The window is drawn in the Omarchy theme's text colour only
(`docs/design/dev-tools`).
