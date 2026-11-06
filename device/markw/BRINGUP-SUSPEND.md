<!-- SPDX-License-Identifier: MIT -->
# markw: suspend (runbook)

Status: s2idle works on oma2 and oma3 and auto-suspend steps 8-10 passed,
but an unattended auto-suspend on 2026-11-03 never resumed, so
auto-suspend stays off. Next: the staged long sleeps L0-L5 (attended),
then enable it and measure the gain (step 7).

## Why

With the screen off the phone stays fully awake: nothing ever suspends it,
so the battery drains as if in use, while MIUI drops into deep sleep. The
goal is a power-key "screen off" that suspends to idle and wakes on the
power key.

## Facts

- `/sys/power/mem_sleep` offers only `[s2idle]` (no PSCI system suspend).
- Wake-capable and enabled: the power key (`pm8941_pwrkey`), the PMIC RTC
  (`rtc-pm8xxx`, rtc0), DWC3 USB, the charger and the fuel gauge.
- The PMIC RTC reads 1979 and Linux can't set it (Qualcomm keeps the
  offset in the modem's storage). Relative alarms (`rtcwake -s`) still
  work.
- ramoops is active (1 MiB at `0x9ff00000`, console 512 KiB), but a crash
  reboots into MIUI from the eMMC, and the record was gone when the probe
  booted again: a hang inside suspend leaves no trace. Hence `pm_test`.

## First attempt (2026-11-01, oma1, `probe-m6-adsp`)

`systemd-run … rtcwake -m freeze -s 30` (Wi-Fi up, USB cable in, ADSP
off). The journal ends at rtcwake's "wakeup from freeze" line; USB and
Wi-Fi never came back; the phone rebooted into MIUI by itself within about
90 s. `suspend_stats/success` was 0: this was the first suspend ever on
this port. pstore was empty afterwards.

## Build (laptop only)

```sh
tools/build-markw-kernel --config markw-config.gz \
  --source linux-v7.1.3-r0.tar.gz --out ~/android/markw/kernel-oma2
K=~/android/markw/kernel-oma2
tools/build-markw-probe --kernel $K/Image.gz \
  --dtb $K/dtbs/qcom/msm8953-xiaomi-markw.dtb \
  --modules $K/lib/modules/7.1.3-msm8953-oma2 \
  --ssh-key ~/.ssh/id_ed25519.pub --mkbootimg ~/mkbootimg/mkbootimg.py \
  --root-uuid <ROOT-UUID> --usb-role otg --adsp \
  --out ~/android/markw/probe-m7-oma2
```

Same options as `probe-m6-adsp`: the kernel's debug options are the only
change (the ADSP driver stays blacklisted).

## Runbook

Every step is the owner's call; the phone's screen goes dark during each
test. Stop at the first failed Pass. A failed step reboots into MIUI: boot
the probe again (`DEBUGING_RUN.sh`) before the next one. `pm_test` stops
a suspend at the named stage, waits 5 s, and resumes without sleeping.
Each test runs detached (`systemd-run`) with `pm_debug_messages` on, and
`journalctl --sync` first, so the journal holds the lead-up.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Install the oma2 modules on the root (`tar -C /usr/lib/modules --zstd -xf -`, `depmod`) | `modules.dep` exists | errors | `rm -rf` the directory | low |
| 1 | Boot `probe-m7-oma2`; read-only: `cat /sys/power/pm_test` | lists `freezer devices platform processors core` | no SSH | MIUI, then `probe-m6-adsp` | low |
| 2 | `echo freezer > /sys/power/pm_test; echo freeze > /sys/power/state` | back in about 5 s; tasks thaw; SSH answers | no return in 1 min | MIUI, boot again | low |
| 3 | The same with `devices` | back in about 5 s; display, touch, Wi-Fi, USB work | no return | the last `calling` device in the journal is the suspect: unload or unbind it and repeat | medium |
| 4 | The same with `platform` (late and noirq stages; for s2idle the last stage before the idle loop) | back; everything works | no return | as step 3 | medium |
| 5 | A real s2idle, `pm_test none`, `rtcwake -m freeze -s 30` | resumes on the RTC; `suspend_stats/success` 1 | no return | if 4 passed, the idle loop (CPU power collapse) is the suspect: retry with the cpuidle states disabled | medium |
| 6 | The same, woken by the power key | resumes on the key | no return | — | medium |
| 7 | Battery: `current_now` over 10 min screen-off awake vs suspended (cable out, runs detached) | suspended draws clearly less | — | — | low |

