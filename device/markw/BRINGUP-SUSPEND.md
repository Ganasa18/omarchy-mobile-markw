<!-- SPDX-License-Identifier: MIT -->
# markw: suspend (runbook)

Status: the first s2idle attempt never resumed (2026-11-01). Kernel
`7.1.3-msm8953-oma2` (oma1 plus `CONFIG_PM_DEBUG`) is being built for a
staged search.

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

The oma1 failure stays unexplained: the only kernel difference is
`PM_DEBUG`, which adds the test hooks and messages. Keep the next
suspends attended and look at `suspend_stats/fail` and the journal after
each; boot oma2 (`probe-m7-oma2`) from now on.
