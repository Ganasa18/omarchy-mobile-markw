<!-- SPDX-License-Identifier: MIT -->
# markw: suspend (runbook)

Status (2026-11-14): oma11 passed 8/8 attended s2idle cycles across two
boots: six 20 s cycles on the first, then 20 s and 120 s on a fresh boot.
Neither boot restarted during these tests; fail stayed 0. Auto-suspend
stays off. Earlier kernels also had passing boots, so longer sleeps and
more boots remain necessary before calling the reset fixed.

Battery control (2026-11-14): 46.884 min unplugged, capacity 99 -> 92%;
after excluding the first 10 min, 36 screen-off samples averaged -49.183 mA
(discharging), capacity 96 -> 92 over 36.513 min. Actual suspended-time delta
was 0 and suspend counters stayed success=2/fail=0. This was awake screen-off
consumption, not a suspend comparison or a measured saving. Percentage-based
lifetime extrapolation is inappropriate while the gauge settles after unplug.

Kernel base: archived `v7.1.3-r0`, not a kernel Git branch/worktree.
Candidate source: `~/android/markw/kernel-oma11-usbpm/build`;
explicit output: `~/android/markw/kernel-oma11-usbpm/out`;
release: `7.1.3-msm8953-oma11`. oma10's source/output remain intact.

## 2026-11-14: fresh-boot 20 s and 120 s gates

Owner-approved RAM boot of the same oma11 image, followed by one 20 s and
one 120 s freeze, stopping on failure. Both passed: measured sleep 20.522 s
and 121.428 s, success 0 -> 1 -> 2, fail 0, same new boot ID throughout.
RTC alarm IRQ 71 woke both; fresh SSH returned, each watchdog disarm was
verified. No new WARNING, Oops or panic was captured.

Preflight initially stopped on taint 512 (W): two boot-time
`pclk0_clk_src: rcg didn't update its configuration` warnings in the first
DSI modeset. This exact clock warning is the accepted oma1/postmarketOS
baseline in [BRINGUP-KERNEL.md](BRINGUP-KERNEL.md), not a clean kernel.
The bounded test sealed those two warning lines and taint 512; any extra
warning or taint bit was a stop condition. Both gates retained that baseline.

Guards retain their limits: qcom_wdt stops during suspend_late and cannot
recover a stall while stopped; the USB recovery timer uses monotonic time,
which pauses in sleep. Tests stayed attended. Auto-suspend remains disabled.
No battery saving has yet been measured. This board exports
current_now but no charge_counter/charge_now/energy_now; the generic power-ab
counter-based s2idle calculation therefore cannot be used unchanged.

## 2026-11-14: auto-suspend gates G1-G3 (7.1.3-msm8953-oma11, same boot)

Owner-approved, one at a time, each under a laptop kmsg stream, a 300 s
watchdog feeder and a 90 s USB dead-man; stop at the first failure.

- **G1 pass**: `rtcwake -m freeze -s 300`, cable in. Slept 300.2 s, RTC
  IRQ 71, same boot, success 2 -> 3, fail 0, taint 512 unchanged (the
  documented DSI clock WARNs), no new WARNING/Oops. 300 s is the length
  that reset oma6 (L2).
- **G2 pass** (fourth try): Power-key wake, cable in, 240 s backup alarm.
  Woke on IRQ 68 `pm8941_pwrkey` after 3.9 s, success 6 -> 7, fail 0;
  the owner saw the lock screen at once. The first three tries woke by
  the alarm (121, 181, 241 s) with the pwrkey count unchanged: the owner
  pressed only after the alarm wake. A press while awake adds 2 to the
  count (press and release); record the count before and after.
- **G3 fail**: `systemctl start omamobile-autosuspend` (not enabled), a
  temporary beep hook in `/usr/lib/systemd/system-sleep/`, cable out,
  Power to blank. First attempt never slept: "staying awake: SSH session
  open", a stale `dmesg -w` session from G2 whose laptop side was gone
  (the check counts USB SSH sessions after the cable is out, until TCP
  gives up). After closing it, second attempt: the screen stayed dark
  after Power, no beeps; with the cable back, no USB network adapter on
  the laptop and no SSH. Owner held Power about 30 s; the phone came up
  in MIUI. Whether it hung entering sleep, asleep or after the wake is
  unknown until the lost boot's journal is read (persistent journal on
  the card: `journalctl -b -1`). Differences from G1/G2: `systemctl
  suspend` (sleep hooks, NetworkManager sleep), cable unplugged before
  the sleep (USB role device -> none), autosuspend's own process.
- MIUI booted, so the modem NV backup is stale again. Auto-suspend was
  only started, so it is inactive after the reset.
- **Lost boot's journal (read after the RAM re-boot, same kernel):** 17:43:26
  suspend requested; 17:43:27 `systemd-sleep` froze `user.slice`, then ran
  the hooks. The test hook's `runuser … pw-play` (PipeWire frozen, and
  pam_systemd's CreateSession failing with UnitAllocationFailed) blocked
  for about 90 s; `timeout 4` wrapped pw-play, not runuser. The owner's six
  Power presses in that window were logged by logind, but the shell was
  frozen, so the screen stayed dark. The cable went back in at 17:44:13.
  At 17:44:57 the hook returned, `PM: suspend entry (s2idle)` followed,
  and the journal ends there: that sleep never resumed before the forced
  restart (new boot 17:45:53). Its conditions (cable replugged while
  frozen, a 90 s stall) are not a clean auto-suspend test, so G3 is a
  test-harness failure plus one unexplained non-wake, not yet evidence
  against auto-suspend. Hook removed on the next boot (2026-11-14).
- Never call into user.slice (runuser, PipeWire, Hyprland) from a
  system-sleep hook: it runs after the freeze. Queue user work with
  `systemd-run --no-block --on-active=N` so it runs after the thaw.
- omamobile-autosuspend fixes found here: an SSH session on usb0 still
  counts after the cable is out (stale TCP); "resumed" is logged even
  when no suspend completed within its 60 s wait. Both fixed and tested
  (`test/autosuspend.sh`); the usb0 filter also checked against the
  phone's real `ss`/`ip` output with a faked carrier of 0.
- **G3 retry: pass** (fresh RAM boot of the same oma11 probe, taint 0).
  The fixed script ran as a transient unit from `/run` with test-only
  beeps (one before `systemctl suspend`, two after a counted resume; no
  sleep hook). Cable in: "staying awake: USB cable in a computer". Cable
  out, Power to blank, twice: 17:55:22-17:56:07 (about 45 s) and
  17:56:34-17:57:16 (about 42 s) asleep, both woken by the owner's Power
  press (pm_wakeup_irq 68), success 0 -> 2, fail 0, no Oops/WARNING,
  owner heard both beep pairs and unlocked with the PIN each time. 300 s
  watchdog armed throughout, then disarmed; unit stopped, auto-suspend
  still disabled.
- **Long sleep: pass** (same boot). The test copy now also arms the
  watchdog for 120 s after each counted resume. Cable out, Power to
  blank: asleep 18:12:35-18:20:58 (about 8 min 23 s), woken by Power
  (pm_wakeup_irq 68), success 2 -> 3, fail 0, taint 0, no Oops/WARNING;
  post-resume watchdog ARMED then DISARMED. Longest sleep on markw that
  resumed since oma3. The battery log is not a comparison: the gauge went
  from Full 94 % to 90 % across the unplug and the sleep, which is unplug
  settling plus one short sleep; no saving is claimed.
- **One-hour sleep: pass** (same boot, battery logger alongside). Cable
  out, Power to blank: asleep 18:29:26-19:32:11 (about 62 min 45 s),
  woken by Power (pm_wakeup_irq 68), success 3 -> 4, fail 0, taint 0, no
  Oops/WARNING; owner heard both beep pairs and unlocked with the PIN.
  Post-resume watchdog ARMED 19:32:12, DISARMED 19:34:13; with the cable
  back the script said "staying awake: USB cable in a computer", then the
  test unit was stopped. Longest resumed sleep on markw so far, past the
  length of the 2026-11-03 non-wake. The gauge read 93 % (just Full,
  then Discharging) before and 85 % after replug: about 8 points in an
  hour, but it started at the top of a fresh charge, where this gauge
  drops fast, and the logger takes no samples while the phone sleeps.
  No saving is claimed; that needs a run started well below Full against
  an awake screen-off run of the same length.
- **Overnight sleep: pass** (same boot, after the Power-only wake policy
  was installed from packages: device-markw 0.1.20, shell 0.2.40,
  omarchy 0.1.12, all 18 Omarchy patches applied). Cable out, Power to
  blank: asleep 2026-11-14 20:25:51 to 2026-11-15 06:56:18 (about 10 h
  30 min) in one suspend, no wake in between, woken by Power
  (pm_wakeup_irq 68, RTC alarm count 0), success 4 -> 5, fail 0, taint 0,
  no Oops/WARNING; post-resume watchdog ARMED then DISARMED.
- **Battery across that sleep** (`tools/markw-battery-log 50400`): 99 %
  at the unplug, 69 % at the replug, 37 886 s of BOOTTIME apart: about
  2.9 points an hour. With the nominal 4100 mAh that is roughly 115 mA on
  average, far above what a phone in a real low-power state draws, so
  s2idle here keeps the phone suspended but does not yet reach a deep
  power state (the start at a fresh charge inflates it a little; it can't
  explain most of it). The awake screen-off control of the same length
  is still to run, and where the current goes (CPU idle states, RPM
  sleep, clocks or regulators left on) is the next question.
- **Where the sleep goes (read-only, 2026-11-15):** both CPU clusters
  reach their deepest genpd state in s2idle (`power-domain-cluster0/1`
  S2 `S2idle` 10 and 7 after five suspends); CPU idle is psci_idle with
  WFI and core power collapse. No RPM sleep counters are available (no
  `rpm-stats` node in the DT; `qcom_stats` is a module, not loaded), so
  whether the SoC reaches XO shutdown/VDD min is not visible yet. Still
  running in sleep: WCNSS (Wi-Fi connected, Bluetooth powered) and ADSP;
  the modem was off.
- **Awake, screen-off control (2026-11-15, 10 min):** cable out, panel
  off (bl_power 4), no suspend, Wi-Fi and Bluetooth as overnight;
  `current_now` every 10 s for 589 s: 53 samples, mean 52 mA, median
  49 mA (44-165 mA; the peaks are the start beep and wakeups).
- **So the overnight 115 mA is not a sleep current.** The phone can't draw
  more asleep than awake with the screen off, and the gauge's capacity is
  not a usable measure across a plug change: after the overnight run it
  went from 69 % to 77 % in about 15 minutes on a laptop port, several
  times what that current can add. Battery saving from s2idle is
  therefore still unmeasured. A fair comparison needs equal long runs
  started at the same capacity and read the same way (at the unplug, by
  `current_now`-integrated awake samples, and at the replug), not single
  capacity readings across a plug change.
- Still before enabling it at boot: more boots and a day's use (the
  2026-11-03 hang came after hours of use).

## 2026-11-14: replacement Power-only display wake policy

Read-only inspection: touchscreen `generic ft5x06 (51)` / `edt_ft5x06`,
IRQ 91 (msmgpio 65), has no power/wakeup attribute on its input/controller
ancestry and is absent from the kernel wake-source list. Power key and RTC
are present. Thus the observed tap-to-PIN behavior while autosuspend is off
is a display/lock wake path; it is not evidence of touch waking a real freeze.

The replacement keeps the global touchscreen enabled. Descriptor
`POWER_KEY_WAKE_ONLY=1` opts markw in; other devices retain input wake.
Lock/default and idle activity mark wake requests with
`OMAMOBILE_WAKE_FROM_INPUT=1`; explicit Power IPC `lock wake` is trusted.
The brightness on path holds the same blocking lock as off, checks bl_power,
and refuses flagged requests while dark. Power can still wake it. Generic
mouse DPMS wake is disabled for the opted-in descriptor in phone.lua.

Only lock controls follow the actual panel state, refreshed from sysfs every
250 ms while locked; the input device is never disabled. A failed panel read
fails open for controls, while the brightness gate still protects dark-panel
wake. There is a polling delay before controls stop accepting input; the
guarded wake check itself runs synchronously under the display lock. An
explicit Power request arriving while a wake process is busy is queued and
replayed on exit. No kernel wake sources or suspend policy are changed.

Offline evidence: old brightness code fails the dark-panel input-wake
regression; replacement passes, including blank/input races, trusted Power,
lit-lock input and unconfigured devices. Both affected package suites pass
against the original Omarchy 4.0.6 package with fuzz=0. Extracted actual QML
JS passes input/Power IPC separation and queued-Power replay under Node.
The phone's qmlformat accepts the exact live candidate lock/idle files.
Live customizations are preserved by patching the captured installed files,
not replacing them with the newer packaged implementation wholesale.

Live gate (low risk, reversible display/shell change; announced before use):
backup five exact current files; stop on any baseline mismatch; arm 180 s
rollback; apply brightness, lock, idle, phone.lua and descriptor changes;
reload Hyprland and restart Omarchy shell. Expect a secure PIN lock and
responsive shell. Three cycles: trusted wake -> panel0/input-device=true;
off -> panel4; two generic input wake IPC calls -> remains panel4; trusted
Power wake -> panel0 and lock controls enabled. Stop/restore on parse error,
shell failure, insecure lock, lost input or wrong panel state. Confirm fresh
SSH before canceling rollback. Physical tap/Power/PIN and longer observation
remain required after automatic gates.

**Live gate result (2026-11-14, `7.1.3-msm8953-oma11`): stopped, rolled
back.** Applied 15:11 with the phone locked; `omarchy-restart-shell` twice
reported "session lock was not re-secured" (the shell's own log shows
secure=true about 2 s and 9 s after each start, so the check, not the lock,
may be at fault; not established). Both armed rollbacks restored all five
files (live sha256 = backup, verified 15:40), and `hyprctl reload` put
touch on and mouse DPMS wake back. Their shell restart was refused because
the session was locked, so they exited 1. The shell started at 15:19:30
still ran the new lock QML until its next restart. With the old brightness
script, its input flag has no effect: touch still lights the dark panel. The
owner later unlocked with the PIN, and the lock was secure again afterwards.
Retry only with the phone unlocked and lit, so the restart needs no relock.

