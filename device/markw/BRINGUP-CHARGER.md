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
- **C4** (`7.1.3-msm8953-oma5`, float 4.35 V, `FV_CFG` 0x2b; owner's
  go): batt-ov latched at 92 s of uptime, in taper at about 4.28-4.30 V,
  and charging stopped at 4.19 V as before. So batt-ov follows the
  float voltage; a lower float doesn't help, and oma6 floats at 4.38 V
  again.
- **The cause, from Qualcomm's downstream `qpnp-smbcharger.c`**
  (LineageOS `android_kernel_xiaomi_msm8953`, lineage-18.1, GPL):
  `CHGR_CFG2` bit 4 is `CHG_BAT_OV_ECC`, the "battery OV disables
  charging" feature. Downstream sets `SMBCHG_BATT_OV_WA` for PMI8950 (and
  PMI8937, PMI8940, PMI8994) and, in `batt_ov_wa_check()` at init, clears
  that bit. If `BAT_IF RT_STS` shows an overvoltage, it then disables
  charging, waits 200 ms and enables it again. Here `CHGR_CFG2` reads
  0x51: the bit is set, and the mainline driver never touches it. Kernel
  patch 0008 (`-oma6`) clears it and restarts charging the same way.
- **oma6 result** (`7.1.3-msm8953-oma6`, 2026-11-06, from a laptop port:
  SDP, 500 mA input): `CHGR_CFG2` reads 0x41 (bit 4 clear), `BAT_IF
  RT_STS` 0x00, and no chg-error in a 20 min log. Charging went past
  the old stop at about 90 %: 89 % at 4.36 V in taper, then `Full` (tcc)
  at 94 % after 9 min, a recharge, and up a percent per cycle to 97 %
  at 18 min. batt-ov never latched. So patch 0008 is the fix for the
  stop at 90 %.
- **Early termination from a USB port.** The battery node has no
  `charge-term-current-microamp`, so `TCC_CFG` keeps its reset value 5,
  300 mA, and from a 500 mA port the taper current (170-200 mA) is below
  it at once: `Full` at 94 %, recharge at 4.28 V, and so on. Kernel
  patch 0009 sets 150 mA (C/27 for 4000 mAh). It changes only the DTB:
  `probe-m12-oma6-iterm` is oma6's kernel and modules with that one
  property added (`fdtput`; `dtc` diff of the two DTBs shows only that
  line). Next, owner's go: boot it, expect `TCC_CFG` & 7 = 2 and one
  taper to 100 % without the cycling.

## Fuel gauge reading (2026-11-15, oma12 candidate)

Why: the gauge's capacity is not a usable measure. After an overnight
suspend test it read 69 % at the replug and 77 % about 15 minutes later on
a laptop port (about 400 mA, so roughly 100 mAh of the 4000 mAh battery,
2.5 points); the night's 99 % -> 69 % therefore says little about the
sleep current (BRINGUP-SUSPEND.md, 2026-11-15). current_now agrees with
what the phone does (about 50 mA screen-off awake, 300 mA screen on,
400 mA charging) but has not been checked against an external meter.

Facts from the source:

- Mainline `pmi8994_fg` reports capacity from the gauge's monotonic SOC
  register (0x09) and reads only temperature, voltage and current from
  the gauge's SRAM. It never loads a battery profile, never writes the
  nominal capacity and never reads the coulomb counter.
- The downstream driver (Xiaomi's GPL `markw-m-oss` kernel,
  `drivers/power/qpnp-fg.c`) loads a 128-byte profile into SRAM at 0x4c0
  when the integrity bit at 0x53c is clear or the loaded profile differs,
  picking it by battery ID. Its SRAM table matches the addresses mainline
  already uses (BATT_TEMP 0x550, voltage and current at 0x5cc).
- markw has three profiles in that tree (`MARKW-qrd-{Default,Coslight,
  Feimaotui}-4v4-4000mah.dtsi`, 4.4 V, 4000 mAh), chosen by a 1, 100 or
  50 kOhm ID resistor. The profile data is GPL source; it is not copied
  here until a step needs it.
- SRAM is volatile but survives a reboot while the battery is connected,
  so the profile MIUI loaded may still be in the gauge when Linux boots.
  Whether it is, is the first thing to learn.

