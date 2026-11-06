<!-- SPDX-License-Identifier: MIT -->
# markw: charger and fuel gauge (runbook)

Status: the charger stops in an error state (batt-ov) near 4.37 V and
never restarts, so the battery stays at about 90 % (2026-11-02,
`7.1.3-msm8953-oma3`). Nothing has been written to the charger. Next:
C1-C3 below; C3 is the first write and the owner's go.

## Facts

- The charger is the PMI8950's SMBCHG (`qcom,pmi8950-smbchg`, driver
  `qcom-smbchg`, registers at 0x1000 on the PMIC's USID 2); the battery
  node is `simple-battery`: 4000 mAh, 3.4-4.38 V, 1 A.
- Registers read through the kernel's regmap
  (`/sys/kernel/debug/regmap/0-02/registers`):
  - float voltage `0x10f4` = 0x2d, 4.38 V (very-high range, 4360 mV +
    20 mV a step), as the battery node asks;
  - fast-charge current `0x10f2` = 0x0b, 1000 mA;
  - `CHGR_STS` `0x100e` = 0xa1: charge type 0, not charging;
  - `RT_STS` `0x1010` = 0x01: chg-error asserted.
- On the laptop's port (SDP, input limit 500 mA, USBIN about 4.8-5.0 V) the
  battery sat at 92 % and 4.23 V for hours with a current of under 1 mA
  (`current_now` -762, reported as microamps): the phone ran from USB and
  the battery neither charged nor drained. The driver still said
  "Discharging".
- In 19 h of uptime: chg-taper-thr 118 times, chg-p2f-thr 23, chg-error 11,
  chg-tcc-thr (charge done) and chg-rechg-thr never. The errors came 2-6 h
  apart; the log also shows USB role changes from a loose cable.
- Disproven 2026-11-02 (see Results): the charge safety timer. 500 mA minus the phone's own
  load leaves little to charge with, so charging never terminates and the
  timer runs out. Battery temperature (about 25 °C) and voltage are normal.

## Logger

`tools/markw-charge-log` records once a minute, on the phone and detached
(the cable may come out): capacity, voltage, current, status, USB type and
input limit, USBIN, `CHGR_STS` and `RT_STS`, plus every charger line from
the kernel log. Read-only.

```sh
tools/phone-ssh 'install -m755 /dev/stdin /usr/local/bin/markw-charge-log' < tools/markw-charge-log
tools/phone-ssh 'systemd-run --unit=x-charge-log --collect /usr/local/bin/markw-charge-log 24'
tools/phone-ssh 'tail /var/tmp/charge-log.csv; cat /var/tmp/charge-kmsg.log'
```

## Runbook

Each step is the owner's; the logger runs through all of them. Only
observation: nothing writes to the charger.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 1 | Unplug the laptop cable for 10 s, plug it back | chg-error clears (`RT_STS` bit 0 low), charge type fast or taper, current positive, capacity climbs | the battery heats past 40 °C, or the phone doesn't come back on USB (`omamobile-usb-rescue`) | unplug | low |
| 2 | Charge from a wall adapter for an hour | USB type DCP, input limit above 500 mA, charge type fast then taper, charge done (tcc) near 100 % | as step 1 | unplug | low |
| 3 | Leave it on the laptop overnight | when chg-error comes back, the log shows how long it charged first | — | stop the logger | none |

## Results

- 2026-11-02 09:37 UTC: logger started (`x-charge-log`, 24 h). First line:
  92 %, 4225 mV, SDP, 500 mA, USBIN 4828 mV, `CHGR_STS` a1, `RT_STS` 01.

- 2026-11-02 12:10 UTC, `7.1.3-msm8953-oma3`, **step 1 (replug)**: unplugged,
  the phone ran from the battery (3904 mV, -409 mA as reported, so negative
  is discharge) and chg-error cleared (`RT_STS` 00). Plugged back, USB came
  back as SDP and chg-error returned **12 s later**: not a safety timer.