**Retry (2026-11-14 15:53, `7.1.3-msm8953-oma11`, same boot): automatic
gates passed.** Unlocked and lit first; staged brightness script aligned
with patch 0019 (DPMS must be lit too); baseline check, 240 s rollback
armed, five files applied, `hyprctl reload`, shell restarted in 9 s.
mouse_move_enables_dpms=false, touchdevice enabled=true. Unlocked: off ->
bl_power 4; two flagged input wakes kept it 4 / DPMS off; trusted wake -> 0.
Locked (secure), three cycles: off -> 4; two `lock wakeInput` -> still 4,
lock controls disabled; `lock wake` (Power path) -> 0, DPMS on, secure,
controls enabled. Fresh SSH confirmed, rollback timer stopped, same boot ID.
Owner's physical check passed: Power off, double tap stays dark, Power
lights the lock, PIN unlocks. Still hand-copied: restore the backup before
any package update or re-patch, then install the packaged version.
Backup/restore script:
`/root/markw-wake-policy2-backup-20261114/rollback` (created at application).
Because the live gate hand-copies tracked files, restore this backup before
package update/re-patching, then install the updated packages. Auto-suspend
remains disabled. No new kernel suspend test is implied by this display gate.

## 2026-11-14: previous global-touch policy (rolled back)

**Later result: rolled back, not ready.** The initial automated off/on gate
and owner's physical check passed, but a later fresh SSH inspection found
panel bl_power=0 with touchdevice.enabled=false. The system was responsive
at 48 minutes uptime. Restore completed and input=true was verified. The
precise interleaving that caused this later mismatch is not yet established;
serialization tests alone did not prove all display paths are covered.
The live hook was removed and its package install is disabled pending that
investigation. The following describes the candidate and earlier gates.

Owner reports that two touches on the dark screen show the PIN pad. The
installed lock forwards input to runWake/omarchy-system-wake; Hyprland still
delivers touchscreen input while the display is off. Disabling mouse DPMS
wake alone does not stop the lock receiving those touches.

The markw-only `omamobile-display-touch` hook sets Hyprland's touchscreen
input enabled=false before display off and true before display on (including
the already-lit early return). It also disables generic mouse/key DPMS wake;
Power's locked binding remains active and reaches brightness-display on via
lock wake -> omarchy-system-wake. This changes compositor input only, not the
kernel RTC/USB wake sources. It does not establish Power-only kernel wake.
Patch 0019 in omamobile-omarchy calls the optional hook; other device packages
do not install it. A blocking lock spans each entire on/off transition so
concurrent blank/wake cannot leave touch disabled on a lit panel.

Validation: both affected package suites passed in LF-normalized Linux
copies. The full series applied to original Omarchy 4.0.6-1 with fuzz=0;
the actual patched brightness script passed fake-compositor/panel tests for
off/on, restore on an already-lit display, failure leaving the panel lit,
both concurrent transition orderings, and operation without a device hook.
The helper separately rejects compositor errors and invalid arguments.

Attended live gate (risk: low, reversible display/input configuration):

1. Read-only: confirm oma11, a responding fresh SSH session and the exact
   previous brightness script; stop on mismatch. Preserve its backup.
2. Arm a 90 s rollback, install helper and tested brightness script. Announce
   the display test. Expect off -> panel bl_power=4 / touch=false, then after
   2 s on -> bl_power=0 / touch=true. Stop and restore on any failed assertion.
3. Confirm through fresh SSH, then stop the rollback timer. These gates
   passed on 2026-11-14, `7.1.3-msm8953-oma11`; autosuspend remains inactive.
4. Owner check pending: Power off, double tap remains dark, Power on and PIN
   input still work. Do not infer this physical test from compositor values.

Live backup/rollback: `/root/markw-power-wake-backup-20261114/rollback`.
It restores the original script, removes the hook, enables touchscreen input
and lights the display. No shell restart or reboot was used. The live files
were copied for this gate; before package update/re-patching, restore the
original tracked brightness script, then install the new device 0.1.20 and
omamobile-omarchy 0.1.12 packages. The patch manager intentionally detects
hand-edited tracked files. A compositor config reload can reset runtime input
settings; the next brightness on/off call reapplies the policy.

## Battery control completed; suspend comparison pending

Read-only baseline capture was started after rollback and verified READY
before the owner was told to unplug: `markw-battery-baseline.service` running
`/run/markw-battery-log.py` from `tools/markw-battery-log`. It waits for
Discharging, records raw telemetry every minute for up to one hour, and
stops on charging/full after replug. Files remain private under
`/var/lib/omamobile/power/*-markw-baseline.csv` with a JSON stop reason.
The first ten minutes can be excluded for unplug settling. Confirm panel
state and actual suspended-time/counter deltas before interpreting a run;
autosuspend is still off. Read results after owner replugs. Stop capture
with `systemctl stop markw-battery-baseline.service` if needed; it changes
no hardware settings. The owner replugged and capture stopped normally.
Results: 46.884 min discharging, 99 -> 92%; after the first 10 min, 36
screen-off samples averaged -49.183 mA, with capacity 96 -> 92% in 36.513 min.
There was one initial screen-on sample; later unplugged samples were dark.
Suspended-time delta was 0; success/fail stayed 2/0. No restart (uptime
continued to 1 h 40 min). Treat capacity as a coarse gauge reading, not a
validated charge counter or a battery lifetime estimate.

USB-connected readings describe charging, not standby drain. Do not derive
suspend current from a sample just after resume: nothing samples while the
system is frozen. The present board exports no charge/energy counter.
This run's raw current_now was negative while discharging; retain raw signs
and do not infer them from a near-zero charging/trickle sample.
Do not run generic `power-ab s2idle` unchanged or report an invented mAh gain.

Next measurement requires an owner-approved longer attended sleep gate and
physical cable removal. A coarse comparison can record capacity, voltage,
temperature and actual elapsed/suspended time over matched screen-off awake
and suspend intervals, with the same radio/background state and a settling
period after unplug. Use hours and repeat the order; report only observed
percentage points/hour with fuel-gauge settling/quantization limitations,
not an exact current or promised battery lifetime. Reject runs with charging,
restart, unexpected screen-on time or insufficient actual suspend duration.
Recover results by replug/fresh SSH; if USB fails, stop and ask the owner,
never automatically reboot. Absolute suspend-current measurement needs a
validated gauge counter or external instrumentation; PMIC driver changes
require the backup checks and a separate experiment.

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

### Staged run results (2026-11-07, `7.1.3-msm8953-oma6`)

On `probe-m13-oma6-wdt` (the watchdog node enabled but disarmed after
its failed bite test), up 10.6 h, cable in, Wi-Fi associated, auto-
suspend inactive.

- **L0: pass.** `suspend_stats` success 0, fail 0; `mem_sleep` offers
  only `[s2idle]`; `/sys/fs/pstore` empty (no ramoops in the DT).
- **L1: pass.** `rtcwake -m freeze -s 120`: USB SSH back about 128 s
  after the start, success 1, Wi-Fi still connected.
