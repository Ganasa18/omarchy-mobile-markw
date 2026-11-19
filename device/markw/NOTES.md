<!-- SPDX-License-Identifier: MIT -->
# Redmi 4 Prime (markw) bring-up notes

Findings from real hardware, newest first. Plan: [ENGINEERING-PLAN.md](ENGINEERING-PLAN.md); first-light runbook: [BRINGUP-M1.md](BRINGUP-M1.md).

## 2026-11-19: M9 P3 fails, lk2nd in `boot` does not start; rolled back (7.1.3-msm8953-oma19)

lk2nd 23.1 written into `boot` by `tools/markw-install lk2nd` (OKAY). After
a reboot and a Power-only cold boot the Mi logo stayed and stock aboot's
fastboot answered (no lk2nd variables, `oem log` unknown). While `boot`
held lk2nd, a RAM boot of the same lk2nd failed too (black screen, no USB).
MIUI's backed-up `boot.img` written back from stock fastboot, `userdata`
kept: the RAM path works again, `boot` hashes as the backup, the eMMC is
`ro=1`, MIUI not booted. Cause unknown; details and next steps in
[BRINGUP-M9.md](BRINGUP-M9.md) P3.

Retry the same day: `boot` written with lk2nd followed by the oma19 probe
at 512 KiB (no MIUI leftovers where lk2nd looks), then a boot with no
reboot reason at all (cable out, Power only): the Mi logo again. lk2nd
loaded from `boot` by stock aboot does not come up on this phone; loaded
by `fastboot boot` it always does. MIUI ran once in between (a poweroff
with the cable in powered it on), so the NV set needs a check.

## 2026-11-19: the idle shell ran a 60 Hz animation timer (7.1.3-msm8953-oma19, omamobile-shell 0.2.44 to 0.2.45)

With nothing on screen to animate, quickshell's main thread woke about 75
times a second and used about 2 s of CPU a minute: on the lock screen, at
home, behind a full-screen app and with the panel off (`bl_power` 4) alike.
Hyprland woke 3-4 times a second, so the shell was sending no frames.

How it was found, read-only (no strace or gdb on the phone):

- Wakeups per thread from `/proc/<pid>/task/*/status` context switches over
  10 s: only the main thread, 67-75 a second in every state.
- The main thread's `ppoll` timeout, read from `/proc/<pid>/syscall` and the
  timespec in `/proc/<pid>/mem`: 13-16 ms in almost every sample, the tick of
  Qt's animation driver.
- `eu-stack -1` samples taken outside `ppoll`:
  `QAnimationDriver::advanceAnimation` -> `QSequentialAnimationGroupJob` ->
  `QQuickItem::setScale`, and a written QML property whose binding emits
  `rotationChanged`.

That pair is the incoming-call card: its caller ring pulses in `scale` and
its answer handle wiggles through a `phase` property that `rotation` binds
to, both while `ringing`. `Call.qml` keeps the card built inside the hidden
call window and passes it mode `"incoming"` whenever there is no call in
progress, so `ringing` was true all the time and both loops ran behind a
hidden window.

Fix (omamobile-shell 0.2.45): `CallCard.ringing` also requires the card to be
visible. After a shell restart, unlocked at home: quickshell 2.1 wakeups a
second (from 74.5), 3 CPU ticks in 10 s (from 29), and the `ppoll` timeout
back to about 1 s (the clock timers). A ringing card is visible, so the
offscreen call render test still draws it.

## 2026-11-19: systemd audit (7.1.3-msm8953-oma19, device-markw 0.1.28, read-only)

Taken on a cold-booted phone, 48 min up, cable in, screen off.

**Healthy:**
- Boot is 22.5 s (kernel 4.3 s, userspace 18.2 s), with no failed unit,
  system or user.
- PID 1 used 20 ms of CPU a minute, and the whole phone was 1.7 % busy
  over 20 s.
- Memory: 1.1 GiB available of 2.8 GiB, zram swap unused. quickshell
  holds 520 MiB RSS and Hyprland 184 MiB.
- No surplus system services: each running one has a job on the phone
  (tqftpserv and rmtfs for the modem, networkd for `usb0`, udisks2 for
  OTG drives).

**Findings, worst first:**
1. NetworkManager logs `device (qrtr0): mtu: failure to set MTU` and
   `do-change-link[6]: failure 22` every 30 s while data is up (99 times
   in 48 min). The bearer reports MTU 1500, but `qmapmux0.0` is 1496: its
   parent `rmnet_ipa0` is 1500 and QMAP takes 4 bytes. `rmnet_ipa0`
   allows up to 2012. Fixed in device-markw 0.1.29 with a udev rule that
   sets `rmnet_ipa0` to 1504. Tried by hand first: the mux link took 1500,
   no warning in the next 40 s, and a 1500-byte don't-fragment ping went
   through.
2. quickshell used 1.95 s of CPU a minute with the panel off
   (`dpmsStatus: 0`), the largest user by far (1 min 39 s since boot).
   It matters while the phone is awake with the screen off (cable in,
   audio, stay-awake), and probably while the screen is on as well.