Only after 5-7 pass does a "power key off, then suspend" policy go into a
package.

## Results

- 2026-11-01: first attempt failed (above).
- **Step 0: pass** (2026-11-01): oma2 modules on the root, `depmod` fine.
- **Step 1: pass** (`probe-m7-oma2`, `7.1.3-msm8953-oma2`): `pm_test` lists
  `none core processors platform devices freezer`.
- **Step 2 (freezer): pass**: tasks froze in 0.03 s and thawed after 5 s.
- **Step 3 (devices): pass**: devices suspended in 0.95 s and resumed in
  0.14 s, no driver error; Wi-Fi reconnected (ping fine), touch present.
  wcn36xx logs `ERROR SMD_EVENT (312) not supported` on suspend, and the
  charger re-detects USB on resume (`USB role none -> device`).
- **Step 4 (platform): pass**: late and noirq stages a few ms each.

So every driver survives suspend; the failure is in the s2idle loop or
the wake from it. Suspect: the lockup detectors, set to panic in oma1
(`BOOTPARAM_SOFTLOCKUP_PANIC`, `BOOTPARAM_HARDLOCKUP_PANIC`). A panic
reboots into MIUI with `panic=10`, which matches a reset with no trace.
- **Step 5: pass** (2026-11-01): `rtcwake -m freeze -s 30` with
  `kernel.watchdog=0`: "Timekeeping suspended for 30.371 seconds", woken
  by IRQ 71 `pm8xxx_rtc_alarm`, Wi-Fi and touch fine after.
- **Step 6: pass**: asleep with a 120 s backup alarm, the owner pressed
  power after about 14 s: woken by IRQ 68 `pm8941_pwrkey`, screen on.
- **The lockup detectors are not the cause**: the same 30 s s2idle with
  `kernel.watchdog=1` resumed fine, and so did one entered with the panel
  on (`dpms=On`).
- **Soak: 10 of 10** cycles of 20 s s2idle plus 5 s awake, all woken by
  the RTC; `suspend_stats` 18 successes, 0 failures on oma2.

## Auto-suspend (device-markw 0.1.7)

`omamobile-autosuspend` suspends to idle once every screen has been off
for `AUTO_SUSPEND_DELAY` seconds (10 on markw), from Hyprland's own
`dpmsStatus`. It stays awake while the cable is in a computer (`usb0`
carrier), while a USB device is plugged in (OTG), while sound plays, while
Stay awake is on, and while anything holds a block sleep inhibitor. The
package installs it disabled.

Read-only check (2026-11-01, oma2, screen off, cable in the laptop):
`omamobile-autosuspend --check` printed `awake: USB cable in a computer`,
with no sleep inhibitor held.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 8 | Install device-markw 0.1.7; `omamobile-autosuspend --check` with the screen on, then off | `screen on`, then `awake: USB cable in a computer` | anything else | — | low |
| 9 | Start it by hand (`systemctl start omamobile-autosuspend`), unplug the cable, power key off; wait 30 s; power key on; plug in and read `journalctl -u omamobile-autosuspend` and `suspend_stats` | one "suspending" and one "resumed", `success` up by one, `fail` 0; screen and Wi-Fi back | no wake on the power key | Power held about 30 s, boot the probe again; `systemctl stop omamobile-autosuspend` | medium |
| 10 | Same with music playing (`mpv` on a file), then with Stay awake on | "staying awake: sound playing", then "Stay awake is on"; no suspend | it suspends | as 9 | low |