- **L2: fail** (owner's go for L2 and L3; L3 not run). `-s 300`, about
  12 min after L1: no SSH 10 min later, and the phone was in MIUI,
  restarted by itself (owner not at it). The boot's journal ends at the
  `rtcwake` line, as on 2026-11-03: the kernel's suspend lines never
  reached the card, so entry, sleep and resume can't be told apart, and
  nothing says what reset it (a panic with `panic=10`, or a reset from
  the secure side). MIUI booted, so the modem backup is stale again.

So the hang needs more than 2 min of sleep, cable or not. Next, one
change per run: a ramoops region so the next hang leaves a log (it has
to survive the reset through MIUI), and L2 with Wi-Fi off (wcn36xx is
the one radio awake in every failed sleep).
- **L2 with Wi-Fi off: fail** (owner's go), on `probe-m12-oma6-iterm`
  (no watchdog node) right after the boot back from MIUI: `nmcli radio
  wifi off`, then `-s 300`. No SSH in 15 min; the phone was in MIUI
  again. So wcn36xx isn't the cause. Next suspect, testable without a
  build: the deepest cpuidle states, which a sleep of minutes reaches and
  one of 2 min may not; disable them in sysfs for one L2 run.
- **Cluster power collapse is rarely reached awake**: the cluster
  domains' S2 (`cluster-power-collapse`, PSCI 0x41000053) showed usage 1
  and 0 in a day's runtime, against thousands for retention (S0) and
  GDHS (S1). A minutes-long s2idle would reach it, so it was the next
  suspect.
- **L2 without cluster power collapse: fail** (owner's go).
  `probe-m14-oma6-nocpc`: the 150 mA DTB with both clusters'
  `domain-idle-states` cut to retention and GDHS (`fdtput`; the `dtc`
  diff is those two lines); genpd listed only S0 and S1. `-s 300`: the
  phone was in MIUI again. So cluster power collapse isn't the cause.
- MIUI keeps no readable reset reason without root: the boot reason
  properties are empty, `/proc/last_kmsg` is 0 bytes, pstore is denied.
- Left to separate, one per run: per-CPU power collapse (cpuidle
  `state1`, which sysfs can disable without a build; with the nocpc DTB
  that leaves only WFI), then the ADSP and modem (a probe without
  `--adsp --modem`).
- **L2 with only WFI: fail** (owner's go). The nocpc probe again, and
  every CPU's cpuidle `state1` (`cpu-power-collapse`) disabled in sysfs,
  so neither CPU nor cluster power collapse could be entered. `-s 300`:
  MIUI again. So the CPU idle states aren't the cause at all. Every
  failed run had the ADSP and the modem up (probes built with `--adsp
  --modem`); the next run takes them out (a probe without those flags).
- **L2 without the ADSP and modem: fail** (owner's go).
  `probe-m15-oma6-norproc`: the 150 mA DTB, built without `--adsp
  --modem` (only WCNSS running). `-s 300`: MIUI again. So neither
  remote processor is the cause. Ruled out so far: Wi-Fi, CPU and
  cluster idle states, the ADSP, the modem. What stays the same: 120 s
  woke once, 300 s never has. A reset after minutes without the CPUs
  doing something they do while awake points at a timer on the secure
  or PMIC side that the running kernel feeds; next, find the length
  that fails (120, 180, 240 s).
- **120 s right after a boot: fail** (owner's go for 120/180/240 s; only
  120 ran). `probe-m15-oma6-norproc` again: MIUI. So the length isn't
  it either; the one pass (L1) is the odd one out. L1 ran on
  `probe-m13-oma6-wdt`, where `qcom_wdt` had bound the APSS watchdog and
  the device had been closed with the magic character (stopped) after the
  bite test; every failing run had the node disabled, so nothing touched
  the watchdog. Next: that L1 condition again (watchdog probe, magic
  close, then `-s 300`), to see whether a firmware-armed watchdog that
  only the driver stops is what resets the phone in s2idle.
- **L1 condition again (watchdog probe, magic close, `-s 300`): fail.**
  The one L1 pass wasn't the watchdog. With `kernel.panic=0` the phone
  still reset, so it isn't a kernel panic either.
- **No resume line reaches the card.** A copier that `fsync`s every
  `/dev/kmsg` read to the card kept only lines up to `PM: suspend entry
  (s2idle)`. A RAM-only probe (Python, LED blue on thaw, then green or
  red after a card write) never lit the LED. So the reset comes before
  userspace thaws, and the card isn't the cause. The "Omarchy shown
  after a power-key wake" earlier was most likely the panel's last frame.
- **ramoops can't carry the trace.** The node is in the DTB (1 MiB at
  `0x9ff00000`) and pstore registers, but a marker written before a
  plain `reboot-to bootloader` was gone after lk2nd and the probe: every
  reset here is a cold one, DDR content is lost.

### Separating the phases (2026-11-08, `probe-m12-oma6-iterm`)

`pm_test` with `/sys/module/suspend/parameters/pm_test_delay`, run
detached (`systemd-run`) and logged to the card after resume:

| Run | Result | Reading |
| --- | --- | --- |
| `pm_test=freezer`, 300 s | pass (312 s, SSH back) | frozen userspace is fine |
| `pm_test=devices`, 300 s and 5 s | reset both times | not valid: at this level IRQs aren't suspended yet, so a handler can hit a suspended block |
| `pm_test=platform`, 300 s | pass (`suspend debug: Waiting for 300 second(s)`, SSH back) | every device suspended through noirq for 5 min is fine |
| s2idle 5 × 60 s | 4 passed, the 5th reset | not one long sleep |
| s2idle 60 s right after a boot | reset | |
| s2idle 100 s (cable still in) | reset in the first | |

So the drivers' suspend and resume are fine: the reset happens inside
the s2idle loop itself (CPUs idle, tick and timekeeping frozen), at a
random point, with a high chance per minute, whatever the idle state
(WFI-only failed too), with or without the remote processors and Wi-Fi.
Wake-enabled while suspended: `wcn36xx_rx` and two tsens interrupts.
Awake, the PMIC fires `mem-avail` (fuel gauge), `chg-taper-thr` and
`soc-delta` several times a minute.

### The wake interrupt, not the idle loop (2026-11-09)

- **A first s2idle 50 s after boot slept 30 min and woke cleanly**
  (`-s 1800`, SSH back, `success` 1). The laptop polled `adb devices`
  the whole time: no reset while asleep.
- **Every failed run resets at the wake, not during the sleep.** With
  the laptop timing it, MIUI's adb appeared 330-336 s after a `-s 300`
  start, the alarm plus MIUI's boot.
- **Not the fuel gauge, not cpuidle.** With `pmi8994_fg` unbound: reset
  at the wake. Booted with `cpuidle.off=1` (no cpuidle driver, so no
  tick freeze or idle states in s2idle) and the fuel gauge unbound: reset
  at the wake.
- **The fuel gauge has a real deadlock of its own** (patch 0010): its
  SRAM release worker takes `chip->lock` while a reader holding the
  lock waits for that worker in `cancel_delayed_work_sync()`. Within
  minutes of a boot every battery reader (upowerd, logind, `cat
  capacity`) was in D state, and an s2idle failed to freeze them
  (`7 tasks refusing to freeze`). Separate from the reset.
- **`pm_test=platform` with an RTC alarm inside it breaks the system.**
  `rtcwake -m no -s 60`, then `pm_test=platform` for 300 s: the alarm
  fires while every device is suspended through noirq, the CPUs aren't
  in s2idle. It came back to Linux, but wedged: `kworker … events
  __lru_add_drain_all`, `__synchronize_srcu`, systemd and quickshell in
  `__flush_work`, so per-CPU work no longer ran somewhere and `exec`
  hung; reading `/proc/interrupts` or `/sys/kernel/irq/*/` hung (an IRQ
  descriptor lock held), and so did sysrq-l. The same test ended by its
  timer instead (no interrupt while suspended) was healthy.

So the reset follows the wake interrupt itself: a PMIC interrupt (the
RTC alarm, or the power key) arriving through the SPMI arbiter's chained
handler while devices are suspended. Real s2idle turns the same fault
into a reset. Next: wake by an interrupt that isn't the PMIC's
(`wcn36xx_rx`, a packet over Wi-Fi), and read the arbiter's wake and
resend path (`IRQCHIP_MASK_ON_SUSPEND`, `irq_set_irq_wake` on the
chained parent, the resend of a pending child after resume).

### A CPU stops running work after the wake (2026-11-09)

- **Cable out: pass.** A run that waited for VBUS to drop, then slept
  300 s: woke, `exec` worked, `/proc/interrupts` read. The phone wedged
  only after the cable went back in.
- **USB controller unbound, cable in (VBUS online): pass**, same as
  cable out; the phone wedged a little after `dwc3-qcom` was bound again.
  `power/wakeup` of `7000000.usb` disabled, cable in: reset at the wake
  (dwc3-qcom arms its PHY wake interrupts only in host mode anyway).
- **Snapshots from inside the wedge.** A Python server started before
  the sleep (imports done, reads `/proc` without `exec`, LocalSend's
  open port 53317 on usb0) answered the laptop after the wake. Already
  in the first snapshot, taken right after the wake and **before** the
  USB controller was bound again: `khugepaged` in `__lru_add_drain_all`
  → `__flush_work` and `kworker/u…+events_unbound` in
  `synchronize_srcu` (fsnotify mark destruction). Both still there
  seven minutes later.

So after an s2idle, per-CPU work no longer runs and SRCU grace periods
never end: one CPU stops taking work (stuck, or idle and deaf to the
IPI that queues it). USB only makes it visible (sshd's `exec`, and the
wake with the cable in turns it into a reset). Next: which CPU, from
per-CPU counters (`/proc/schedstat`, `/proc/softirqs`, the arch timer's
`per_cpu_count`) in the same snapshot server.

### What resets the phone (2026-11-09)

- **Not the kernel's lockup panics.** `markw.config` builds in
  `BOOTPARAM_SOFTLOCKUP_PANIC` and `BOOTPARAM_HARDLOCKUP_PANIC` (the
  buddy detector) and the probes boot with `panic=10`, so a stuck CPU
  could have panicked and rebooted. With `hardlockup_panic`,
  `softlockup_panic` and `panic` all 0 at runtime, a `-s 300` sleep with
  the cable in still reset at the wake.
- **The PMIC calls it a PS_HOLD reset.** A debug module (out of tree,
  not in the repo) read the PON block over the PMIC's regmap and, with
  the owner's go, wrote the reboot mode qcom-pon writes for `reboot
  bootloader` (0x02 << 2 into `PON_SOFT_RB_SPARE` 0x88f). The next
  failing sleep landed in fastboot instead of MIUI, so the reasons
  survived: `PON_REASON1` 0x21 (hard reset + PON1), `POFF_REASON1` 0x02
  (PS_HOLD), warm-reset reasons 0, the same as after `adb reboot
  bootloader`. Not the PMIC watchdog, not undervoltage, not the keys:
  the SoC dropped PS_HOLD itself (Linux, or the secure side after a bus
  hang or a watchdog bite).

### Correction: the wedge was ours (2026-11-09)

The kernel log captured by the snapshot server (read from `/dev/kmsg`
by the same pre-started Python process) shows an Oops **before** the
sleep, minutes after the fuel gauge was unbound:

```
Unable to handle kernel paging request at virtual address fffffffffffffffc
CPU: 6 … Comm: kworker/6:2
Workqueue: events power_supply_changed_work
pc : notifier_call_chain+0x84/0x1d4
lr : blocking_notifier_call_chain+0x58/0x8c
```

`pmi8994_fg` registers a power supply notifier and never unregisters
it, so after the unbind the next `power_supply_changed()` (a plug, the
USB controller binding, the charger's own events at a wake) called into
the freed chip. The dead worker left CPU 6's per-CPU work stuck for good:
that is the `__lru_add_drain_all` / `synchronize_srcu` wedge, the hung
`exec`, the hung `/proc/interrupts`, and why plugging the cable or
binding the USB controller "caused" it. Patch 0011 unregisters it.

So every run with the fuel gauge unbound is unreliable about the wedge:
"pm_test=platform with an RTC alarm", "wake by Wi-Fi", "cable out",
"USB controller unbound" and "a CPU stops running work" above. What
still stands, all from runs with the fuel gauge bound or matching them:
the reset happens at the wake, not during the sleep; it needs the cable
in (no run with the cable out and the fuel gauge bound yet); a first
sleep 50 s after boot slept 30 min cleanly; the PMIC logs it as a
PS_HOLD reset; the kernel's lockup panics aren't the cause. Next: the
same sleep on a kernel with patches 0010 and 0011 and the fuel gauge
bound, lockup panics off, the reboot mode set to bootloader and the
snapshot server reading `/dev/kmsg`.

### Clean runs on oma7 (2026-11-09, `7.1.3-msm8953-oma7`)

`probe-m16-oma7` (patches 0010 and 0011, the fuel gauge bound),
lockup panics off, `kernel.panic=0`, the PMIC reboot mode set to
bootloader so a reset lands in fastboot. Every run below reset or hung
unless it says otherwise; the PMIC logged each reset as PS_HOLD
(`PON_REASON1` 0x21, `POFF_REASON1` 0x02).

- **300 s, cable in: reset at the wake** (fastboot about 25 s after the
  alarm).
- **300 s, cable out: reset at the wake.** So the cable isn't needed;
  the "needs the cable" above came from fuel-gauge-unbound runs.
- **60 s with the CPU capped at 652.8 MHz: reset.** `qcom-cpr4pd` never
  sets less than its 650 mV floor, the 652.8 MHz voltage, so the CPU
  voltage (CPR performance state dropped by genpd at suspend) isn't it.
- **60 s with WCNSS stopped (`remoteproc0` state `stop`): reset; with
  WCNSS and the ADSP both stopped: reset.** With the modem-less probe of
  2026-11-07 that leaves no remote processor as a suspect.
- **20 s right after a boot: reset**, no debug module loaded. So the
  length doesn't matter; the earlier short passes were luck.

**Breadcrumbs.** A debug module (not in the repo) writes progress codes
to the PMIC's `XVDD_RB_SPARE` register (pm8953 0x88e, a spare only a
battery removal clears; the bootloader clears `SOFT_RB_SPARE` 0x88f
after reading it) from kprobes, so a code survives the reset:

| Probes | Result after the reset or a Power-held restart |
| --- | --- |
| suspend stages | `0x71`: the whole kernel resume finished (`suspend_devices_and_enter` returned), then a hang |
| suspend stages, post-resume heartbeat | `0x61`: `dpm_resume_early` entered, a reset before it returned |
| every early/normal resume callback numbered | `0xfe`: every callback returned; hung about a minute later |
| system and runtime PM callbacks per device | `0xfd`: a callback had returned, none was running |
| IRQ handlers, PM callbacks, `die`/`panic`/restart | `0xfc` once (`die()`, an Oops), `0xfd` the next time |

So the wake itself, the s2idle loop and the devices' resume callbacks
all complete. The reset or hang comes during or after the resume, from
none of the probed callbacks, and almost never through `die()` or
`panic()`: a silent stall that the secure side or the hardware turns
into a PS_HOLD reset, the pattern of a bus access to a block whose
clock or power is off. `pm_test=platform` (everything but the s2idle
loop itself) has passed every time, so it takes a real s2idle:
timekeeping and the tick frozen, the clock events suspended.

**A separate charger bug.** With the battery full and the cable in,
the charger cycles every few seconds: it charges at about 90 mA, below
the 150 mA termination current, terminates, the battery relaxes from
4.37 to 4.31 V, and it recharges (in 5 min: about 110 `chg-tcc-thr`,
110 `chg-p2f-thr`, 55 `chg-rechg-thr`, each also waking the fuel
gauge's SRAM reader). It isn't the suspend fault (the cable-out run),
but it wants a recharge threshold that holds; see BRINGUP-CHARGER.

Auto-suspend stays disabled (device-markw 0.1.18 ships it off).
- **60 s without the memory-mapped timer: reset.** `probe-m17-oma7-notimer`
  (the oma7 DTB with `/soc@0/timer@b120000` set to `disabled`, the only
  `dtc` diff; the broadcast clock event became `bc_hrtimer`). So
  `arch_mem_timer` being suspended and resumed in s2idle isn't it.
- **60 s on oma8, without the rpmpd suspend hack: reset** (into MIUI;
  the reboot-mode module was built for oma7). `7.1.3-msm8953-oma8` adds
  a patch dropping "soc: qcom: rpmpd: add hack to speed up
  suspend/resume", which msm8953-mainline/linux issue 262 lists among
  the commits that may be dropped: it moves the RPM power domains'
  genpd noirq callbacks to the late and early phases. Removing it
  changed nothing here, so it isn't the cause, and the patch is not
  kept. Issue 262 also lists "usb: dwc3: qcom: re-configure wrapper
  registers on resume", "interconnect: qcom: msm8953: enable sync
  callback" and "psci: Allow forcing PSCI domains", all already in this
  tree. MIUI booted, so the modem backup is stale again.
- **The 2026-11-01 soak itself now fails.** `probe-m7-oma2` (the same
  image), `rtcwake -m freeze -s 20`, no sysctl changed: reset in the first
  cycle, where it once passed 10 of 10. 60 s on the same image: reset. So
  the kernel, the DT and the procedure aren't what changed.
- **Userspace is not needed.** oma7 with `systemd.unit=multi-user.target`:
  hang. Also without `ltr501`, `iio-sensor-proxy`, zram, rmtfs, usb-rescue
  and the charge LED rule: reset. Also with every service stopped except
  dbus, sshd, journald, logind, networkd, nsresourced, oomd, resolved, udevd
  and wpa_supplicant: reset.
- **Neither is the root.** `probe-m19-oma7-noroot` (no `--root-uuid`: stays
  in the initramfs, no systemd, nothing mounted from a disk, no firmware
  loaded; `rtc-pm8xxx`, a shell script, and the PON debug module, which
  only sets the reboot mode once and hooks nothing): 20 s, in the first
  cycle the phone was in fastboot 43 s after the start. Its PON registers
  were not read and its log was in RAM, so "reset" rests on the reboot mode
  alone. oma2 without a root is not done.
- **What this leaves.** The kernel on this phone's firmware and hardware.
  MIUI is still the 2019 build and lk2nd the 2026-10-26 image. The fault is
  not constant: a few 20 s sleeps passed today with debug modules loaded.
- **Open: why the 2026-11-01 soak passed then and not now.** Persistent
  charger state looks unlikely: `smbchg_init()` rewrites the termination and
  recharge registers at every boot, and the first long sleep that never woke
  (2026-11-03, oma3) came before the charger patches of 2026-11-06. Not
  compared: battery voltage, temperature and the time since power-on on the
  passing and failing runs.
- `kernel-modules-hook` (via Omarchy) deletes hand-installed module trees at
  boot. `linux-modules-cleanup.service` is masked by hand on this phone; the
  install needs the same.

### The hang without a suspend (2026-11-10, oma7)

- `probe-m16-oma7` (the full system), booted to read the battery history:
  SSH answered once, and about a minute later the phone was gone (no USB,
  no Wi-Fi, no fastboot, no adb) with nothing run on it, no debug module
  loaded and no suspend. The screen was black and the red charge LED lit,
  the LED rule's last state: a hang, not a reset. Power held about 30 s
  restarted it into MIUI.
- So the fault isn't the suspend. It matches the runs that passed a sleep
  and died a minute later (crumb2; breadcrumb `fe`, every callback
  returned). Suspend makes it likelier or sooner; the fault is a hang or a
  reset that can come at any time.
- **The battery ran from nearly full to 6 % that day with the cable in a
  laptop port all the time.** Contributing: long waits in fastboot and
  lk2nd, the charger toggling every ~3 s at full, hangs that stop the
  charger driver, and about 500 mA from the port. The passing 2026-11-01
  soak and today's failures may differ in battery voltage; nothing so far
  measured it during a run. The PON reasons read on earlier resets were
  PS_HOLD, not undervoltage.
- Next (with the battery above 80 % from a wall charger in MIUI): oma7, no
  suspend, cable in the laptop, the reboot mode set to bootloader; every
  10 s stream voltage, current, capacity, charger status, the USB role and
  new kmsg lines to the laptop for 10 minutes. Suspend is parked until the
  hang is understood.
- Dropped: the rpmpd patch tried as oma8 (no effect) and its config bump;
  the kernel stays `-oma7`. Kept for the next runs: `probe-m7-oma2` (the
  control), `probe-m16-oma7`, `probe-m19-oma7-noroot`.

### Found: an I2C write to a suspended QUP (2026-11-10)

Battery 83-87 %, the PMIC reboot mode set to bootloader, lockup panics
and `kernel.panic` off, 20 s sleeps (`rtcwake -m freeze`) unless noted.
Each reset read as PS_HOLD (`PON_REASON1` 0x21, `POFF_REASON1` 0x02).

| Run | Kernel | Result |
| --- | --- | --- |
| Control, nothing changed | oma7 | reset at the wake, first cycle |
| `performance`, 2016 MHz (CPU rail 955 mV) | oma7 | reset, first cycle |
| `probe-m20-oma7-cprtop`: every CPU OPP requires CPR level 20160, so 955 mV at every frequency | oma7 | reset, first cycle: **not the CPU rail** |
| `cpuidle.off=1`, fuel gauge bound | oma7 | hang at the wake |
| `pm_test=platform` 60 s with an RTC alarm inside | oma7, and oma9 (PCNoC `keep_alive`) | reset |
| `pm_test=platform` 60 s, **no** alarm | oma9 | hang: so the alarm wasn't the difference, and PCNoC `keep_alive` changed nothing (dropped) |
| `pm_test=freezer` 60 s | oma9 | pass |
| `pm_test=devices` 60 s | oma9 | survived, with an Oops (below) |
| **LED triggers set to `none` right after boot**, then 10 × 20 s | oma9 | **10 of 10** |
| the same, one 300 s sleep | oma9 | **pass** (11 successes, 0 failures, no abort) |

The Oops from `pm_test=devices`:

```
Internal error: synchronous external abort: 0000000096000010 [#1] SMP
Workqueue: leds set_brightness_delayed
pc : qup_i2c_xfer_v2+0xc1c/0xcd4
 regmap_i2c_write
 aw2013_brightness_set+0x174/0x2bc [leds_aw2013]
```

The notification LED (AW2013 on the QUP at `78b6000`) follows the
`qcom-battery-charging` and `qcom-battery-full` triggers (device-markw
0.1.18's udev rule). Every `power_supply_changed()` around suspend and
resume (charger, fuel gauge) queues an I2C write for it. `i2c-qup`'s
system suspend turns the QUP clocks off but leaves its runtime PM status
active and doesn't mark the adapter suspended, so that write reaches the
clock-gated controller: an external abort when it is caught, a bus hang
and a PS_HOLD reset otherwise. It also explains the variation: the more
the charger and fuel gauge report (a full battery cycling every few
seconds, the cable in), the likelier a write lands in the window. The
dead `leds` worker holds the LED's lock, so afterwards writing the
trigger and the shutdown hang (Power held to restart).

Not explained by this: the failures before the LED rule (2026-11-03,
oma3) and the hang a minute after boot without a suspend (2026-11-10);
another I2C client written from the kernel at a bad time would fit
both, the fix below covers every client of that controller.

**Fix:** patch `0012-i2c-qup-refuse-transfers-while-system-suspended`
marks the adapter suspended (the I2C core then rejects late transfers
with `-ESHUTDOWN`) and suspends through `pm_runtime_force_suspend()`.
Release `7.1.3-msm8953-oma10`; the PCNoC `keep_alive` patch (oma9) is
dropped.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| Q0 | Install the oma10 modules on the root (`tar … --zstd -xf -`, `depmod`) | `modules.dep` exists | errors | `rm -rf` the directory | low |
| Q1 | Boot `probe-m22-oma10`, LED triggers left as the rule sets them (red charging) | boots; LED red | no SSH | MIUI, then `probe-m16-oma7` | low |
| Q2 | 10 × 20 s s2idle, then 300 s, LED triggers on | all wake; `fail` 0; no `external abort`; at most one `Transfer while suspended` warning | a reset or hang | boot the probe again | medium |
| Q3 | L1-L5, then auto-suspend (steps 8-10) | as listed | — | — | medium |

### Correction: the LED was not the cause (2026-11-10, oma9 and oma10)

Every run below reset (or hung into a reset to MIUI) at the first wake,
cable in, charging at about 80 %:

| Run | Kernel |
| --- | --- |
| Q2, LED triggers on (red) | oma10 |
| triggers `none`, red lit as a static `brightness` from userspace | oma10 |
| the same, touch (`2-004a`) and BMI120 (`0-0068`) unbound | oma10 |
| every LED off, the charge LED rule masked, bare `rtcwake -m freeze -s 20` | oma10 |
| device-markw 0.1.19 with a sleep hook darkening the LED, `systemctl suspend` | oma9 |
| every LED off, rule masked, bare `rtcwake` (the 10/10 setup repeated) | oma9 |
| the same with `nmcli radio wifi off` | oma9 |

So the 10 of 10 with the LEDs off (above) does not reproduce on the same
kernel: it was not the LED. The one difference found between that boot
and today's failing ones is Wi-Fi: connected the whole time in the
passing boot (12 connects), never connected in any failing boot. Radio
off fails too, so "connected" itself (WCNSS awake, its L5 and RPM votes
held) is the next thing to test, not "Wi-Fi off". The passing boot also
reached systemd at 5 s against 17-27 s in the failing ones.

Patch 0012 (i2c-qup) stays as a correct fix for the Oops, not as the
fix for this; oma10 is not shown to be better or worse than oma9.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| W1 | oma9, Wi-Fi connected to the access point (check `nmcli dev` shows `wlan0:connected`), LEDs as they are, `cycles.sh 3 20` | all wake | a reset | MIUI, `adb reboot bootloader`, the probe again | medium |
| W2 | If W1 passes: the same, Wi-Fi connected, then `nmcli dev disconnect wlan0` (radio on, not associated) | resets, if association is what matters | — | as W1 | medium |

Parked again on 2026-11-10, by the owner's call; other features first.
Leads gathered for the next attempt:

- **The MPM.** msm8953 mainline has no `qcom,mpm` node, so nothing hands
  the RPM the wake sources or replays them after a sleep. A 2024 attempt
  on the Fairphone 3 (MPM node on GIC SPI 171, `qcom,rpm-msg-ram` at
  offset `0x1d4`, size `0x48`, `wakeup-parent = <&mpm>` on the TLMM, the
  SPMI periph IRQ on MPM pin 88) never saw the MPM interrupt fire, with
  no reply ([LKML, 2024-01-16](https://lkml.rescloud.iu.edu/2401.2/00403.html)).
  The same work in msm8953-mainline/linux#153 settles it: the MPM is
  only for the deep (RPM) sleep, not s2idle, and the Fairphone 3 on
  msm8953-mainline 6.11 sleeps in s2idle and wakes on incoming calls and
  SMS without it (a qrtr-smd wakeup patch, 2024-11). So **s2idle works
  on the same SoC and kernel tree**: the markw fault is in this board or
  our setup, not in msm8953 s2idle itself. A weak lead, not a cause.
- **Same kernel, different result.** oma2 passed 10 of 10 on 2026-11-01
  and failed at the first cycle on 2026-11-09. What changed between the
  two lies outside that kernel image: the battery (charge level, the
  charger state, the cable), the root on the microSD, lk2nd, and the
  installed packages and services. Compare those first.
- **Checked 2026-11-11, both gone:**
  - Firmware: MIUI is still V10.2.2.0 (April 2019, the last release for
    markw; the updater unchanged since 2019), so no OTA replaced RPM or TZ;
    lk2nd is the 2026-10-26 image, loaded from the laptop each time.
  - Wi-Fi "connected" was really the boot path: a probe booted straight
    from Xiaomi's fastboot (after `adb reboot bootloader` or a reset into
    the bootloader) gets no `local-mac-address` from lk2nd, wcn36xx comes
    up with MAC 00:00:00:00:00:00 and NetworkManager fails every
    activation (`set-hw-addr ... failure 99`, `config-failed`). Every
    oma9/oma10 run after 16:46 on 2026-11-10 was booted that way. Booted
    properly (fastboot, lk2nd, probe) with Wi-Fi connected, the LEDs off
    and the rule masked, oma9 still reset at the first 20 s wake. The
    journal per boot shows failures with lk2nd too (all of oma7 on
    2026-11-09). So the 11 of 11 is unexplained: not the LED, Wi-Fi, the
    boot path, the firmware or the kernel build.
  - Always boot probes through lk2nd (`tools/markw-debug boot`), or Wi-Fi
    is missing and results don't compare.
- **A boot either sleeps or it doesn't (2026-11-11, oma9 via lk2nd).**
  - One boot, in which the cable was pulled during the boot and plugged
    back in at about 345 s, passed **10 of 10**: 6 with the cable out
    (discharging, 93-94 %) and then 4 with it in. The next boot, cable in
    throughout, reset at its first wake. The per-boot journal agrees:
    every boot passes all its sleeps or fails its first one (oma6 passes
    on the morning of 2026-11-09, all of oma7 failing, the 11/11 oma9
    boot). So the fault is a state fixed at boot, not something that
    builds up from sleep to sleep. The cable alone isn't it: the 11/11
    boot had it in from power-on.
  - Kernel state, a passing boot (after its sleeps) against a failing one
    (before its first): the cmdline, modules and driver bindings are
    identical. Differences: the eMMC powered off in the passing boot (L8
    off, no load on L5), and the CCI and QUP2 clocks left on. All of
    these can be after-sleep leftovers.
  - **Not the eMMC:** a failing-type boot with the eMMC host unbound
    before the first sleep (`7824900.mmc`, L8 off; a harmless
    `regulator_put` warning for vqmmc) still reset at the first wake.
  - Next time: snapshot **before** the first sleep of every boot, then
    sleep once; after a few boots there will be a passing one to diff
    fairly. Pulling the cable during the boot may make a passing boot
    likelier (one data point). Snapshot command: the regulator, clock,
    genpd and interconnect summaries from debugfs, `/proc/interrupts`,
    `lsmod`, the platform bindings and `dmesg` (they hold identifiers:
    keep them off the repo).
  - **Open: does unplugging before the sleep save a failing boot?**
    Tried on 2026-11-11 (oma9 via lk2nd, cable in from power-on, Wi-Fi
    connected, LEDs off and the rule masked, a snapshot before any sleep),
    but the cable was never pulled: the phone reset into MIUI at the first
    wake with the cable in, as the cable-in boot before it did. That makes
    a second failing boot with a before-sleep snapshot, but the question
    is still open. To repeat it, pull the cable before the first
    `rtcwake -m freeze -s 20` and check that `usb=0` in the log.
- msm8953-mainline#167 (Redmi 5 Plus, `vince`): suspend aborted by
  `rmi4_i2c` (touch) failing to suspend, and a display WARN; a different
  failure (the suspend aborts, the phone survives), not ours.
- **cheetah's plan** (`device/cheetah/SUSPEND-PLAN.md`) for the userspace
  side once the kernel holds: a `sleep.conf.d` drop-in
  (`MemorySleepMode=s2idle`, no hibernation), a `system-sleep` hook that
  quiesces Wi-Fi with a fallback, a watcher that sleeps only with the
  panel off and the session locked, and Omarchy's `suspend-off` toggle
  kept set until suspend is proven.
- The hang without a suspend (above) may be the same fault; the
  10-minute no-suspend log run is still the cheapest next step.

### Read-only follow-up and DWC3 source audit (2026-11-13)

The owner reported MIUI after the failed m23 test, then requested the
debug boot. Booted through lk2nd into `probe-m23-oma10-syncstate` in RAM;
SSH reports `7.1.3-msm8953-oma10`. No suspend was run in this follow-up.
`omamobile-autosuspend.service` is inactive and disabled; `mem_sleep`
offers only `[s2idle]`; pstore has no files. The current command line
contains `fw_devlink.sync_state=timeout`, and GCC and the qnoc providers
report their forced sync at about 11.49 s.

The previous `/root/suspend-m23.log` contains only:

```text
21:20:57 start: Startup finished in 5.179s (kernel) + 15.847s (userspace) = 21.026s  usb=1 cap=97
21:20:57 cycle 1: sleeping
```

This records entry into the first test, not the suspend stage at which
the phone stopped. The saved previous-boot journal tail has no suspend
or resume messages either. Neither establishes whether the failure was
entry, wake, or a post-resume stall. Raw captures remain under ignored
`logs/suspend-audit-20261113/`; do not publish them without redaction.

Audit of the project's base tag, **not a verified copy of the running
binary's build directory**:

- In [`drd.c`](https://github.com/msm8953-mainline/linux/blob/v7.1.3-r0/drivers/usb/dwc3/drd.c),
  `dwc3_usb_role_switch_set()` calls `dwc3_pre_set_role()` synchronously
  before `dwc3_set_mode()` queues the role work on `system_freezable_wq`.
  Freezing that queue therefore does not protect the earlier notifier.
- In [`dwc3-qcom.c`](https://github.com/msm8953-mainline/linux/blob/v7.1.3-r0/drivers/usb/dwc3/dwc3-qcom.c),
  `dwc3_qcom_set_role_notifier()` gets runtime PM and writes the QSCRATCH
  VBUS override without testing `pm_suspended`. The system-suspend path
  turns off the wrapper clocks. A role notification in that window is
  a candidate for investigation, not an observed cause on markw.
- A [2026-11-10 upstream test report](https://lkml.iu.edu/hypermail/linux/kernel/2611.1/09753.html)
  describes a SoC reset on a OnePlus Pad 3 (SM8750) when a cable change
  invokes that notifier in s2idle/noirq. Deferring the glue notification
  until the freezable role worker runs resolved the reported tests.
  Different board and charger notification path: do not assume markw
  reaches the same window or copy that patch without checking its callers.
- The older [failed-resume runtime-PM fix](https://lkml.iu.edu/2409.1/08994.html)
  is already represented in this tag's `core.c`: `dwc3_pm_resume()`
  re-enables runtime PM on its error paths. It is not a missing fix to add.

Next evidence needed: correlate charger role notifications with the
DWC3 system-PM phase and clock restoration, including a stable-cable
case. This must also account for the earlier cable-out failures and the
hang without suspend. Before any new suspend, prepare an attended,
owner-approved runbook with laptop log streaming, a suitable watchdog
and USB recovery plan; stop at the first hang/reset. Keep auto-suspend
disabled. No new patch or hardware test is justified by this audit alone.

### DWC3 role deferral candidate (2026-11-13, offline verification)

The owner requested a fix and an offline candidate is being prepared.
The three audited DWC3 C files match the originals in the actual oma10
build byte-for-byte (SHA-256 checked). The base is therefore confirmed,
although the role race has not yet been observed on this phone.

Design: cache the connector's `enum usb_role` separately from the desired
controller mode and defer the glue notification into `drd_work`, which
runs on `system_freezable_wq`. Pass the notification before the worker's
mode-equality early returns: NONE and DEVICE can use the same peripheral
mode and must still reach the glue. Protect the cached role and pending
flag with `dwc->lock`; consume them under `dwc->mutex` in the worker.
An internal mode-only request must not erase a pending connector role.
The USB role-switch and extcon entry points both use the deferred path;
the OTG role transitions already run in the worker and stay there.

This follows the [DWC3 maintainer's core-side proposal](https://lore-kernel.gnuweeb.org/linux-usb/auu9hx_Xnjbi3WkB%40vbox/).
It avoids a second lock around Qualcomm's suspend callbacks and applies
to both external role notification paths. Changing only the charger
workqueue would leave other callers exposed. Disabling OTG would hide a
feature without fixing the shared path. Neither alternative is selected.

Implementation and verification checklist:

- [x] Run `python3 device/markw/kernel/test/usb-role-pm.py SOURCE` against
  oma10; require failure specifically because a glue notification runs
  while the simulated role worker is frozen.
- [x] Add patch 0013, preserving NONE/DEVICE and pending-role semantics;
  run the same test against patched source and require success.
- [x] Build in a fresh `kernel-oma11-usbpm` directory, never the oma10
  output; use a distinct `-msm8953-oma11` release and matching modules.
- [x] Run strict checkpatch, touched C files with `W=1`, and device-tree
  validation. Record unavailable checks and new warnings explicitly.
- [x] Build a RAM-only probe preserving m23's DT/initramfs options and
  `fw_devlink.sync_state=timeout`; retain m23 for rollback.
- [x] Write exact gated hardware commands with expectations, stop
  conditions, rollback and risk before requesting a boot or suspend.

No hardware result is implied by the host test: its hardware calls are
stubbed, and it exercises the real role-ingress functions and the worker
prefix before mode-specific controller handling. A passing host test is
only evidence for deferral and role bookkeeping. Auto-suspend stays off
until repeated attended tests pass across boots, including long sleeps.

Offline results (2026-11-13):

- Patch 0013 applies to the actual oma10 source with zero fuzz. The
  compiled source matches the reviewed candidate for all four DWC3 files.
- Host regression: original source fails with `glue notifier ran while
  the role worker was frozen`; patched source passes role-switch and
  extcon deferral, coalescing, NONE/DEVICE and pending-role checks.
- Full `Image.gz`, modules and markw DTB build with LLVM 20.1.8 and
  `W=1`: success. There are warnings outside the touched DWC3 C files;
  none name those three C files. This is not a warning-free full tree.
- `checkpatch --strict --no-signoff`: 0 errors, 0 warnings, 0 checks.
- Full-binding `dt-validate`: the kernel baseline, candidate and probe
  variants have the same 447 non-empty diagnostic lines (including
  pre-existing board-compatible/OPP binding issues). No new diagnostics;
  this is not a clean full-tree schema result. Generating the schema
  also reports a duplicate `qcom,fg.yaml` schema ID in the base tree.
- Configuration comparison permits only the release/compiler text and
  the host OpenSSL ML-DSA capability change; unselected ML-DSA options
  disappear, and the RSA selection is unchanged. No other selected
  kernel configuration changes.
- Initramfs modules are replaced with oma11's matching-vermagic files.
  Probe payloads, ARM64 image bounds, v0 image IDs and all artifact
  checksums are verified. The regular candidate preserves m23's DTB and
  command line. Repacking m23 unchanged reproduced its SHA-256 exactly.
- The module archive passed zstd integrity and path-scope checks; it
  excludes build/source symlinks and includes the watchdog module.
- Code review found no correctness blocker; extcon ingress coverage was
  added after review. No modules installed on the phone, no new boot and
  no suspend test were performed. The last read-only phone check reports
  oma10, 73 minutes uptime, auto-suspend disabled, modules cleanup masked
  and battery 99 percent.

Artifacts are under `out/markw/`, with a top-level `SHA256SUMS` and
per-probe checksums. Raw build/test/schema logs remain in ignored
`logs/suspend-audit-20261113/`. Kernel candidate and hardware result must
be reported separately: the suspend-reset goal is still unverified.

#### Gated candidate runbook (not executed)

All commands below run from the repository in Git Bash. Require the
offline build/validation/package results before gate D1. Each gate is
the owner's call, and each boot or reboot needs explicit approval.
Announce the screen interruption before D2 and the temporary freeze/dark
screen before D5. No flashing and no Android partition writes.

The m23 DTB has the APSS watchdog **disabled**, and this candidate keeps
that DTB unchanged. The timer below can recover a USB-only failure after
userspace resumes; it cannot recover a full SoC stall. Before D5, prepare
and obtain approval for a separate safety-only probe/runbook providing
the project's required watchdog coverage. D5 is blocked until that
prerequisite is met. Do not enable another DT node
silently as part of this candidate. All suspend tests must be attended.

Safety-only preparation is now available as
`out/markw/probe-oma10-watchdog/boot.img`: the m23 kernel and ramdisk,
with `device/markw/overlays/watchdog-test.dtso` applied and
`modprobe.blacklist=qcom_wdt` appended to the command line. The DT dump
diff is exactly one `status` property, disabled to okay. The kernel's
default DTS stays disabled. Autoload is blocked before the enabled node
is ever booted; an explicit module load is its own approved gate.

The matching candidate is
`out/markw/probe-oma11-usbpm-watchdog/boot.img`. It uses the same safety
DTB and blacklist argument, with oma11 and its matching initramfs modules.
Check both probes' `SHA256SUMS` before use. These are local artifacts,
not files to commit or publish.

| Safety gate | Commands / action | Expect / Pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| S0 | After approval: `./DEBUGING_RUN.sh --restart --probe "$PWD/out/markw/probe-oma10-watchdog/boot.img"` | oma10, SSH; watchdog node enabled, `modprobe.blacklist=qcom_wdt` present, qcom_wdt not loaded | missing SSH, unexpected module autoload or kernel error | physical recovery; m23 boot only after approval | medium |
| S1 | Start `tools/phone-ssh --fresh 'dmesg -w' > logs/markw-watchdog.kmsg &`; then, after approval, `tools/phone-ssh --fresh 'modprobe qcom_wdt'` | registered watchdog; no Oops/abort | load failure or new error | stop, keep module loaded; no unload/reboot without approval | medium |
| S2 | Upload `out/markw/watchdog-feed.py` as below; `tools/phone-ssh --fresh 'python3 /run/markw-suspend-wd.py --check'` | qcom_wdt binding and CONFIG_WATCHDOG_NOWAYOUT off; no device opened | unexpected driver/config or failed SSH | do not open/arm it | none |
| S3 | After approval, start the guarded feeder below, while awake | fresh SSH; service active and `ARMED: qcom_wdt, timeout=30s` in its journal | cannot confirm ARMED/live service, new error or link loss | feeder disables/magic-closes at its deadline if userspace lives; physical recovery on a full stall | medium |
| S4 | Fresh SSH then stop the feeder below; inspect log | service stopped successfully, explicit `DISARMED` message and PID removed; no errors | stop/disarm failure | no further test; keep owner present | low |

S3/S4 commands, with the laptop log stream already running:

```sh
tools/phone-ssh --fresh 'cat > /run/markw-suspend-wd.py' < out/markw/watchdog-feed.py
tools/phone-ssh --fresh 'python3 /run/markw-suspend-wd.py --check'
tools/phone-ssh --fresh 'systemd-run --unit=markw-suspend-wd --property=RuntimeMaxSec=320 /usr/bin/python3 /run/markw-suspend-wd.py'
tools/phone-ssh --fresh 'systemctl is-active markw-suspend-wd.service; journalctl -u markw-suspend-wd.service -n 8 -o cat --no-pager'
# Only after the fresh-login check succeeds:
tools/phone-ssh --fresh 'systemctl stop markw-suspend-wd.service; test ! -e /run/markw-suspend-wd.pid; journalctl -u markw-suspend-wd.service -n 10 -o cat --no-pager'
```

`CONFIG_WATCHDOG_SYSFS` is off in oma10/oma11: identity/timeout/state
attributes do not exist even when the driver is bound. The feeder first
checks the driver binding and config without opening the device. Opening
the device in S3 arms it; GETSUPPORT/GETTIMEOUT then confirm qcom_wdt,
magic-close support and timeout at least 30 s. Any inspection failure
still attempts DISABLECARD, magic close and descriptor close. It feeds
every 2 s and disables/magic-closes on TERM/INT/HUP or after 300 s of
boot time. Require the explicit successful DISARMED result, not merely
PID-file absence. It does not deliberately trigger a watchdog reset.
`qcom_wdt_suspend()` stops the watchdog in suspend_late and
`qcom_wdt_resume()` restarts it in resume_early. Thus it protects a
post-resume stall after that callback, but cannot reset a hang while it
is stopped for sleep. Retain the USB dead-man and attended recovery;
do not claim the watchdog covers every suspend stage.

Once S0-S4 pass, obtain separate approval for the candidate's D2 boot.
On the candidate, repeat S1-S3 (with its log stream) before D4/D5 and
leave the feeder running through the single suspend. After a successful
fresh-login check, cancel both the recovery timer and the feeder.

| Gate | Commands / action | Expect / Pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| D0 | `tools/phone-ssh --fresh 'uname -r; uptime; systemctl is-enabled omamobile-autosuspend.service; systemctl is-enabled linux-modules-cleanup.service'` | oma10, auto-suspend disabled, modules cleanup masked | missing SSH, unexpected release, cleanup active | no changes | none |
| D1 | After approval: `tools/phone-ssh --fresh 'tar -C /usr/lib/modules --zstd -xf - && depmod 7.1.3-msm8953-oma11' < out/markw/modules-7.1.3-msm8953-oma11.tar.zst` | new release directory and `modules.dep`; existing oma10 modules retained | extraction/depmod error | keep booting m23; remove only the unused oma11 directory after a path check | low |
| D2 | After approval for the full RAM boot sequence: `./DEBUGING_RUN.sh --restart --probe "$PWD/out/markw/probe-oma11-usbpm-watchdog/boot.img"` | fastboot, lk2nd, then SSH; `uname -r` is oma11 | no fresh SSH in 3 min or unexpected boot mode | owner recovers physically, then approves boot of m23 | medium |
| D3 | `tools/phone-ssh --fresh 'uname -r; uptime; cat /proc/sys/kernel/tainted; systemctl is-active omamobile-autosuspend.service'`; capture this boot's kernel log locally | oma11; no new Oops, external abort or missing-driver error; auto-suspend inactive | new error, lost USB or spontaneous reset before any suspend | stop; owner approves m23 boot | none |
| D4 | Start the laptop log stream and arm/verify the detached USB recovery timer below | stream is receiving; fresh SSH reports timer active | stream or fresh login fails | stop timer while SSH still works; do not suspend | low |
| D5 | After separate approval: `tools/phone-ssh --fresh 'systemd-run --unit=oma11-suspend-once /usr/bin/rtcwake -m freeze -s 20'` | wakes after about 20 s; same boot ID, success counter increases, no failure or abort | no fresh SSH after the recovery window, reset, Oops, unexpected IRQ/device failure | stop at the first failure; physical recovery if needed; m23 only after approval | medium |

D4 setup (save boot ID and counters in private logs, not in this plan):

```sh
tools/phone-ssh --fresh 'cat /proc/sys/kernel/random/boot_id; cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail' > logs/oma11-before.txt
tools/phone-ssh --fresh 'dmesg -w' > logs/oma11-suspend.kmsg &
stream_pid=$!
tools/phone-ssh --fresh 'systemd-run --unit=oma11-usb-deadman --on-active=90 /usr/bin/systemctl start omamobile-markw-usb-rescue.service'
tools/phone-ssh --fresh 'systemctl is-active oma11-usb-deadman.timer'
```

After D5, allow the 20 s sleep and the recovery window to finish, then
check one fresh SSH login. If it fails, stop sending commands and ask the
owner about the screen/recovery; do not launch another sleep or a remote
reboot. If it succeeds, compare boot ID and counters against the private
before file, inspect the streamed log, then cancel recovery:

```sh
tools/phone-ssh --fresh 'cat /proc/sys/kernel/random/boot_id; cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail' > logs/oma11-after.txt
tools/phone-ssh --fresh 'if systemctl is-active --quiet oma11-usb-deadman.timer; then systemctl stop oma11-usb-deadman.timer; fi'
tools/phone-ssh --fresh 'if systemctl is-active --quiet markw-suspend-wd.service; then systemctl stop markw-suspend-wd.service; fi; test ! -e /run/markw-suspend-wd.pid; journalctl -b -u markw-suspend-wd.service -n 10 -o cat --no-pager'
kill "$stream_pid"
```

One successful sleep is not acceptance: the previous fault varied by
boot. Only after D5 passes, prepare separately approved repetitions on
fresh boots, then the longer 120/300 s gates and a cable-out comparison.
Do not change LEDs, Wi-Fi association, charger policy or CPU idle states
at the same time. Record date, release, cable state and results for each.

#### Safety gate attempt (2026-11-13, 7.1.3-msm8953-oma10)

The owner approved S0-S4. S0 passed: checksum-verified safety probe
booted through lk2nd, fresh SSH, enabled watchdog DT node, blacklist
argument present, qcom_wdt not autoloaded, taint 0 at 94 s uptime.
The laptop kmsg stream was receiving before the explicit module load.
S1 passed: qcom_wdt bound at b017000.watchdog and /dev/watchdog0 exists.

S2's initial SYSFS check failed because CONFIG_WATCHDOG_SYSFS is unset,
not because probe failed. Added `tools/markw-watchdog-feed` using the
standard watchdog ioctls and guarded read-only `--check`. Six host tests
cover inspection failure cleanup, successful inspect/feed/disarm, failed
open/ping PID cleanup, TERM and no opening in --check. Code review found
a PID-lifetime issue, which was fixed and rechecked. The phone's first
`--check` passed: qcom_wdt binding and NOWAYOUT off, no device opened.

Before the revised helper could be uploaded, a fresh SSH connection
timed out. The existing capture connection ended with reset by peer.
S3/S4 were **not executed**: no feeder was started and no watchdog was
opened by this session. No suspend was attempted and oma11 was not
booted. Stop condition reached; no further commands sent to the phone.

The saved kmsg ends with SSH audit events at about 467 s uptime, without
an actual Oops/BUG/external-abort/panic or a suspend-entry line. A loose
case-insensitive `Oops:` search matched `ramoops:`; word-boundary search
confirms no crash report was captured. This log does not distinguish a
reset, full hang or USB-only loss. Await the owner's screen/status report
before recovery or another approved boot. Raw kmsg stays private in
`logs/suspend-audit-20261113/watchdog-safety.kmsg`.

#### Safety gates passed (2026-11-14, 7.1.3-msm8953-oma10)

The owner restored ADB connectivity and explicitly approved another
RAM-only safety boot and S0-S4. Probe and helper checksums were verified;
all six host helper tests passed before the boot. MIUI -> fastboot ->
lk2nd -> safety probe completed without flashing.

- S0: fresh SSH, oma10, enabled watchdog node, blacklist present and
  qcom_wdt absent before explicit load; taint 0 at 117 s uptime.
- S1/S2: laptop kmsg capture receiving before modprobe; qcom_wdt loaded,
  tested Python helper uploaded to /run, read-only --check confirmed
  driver binding and NOWAYOUT off without opening the device.
- S3: feeder started as markw-suspend-wd.service; a fresh SSH login
  confirmed the live service and `ARMED: qcom_wdt, timeout=30s`.
- S4: stopped through a fresh SSH login. The unit recorded
  `DISARMED: disable ioctl succeeded, magic close completed`, followed
  by successful deactivation. PID file removed; service inactive.
- Private before/after boot IDs match. Final fresh login: oma10, about
  4 minutes uptime, taint 0, auto-suspend disabled. No actual
  Oops/BUG/external-abort/panic in the streamed capture. Capture closed
  after verification. No deliberate watchdog reset, suspend or oma11
  boot was performed.

Raw evidence remains private:
`logs/suspend-audit-20261113/watchdog-safety-20261114.kmsg`,
`watchdog-safety-20261114-unit.log` and the matching boot-ID files.
This validates awake arm/feed/disarm only. The driver's late-suspend
stop/early-resume restart still limits coverage as described above.
Await separate approval for D1-D3 (oma11 modules, RAM boot and preflight);
do not infer approval for D5 from this successful safety check.

#### Candidate first boot passed (2026-11-14, 7.1.3-msm8953-oma11)

The owner explicitly approved module installation, candidate RAM boot
and preflight, with suspend left for a separate approval.

- D1: normalized the local checksum manifest's CRLF endings to LF,
  then all five artifact checksums passed. The oma11 module directory
  did not exist before installation; oma10's modules.dep was present.
  Extracted only the verified oma11 archive into /usr/lib/modules and
  ran depmod. qcom_wdt vermagic matches `7.1.3-msm8953-oma11` on aarch64.
  The old module directory was retained. No new driver was loaded into
  the old kernel.
- D2: owner-approved restart to fastboot, lk2nd RAM load, then
  probe-oma11-usbpm-watchdog RAM load. Fresh SSH reports oma11.
- D3: at 78 s uptime, watchdog DT enabled, autoload blocked and module
  absent before explicit load, taint 0. systemctl --failed was empty.
  Laptop kmsg capture was receiving before modprobe qcom_wdt; the
  guarded helper's read-only --check passed without opening watchdog0.
- Suspend preflight: mem_sleep `[s2idle]`, pm_test `[none]`, success 0,
  fail 0; /usr/bin/rtcwake exists and the USB rescue unit/helper are
  available. Auto-suspend remains disabled. At about 2 minutes uptime,
  taint remained 0 and no Oops/BUG/external-abort/panic was captured.

No watchdog feeder has been started on oma11, and no suspend has been
run. The kernel capture remains active for this debugging session in
`logs/suspend-audit-20261113/oma11-20261114.kmsg` (private). Await explicit
approval for D4/D5 before arming the watchdog/recovery timer and running
one 20 s freeze. A successful boot is not a successful suspend result.

#### First oma11 suspend passed (2026-11-14, 7.1.3-msm8953-oma11)

The owner approved exactly one 20 s test. Preflight: s2idle, pm_test
none, counters 0/0, watchdog check passed, laptop stream active. Started
the guarded feeder and confirmed live service plus ARMED/30s through a
fresh login. Armed oma11-usb-deadman.timer (90 s), verified both guards
from another fresh login, synced the journal and dispatched exactly one
`rtcwake -m freeze -s 20` as oma11-suspend-once.service.

The original stream captured suspend entry and later ended with
connection reset by peer. Waited for the recovery window, without
sending additional commands; the first post-window fresh SSH succeeded
at about 197 s after dispatch. This is the check time, **not a measured
197 s USB recovery delay**: no earlier fresh connection was attempted.

Results:

- Same private before/after boot ID; still oma11. Success 0 -> 1,
  fail 0 -> 0; taint remains 0. No reboot occurred during this trial.
- Fresh dmesg contains `PM: suspend entry (s2idle)` at 521.844101 and
  `PM: suspend exit` at 523.371984 monotonic time, with tasks restarted.
  Monotonic time excludes sleep and is not the sleep duration.
- The unit's realtime duration is 22.389 s and its monotonic duration
  2.206 s, giving about **20.183 s suspended**. pm_wakeup_irq is 74,
  mapped in /proc/interrupts to pm8xxx_rtc_alarm on this boot.
- USB role none -> device is logged during resume. The rescue unit
  completed after resume and again when the dead-man fired; its journal
  contains no rebind/link-back message. The old TCP stream was lost,
  while a new SSH connection worked without a manual cable replug.
- The feeder reached its 300 s boot-time deadline and logged
  `DISARMED: disable ioctl succeeded, magic close completed`, then
  deactivated successfully. By cleanup, both transient guard units had
  been garbage-collected. PID file absent. Stopping an absent timer
  initially returned an error; cleanup must handle each guard separately
  and must not chain watchdog disarm behind a timer-stop success test.

Private evidence: `oma11-20s-before.txt`, `oma11-20s-after.txt`,
`oma11-20s-after.kmsg`, `oma11-20s-units.log`, `oma11-20s-unit.jsonl` under
`logs/suspend-audit-20261113/`. No more cycles or reboots were attempted.
The single success does not establish that DWC3 was the only cause, or
distinguish the candidate from an accidentally passing boot as seen on
oma2/oma9. Keep automatic suspend disabled. Next proposed gate: five
owner-approved 20 s repetitions on this boot, each with fresh
guards/capture and same-boot/counter checks; stop at the first failure.
Re-arm a bounded feeder for each trial rather than exceeding its 300 s
limit across a long sequence. Cross-boot and long-sleep tests still
remain, each under the owner's explicit approval.

#### Five-repeat batch passed (2026-11-14, 7.1.3-msm8953-oma11)

The owner approved five further 20 s cycles on the existing oma11 boot.
Baseline was success 1, fail 0, pm_test none. Each cycle received a new
laptop capture, separately named watchdog service and 90 s USB recovery
timer, fresh-login guard verification and exactly one rtcwake dispatch.
The first new SSH check was after 35 s; no retries or manual cable
replugs were needed. Each guard pair was cleaned up independently.

| Repetition | Approx. suspended time | Success counter | Fail | Boot / taint / wake |
| --- | --- | --- | --- | --- |
| 1 | 20.967 s | 1 -> 2 | 0 | same boot / 0 / RTC IRQ 74 |
| 2 | 20.437 s | 2 -> 3 | 0 | same boot / 0 / RTC IRQ 74 |
| 3 | 21.307 s | 3 -> 4 | 0 | same boot / 0 / RTC IRQ 74 |
| 4 | 19.932 s | 4 -> 5 | 0 | same boot / 0 / RTC IRQ 74 |
| 5 | 19.841 s | 5 -> 6 | 0 | same boot / 0 / RTC IRQ 74 |

The host validator checks the original private boot ID, exact counter
increment, oma11 release, taint 0, mapped RTC IRQ, 18-25 s sleep inferred
from realtime minus monotonic journal duration, no captured critical
kernel fault, and explicit ARMED/DISARMED messages for that cycle's unit.
The transient controller for repetitions 2-5 was reviewed read-only;
one rtcwake dispatch per invocation, with immediate exit on first error.
It does not attempt another sleep or another SSH command after a failed
connection; bounded guards would remain until their deadlines on that
failure path. That path was not taken in this batch.

Final fresh login: oma11, about 44 minutes uptime, success 6, fail 0,
taint 0, auto-suspend disabled. Feeder PID absent and all five watchdog
services and all five recovery timers inactive. Every cycle's explicit
disarm was verified. No reboot, extra cycle or configuration change was
performed. Together with the initial trial, this is **6/6 short sleeps
on one boot**, not a cross-boot stability result.

Evidence remains private in `logs/suspend-audit-20261113/batch20-*`,
including per-cycle snapshots, unit JSON, dmesg and result JSON plus
`batch20-summary.json`. None of these raw logs should be published.

Next proposed gate (not executed; needs approval): reboot the same
RAM-only oma11-watchdog image once through lk2nd, repeat preflight,
then one 20 s and one 120 s sleep with fresh guards for each and stop on
the first failure. Reuse the installed oma11 modules; verify their
presence and the cleanup mask before reboot. After reboot, map the RTC
IRQ again rather than assuming it remains 74; expected counters on the
new boot are 0 -> 1 -> 2 with fail 0. Use the existing D4/D5 commands
with distinct unit names and `rtcwake -m freeze -s 20`, then `-s 120`.
Check through fresh SSH after the requested duration plus 15 s, then
clean guards. The 300 s bounded feeder is adequate for each individual
20/120 s gate with this margin; do not reuse one feeder for the entire
sequence. A 300 s sleep needs a separately prepared longer safety window.

## Suspend drain by the coulomb counter (plan, 2026-11-15)

oma12 and later expose the gauge's coulomb counter, which keeps counting
through s2idle (BRINGUP-CHARGER.md, G5b: 28 mA asleep against 61 mA awake
over a 3-minute sleep). J4 measures a real auto-suspend: cable out, the
packaged `omamobile-autosuspend` started (not enabled) with the 300 s
watchdog feeder armed after each resume, the counter snapshotted at the
unplug and at the replug, the owner waking the phone with Power after
about 30 minutes. Pass: one suspend, Power wake, fail 0, no Oops; the
result is the average current over the sleep from the counter's
difference, with the awake minutes before and after subtracted using
current_now.

### J4 result (2026-11-15, `7.1.3-msm8953-oma14`)

- Pass as a suspend: test copy of auto-suspend from `/run` (not
  enabled), laptop kmsg stream, qcom_wdt loaded and the feeder's
  preflight passed. Cable out, Power to blank: asleep 16:01:09-17:37:35
  (about 96 min 25 s) in one suspend, woken by Power (pm_wakeup_irq 68),
  success 0 -> 1, fail 0, taint 0, no Oops/WARNING; post-resume watchdog
  ARMED, then disarmed at its 120 s deadline.
- **Counter over the sleep:** the logger's two samples bracket it
  (BOOTTIME apart 5795.8 s, MONOTONIC 10.4 s, so 5785 s asleep). The
  counter fell 83.8 mAh: **52 mA average asleep** (51.6 mA if the 10 s
  awake inside the pair drew 270 mA). The second sample came 4 s after
  the replug (Charging, +224 mA), which moves this by under 0.3 mAh.
- So over a real sleep s2idle draws what the awake, screen-off control
  drew (52 mA mean, 49 mA median over 10 min), not the 28 mA of G5b's
  3-minute rtcwake sleep. No net saving from s2idle is shown yet. G5b's
  number came from a sleep just after 60 s of quiet; what draws the
  extra over a long sleep (Wi-Fi/Bluetooth on WCNSS, ADSP, no RPM
  low-power state visible) is the next question, read-only first.
- Logger note: it stops at the first Charging sample, so the owner's
  quick replug after the wake ended it with no post-resume awake sample;
  that cost nothing here because the sleep interval is complete.

### RPM sleep stats: the SoC never reaches XO shutdown (2026-11-15, oma14)

Read-only, from userspace after the owner's go, as downstream
`rpm_stats.c` (Xiaomi GPL kernel `markw-m-oss`, `msm8953-pm.dtsi`:
`qcom,rpm-stats`, base 0x200000 plus the offset at 0x290014, version 2)
and mainline `qcom_stats` (`qcom,rpm-stats`, base 0x290000, offset at
+0x14 masked to 16 bits, as sdm630.dtsi) both read them:

- 0x290014 reads 0x900b0, so the records sit at 0x2900b0 on either
  reading. msm8953.dtsi has no `rpm-stats` node, which is why
  `qcom_stats` never bound.
- After the 96-minute J4 sleep in this boot: `vlow` (XO shutdown) count 0,
  accumulated 0 s; `vmin` (VDD min) count 0, accumulated 0 s. s2idle here
  idles the CPUs and clusters (genpd S2), but the SoC never leaves XO on,
  which is why the sleep draws what awake screen-off draws (52 mA).
- A first try read the records with 36-byte slices and got SIGBUS in the
  Python process (kernel fine, taint 0): `/dev/mem` maps this as device
  memory, which faults on the unaligned loads `memcpy` uses. Read it with
  aligned 32-bit loads only, as `readl` does.
- Candidates that can hold XO from the apps side (awake snapshot, clocks
  enabled): LPASS internal digital codec core 9.6 MHz, venus AXI/AHB,
  camss AHB, plus WCNSS (Wi-Fi up) and ADSP running. Which RPM master
  never votes for sleep (APSS, MPSS, PRONTO, TZ, LPASS) is in the RPM
  master stats in message RAM (downstream `qcom,rpm-master-stats@60150`,
  stride 4096, version 2); not read yet.
- Upstream-ready follow-up: an `sram@290000 { compatible =
  "qcom,rpm-stats"; reg = <0x00290000 0x10000>; }` node in msm8953.dtsi so
  `qcom_stats` exposes these in debugfs.

### RPM master stats: three masters never sleep (2026-11-15, oma14)

Read-only after the owner's go, message RAM 0x60150 + n * 4096, version 2
layout of downstream `rpm_master_stat.c`, aligned 32-bit reads; boottime
12121 s, after the 96-minute J4 sleep:

| Master | active_cores | numshutdowns | xo_count | xo accumulated |
| --- | --- | --- | --- | --- |
| APSS | 0x1 | 0 | 0 | 0 s |
| MPSS | 0x1 | 0 | 0 | 0 s |
| PRONTO | 0x1 | 3091 | 3091 | 5838 s |
| TZ | 0x0 | 0 | 0 | 0 s |
| LPASS | 0x1 | 5 | 4 | 0.1 s |

RPM shuts XO down only when every master has voted for sleep, so:

- **APSS never tells RPM it sleeps.** Mainline msm8953.dtsi's deepest
  domain state is `cluster_pc` (PSCI 0x41000053: CPU mode 3, cluster mode
  5, system field 0). Downstream `msm8953-pm.dtsi` has a third level above
  the clusters, `system` (CCI SPM, `qcom,psci-mode-shift = <8>`), whose
  `system-pc` (mode 3) carries `qcom,notify-rpm`; that is the state that
  hands the apps side to RPM. Mainline has no system-level domain, so
  s2idle reaches cluster PC (genpd S2) and RPM still sees APSS active.
- **MPSS is active from boot**: the modem remoteproc is `disabled` in our
  DTB (BRINGUP-MODEM.md), so the modem never runs and never votes sleep.
  Whether an unbooted MPSS blocks XO shutdown on its own is not proven
  here; it is a candidate.
- **LPASS barely sleeps** (0.1 s of XO off in the whole boot): the ADSP
  runs and the LPASS internal digital codec core clock (9.6 MHz) stays
  enabled while idle.
- PRONTO (WCNSS: Wi-Fi and Bluetooth) is not the problem: it slept about
  97 minutes, the whole J4 sleep, with Wi-Fi connected.

Next, one change per boot, read-only stats before and after each short
sleep: (1) a system-level domain idle state above cluster0/cluster1 with
the `system-pc` PSCI parameter (mode 3 at bit 8, so 0x353 in the low bits; the affinity-level field in bits 24-25 is 1 for cluster_pc and likely 2 here, 0x42000353;
to verify against TZ's PSCI before use), (2) LPASS idle: what holds the
codec clock, (3) MPSS: boot the modem idle (BRINGUP-MODEM.md) or confirm
it doesn't matter.

### Candidate: a system power domain (step A, 2026-11-15, offline)

`device/markw/kernel/patches/0017-arm64-dts-qcom-msm8953-add-a-system-power-domain-above-the-clusters.patch`
(moved to `patches/` after K1-K3 passed): `power-domain-system` in
`/psci` as the parent of cluster0/cluster1, with one state `system-pc`,
PSCI 0x42000353 (CPU 3, cluster 5, system 3 at bit 8, power-down,
affinity level 2), exit latency 11 ms as the vendor's `system-pc`
latency, min residency 100 ms to keep it out of short idles.
`tools/markw-rpm-stats` reads the RPM sleep and master stats (read-only).

Offline: firmware is PSCIv1.0 in OS-initiated mode (`/sys/kernel/debug/psci`,
"OSI is supported"; setting PC mode fails, so OSI stays), and in OSI the
highest domain to power off supplies the whole composite state
(`psci_set_domain_state` replaces it). `checkpatch --strict` clean; the
tree's `msm8953-xiaomi-markw.dtb` builds with W=1 and no dtc warning.
The probe DTB is oma14's probe DTB (touchscreen and watchdog `okay`)
decompiled, with only these nodes added (phandles 0xdb/0xdc above the
old maximum 0xda) and recompiled; the IMU's `mount-matrix` was copied
back byte for byte (a dts round trip reads its `\00` escapes as octal).
Probe `out/markw/probe-oma14-syspc/boot.img`: oma14's Image.gz, ramdisk,
header and command line unchanged; modules stay oma14's.

Known gaps: genpd doesn't tie the parent's state to the clusters' (the
vendor's `min-child-idx` does), so a cluster in retention under a
system-pc request is up to the firmware to refuse (it should answer
DENIED in OSI). No MPM yet: if every other master slept, XO could stop
with no MPM-routed wake interrupt. Here MPSS never sleeps (modem off),
so XO stays on and the GIC still wakes the CPUs.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| K1 | After the owner's go: `./DEBUGING_RUN.sh --restart --probe out/markw/probe-oma14-syspc/boot.img`; laptop `dmesg -w` stream once SSH answers | SSH; `uname -r` oma14; `/sys/kernel/debug/pm_genpd/power-domain-system` present; taint 0 | no SSH in 3 min, Oops, CPU stall | Power held about 30 s (MIUI), then the oma14 probe | medium |
| K2 | Read-only: after 5 minutes screen off, `pm_genpd/power-domain-system/idle_states` and `tools/markw-rpm-stats` | system-pc usage > 0 and APSS `numshutdowns` > 0, or a clear refusal (Rejected count) | lockups, RCU stalls | as K1 | low |
| K3 | Guarded `rtcwake -m freeze -s 60` (watchdog feeder 300 s, USB dead-man, kmsg stream) | resumes by RTC; APSS shutdowns rise; vlow stays 0 while MPSS is off | no resume | Power held, oma14 probe | medium |

#### Results (2026-11-15, `7.1.3-msm8953-oma14`, probe-oma14-syspc)

- K1 pass: RAM boot, SSH, system running; `power-domain-system` present
  as the parent of both clusters; taint 512 (the two known `clk-rcg2`
  DSI WARNs at 14 s), no Oops.
- K2 pass (no regression): 5.5 minutes awake, idle: system-pc usage 0,
  cluster0 never in cluster_pc while awake (S2 usage 0); no stall or
  lockup. The 100 ms residency keeps it out of awake idle here.
- K3 pass: guarded `rtcwake -m freeze -s 60` (feeder 300 s, USB dead-man,
  kmsg stream), cable in. Slept 61.0 s, woken by the RTC (IRQ 72),
  success 0 -> 1, fail 0, taint unchanged, no Oops or new WARNING,
  watchdog armed and disarmed. system-pc S2idle 1; cluster0/cluster1
  cluster_pc S2idle 1 each.
- **RPM master stats: APSS `numshutdowns` 0 -> 1**, the first apps
  handoff to RPM on markw. `vlow`/`vmin` still 0: MPSS (modem off) and
  LPASS (ADSP awake) still hold XO, as expected. PRONTO slept through it.
- Next: LPASS (what keeps the ADSP and the codec clock awake), then MPM
  for wake interrupts, then MPSS; XO shutdown needs all three.

### Candidate: gate the codec's mclk across suspend (step LPASS, 2026-11-15)

Read-only on oma14 (probe-oma14-syspc): every PCM `closed`, yet
`LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE` (9.6 MHz) is prepared and
enabled with one consumer, `c0f0000.codec` `mclk`. `msm8916-wcd-digital`
enables mclk in probe and disables it only in remove. On msm8953 that is a
q6afe clock, so the ADSP keeps it, and its XO vote, for the whole boot.
The vendor's `msm8x16-wcd.c` turns this clock on before every digital
register access and off 50 ms later, and off at codec suspend, so the
registers need it.

`device/markw/kernel/patches/0018-ASoC-codecs-msm8916-wcd-digital-gate-mclk-across-system-suspend.patch`:
system-sleep PM ops that put the regmap in cache-only mode and disable
mclk at suspend, and on resume enable it, leave cache-only and
`regcache_sync` (writes only what changed meanwhile). Offline: W=1 no
warning, `checkpatch --strict` clean. Built against the oma14 tree as an
unsigned `snd-soc-msm8916-digital.ko` (the build's signing key is not
kept; signatures aren't enforced, so it loads with taint E), sha256
`eb43466f…`, installed on the phone in
`/usr/lib/modules/7.1.3-msm8953-oma14/updates/` (depmod picks it over
the original, which stays in place).

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| L1 | After the owner's go: RAM boot `probe-oma14-syspc` again | SSH; module from `updates/` loaded; sound card present; codec clock enabled while awake as before | no SSH, no card | `rm` the `updates/` file, `depmod`, reboot | medium |
| L2 | Play a short tone (the speaker sounds), then guarded `rtcwake -m freeze -s 60` | resume; LPASS `numshutdowns`/XO time rise; no Oops | no resume | as L1 | medium |
| L3 | Play the tone again after the resume | sound as before (the codec kept its state) | silence | as L1 | low |

#### Results (2026-11-15, `7.1.3-msm8953-oma14` + candidate 0018 module)

- L1 pass: RAM boot of probe-oma14-syspc; `snd-soc-msm8916-digital` from
  `updates/`, taint 8704 (E for the unsigned module, W for the known DSI
  WARNs); sound card present; the codec clock on while awake, as
  designed (only suspend gates it).
- L2 pass: a tone played (`pw-play` rc 0, every PCM closed again after),
  then a guarded 60 s `rtcwake` freeze: resumed by the RTC, success 0 ->
  1, fail 0, no Oops or new WARNING, watchdog armed and disarmed.
  **LPASS XO-off time 0.1 s -> 61.2 s, shutdowns 5 -> 6**: the ADSP now
  sleeps through s2idle. APSS shutdowns 0 -> 1 again (system-pc).
  The codec clock is enabled again after the resume.
- L3: the tone played again after the resume (`pw-play` rc 0, no ASoC,
  q6afe or codec errors); the owner heard both tones, before the sleep and after the resume: L3 pass.
- Left holding XO: MPSS only (modem off). vlow/vmin still 0.

### Candidate: the MPM wakeup controller (step MPM, 2026-11-15)

Why before the modem: once MPSS sleeps too, RPM can shut XO down and the
GIC stops seeing interrupts; without MPM only RPM's scheduled wakeup
would bring the CPUs back, never the power key.

`device/markw/kernel/patches/0019-arm64-dts-qcom-msm8953-add-the-MPM-wakeup-interrupt-controller.patch`,
from the vendor's `qcom,mpm@601d4` (`msm8953-pm.dtsi`: vMPM in message RAM
at 0x601d4, IPC 0xb011008 bit 1, `interrupts = <0 171 1>`, 96 pins,
`gic-map` values are GIC hwirqs: SPMI `<88 222>` is SPI 190, TSENS
`<2 216>` is SPI 184, both matching mainline's nodes) and mainline's
agatti layout: `apss_mpm` slice in `rpm_msg_ram`, `mpm` in the RPM node,
SPMI's `periph_irq` through `&mpm 88`, `system_pd` a child of `mpm`.
`CONFIG_QCOM_MPM=y` (built in: the SPMI arbiter, and with it the power
key, charger, gauge and USB role, waits for it). TLMM gets no
`wakeup-parent`: `pinctrl-msm8953` has no MPM map. Built as
`7.1.3-msm8953-oma15` with 0017-0019 applied.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| M1 | After the owner's go: install oma15 modules, RAM boot the oma15 probe | SSH; `qcom_mpm` bound; `/proc/interrupts` shows the SPMI interrupt under the MPM domain; power key, charger status and battery as before | no SSH in 3 min (SPMI or USB role missing) | Power held about 30 s (MIUI), then probe-oma14-syspc | medium-high |
| M2 | Guarded `rtcwake -m freeze -s 60` | resume by RTC through MPM; APSS and LPASS sleep as in K3/L2 | no resume | as M1 | medium |
| M3 | Cable out, auto-suspend test copy, Power to wake (owner) | Power wakes it; success +1 | no wake | as M1 | medium |

#### Results (2026-11-15, `7.1.3-msm8953-oma15`, probe-oma15-mpm): stopped at M1

- Built and booted fine: oma15 modules installed, SSH, taint 512, no
  Oops; `qcom_mpm` bound (GIC hwirq 203 = SPI 171); SPMI through MPM works
  (power key, RTC alarm, VADC interrupts present; battery reads).
- **But cpuidle was gone:** `CPUidle PSCI: failed to create CPU PM domains
  ret=-517`, then `CPU 0 failed to PSCI idle` and `Failed to create
  psci-cpuidle device`; no `cpuidle` directory. A guarded 60 s rtcwake
  still resumed by RTC (IRQ 75), but MONOTONIC kept running (61.9 s)
  and APSS shutdowns stayed 0: with WFI only, nothing slept.
- Why: `system_pd` now has `power-domains = <&mpm>`. The PSCI domain
  driver probes at arch_initcall_sync and defers until the MPM's genpd
  provider exists; the MPM node sits in the RPM node, so its device only
  appears once rpm-proc probes, and deferred probes are retried only at
  late_initcall. `psci-cpuidle` is a faux device created at
  device_initcall that can't defer, so it fails for good in between.
  Moving the node would not fix it: the MPM driver itself registers at
  device_initcall.
- Rolled back to probe-oma14-syspc (oma14 with the 0018 module): cpuidle
  states back, system running.
- Next for MPM: keep the PSCI topology free of the MPM at boot and link
  them once the MPM probes (the MPM driver adding itself as the parent of
  the PSCI system domain, or the PSCI domain driver tolerating a parent
  that comes later); or check how agatti avoids it. 0017 and 0018 are
  unaffected.

#### Results (2026-11-15, `7.1.3-msm8953-oma16`, probe-oma16-mpm)

oma16 = 0001-0018 plus candidates 0019 (MPM DT), 0020 (dt_idle_genpd
skips a parent that isn't there yet) and 0021 (the MPM links itself as
parent of the domains that name it), `CONFIG_QCOM_MPM=y`. Build warnings
as oma15; DTB identical to oma15's.

- M1 pass: SSH, taint 512, cpuidle back (state0/state1);
  `dt-idle-genpd: /psci/power-domain-system: parent domain not ready, not
  linked` at 0.06 s, then `qcom_mpm ...: parent of
  /psci/power-domain-system` at 0.57 s; genpd shows the MPM over the
  system domain over both clusters. SPMI through MPM: power key, RTC
  alarm present; battery reads; system running.
- M2 pass: guarded 60 s rtcwake, cable in: slept 60.5 s (MONOTONIC 2.0 s
  of 62.5 s wall), woken by the RTC alarm, success 0 -> 1, fail 0, no
  Oops or new WARNING, watchdog armed and disarmed. system-pc S2idle 1;
  the MPM domain powered off once (vMPM written, RPM notified). RPM: APSS
  shutdowns 1, LPASS XO off 62.1 s, PRONTO 63.2 s; vlow/vmin 0 (MPSS).
- M3 (Power wake, cable out) next, with the owner.
- M3 pass: test copy of auto-suspend from `/run`, cable out, Power to
  blank: asleep 21:36:36-21:46:51 (about 10 min 15 s), **woken by the
  power key through the MPM-routed SPMI interrupt** (pm_wakeup_irq 69,
  `pm8941_pwrkey`), success 1 -> 2, fail 0, taint 512, no Oops; the
  owner heard the beeps and unlocked; post-resume watchdog ARMED, then
  DISARMED at its deadline. APSS shutdowns 1 -> 2.
- But LPASS did not sleep in M3 (XO-off time still 62.1 s, shutdowns 6):
  the test copy plays its beep right before `systemctl suspend`, so
  PipeWire likely still had the PCM open; in L2/M2 the sleep started
  seconds after the tone. To check: whether an open PCM at suspend keeps
  the ADSP up (q6afe port still running), and if so, suspend the stream
  (or let PipeWire close it) before sleep.

**LPASS after a tone, checked 2026-11-15 on `7.1.3-msm8953-oma16`** (cable in,
guarded 60 s `rtcwake -m freeze`, `tools/markw-rpm-stats` before and after):

| Run | Tone before the sleep | LPASS XO-off time | Result |
| --- | --- | --- | --- |
| m4 | about 10 s before | 62.1 -> 123.1 s | slept |
| m5 | none (a quoting bug in the test script stopped `runuser`) | 123.1 -> 184.9 s | slept |
| m6 | 1 s before, from the sleeper unit; the PCM still read `state: RUNNING` | 184.9 -> 184.9 s | stayed up |

Each run had success +1, fail 0, no Oops and no new WARNING. So the codec's mclk
gating (0018) holds. The ADSP stays up only when a stream is still open as the
phone sleeps, which is what M3's test copy did. PipeWire closes an idle sink
after a few seconds, so ordinary use reaches XO-off on the LPASS side. A sound
played right at suspend, a paused player still holding the device, or the test
copy's own beep keeps it up for that sleep. No kernel change is planned for
this. If it matters later, the auto-suspend hook can wait for
`/proc/asound/card0/pcm*p/sub0/status` to read `closed`.

**Adopted 2026-11-15:** candidates 0019-0021 are now patches 0019-0021, and
`markw.config` carries `CONFIG_QCOM_MPM=y` with the release name
`-msm8953-oma16`. The committed tree builds the kernel that passed M1-M3 (the
three patches match the oma16 build export byte for byte). The MPM must be
built in, never a module: the SPMI bus names it as its interrupt parent.

### Step MPSS: does a modem that never booted hold XO? (runbook N, 2026-11-15)

APSS, LPASS and PRONTO now vote sleep in s2idle (K3, L3, M3, m4-m6), and
`vlow`/`vmin` are still 0. The one master left is MPSS: `active_cores` 0x1
and `numshutdowns` 0 for the whole boot, because `qcom_q6v5_mss` stays
blacklisted (BRINGUP-MODEM.md step 4), so the modem never boots and never
tells RPM that it sleeps. Downstream boots the modem at every boot. The
question is whether a modem that boots and then idles votes sleep, letting
RPM reach XO shutdown.

Before the run: a fresh read-only backup of the six NV partitions,
`20261115T150215Z-after-miui` (MIUI had changed `modemst1`, `modemst2` and
`persist` since 2026-11-12's). All six sums match on both sides. Nothing
else changes on the phone: the modem starts by hand as in BRINGUP-MODEM.md
step 5 (rmtfs on RAM copies, partitions `ro=1`). ModemManager is not
started, so the modem isn't brought online, and no data is used.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| N1 | Read-only: `tools/markw-rpm-stats` | MPSS `numshutdowns` 0 | — | — | none |
| N2 | `systemctl start omamobile-markw-rmtfs tqftpserv`, `modprobe qcom_q6v5_mss`, `echo start` to the MPSS remoteproc's `state`, kmsg streamed | `running`, QRTR services listed, partitions `ro=1`, no crash loop | a crash or restart loop, eMMC errors | `echo stop`, then a reboot if it won't stop | medium |
| N3 | Two minutes idle, then `tools/markw-rpm-stats` | MPSS `numshutdowns` rises (the modem sleeps while awake idle) | — | as N2 | low |
| N4 | Guarded 60 s `rtcwake -m freeze` (watchdog feeder 300 s, USB dead-man, kmsg stream), cable in, no sound before it | resumes by RTC; `vlow` count above 0, or MPSS still awake with a reason | no resume; watchdog reset | Power held about 30 s (MIUI), then the oma16 probe | medium |
| N5 | `echo stop` to the modem, then stop rmtfs and tqftpserv | `offline`; partitions `ro=1` | — | reboot | low |

If XO shuts down in N4, the RTC alarm has to wake the CPUs through the MPM
(SPMI is MPM pin 88; the power key went the same way in M3). Only the
watchdog brings the phone back if it doesn't.

#### Results N (2026-11-15, `7.1.3-msm8953-oma16`, probe-oma16-mpm)

- N1: MPSS `numshutdowns` 0 for 41 minutes of uptime (modem never booted).
- N2 pass: rmtfs on RAM copies, tqftpserv, `qcom_q6v5_mss`, `echo start`:
  `running` 1.1 s later, partitions `ro=1`, no crash.
- N3 pass: two minutes idle without ModemManager, **MPSS `numshutdowns`
  0 -> 17, XO-off vote 111.6 s**: an idle modem sleeps by itself.
- N4: guarded 60 s `rtcwake -m freeze`, cable in, no sound. RTC wake (IRQ
  74), success 5 -> 6, fail 0, no Oops or new WARNING. MPSS, LPASS and
  PRONTO all voted XO off through the sleep (+147 s, +62 s, +63 s) and
  APSS power-collapsed (`numshutdowns` 5 -> 6), **yet `vlow` stayed 0**.
- N5 pass: modem `offline`, rmtfs and tqftpserv stopped, partitions `ro=1`.
- **APSS has `xo_count` 0 for the whole boot**: it hands off to RPM, but
  its sleep set still asks for XO. So the modem was not the last blocker;
  APSS's own XO vote is.

### What holds APSS's XO vote: two leaked clocks (2026-11-15, read-only)

`bi_tcxo` (the RPM XO clock, which votes in the sleep set too) has these
enabled children while idle, from `/sys/kernel/debug/clk`:
`vcodec0_clk_src`, `cci_clk_src`, `usb30_mock_utmi_clk_src` (cable in),
`blsp1_qup2_i2c_apps_clk_src` and `gpll0_early`. Two are leaks:

- **Venus**: `gcc_venus0_vcodec0_clk`, `_axi_clk` and `_ahb_clk` enabled
  once, though Venus never probes (no `venus.mdt`, probe -22; see NOTES.md
  2026-11-12). `venus_probe()` turns the core on with
  `pm_runtime_get_sync()`, and its error path ends with
  `pm_runtime_put_noidle()` and `pm_runtime_set_suspended()`, which never
  run the suspend callback, so the clocks stay on. Calling the callback
  wouldn't help either: `venus_runtime_suspend()` starts with
  `hfi_core_suspend()`, which fails with no firmware running. markw has no
  Venus firmware it can use, so the fix here is to disable the node.
- **CCI**: `gcc_camss_cci_clk`, `cci_ahb`, `camss_ahb` and `camss_top_ahb`
  (the CCI node's four clocks) enabled 6 times while `1b0c000.cci` reads
  `suspended`, after exactly 6 suspends in this boot. `cci_suspend()` skips
  a runtime-suspended device, but `cci_resume()` turns the clocks on
  regardless, and the autosuspend it then requests does nothing because
  the status still reads `suspended`. One leaked enable per resume. So the
  first sleep of a boot is free of it and every later one is not.
  Candidate `device/markw/kernel/candidates/0022-i2c-qcom-cci-dont-turn-the-clocks-on-at-resume-for-a-suspended-device.patch`
  uses `pm_runtime_force_suspend/resume` instead. checkpatch `--strict`
  0/0/0, W=1 no warning. The module is built against oma16 (unsigned, so
  taint E): `out/markw/i2c-qcom-cci-resume.ko`.

WirePlumber holds the camera nodes open (`/dev/video0`, `v4l-subdev*`,
`media0`), but nothing streams. camss and the sensors read `suspended`.

### Runbook O: drop the two leaks, one per boot

Probe `out/markw/probe-oma16-novenus/boot.img`: oma16's probe with one
DTB change, `venus@1d00000` `status = "disabled"` (a dts diff of the two
DTBs shows only that line). Modules stay oma16's.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| O1 | After the owner's go: `./DEBUGING_RUN.sh --restart --probe out/markw/probe-oma16-novenus/boot.img`, kmsg stream once SSH answers | SSH, oma16, no venus device bound, no `gcc_venus0_*` enabled, taint as before, display, Wi-Fi and sound as before | no SSH in 3 min, Oops | Power held about 30 s (MIUI), then the oma16 probe | low |
| O2 | Modem started as N2; a first guarded 60 s sleep, cable out (a detached unit waits for the unplug, owner unplugs and replugs) | APSS `xo_count` rises; `vlow` count above 0 if nothing else holds XO | no resume, watchdog reset | as O1 | medium |
| O3 | Install `i2c-qcom-cci-resume.ko` to `updates/`, `depmod`, reboot into the same probe (owner's go) | CCI clocks at 0 after each of three guarded sleeps; the cameras still enumerate | camera probe errors | remove the file, `depmod`, reboot | low |

If XO shuts down in O2, the RTC alarm has to wake through the MPM (SPMI,
pin 88), as the power key did in M3. The watchdog doesn't guard the sleep
itself: `qcom_wdt` stops the timer in its late system-suspend callback. A
phone that doesn't wake needs Power held for about 30 s (MIUI), then the
probe again.

#### Results O (2026-11-15, `7.1.3-msm8953-oma16`, probe-oma16-novenus)

- O1 pass: the reboot went straight to fastboot (no MIUI, so the morning's
  NV backup still holds). `venus@1d00000` `disabled`, no Venus device,
  `gcc_venus0_*` all 0, taint 512 as before, no Oops, Wi-Fi, display and
  the sound card up. icc and gcc still force `sync_state` at 12 s (the
  probe's command line keeps `fw_devlink.sync_state=timeout`). Awake,
  screen on, `bi_tcxo`'s enabled children are only the display
  (`dsi0vco`, `esc0`, `vsync`), USB (cable in) and `gpll0_early`.
- O2: modem started as N2, then a detached unit waited for the owner's
  unplug, slept a guarded 60 s and beeped twice after the resume. RTC
  wake (IRQ 74), success 0 -> 1, fail 0, no Oops. **APSS voted XO off for
  the first time: `xo_count` 0 -> 1, 61.5 s.** MPSS (+59 s), PRONTO
  (+62 s) and LPASS (+62 s) voted XO off through the same sleep. `vlow`
  is still 0, so all four masters voting XO off is not enough.
  `gcc_camss_cci_clk` read 0 before this first sleep and 1 after it: the
  one leaked enable per resume that candidate 0022 fixes.
- The modem was stopped afterwards (`offline`); partitions `ro=1`.

### What else keeps XO on: the MPM wakeup time (2026-11-15, offline)

- Read-only, awake: the vMPM words at 0x601d4 read `00000000 00000000`
  first, then enable `0 0 0x01000000` (pin 88, SPMI), edges 0, polarity
  `0 0 0x01000000`, status 0.
- Downstream `mpm-of.c` (Xiaomi `markw-m-oss`) writes those first two
  words in `msm_mpm_set()`: the absolute arch-timer time (19.2 MHz) at
  which the APSS wants to be woken. For system suspend `lpm-levels.c`'s
  `get_cluster_sleep_time()` returns `~0ULL`, so the words say "no
  timer". Mainline `irq-qcom-mpm` skips both words (the `+ 2` in its
  offsets) and leaves them 0, a wakeup that is already due. RPM likely
  won't shut XO down for a sleep it thinks is over.
- Candidate
  `device/markw/kernel/candidates/0023-irqchip-qcom-mpm-tell-RPM-there-is-no-wakeup-timer-in-s2idle.patch`:
  in `mpm_pd_power_off()`, write `U64_MAX` while `idle_should_enter_s2idle()`,
  and 0 otherwise. Outside s2idle nothing changes: RPM can't see the
  CPUs' timers, and with XO off nothing would fire them. checkpatch
  `--strict` 0/0/0. The MPM is built in, so this needs kernel oma17
  (0001-0021 plus 0023).

### Runbook P: the MPM wakeup time (oma17)

Kernel `7.1.3-msm8953-oma17` = the committed patches 0001-0021 plus
candidate 0023 (W=1: the same three warnings as oma16, none in the MPM).
Probe `out/markw/probe-oma17-mpmt/boot.img`; its DTB is byte for byte the
no-Venus probe's. oma17's modules (820) were installed before the reboot.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| P1 | After the owner's go: `./DEBUGING_RUN.sh --restart --probe out/markw/probe-oma17-mpmt/boot.img` | SSH, oma17, taint as before, `/sys/kernel/debug/pm_genpd` with the MPM above `power-domain-system`, cpuidle states as on oma16 | no SSH in 3 min, Oops, cpuidle missing | Power held about 30 s (MIUI), then the no-Venus oma16 probe | low |
| P2 | Read-only after some minutes awake: vMPM words still 0 (no s2idle yet), `vlow` 0 (cpuidle unchanged) | as expected | `vlow` above 0 while awake (idle changed) | as P1 | low |
| P3 | As O2: modem up, cable out, one guarded 60 s sleep, two beeps after it | RTC wake; **`vlow` count above 0** | no wake (Power held about 30 s) | as P1 | medium |

#### Results P (2026-11-15, `7.1.3-msm8953-oma17`, probe-oma17-mpmt)

- P1 pass: RAM boot to oma17 (no MIUI), taint 512 (the two known DSI
  `clk-rcg2` WARNs at 14 s), no Oops, MPM still the parent of
  `power-domain-system`, cpuidle WFI and cpu-power-collapse, display,
  Wi-Fi and sound up.
- P2 pass: awake, the vMPM wakeup words read 0 and `vlow` 0, so idle is
  unchanged.
- P3 (cable out, modem idle, first sleep of the boot): the vMPM wakeup
  words read `ffffffff ffffffff` afterwards, so 0023 writes them. The
  Power key woke it after about 45 s (IRQ 69, `pm8941_pwrkey`). APSS
  (+44.6 s), MPSS, PRONTO and LPASS all voted XO off, **`vlow` still 0**.
  So the wakeup time alone was not the blocker.

### IPA: ipa2-lite never turns its RPM clock off (2026-11-15)

`ipa_clk` (an RPM clock with a sleep-set vote, 9.6 MHz) stays enabled for
the whole boot. ipa2-lite takes it with `devm_clk_get_enabled()`, and its
runtime suspend only lowers the rate to 9.6 MHz, never disabling it. The
vendor IPA driver gates its clock and bus vote when it has no active
clients.

Test Q, same boot: modem stopped, `7900000.ipa` unbound from `ipa`
(remove returns early while the modem is down; netdevs, IRQs, QMI and the
clock are devm, `ipa_clk` 0, taint unchanged), modem started again
without IPA: `running`, MPSS still sleeps on its own (49 shutdowns in two
minutes). Then a second guarded 60 s sleep, cable out. RTC wake, success
1 -> 2, fail 0, no Oops. **APSS power-collapsed but did not vote XO off**
(`numshutdowns` 1 -> 2, `xo_count` stayed 1): this was the boot's second
sleep, and the CCI clocks already held one leaked enable from the first
resume (`gcc_camss_cci_clk` 1 before the sleep). So Q says nothing about
IPA; the CCI fix has to come first.

### Runbook R: the CCI fix, then IPA

`i2c-qcom-cci.ko` with candidate 0022, built against oma17 (unsigned,
taint E): `out/markw/i2c-qcom-cci-resume-oma17.ko`, installed as
`/usr/lib/modules/7.1.3-msm8953-oma17/updates/i2c-qcom-cci.ko` (depmod).
The modem is stopped again, partitions `ro=1`.

| Step | What | Expect / pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| R1 | After the owner's go: reboot into the same oma17 probe | `modinfo -n i2c_qcom_cci` is the updates file; both camera sensors bound; taint adds E only | camera probe errors, Oops | delete the file, `depmod`, reboot | low |
| R2 | Two guarded 60 s `rtcwake` sleeps, cable in | `gcc_camss_cci_clk` 0 after each | the count rises | as R1 | low |
| R3 | Modem stopped, IPA unbound, modem started (as Q), then a guarded 60 s sleep, cable out | APSS `xo_count` rises; `vlow` above 0 if IPA was the last holder | no wake (Power held about 30 s) | as R1 | medium |

#### Results R (2026-11-15/16, `7.1.3-msm8953-oma17` + 0022 module)

- R1 pass: `i2c_qcom_cci` from `updates/` (taint 8704 = 512 + E for the
  unsigned module), both camera sensors bound and runtime suspended, CCI
  clocks 0.
- R2 pass: two guarded 60 s `rtcwake` sleeps, cable in, RTC wakes (IRQ
  72), success 0 -> 2, fail 0, no Oops or new WARNING;
  `gcc_camss_cci_clk` 0 after each. 0022 fixes the leak.
- **R3: the SoC reached VDD minimization for the first time.** IPA
  unbound (`ipa_clk` 0), modem started without it, cable out, the boot's
  third sleep (so the CCI fix was carrying it). Guarded 60 s sleep, RTC wake
  (IRQ 72), success 2 -> 3, fail 0, no Oops. **`vmin` count 0 -> 4,
  61.3 s accumulated**; `vlow` stayed 0 (on this RPM the deep mode taken
  is `vmin`). APSS +61.4 s, MPSS +58.8 s, PRONTO +61.9 s and LPASS +61.8 s
  of XO-off votes. P3 differed from R3 only in IPA (bound in P3), so
  **ipa2-lite's always-on RPM clock was the last blocker**.
- The modem then ran overnight without IPA (8 h 23 min, `running`, no
  crash, partitions `ro=1`) and was stopped in the morning.

What the deep sleep needed, in order of discovery: APSS's system-pc
domain (0017), the codec mclk gated (0018), the MPM (0019-0021), a
booted modem that idles, Venus disabled (failed probe leaks its clocks),
the CCI resume leak fixed (0022), the vMPM wakeup time in s2idle (0023;
not shown necessary on its own), and IPA's clock off.

Next, one change per boot: ipa2-lite gating its clock when runtime
suspended (its registers must not be touched then), Venus disabled in the
markw dts, then the sleep current measured with the coulomb counter
against the 52 mA of an awake, screen-off phone.