3. The Wi-Fi regulatory domain is world (`00`): `set-wireless-regdom`
   exits 1 at boot because `/etc/conf.d/wireless-regdom` names no
   country. Setting it is a per-phone setting and stays out of the repo;
   it was set on this phone by hand (the owner's go).
4. feedbackd 0.8.9's udev rule runs `/usr/libexec/fbd-ledctrl`, but the
   package installs `/usr/lib/fbd-ledctrl`, so three LED lines fail at
   each boot. Our own LED rules don't use it.
5. `plocate-updatedb.timer` and `man-db.timer` run daily, but both
   services already carry `ConditionACPower=true` (man-db upstream,
   plocate through Omarchy's `ac-only.conf`), so they never run on
   battery. Not an issue. device-markw 0.1.29 added the same condition
   again before this was seen; 0.1.30 drops it.
6. udev's coldplug sits idle from about 7.4 s to 13.1 s: module
   autoloads (camss, rtc, qrtr, the compass) only begin at 13.4 s. Not
   chased, since the whole boot is 22.5 s.
7. systemd-homed, userdbd and nsresourced run with no home areas. They
   stay, since `pam_systemd_home` is in the login stack.

## 2026-11-19: overnight soak with data up passes (7.1.3-msm8953-oma19, device-markw 0.1.27, modemmanager 1.24.2-2.3)

- ModemManager 2.3 (netlink use-after-free fixed) passed the 1 s and 5 s
  reconnects that crashed 2.1, and a guarded 60 s data-on suspend
  (BRINGUP-SUSPEND CD).
- Then an overnight auto-suspend with data on LTE (BRINGUP-SUSPEND CE):
  - 11 h 50 min asleep, woken by Power, `vmin` for 97 % of it;
  - about 12.2 mA by the charge counter (144 mAh, 100 -> 97 %);
  - ModemManager kept its PID through the sleep and the reconnect, no
    core dump, no kernel error.
- The timeout-guarded logger recorded every sample this time.
- This closes AA and the long-sleep risk in BRINGUP-M9 §1.
- Auto-suspend is still started by hand. Enabling it at boot is next,
  with the owner's go.

## 2026-11-18: second soak, vmin 97 % of the sleep, ModemManager segfaults on resume (7.1.3-msm8953-oma19, device-markw 0.1.27, modemmanager 1.24.2-2.1)

- `omamobile-autosuspend` started by hand again, mobile data up on LTE.
  Cable out at 13:58; it suspended at 13:59:03 and slept until the
  owner's Power press at 16:40:00 (`pm_wakeup_irq` 69, `pm8941_pwrkey`),
  the cable back in a minute later: one suspend, 9657 s, success 1,
  fail 0, no stray wake, no Oops, no new kernel warning.
- The 0.1.27 hook did its job: ModemManager disconnected the bearer on
  "about to suspend" (the patched cleanup, no abort), the hook logged
  `rmnet_ipa0 down: no data link`, and RPM `vmin` counted 9353 s, 97 % of
  the sleep. UPower read 100 % before the sleep and 99 % at the wake, so
  roughly 13 mA or less. The minute logger wrote nothing from 13:24 to
  16:44 for a reason not found yet, so there is no counter reading for
  the sleep; the next soak's logger reads each value under `timeout`.
- On resume ModemManager reconnected and died with SIGSEGV right after
  "net link qmapmux0.0 created (mux id 1)": a call through a NULL
  function pointer (pc 0x30, from `ModemManager+0x188b0c`). systemd
  restarted it and data came back on LTE. It is the quick-reconnect crash
  of BRINGUP-MODEM.md: CLOCK_MONOTONIC stops in suspend, so to
  ModemManager the reconnect came about a second after the pre-suspend
  disconnect, inside the 1-5 s window that crashed there.
- Cause, from a 1.24.2-2.2 build with `modemmanager-debug` (its `.text`
  is byte for byte 2.1's, so the 2.1 core maps onto it): a use-after-free
  in `transaction_complete()` (`src/mm-netlink.c:242`, inlined into
  `netlink_messages_cb`). `g_hash_table_remove()` frees the transaction,
  then `tr->completion_fn` is read from it: `blr` through `[x25+32]`, the
  field at offset 32. Upstream fixed it in `9317cbc4702c` ("netlink: fix
  use-after-free calling completion_fn on transaction completion",
  2026-10-04), on `main` and in no release yet. modemmanager 1.24.2-2.3
  carries it as 0002. Until 2.3 is installed and survives resumes, every
  resume with data on risks a crash, and auto-suspend stays off at boot.
- Minor: the autosuspend loop's screen check opens a `runuser` session
  every 5 s, 495 pairs of PAM lines in the journal by 16:46.

## 2026-11-18: first auto-suspend soak, one 19 h sleep without vmin (7.1.3-msm8953-oma19, device-markw 0.1.26)

- `omamobile-autosuspend` started by hand for the boot (still disabled at
  boot). Cable out about 13:15; it suspended at 13:17 and slept until the
  owner's Power press at 08:37 the next morning: one suspend, 69630 s,
  success 1, fail 0, no stray wake, no Oops. Unlock, touch, Wi-Fi and USB
  came back; ModemManager restarted and mobile data reconnected by itself.
- But RPM `vlow` and `vmin` stayed 0, although APSS, MPSS, PRONTO and LPASS
  each voted XO off for the whole sleep. The gauge fell 100 -> 89 % (a rough
  23 mA; no counter reading at the unplug), against about 11.6 mA in vmin.
- Cause: ModemManager (`--test-quick-suspend-resume`) aborted on "system is
  about to suspend", `mm_iface_modem_count_bearers: assertion failed: (max
  >= ctx.count)`, two minutes after the hotspot test's disconnect and
  reconnect. Its `qmapmux0.0` stayed behind, down, and the sleep hook took
  any link on `rmnet_ipa0` as a data link (`rmnet_ipa0 stays up: qmapmux0.0
  carries data`), so the IPA clock held XO through the sleep.
- device-markw 0.1.27: the hook counts a data link only when it is itself
  up. ModemManager's crash stays open: it is the third in two days
  (SIGSEGV 2026-11-16 19:41 and 2026-11-17 11:29, this SIGABRT), and mobile
  data was off for the whole sleep, so test AA (data across sleeps) is not
  answered yet.

## 2026-11-17: the hotspot shares mobile data (7.1.3-msm8953-oma19, shell 0.2.43, device-markw 0.1.26)

- Owner test from the Hotspot page: the access point came up (WPA2, PMF
  off as `omamobile-hotspot` sets it for wcn36xx), the dispatcher opened
  DHCP, DNS and forwarding on `wlan0`, and a phone joined by the QR code
  and got an address from dnsmasq.
- First try without internet: mobile data was off. wcn36xx has one radio,
  so the hotspot can't relay the phone's own Wi-Fi client link; it shares
  mobile data only (the page's footnote says so). Second try with data on:
  the joined phone browsed, about 3 MB through `FORWARD` and out of
  `qmapmux0.0`, NAT by NetworkManager's `nm-shared-wlan0` nftables table.
- The 20 min dead-man (`nmcli connection down Hotspot`) ended the first
  try on time and Wi-Fi client mode came back by itself, the dispatcher
  removing its four rules.
- Shell log: a QML binding loop on a `Text` width in `HotspotPanel.qml`
  (line 213), harmless; to fix in the next shell version.

## 2026-11-14: Power-only display wake works on the phone (7.1.3-msm8953-oma11)

- First live attempt (phone locked) stopped: the shell restart reported the
  lock not re-secured, and both rollbacks restored the files. Retried with
  the phone unlocked and lit: all automatic gates passed (input wake keeps a
  dark panel dark, locked and unlocked; Power path lights it; lock secure).
- Owner check passed: double tap on a dark screen stays dark; Power + PIN
  work. The touchscreen device stays enabled. Hand-copied live files, not yet
  packaged; auto-suspend still off. Details: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-14: unplugged battery control retrieved (7.1.3-msm8953-oma11)

- Capture ended normally on replug. Unplugged duration 46.884 min, reported
  capacity 99 -> 92%. Excluding the first 10 min, 36 screen-off samples averaged
  -49.183 mA (discharging); capacity 96 -> 92% over 36.513 min. Do not extrapolate
  lifetime from this settling/quantized percentage reading.
- Actual suspended-time delta 0, suspend success/fail unchanged at 2/0;
  autosuspend was inactive. This is the awake screen-off control, not a
  suspend saving. Uptime continued to 1 h 40 min without restart.
- Touchscreen edt_ft5x06 has no wakeup attribute on its input/controller
  ancestry and no kernel wake-source entry. Tap-to-PIN while awake therefore
  needs lock/display policy, not disabling the global touchscreen device.
  Replacement policy prepared and syntax checked; live gates pending.
  Details: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-14: touch policy rolled back; battery baseline started (7.1.3-msm8953-oma11)

- After the owner asked whether the phone was stuck, fresh SSH still worked
  at 48 minutes uptime. Panel bl_power was 0 but Hyprland touchdevice.enabled
  was false. Restored the original brightness script, removed the live hook,
  and verified touchdevice.enabled=true through a fresh connection. No reboot.
  Owner's earlier physical Power/PIN check passed, but this later mismatch
  means the policy is not ready. Candidate helper stays unstaged in packages.
- Started read-only markw-battery-baseline.service. READY was verified before
  telling the owner to unplug. tools/markw-battery-log waits for Discharging,
  records raw telemetry for up to one hour, and ends on replug. Autosuspend
  remains inactive: this is the screen-off awake control, not a suspend result.
  No saving or average suspend current has been measured.

## 2026-11-14: gate touch input with display power (7.1.3-msm8953-oma11)

- Owner requests Power-only wake: double tap on a dark screen showed PIN.
  markw's optional display-touch hook now disables compositor touch input on
  display off, restores it before display on; Power remains a keyboard bind.
  Complete transitions are serialized to prevent a lit panel with touch off.
- Actual phone off/on gate passed: bl_power 4 / touch=false, then 0 / true;
  fresh SSH remained available. Original script backed up; rollback timer
  stopped after verification. No restart or automatic suspend enabled.
- Physical Power/double-tap/PIN check is pending owner feedback. A compositor
  reload can reset runtime input settings until the next on/off transition.
  Battery benefit remains unmeasured. See [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md)
  for tests, live rollback and package-update handling.

## 2026-11-14: second oma11 boot passed 20 s and 120 s suspend (7.1.3-msm8953-oma11)

- Owner-approved fresh RAM boot; measured sleep 20.522 s and 121.428 s.
  Same new boot throughout, success 0 -> 2, fail 0, RTC IRQ 71 wakes,
  fresh SSH returned and watchdog disarms verified. Total candidate evidence:
  eight passing cycles across two boots, including one two-minute sleep.
- Preflight taint 512 came from two initial DSI pclk0 clock warnings already
  documented on oma1/postmarketOS in BRINGUP-KERNEL.md. Tests accepted only
  this sealed baseline; no additional warning or taint bit appeared.
- Auto-suspend stays disabled; longer sleeps and more boots remain. Battery
  saving is unmeasured: this board has no exported charge/energy counter.
  Details: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-14: six short sleeps passed on one oma11 boot (7.1.3-msm8953-oma11)

- Five owner-approved repetitions after the first trial all passed:
  approximately 20.967, 20.437, 21.307, 19.932 and 19.841 s suspended.
  Same original boot ID throughout; success 1 -> 6, fail 0, taint 0,
  RTC IRQ 74 on each wake. Fresh SSH worked after 35 s each time.
- Each trial had a fresh laptop capture, watchdog feeder and USB recovery
  timer. Every disarm was verified; final PID absent and all batch guards
  inactive. No manual cable replug or reboot during the batch.
- Auto-suspend remains disabled. Earlier kernels also had passing boots,
  so 6/6 on this boot does not prove the root cause fixed. Next proposed
  owner-approved gate: fresh oma11 boot, then 20 s and 120 s tests.
  Details: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-14: first oma11 20 s suspend passed (7.1.3-msm8953-oma11)

- One owner-approved `rtcwake -m freeze -s 20`, under laptop capture,
  watchdog feeder and USB recovery timer: same boot ID, success 0 -> 1,
  fail 0 -> 0, taint 0. No restart in this trial.
- Realtime minus monotonic unit duration gives about 20.183 s asleep;
  wake IRQ 74 maps to pm8xxx_rtc_alarm. Original SSH stream reset, but a
  fresh login after the recovery window succeeded without cable replug.
- Feeder deadline completed with successful disable ioctl/magic close;
  transient guards were already gone at cleanup. Treat absent timer
  units as expected and disarm watchdog independently.
- This is only one successful boot/cycle; older kernels had passing boots
  too. Auto-suspend stays disabled pending repetitions, fresh boots and
  long sleeps. Details/evidence: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-14: oma11 candidate boots; suspend not yet tested (7.1.3-msm8953-oma11)

- DWC3 role-deferral candidate booted through lk2nd in RAM with its own
  matching modules. oma10 modules retained for rollback; nothing flashed.
- Fresh SSH: taint 0, no failed system units, no captured Oops/panic.
  Watchdog autoload stayed blocked; explicit load under laptop capture
  and read-only binding/NOWAYOUT preflight succeeded without arming it.
- Only s2idle offered, pm_test none, suspend success/fail both 0.
  Auto-suspend remains disabled. Await separate approval for one 20 s
  attended test; this boot does not establish that suspend is fixed.

## 2026-11-14: watchdog safety gate passed (7.1.3-msm8953-oma10)

- RAM-only safety probe enables the existing watchdog node with a
  separate overlay and blocks qcom_wdt autoload. Explicit module load
  under laptop kmsg capture succeeded; kernel taint remained 0.
- CONFIG_WATCHDOG_SYSFS is off: absent identity/timeout/state attributes
  do not mean the driver failed. The guarded `tools/markw-watchdog-feed`
  checks binding/NOWAYOUT before opening, then uses standard ioctls.
- Fresh SSH confirmed `ARMED: qcom_wdt, timeout=30s`; stopping the unit
  confirmed successful disable ioctl and magic close. Same boot ID,
  PID removed, service inactive, no new captured Oops/panic. No deliberate
  watchdog bite or suspend was tested.
- qcom_wdt stops in suspend_late and restarts in resume_early. This
  safety net cannot recover a hang while it is stopped for sleep.
  Auto-suspend remains disabled; oma11's DWC3 candidate is still unbooted.
  Commands/results: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

## 2026-11-12: the interconnects stayed at their boot maximum (7.1.3-msm8953-oma10)

- **Every interconnect vote was INT_MAX for the whole boot**
  (`/sys/kernel/debug/interconnect/interconnect_summary`: `slv_ebi`,
  `mas_apps_proc`, `mas_oxili` ... 2147483647), so the buses and the DDR
  ran at their top rate with the screen off. The icc providers keep that
  boot maximum until their `sync_state`, which waited on a consumer that
  never probes: Venus (`1d00000.venus`, no `venus.mdt`). The phone's own
  Venus firmware (modem partition, `image/venus.*`) loads but the driver
  rejects it ("Unsupported property: 0", probe -5), so that is no way out.
- **Fix: `fw_devlink.sync_state=timeout`** on the probe's command line
  (`initramfs/build`): "Timed out. Forcing sync_state()" for gcc and the
  three qnoc providers at 11.5 s, after which the votes are the real ones
  (`slv_ebi` about 1-1.6 GB/s idle, peaks on demand). Display, SD card
  (89 MB/s read), USB, Wi-Fi and every unit as before.
- **Measured** (`probe-m23-oma10-syncstate` = m22 with only that argument
  added; unplugged, screen off, Wi-Fi and modem off, `power-log.py` every
  20 s): m22 60 mA median (61.7 mean, 50 samples), m23 50 mA median (53.3
  mean, 62 samples). About 16 % less; most of the rest is a phone that
  never suspends.
- **The battery percentage misleads after an unplug:** it fell 7 points in
  22 minutes at 50 mA (about 1.2 %/h by the current), following the
  voltage settling from 4.32 to 4.15 V. Judge drain by `current_now`, not
  by `capacity`; the "70 % overnight" came from the same gauge.
- Still open: `clk_ignore_unused pd_ignore_unused` keep unused clocks and
  power domains on; quickshell uses about 450 ms of CPU every 20 s with the
  screen off.

## 2026-11-12: desktop mode flicker, app launch delay, storage speed (7.1.3-msm8953-oma10)

- **Desktop mode flickered on the lock screen after a wake: Omarchy's
  clamshell sync put the panel's scale back.** `omarchy-hyprland-monitor-clamshell`
  (run by `omarchy-hyprland-monitor-watch` on every monitor event, again
  1, 3 and 7 s later, and by `omarchy-system-wake`) treats `DSI-1` as a
  laptop's internal panel and applies `hl.monitor({ output = "DSI-1",
  scale = 2 })` from `monitors.lua`, without a transform. In landscape
  desktop mode (1.5, transform 3) the scale jumped to 2 about 1.4 s after
  the power key, the shell's `reapply` reloaded Hyprland, and every
  reload ran `monitors.lua`'s phone rule before `desktop.lua`'s, a modeset
  through the phone's scale on the way: the lock screen showed both
  sizes at once. Fixed by omamobile-omarchy patch 0018 (clamshell only
  where `omarchy-hw-laptop`) and by `reapply` applying `desktop.lua`'s
  monitor rule alone with `hyprctl eval`, at most once per 5 s
  (omamobile-shell 0.2.37). Checked: three power-key sleep/wake cycles
  stayed at 1.5/3 with no reload, and the owner's own lock/wake too.
- **A tap took about a second to show anything; the microSD is not the
  cause.** Read-only O_DIRECT on the root card (Lexar 633x 32 GB, U1 A1,
  running UHS SDR104 at 200 MHz): 78 MB/s sequential, ~2650 random 4K
  reads/s (median 0.36 ms); the eMMC (HS400) 258 MB/s and ~3790/s.
  Files (Nautilus) mapped its window ~1.0 s after a launch warm and
  2.2-3.7 s cold: ~0.6 s is the app itself, the rest the launch chain
  (`omamobile-launch` ~0.2 s, `uwsm-app` and `gtk-launch` ~0.2 s).
  Dropping `gtk-launch` (`uwsm-app -- ID.desktop`) gained nothing
  measurable. The fix is feedback instead: a launch splash (icon and
  name) the moment a tile or drawer entry is tapped (omamobile-shell
  0.2.37). zram (1.4 GB zstd) is in use; nothing swaps to the card.
- **The power key's long-press timer fired after a slow lock.**
  `omamobile-keys` dropped the press marker only after the short press
  had run, and locking waits up to 3 s for the lock to be secure (the
  long press is 0.6 s), so the long press ran too: the system menu, or
  a wake of the screen it had just turned off. The marker now goes on
  release (omamobile-shell 0.2.37, `test/keys.sh`).

## 2026-11-07: notification LED and haptics (7.1.3-msm8953-oma6)

- **The USB rescue brought a dead link back (device-markw 0.1.17).** On
  `probe-m13-oma6-wdt` the laptop lost USB SSH while the phone ran on.
  The kernel log has `dwc3-qcom: remote wakeup not configured` at 160 s,
  as when the host suspends the port, and an unexplained role change
  none to device at 35053 s with no link after it. At the owner's replug
  (36806 s) the rescue unit found no carrier for 15 s, rebound the
  gadget, and logged "link back" 6 s later; SSH answered. Whether
  Windows' selective suspend of the NCM adapter is the first cause is
  not yet checked.
- **The LED is an AW2013 (`1-0045`, `leds_aw2013`) with three channels
  at 5 mA each.** Red and green light (owner, by eye). Blue never lit,
  not even held on for 15 s, while the chip's registers showed it set
  exactly as green is (`0x30` channel enable 0x04, `0x36` PWM 0xff,
  `0x33` 5 mA): the driver drives it, so either this unit's LED has no
  blue die or 5 mA is too little for it. Not pursued.
- **Charging LED** (device-markw 0.1.18): red follows the fuel gauge's
  `qcom-battery-charging` trigger, green `qcom-battery-full`, set by a
  udev rule on the LEDs' add and the battery's events, and only where
  the LED has no trigger (feedbackd's `pattern` blink is left alone).
  Red lit while charging (owner, by eye).
- **Haptics:** the PMI8950 haptics (`qcom_spmi_haptics`, input
  `spmi_haptics`) played a 150 ms and two 300 ms FF_RUMBLE effects
  (`tools/ff-rumble --name spmi_haptics`), felt by the owner.
  feedbackd 0.8.9's own `72-feedbackd.rules` already tags it `vibra`,
  so nothing of ours is needed for that.

## 2026-11-06: Omarchy held at 4.0.6, charging to the top (7.1.3-msm8953-oma6)

- **`omarchy update` would have taken Omarchy to 4.5.0-3, which our
  patch series doesn't apply to.** `omamobile-update check` showed no
  blockers and 84 updates. The series tested against the real aarch64
  4.5.0-3 package (`test/patches.py` with `OMARCHY_PKG`, in an alpine
  container for `bsdtar`): 12 of 16 patches fail with `--fuzz=0`, among
  them 0003 (the lock's number pad), 0011 (PIN or password) and 0012 (the
  update wrapper); only 0007, 0009, 0010 and 0013 apply. The hook applies
  all or nothing, so the update would have left a touch-only phone with
  Omarchy's own lock. Upstream holds Omarchy at 4.0.6 for the same reason
  (#434) by pinning it in its signed `[omamobile]`. This fork has no
  such repository, so `rootfs/pacman.conf` and the phone's
  `/etc/pacman.conf` (owner's go) carry `IgnorePkg = omarchy
  omarchy-settings` until the series is rebased. The update check still
  lists the two; pacman skips them.
- **Charging:** oma6 goes past the old stop at about 90 %; the
  termination current fix (patch 0009, 150 mA) is in
  [BRINGUP-CHARGER.md](BRINGUP-CHARGER.md).

## 2026-11-06: the laptop link died without OTG (7.1.3-msm8953-oma3)

- **"USB device not recognized" again, with no OTG in the boot.** The
  boot ran 73 h (`probe-m10-modem`). The kernel log shows two separate
  things:
  - **A charger error drops the link.** Each `Charger error` (the batt-ov
    latch, BRINGUP-CHARGER.md) was followed about 0.5 s later by `USB
    role device -> none` and `usb0: Lost carrier`, while the cable stayed
    in. The link came back only when the role returned to device: the
    first time 8.5 h later.
  - **Then the gadget wedged for good.** On Nov 6 `usb0` lost and gained
    carrier every 1-2 s for a while (the computer resetting the
    device, or a loose plug), then lost it with the role still
    `device`. Every later replug switched `none -> device`, and `usb0`
    never gained carrier again, until the owner rebooted.
- **Why a replug can't fix it:** DWC3 runs its gadget at `none` too (its
  role-switch default mode is peripheral), so `none -> device` asks for
  the mode it is already in, which `__dwc3_set_mode` skips. Nothing
  restarts the device side, after host mode (Nov 3) or after this.
  omamobile-device-markw 0.1.17 rebinds the gadget from udev when a
  computer's port gives no carrier 15 s after a switch to device; a
  kernel fix (stopping the gadget at `none`) can follow.

## 2026-11-03: the modem runs on Linux (probe-m10-modem, 7.1.3-msm8953-oma3)

- **The modem boots** from `qcom_q6v5_mss` with `echo start` to its
  remoteproc `state` (no auto-boot), over rmtfs on RAM copies of the NV
  partitions and tqftpserv; pd-mapper is not needed (no `.jsn` maps on
  this firmware). Its QMI services appear on QRTR and IPA brings up
  `rmnet_ipa0`; the eMMC stays `ro=1`. BRINGUP-MODEM.md steps 4-6.
- **ModemManager** creates it through `qcom-soc` and waits at
  `sim-missing` until a SIM is in the tray.
- **The eMMC and the SD card swapped numbers** this boot (eMMC
  `mmcblk1`). Find partitions by PARTNAME and device type `MMC`.
- **A MIUI boot writes the modem's NV** (`modemst1`, `modemst2`,
  `persist` changed): take a fresh read-only backup after each one.

## 2026-11-03: OTG to an ESP32 from Flash (7.1.3-msm8953-oma3)

- **An unattended auto-suspend never woke** (2026-11-03 01:01, oma3):
  `PM: suspend entry (s2idle)` is the boot's last line, and the backup
  alarm didn't wake it either. Auto-suspend stays off until staged long sleeps
  pass: [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).

- **Modem scope (owner): mobile data only.** SMS and calls are not needed
  for now and not part of the 90 % gate for the persistent install. Data
  goes over IPA v2.6L (the msm8953 tree's `ipa2-lite`, already in oma3
  and bound at boot), not BAM-DMUX; it needs the modem node enabled in
  the probe, rmtfs on RAM copies of the NV partitions, and packages not
  yet installed: BRINGUP-MODEM.md.
- **Time zone** was UTC from the image; set to the owner's zone with
  `timedatectl set-timezone` (the clock itself was NTP-synced).

- **The OTG plug works on oma3**: no hang, the board powered, `ttyUSB0`
  (CP210x) listed. esptool reached the chip, then lost it at the stub
  flasher (a crystal-frequency warning first): a brownout on OTG power,
  or the 460800 baud.
- **After unplug the laptop link did not come back** ("Device Descriptor
  Request Failed"), but the phone never hung. The gadget came back on its
  own after leaving host mode, and died 1 s later at a late `USB role
  none -> device`. A replug didn't revive it. Details: BRINGUP-OTG.md,
  2026-11-03.
- **Flash ran the phone out of memory**: 1.87 GB RSS, swap full, OOM-killed.
  That was the frozen window and the battery drain. Its log built a new
  array per line; omamobile-flash 0.1.6 caps it in a ListModel.

## 2026-11-02: light sensor at boot, proximity, charger (7.1.3-msm8953-oma3)

- **The kernel binds the LTR-559 at boot** with patch 0003 (a 100 ms wait
  after the supplies come up): `iio:device1`, before the BMI120 at 12 s;
  the bind unit found it owned (BRINGUP-KERNEL.md, oma3 step 2).
- **Proximity near level 50.** Prompted on the phone, the proximity channel
  read 19-33 uncovered and 58-237 under a finger (up to about 1500 pressed
  flat). The kernel's `in_proximity_nearlevel` is 0 (no DT property).
  device-markw 0.1.13 sets `PROXIMITY_NEAR_LEVEL=50` by udev; iio-sensor-proxy
  then reports `HasProximity`, polls every 0.7 s (near above 55 with its
  hysteresis) and sent "near" when covered and "far" uncovered.
- **Charger: chg-error follows batt-ov**, not a timer: BRINGUP-CHARGER.md.
- **Touch keys (menu, home, back) work** with patch 0005: the maXTouch
  (family 166, firmware 1.0.AB, 36 objects) has a T15 key array, enabled
  and reporting, one by three keys; without `linux,keycodes` atmel_mxt_ts
  dropped its messages. Read-only over I2C (object table at 0x0007, T15 at
  0x039c: `0b 0e 00 01 03 ...`). Booted with a DTB carrying the keymap
  (`probe-m9k-oma3`), pressed once, twice and three times: left gave
  KEY_MENU, middle KEY_HOMEPAGE, right KEY_BACK. omamobile-shell 0.2.30
  binds them.
- **USB stuck after a burst of replugs.** After about six unplugs and
  plugs within 90 s (a loose cable, the phone being turned), the gadget
  stayed in UDC state `default` with `usb0` down while VBUS was online and
  the role was `device`; Windows listed "Unknown USB Device (Device
  Descriptor Request Failed)" through further replugs, other ports
  included. The gadget was still bound to `7000000.usb` at high speed.
  Rebinding it over Wi-Fi SSH (`echo "" > UDC`, then `7000000.usb`)
  brought it back at once: `configured`, `usb0` up, NCM on the laptop, SSH
  over USB. A single 10 s replug earlier the same day had come back on its
  own. Candidate fix, not done: rebind the UDC when it sits in `default`
  for some seconds with VBUS online and the device role set, as
  `omamobile-usb-rescue` closes the data switch on cheetah.
- **Rotation follows the phone.** Recorded once a second over Wi-Fi SSH
  (the USB cable drops when the phone moves): upright reads raw +x and
  iio-sensor-proxy says `normal`; right side down -y, `left-up`; upside
  down -x, `bottom-up`; left side down +y, `right-up`. So the DT mount
  matrix, odd determinant and all, gives the right orientations.
  `omamobile-autorotate` (omamobile-sensors) run as a user unit turned
  DSI-1 through transforms 0-3 with them and back. A claim from outside the
  login session (`runuser`) is refused by polkit ("Sensor claim not
  allowed"); the user unit is allowed.
- **The shell's layout breaks in landscape** (the owner, by eye): the home
  screen, bar and lock screen are laid out for portrait only, as on
  cheetah, where rotation stays locked until the quick-settings tile opens
  it. Not packaged for markw yet: omamobile-sensors brings cheetah's AoC
  proxy and conflicts with iio-sensor-proxy.

## 2026-11-02: sensors (7.1.3-msm8953-oma2)

- **IMU and compass probe at boot.** `bmi120` (accelerometer, gyroscope)
  and `yas537` (magnetometer) on the i2c-gpio bus 0 (`0-0068`, `0-002e`)
  appear as IIO devices. yas5xx finds no mount matrix and uses identity.
- **The LTR-559 light and proximity sensor misses its probe.** `0-0023`
  (`liteon,ltr559`) had no driver after boot, wasn't deferred, and ltr501
  logged nothing. The chip answers: part ID 0x92 and manufacturer 0x05,
  which ltr501 expects. Bound by hand it probed cleanly as `iio:device2`.
  Covered, proximity rose from about 25-40 to 96-138 and light fell from
  about 130-240 lux to 0. Likely cause, not proven: ltr501 enables the
  supplies and reads the part ID at once, before the chip's start-up time.
  device-markw 0.1.12 binds it after boot (`omamobile-markw-light`); a
  kernel fix (a delay after the supplies come up) would replace that.
- **Accelerometer axes** (detached test, prompts on the phone): upright
  read +x (raw), left side down +y, right side down -y, flat screen up +z
  (about 1 g each). An "upside down" step also read +x, so it was held
  some other way; the axes are not fully pinned down. The DT carries a
  mount matrix (`0,-1,0; -1,0,0; 0,0,1`), whose determinant is -1, which a
  plain rotation can't have; check it when rotation is wired up.
- **iio-sensor-proxy 3.9** (installed by hand, not yet in a package)
  reports the accelerometer (polling: the bmi120 has no IRQ, so its buffer
  can't be enabled) and the light sensor; it skips proximity until a
  `PROXIMITY_NEAR_LEVEL` udev property exists. A rotation test logged
  nothing: the script's claim ended with each `gdbus` call. Orientation is
  to be checked by eye when Hyprland's auto-rotation is wired up.

## 2026-11-01: power key bounce, idle power, s2idle (7.1.3-msm8953-oma2)

- **The power key bounces.** Held, `pm8941_pwrkey` reports a release and a
  new press about 20 ms apart (the DT debounce is 15625 us). Hyprland
  passes both on, so omamobile-keys locked the phone on the false release
  and the hold never reached the system menu. omamobile-shell 0.2.21
  voids a release followed by a press within 80 ms. A raised PMIC
  debounce in the DT would also work; not tried.
- **Idle wakeups with the panel off**, per second: `sugov:0` 435 (schedutil
  switching the clock about 90 times a second, as cpufreq-dt reports a
  1 ms transition latency and the rate limit was 1.5 ms), quickshell
  about 63-107, `rcu_preempt` about 95, SD writeback kworkers about 80.
  A 20 ms schedutil rate limit (device-markw 0.1.5) cut sugov to 15 and
  the switches to 5. Idle sits at 652.8 MHz either way.
- **Omarchy turns Wi-Fi power save off** in
  `/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf`. NetworkManager
  reads `/etc` after `/usr/lib`, so a `/usr/lib` drop-in can't override it;
  device-markw 0.1.4 ships `/etc/.../zz-omamobile-wifi-powersave.conf`.
  wcn36xx with power save: ping averages about 50 ms, SSH and pacman fine.
- **The idle cycle kept the panel on for about 5 minutes** (screensaver
  animation at 150 s, lock at 300 s, blank 10 s later). `shell.json`
  `"idle": {"screensaver": 0, "lock": 60}` is read live, without a shell
  restart.
- **s2idle works on oma2:** every `pm_test` stage passes, a real s2idle
  wakes on the PMIC RTC alarm (IRQ 71) and on the power key (IRQ 68),
  and 10 of 10 soak cycles passed. wcn36xx logs `ERROR SMD_EVENT (312) not
  supported` at each suspend, harmless so far. The first attempt, on
  oma1, never resumed and rebooted into MIUI with an empty pstore; neither
  the lockup detectors nor a lit panel reproduce it. Details:
  [BRINGUP-SUSPEND.md](BRINGUP-SUSPEND.md).
- **A crash loses its ramoops record**: the reboot goes to MIUI from the
  eMMC, and the record is gone when the probe boots again.

## 2026-10-28: Wi-Fi from the package, Bluetooth, keyboard after screen-off (7.1.3-msm8953)

- **Wi-Fi needs no hand steps on a new card.** The probe DTB leaves WCNSS
  `okay`, and `omamobile-markw-firmware` (device-markw 0.1.2) copies the
  Pronto firmware and this phone's `WCNSS_qcom_wlan_nv.bin` before udev
  loads the drivers. Nothing in the image blacklists the WCNSS modules. The
  hand-made bring-up blacklist is out of `/etc/modprobe.d` (kept as
  `/var/tmp/omamobile-wcnss-bringup.conf.disabled`), and `wlan0` connects
  at every boot.
- **The firmware copy, tested on the phone:** the root has no `cmp`, so
  `--check` first reported every file as changed; it now compares with
  `sha256sum`. Only `a506_zap.elf` was missing. One run copied it, and a
  second run and the unit under systemd copied nothing.
- **Bluetooth comes up with Wi-Fi.** `btqcomsmd` binds the WCNSS `bluetooth`
  SMD node, giving `hci0` (manufacturer 0x001d, HCI version 0x08: 4.2).
  `bluetoothd` is active, the controller powers on, and rfkill blocks
  nothing. A 12 s scan saw 5 devices (counted only). The public address
  isn't a known shared firmware default; whether it stays the same across
  boots is not yet checked. Pairing is not yet tested.
- **The floating show-keyboard button was gone after the screen went off
  and on.** The lock folds squeekboard, the button stayed only after a
  fold by its own tap, and the lock's focus change cleared it.
  omamobile-shell 0.2.19 keeps it after any fold, until another app takes
  focus. Confirmed by the owner, also after a restart.
- **The keyboard over the lock after the screensaver:** omamobile-omarchy
  0.1.8 (patches 0006 and 0007) turns squeekboard back on and unfolds it,
  also when a touch locks through the idle service. Both apply with
  `--fuzz=0` on Omarchy 4.0.6-1 and are applied on the phone, but haven't
  been tried with the screensaver yet.

## 2026-10-27: lock screen keys, app switcher and Wi-Fi preparation (7.1.3-msm8953)

- **The power button woke the lock without the keyboard.** After the power
  button turned the screen off and on, the lock's PIN pad worked but tapping
  the field or ABC brought no QWERTY. `omamobile-keys` calls
  `omarchy-shell lock wake`, which only ran `omarchy-system-wake`: the field
  kept its focus but got no new focus-in, so squeekboard was never asked
  back. Patch 0009 now also calls the lock view's `forcePasswordFocus()`
  (omamobile-omarchy 0.1.7). It applies with `--fuzz=0` to the phone's
  Omarchy 4.0.6 (`omamobile-omarchy-patches apply --series` from a scratch
  copy, 14 of 14 applied).
- **Still open: no keyboard on the lock after the screensaver.** A touch on
  the screensaver locks through the idle service (0007,
  `screensaver-wake: user returned`), and Qt then logs
  `QWaylandTextInputv3::enableSurface … Trying to enable … but … is focused`.
  The first lock after boot has no such warning, and QWERTY works there.
  The screensaver also turns `screen-keyboard-enabled` off (0006) and
  depends on `restore_osk` to turn it on again. Not yet known which of the
  two is to blame: the next test starts the screensaver from the laptop and
  logs that key and squeekboard's `Visible` while the owner touches the
  screen. For now the owner unlocks with a PIN (number pad).
- **The unlock type is recorded apart from the secret.** `passwd` alone
  leaves `~/.config/omamobile/credential` at `password`, so the lock opens
  on QWERTY even with a numeric secret. `omamobile-set-pin` records `pin`
  and drops Omarchy's `credential-password` toggle.
- **Closing apps:** swipe up on the dock (the search pill) for recent apps,
  then flick a card up. Summoned over IPC (`omarchy-shell shell summon
  omamobile.switcher '{}'`), the `omamobile-switcher` layer came up with
  no errors.
- **A keyboard folded by the hide button never came back.** squeekboard
  unfolds only on a new focus-in, and a tap on a field that already has
  focus (a terminal) gives none, while the button vanished with the
  keyboard. `omamobile.keyboard` 0.1.1 (omamobile-shell 0.2.18) keeps the
  button in the corner as "show keyboard" until the keyboard unfolds or
  another window takes focus. Confirmed by the owner.
- **Wi-Fi joined but had no internet.** There were two causes:
  - The network was a guest network with a captive portal: every HTTP
    request got a 302 to its login page, and NetworkManager reported
    `portal`.
  - markw's `20-usb-gadget.network` set `Gateway=172.16.42.2` at metric 0,
    which beat Wi-Fi (600, or 20600 while NetworkManager reports a
    portal), and a Windows host shares no internet. The gateway is now a
    `[Route]` at metric 1000 (omamobile-device-markw 0.1.1).
- **`tools/markw-debug fastboot` from Arch:** `systemctl reboot bootloader`
  fails with "Too many arguments" and the phone never reboots. It is now
  `systemctl reboot --reboot-argument=bootloader`.
- **Wi-Fi not yet running.** NetworkManager reports Wi-Fi `missing`.
  - The kernel has `qcom_wcnss_pil`, `wcn36xx`, `wcnss_ctrl` and
    `btqcomsmd` (all modules).
  - The probe DTB disabled `remoteproc@a204000` (Pronto, `qcom,pronto-v3-pil`,
    iris `qcom,wcn3660b`) and has no `firmware-name`, so the driver asks for
    `wcnss.mdt` and wcn36xx for `wlan/prima/WCNSS_qcom_wlan_nv.bin`.
  - The firmware is on the phone: `modem` (mmcblk0p1, vfat) has
    `image/wcnss.mdt` with `wcnss.b00`–`b12`, and `persist` has
    `WCNSS_qcom_wlan_nv.bin`, this phone's calibration (`system`'s copy is
    only a 31-byte link to it). Both partitions were mounted read-only and
    unmounted again, and the files were copied on the phone only, to
    `/usr/lib/firmware/updates/` on the card. They never leave the phone.
  - Bring-up blacklist on the card:
    `/etc/modprobe.d/omamobile-wcnss-bringup.conf` (`qcom_wcnss_pil`,
    `wcn36xx`, `wcnss_ctrl`, `btqcomsmd`).
  - `initramfs/build` now leaves WCNSS `okay`; the modem and LPASS stay
    `disabled`. Built and checked (`a204000 okay`, `4080000` and `c200000`
    `disabled`, touch `4a okay`), not booted yet. The previous probe is
    kept as `probe-m3-prewifi` for rollback.
  - **Result (same day, WCNSS probe, by hand under a dmesg stream):**
    - The node came up `okay` at boot with nothing loaded (the blacklist
      held), and the 7 MiB `wcnss@8e700000` region was reserved.
    - `modprobe qcom_wcnss_pil` gave `Booting fw image wcnss.mdt` and
      `remote processor a204000.remoteproc is now up`, then the
      `WCNSS_CTRL`, `WLAN_CTRL` and `IPCRTR` SMD channels.
    - `modprobe wcnss_ctrl` reported `WCNSS Version 1.5 1.2`, then
      `expected cold boot completion` (a timeout warning: Pronto stayed
      `running`), and the BT and FM channels appeared.
    - `modprobe wcn36xx` reported firmware `WCN v2.0 RadioPhy
      vIris_TSMC_4.0 with 48MHz XO`, API 1.5.1.2, and `wlan0` came up.
    - NetworkManager reports Wi-Fi `enabled` and rfkill doesn't block it.
      A scan found 17 networks on 2.4 and 5 GHz, with no wcn36xx errors.
    - Not yet done: connecting, autoloading at boot (remove the bring-up
      blacklist, one boot), Bluetooth (`btqcomsmd`), and power cycles.

## 2026-10-27: M3, Arch from the microSD card (7.1.3-msm8953)

- **Arch boots from the card.** lk2nd, then `probe-m3`, then switch_root
  to the card by UUID. The panel shows systemd's status lines (still the
  lk2nd framebuffer through simplefb, see below), systemd-networkd puts
  `172.16.42.1` on usb0, and SDDM autologs in the user.
- **Windows host:** Arch's usb0 is static (`20-usb-gadget.network`), with
  no DHCP server, so the host needs `172.16.42.2/24` set by hand once
  (admin PowerShell: `New-NetIPAddress -InterfaceAlias '<adapter>'
  -IPAddress 172.16.42.2 -PrefixLength 24`). The initramfs udhcpd hands
  out the same address, so M1 still works.
- **First boot stopped at "Update is Completed":** the image ships
  machine-id `uninitialized`, so systemd-firstboot waited on /dev/console
  (ttyMSM0, unreachable). Fixed with `systemd.firstboot=off` on the probe
  cmdline. omamobile-firstboot does that setup instead.
- **SSH dropped by ufw (`[UFW BLOCK] IN=usb0 … DPT=22`).** The
  postmarketOS kernel has no `xt_hl` or `ip6t_rt` (and warns about
  `limit`), so `ip6tables-restore` fails on `/etc/ufw/before6.rules` and
  every `ufw` command ends in `problem running ufw-init`. Omarchy's
  firewall leaf had already turned ufw on (IPv4 loaded), and firstboot's
  `services and firewall` step failed on its first `ufw` call, before the
  usb0 rule. That step is essential, so firstboot.conf stayed and the
  setup reran at every boot. Neither a `/run` mask of `ufw.service` nor an
  `ExecStartPost` ACCEPT helped: the commands, not the unit, enable ufw.
  Fixes: omamobile-firstboot 0.1.1 allows SSH on usb0 before Omarchy's
  leaves and drops to `IPV6=no` on a kernel without the matches; the card
  was repaired with `IPV6=no`. The real fix is a kernel with them.
- **No readable RTC:** the clock read 1970 in the initramfs (no `rtc0`)
  and 2026-10-18 (systemd's epoch) in Arch. gpg found the keyring key
  "created 8 days in the future", skipped it and the `pacman keyring`
  step failed. The root image now touches `/usr/lib/clock-epoch`; the
  card got one by hand.
- **GUI: GPU firmware was the blocker.** In Arch, msm DRM binds
  (`card0-DSI-1`, `panel_mdss_nt35596_ebbg`, `fb0: msmdrmfb`), but
  without `qcom/a530_pm4.fw` the Adreno 506 never starts. freedreno then
  fails (`get_param … -6`, `fd_pipe_new2: allocation failed`, `egl:
  failed to create dri2 screen`), and Hyprland aborts, both the user
  session and SDDM's greeter compositor, which takes `sddm-greeter-qt6`
  down with it. Every file needed is on the phone's own `system`
  partition (`/etc/firmware`: `a530_pm4.fw`, `a530_pfp.fw`,
  `a506_zap.mdt` and `.b00`-`.b02`). It was mounted `ro,noload` on the
  phone and copied there into `/usr/lib/firmware/updates/qcom/` (zap
  under `msm8953/xiaomi/markw/`), so no blob left the phone. After
  `systemctl restart sddm`: `loaded qcom/a530_pm4.fw from new location`,
  and Hyprland, Quickshell, squeekboard and Omarchy's lock screen came
  up. To do: a provisioning step that copies these (as
  `tools/phone-provision` does for cheetah), never the repo.
- **Touch: this unit has an Atmel maXTouch, not an FT5336.** lk2nd enables
  `touchscreen@38` (`edt,edt-ft5336`) from the panel name, and
  `edt_ft5x06` failed its probe. An I2C trace showed the ID read at 0x38
  NAKed (`ret=-6`) with the supplies on, and `i2cdetect -r 2` found only
  0x4a. The probe DTB now also enables `touchscreen@4a`:
  `atmel_mxt_ts 2-004a: Family: 166 Variant: 7 Firmware V1.0.AB`,
  2160x3840 range (libinput scales it to the panel). Typing on
  squeekboard works. A missing `maxtouch.cfg` is harmless: the chip
  keeps its config in NVM.
- **The USB link drops for a few seconds now and then** once the session
  runs (`dwc3-qcom … remote wakeup not configured`, then `Charger
  error`). Probably the Windows host suspending the idle NCM adapter;
  not yet confirmed. SSH with a retry works around it.
- **Recovery without buttons:** when Arch can't be reached, the probe
  with `fastboot --cmdline '<probe cmdline> omamobile.stay' boot` stays
  in the initramfs: SSH up, eMMC read-only, the card's root partition
  writable for repairs. From there, `reboot-to bootloader` reached stock
  fastboot. A boot dead-man (`multi-user.target` JobTimeout 60 min,
  reboot to the bootloader) now covers a hung Arch boot.
- **Forced restart:** Volume Down + Power for 30-40 s when Arch hangs and
  SSH is gone.

## 2026-10-27: M1 first light, kernel and SSH from RAM (7.1.3-msm8953)

- **Stock state (read-only, adb then fastboot).** Android 6.0.1,
  `verifiedbootstate=orange`; `fastboot oem device-info` reports
  unlocked and critical unlocked. `fastboot getvar unlocked` answers
  empty on this aboot, so the runbook uses `oem device-info`.
- **lk2nd 23.1 RAM-booted** (`fastboot boot`, 360 KiB): `product:
  lk2nd-msm8953`, log `Detected device: Xiaomi Redmi 4 Prime (markw)
  (compatible: xiaomi,markw)`. The cmdline from aboot names the panel
  `qcom,mdss_dsi_nt35596_ebbg_1080p_video`, so this unit is the NT35596
  EBBG variant. lk2nd then reports `Invalid boot image header` and stays
  in fastboot: expected, nothing follows lk2nd on the boot partition
  because it was never flashed. Two `Command timeout error` lines early
  in its log are not explained yet.
- **Probe RAM-booted from lk2nd** (`probe-m1/boot.img`, 17 MiB): the
  Windows 11 host bound the NCM function with its in-box `UsbNcm` driver
  and had `172.16.42.2` about 4 s after `Booting`; the ACM port appeared
  as a COM port; `ssh root@172.16.42.1` worked.
- **Guard:** `mmcblk0`, `mmcblk0boot0/1` and all 49 partitions `ro=1`.
  eMMC HS400, 29.1 GiB; `mmcblk0rpmb` present as a chardev only. No
  microSD inserted (mmc1 host probed, no card).
- **Health:** no oops or panic, pstore empty, UDC `configured`, 8 CPUs,
  MemTotal 2.87 GB (3 GB variant), CPU and GPU zones at 29-31 °C.
  Known MSM8953 messages: `psci: [Firmware Bug]: failed to set PC mode:
  -1`, `cpu cpu0: Failed to set OPP config`.
- **Charger:** `qcom-smbchg … Charger error` at 8.3 s. The USB supply
  reads `online=1` but the battery `Discharging` (capacity 94, 4.23 V,
  health Good) on a laptop port. Charging is M6 work; keep sessions short
  until it is understood.
- **Display:** the screen goes dark once the kernel takes over. Expected:
  the probe carries no display driver (`/sys/class/drm` and `/proc/fb`
  empty), and unused clocks and regulators turn off.
- **Return path:** `reboot-to bootloader` (with `qcom-pon` loaded) reached
  stock fastboot within 2 s; lk2nd is gone, as it lived in RAM only.
  Nothing was written to the phone in this session.
