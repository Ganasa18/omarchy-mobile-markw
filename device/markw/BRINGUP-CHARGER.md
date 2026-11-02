<!-- SPDX-License-Identifier: MIT -->
# markw: charger and fuel gauge (runbook)

Status: the charger stops in an error state on the laptop's USB port, and
the driver reports the idle battery as "Discharging" (2026-11-02,
`7.1.3-msm8953-oma2`). Nothing has been written to the charger.

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
- Likely, not proven: the charge safety timer. 500 mA minus the phone's own
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
