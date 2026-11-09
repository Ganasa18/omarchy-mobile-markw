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