- Read-only registers right after: `BAT_IF RT_STS` 0x1210 = 0x10, bit 4,
  **batt-ov**, at a battery voltage of 4.21-4.27 V; `BAT_IF CMD_CHG` 0x00
  (charging enabled, the driver's active-low `CHG_EN`); `USB RT_STS` 0x04
  (source present); `MISC RT_STS` 0x01 (power-ok); float voltage 0x2d,
  4380 mV by the driver's table, as the markw DTS asks. Battery 20.7 °C.
- Five minutes later the charger was charging on its own: 4368 mV, +123 mA,
  "Charging", charge type taper (`CHGR_STS` 0x87), batt-ov clear.
- Reading, not proven: the charger tapers to 4.38 V, batt-ov trips at or
  just above it, the error latches and charging stops without a
  termination (tcc never fired), the battery relaxes to about 4.21 V and
  nothing restarts it, while the driver reports "Discharging". The logger
  now records `BAT_IF` and `USB` RT_STS too, every 2 s for a minute after a
  plug change, to see which bit comes first.
- 12:14-12:40 UTC, the new logger: at 12:14:46 taper at 4368 mV, +123 mA,
  batt-ov clear; chg-error at 12:15 (uptime 6431 s); from 12:17 on, 4221
  falling to 4202 mV, about 0 mA, `CHGR_STS` a1, chg-error and **batt-ov
  still set at 4.20 V**. So batt-ov stays asserted 180 mV below the float
  voltage: either it latches until the charger is re-enabled, or the
  charger's battery-voltage comparator reads well above what the fuel
  gauge reports. Telling the two apart, or clearing the state, needs a
  write to the charger: the owner's call, not yet done.

## What the driver leaves alone, and the next runbook (2026-11-03)

From the oma3 source (`drivers/power/supply/qcom-smbchg.c`):

- (Corrected 2026-11-06: `smbchg_init()` does write them.) `CHGR_CFG1`
  0x10fb selects termination and recharge on the fuel gauge, `CHGR_CFG2`
  0x10fc enables auto-recharge and current termination, and `CHGR_CFG`
  0x10ff sets the recharge threshold to 100 mV below float.
- `batt-ov` has no handler, and `chg-error` only logs and notifies. So
  nothing in Linux restarts charging after a batt-ov.
- With a 200 mV threshold, recharge would start at about 4.18 V. On the
  laptop the phone runs from USB and the battery holds 4.20 V, so it would
  never get there: that alone would explain a battery that sits at about
  90 % for hours.
- The driver's one way to restart the charge path is the USB supply's
  writable `online` (`smbchg_usb_enable`, the `USBIN_SUSPEND` bit): 0
  suspends the input, 1 resumes it. The data link stays up (VBUS is
  still there). A replug did the same on 2026-11-02 and cleared
  chg-error.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| C1 | Read-only, while stuck (chg-error and batt-ov set, about 4.20 V): `grep -E '^(10f4\|10f5\|10f7\|10f9\|10fb\|10fc\|10fd\|10ff\|1210\|1242):' /sys/kernel/debug/regmap/0-02/registers` | the values, decoded here: recharge source and threshold, auto-recharge on or off, termination on or off | the file is missing (find the SMBCHG regmap first; read nothing else) | — | none |
| C2 | Read-only: charge from a wall adapter for an hour, logger running | DCP, input limit above 500 mA; whether tcc (charge done) fires near 100 %, or batt-ov comes first | battery past 40 °C | unplug | low |
| C3 | **Owner's go (a write through the driver).** While stuck, as in C1: `echo 0 > /sys/class/power_supply/<usb supply>/online`, 10 s, `echo 1 >` the same; watch the logger | chg-error clears, charging resumes (taper, current positive); then whether batt-ov trips again and at what voltage | batt-ov or chg-error set right after the resume with the battery under 4.30 V (a comparator offset, not a latch); battery past 40 °C | `echo 1 >` `online` (the default); unplug and replug | low |

C1 says whether auto-recharge is on at all; C2 whether a stronger
charger reaches termination before batt-ov; C3 whether batt-ov latches
until the charge path restarts. Only then a fix: likely a driver change
that sets recharge and termination explicitly (as the battery node
asks) and restarts the charge path after a batt-ov once the voltage
has dropped, with a patch in `device/markw/kernel/patches`.

### Results (2026-11-06)

- **C1** (`7.1.3-msm8953-oma3`, charging in taper): `CHGR_CFG1` 0x47
  (termination and recharge on the fuel gauge), `CHGR_CFG2` 0x51
  (inhibit on, auto-recharge on, current termination on), `CHGR_CFG`
  0x08 (100 mV), `TCC_CFG` 0x05 (300 mA). The battery took 147 mA at
  4.368 V, below the termination current, and the charger kept going:
  `pmi8994_fg` never sets the fuel gauge up for termination, so with
  those sources it never fires. Kernel patch 0006 (`-oma4`) moves both
  to the charger's analog sensing.
- **oma4 boot** (`probe-m11-oma4`, owner's go): `CHGR_CFG1` 0x41 as
  meant. Still a chg-error with batt-ov at 65 s of uptime, the battery
  at 4.19 V afterwards.
- **C3** (owner's go), stuck as in C1: `online` 0 cleared chg-error and
  batt-ov at once (the battery took over, about 60 mA at 4.10 V). `online`
  1: charging resumed and, new with oma4, terminated: `Full`, the tcc bit
  set. It then cycled every few seconds between `Full` and recharging,
  the battery between 4.28 and 4.37 V: the 100 mV recharge threshold is
  4.28 V, where the battery relaxes to. 1 s after a termination at
  354 s, batt-ov latched again and charging stopped at 4.19 V.
- So batt-ov trips near the top of a charge (4.35-4.37 V by the fuel
  gauge, and right after termination), below the 4.38 V float the
  battery node asks for, and nothing clears it but a charge path
  restart. Next, one change per boot, owner's go each: C4, float 4.35 V
  (`voltage-max-design-microvolt`), to see whether batt-ov stops; then a
  200 mV recharge threshold against the cycling; then, if batt-ov still
  comes, a driver handler that restarts the charge path after it.