Patch 0014 (`power: supply: pmi8994_fg: report the coulomb counter and
gauge state`) is read-only: `charge_counter` (CC_CHARGE 0x570 scaled by
the nominal capacity at 0x4f4, uAh), `voltage_ocv` (0x588), and
`/sys/kernel/debug/pmi8994_fg/info` with the profile integrity flag, the
battery ID, the gauge's own SOC, the nominal capacity, the counter and the
first 32 bytes of the loaded profile. Nothing is written to the gauge.
Release `7.1.3-msm8953-oma12`; the probe is oma11's watchdog probe with
only the kernel and its seven initramfs modules replaced (same DTB, same
command line; the repack tool reproduces oma11's image byte for byte when
given oma11's own modules).

Offline checks (2026-11-15): `checkpatch --strict --no-signoff` 0/0/0;
the driver with `W=1`: no compiler warning, and 109 kernel-doc warnings
before and after (all from the file's existing `@brief` comments). The
kernel built with `tools/build-markw-kernel` (Alpine clang 20.1.8; oma11's
config came from an Ubuntu clang 20.1.8 build, the only config difference
apart from the release and OpenSSL's ML-DSA options). The markw DTB is
byte-identical to oma11's. Probe `out/markw/probe-oma12-fg/boot.img`:
oma11 watchdog probe's header, command line and DTB, oma12's Image.gz and
seven initramfs modules (vermagic checked); unpacked again, every part
matches. Image and modules tarball checksums are in the probe's
`SHA256SUMS` and next to the tarball (local, not committed).

### Runbook G (each step after the owner's go)

| Step | Command | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| G0 | `tools/phone-ssh --fresh 'uname -r; cat /proc/sys/kernel/random/boot_id'` | oma11, phone answers | no SSH | none | none |
| G1 | `tools/phone-ssh --fresh 'tar -C /usr/lib/modules --zstd -xf - && depmod 7.1.3-msm8953-oma12' < out/markw/modules-7.1.3-msm8953-oma12.tar.zst` | new release directory, oma11's kept | extraction or depmod error | remove only `/usr/lib/modules/7.1.3-msm8953-oma12` | low |
| G2 | `./DEBUGING_RUN.sh --restart --probe "$PWD/out/markw/probe-oma12-fg/boot.img"` | fastboot, lk2nd, SSH within 3 min; `uname -r` is oma12 | no fresh SSH in 3 min | owner recovers physically; boot oma11's probe | medium |
| G3 | `tools/phone-ssh --fresh 'cat /proc/sys/kernel/tainted; dmesg | grep -iE "pmi8994|fg|oops|abort"; cat /sys/kernel/debug/pmi8994_fg/info; cd /sys/class/power_supply/qcom-battery; cat capacity voltage_now voltage_ocv current_now charge_counter'` | taint 0, no FG error, info prints; OCV near voltage_now at low current | an SRAM access error or timeout | reboot to oma11 | none |
| G4 | Sample `charge_counter` and `current_now` every 10 s for 10 min awake (screen off, cable out) | counter moves by about the integral of current_now | counter frozen, jumps, or moves the wrong way by much | none | none |
| G5 | Read `charge_counter` before and after a 300 s `rtcwake -m freeze` (watchdog feeder and dead-man as in BRINGUP-SUSPEND) | counter keeps moving during the sleep | as for any suspend gate | as for any suspend gate | medium |

G3 tells which way to go: an integrity bit set and a profile head matching
one of the three markw profiles means the gauge already runs on MIUI's
profile, and the jumps come from something else (no capacity learning, or
SOC recalculated at plug events). A clear bit, or a head matching none,
means the gauge runs on OTP defaults; loading a profile is then a write to
the gauge and a separate, gated step.

### Results (2026-11-15, `7.1.3-msm8953-oma12`)

- G0-G2 pass: oma12 modules installed next to oma11's (820 modules,
  depmod clean); `DEBUGING_RUN.sh --restart --probe …/probe-oma12-fg`
  went fastboot, lk2nd, probe, SSH; `uname -r` oma12. Taint 512, the
  documented DSI clock WARNs; no fuel gauge or SRAM error.
- G3: the gauge **runs on a markw profile**. `profile_integrity: 0x01
  (loaded)`, and the 32-byte profile head matches the Feimaotui profile
  (`MARKW-qrd-Feimaotui-4v4-4000mah.dtsi`) in every byte; the nominal
  capacity in SRAM is 4 203 000 uAh, the value in that profile's
  nominal-capacity word (0x106b). The Default and Coslight profiles
  differ from the fourth byte. So MIUI's profile survives in the gauge
  across the boot into Linux, and a profile load is not what's missing.
  At the same moment: capacity 95 %, the gauge's own `battery_soc` 92.25 %,
  voltage_now 4.013 V, voltage_ocv 4.272 V while charging.
- G4 pass (cable in, charging at about 158 mA): over 125 s the counter
  rose 5.4 mAh and the integral of current_now was 5.5 mAh. The counter
  tracks the current within about 2 % and in the same direction
  (charging raises it, as current_now is positive when charging). In the
  same two minutes capacity went 95 % -> 96 % for 0.13 % of the
  battery's charge: the reported percentage is the problem, not the
  gauge's measurement.
- Downstream exposes this register as `CHARGE_NOW_RAW` (a raw count to
  take differences of), not as remaining charge; read it that way.
- Next: G5, whether the counter keeps counting across a suspend. If it
  does, sleep drain is measurable from its difference, and a correct
  capacity can come from the counter between a full charge and empty
  instead of from the monotonic SOC.