Results (2026-11-03, `7.1.3-msm8953-oma3`, `probe-m9k-oma3`, device-markw
0.1.13 replacing 0.1.0 and the hand-copied files, all byte-identical):

- **Step 8: pass**: `--check` printed `awake: USB cable in a computer`
  with the screen off and `screen on` with it lit.
- **Step 9: pass**: "screen off for 10s: suspending", then "resumed
  (suspend_stats success 1, fail 0)" after about 52 s asleep, woken by
  IRQ 68 (`pm8941_pwrkey`), not by the 240 s backup RTC alarm; Wi-Fi came
  back (the log was read over it).
- **Step 10: pass**: a quiet test tone (`pw-play`, cable out) gave
  "staying awake: sound playing", and Stay awake gave "staying awake:
  Stay awake is on"; no suspend in either. The cable is checked first, so
  run these with it out, or the log names the cable instead.

Before this, 10 h on battery with the screen mostly off and nothing
suspending drew 729 mAh, 73 mA on average.

After 8-10 pass: `systemctl enable --now omamobile-autosuspend`, and a
later package version enables it by default. Step 7 (the battery
comparison) then measures the real gain.

The oma1 failure stays unexplained: the only kernel difference is
`PM_DEBUG`, which adds the test hooks and messages. Keep the next
suspends attended and look at `suspend_stats/fail` and the journal after
each; boot oma2 (`probe-m7-oma2`) from now on.

## A long sleep that never woke (2026-11-03, oma3)

The same boot as steps 8-10 (`probe-m9k-oma3`), auto-suspend still
started by hand, nobody at the phone. Its journal, read in the next boot:

- 00:33 a suspend of about 52 s, resumed (the step 9 run); then six
  "staying awake" lines (cable, sound, Stay awake) for the step 10 runs.
- 01:01:38 "screen off for 10s: suspending". NetworkManager went to
  sleep (Wi-Fi deauthenticated "by local choice"), wcn36xx logged its
  usual `ERROR SMD_EVENT (312) not supported`, and at 01:01:40
  `PM: suspend entry (s2idle)` is the last line of the boot. No "resumed",
  no 240 s backup alarm wake, no panic; the next boot came up on its own
  (its clock started before the last line, so how long it hung is
  unknown). Whether pstore held anything was not checked.

So s2idle hangs sometimes, not always: 13 short sleeps woke, this one and
the first oma1 attempt didn't. What differed this time: no cable, Wi-Fi
associated until the suspend, and the whole session had run for hours.
The staged runs below look for the length or the condition that hangs,
one change per run, with the backup RTC alarm armed every time.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| L0 | Read-only: `systemctl is-active omamobile-autosuspend` (inactive), `cat /sys/power/suspend_stats/{success,fail}`, `journalctl --list-boots` | auto-suspend off; counts noted | it is active (stop it first) | — | none |
| L1 | Cable in, Wi-Fi up: `journalctl --sync; systemd-run --unit=x-sleep rtcwake -m freeze -s 120` | wakes on IRQ 71 after 120 s, USB SSH back, `success` +1 | no wake in 5 min | hold Power about 30 s, boot the probe again | medium |
| L2 | As L1 with `-s 300` | as L1 | as L1 | as L1 | medium |
| L3 | As L1 with `-s 900` | as L1 | as L1 | as L1 | medium |
| L4 | Cable out (Wi-Fi SSH tile on), `-s 900`; plug back after | wakes, Wi-Fi SSH answers within 1 min of the alarm | no wake | as L1 | medium |
| L5 | As L4 with `nmcli radio wifi off` before (the cable carries the check afterwards) | wakes; `nmcli radio wifi on` restores Wi-Fi | no wake | as L1 | medium |

A hang at L1-L3 says the length matters; one only at L4 points at the
cable or Wi-Fi, and L5 then separates those. After each hang, read the
lost boot's journal (`journalctl -b -1 -k | tail -50`) before anything
else. The screen goes dark at each step; announce it.
