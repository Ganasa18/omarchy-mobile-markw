<!-- SPDX-License-Identifier: MIT -->
# markw: mobile data over the modem (runbook)

Status: steps 0-7 passed (2026-11-12, `oma10`): SIM registered on LTE,
data over `qmapmux0.0` works but slowly (radio suspected). Next: a
speed comparison with MIUI at the same spot, data with Wi-Fi off, then
step 8 (packaging).

## Scope (owner's decision, 2026-11-03)

- **Mobile data only**: a SIM in the phone gives an internet connection,
  as Wi-Fi does. **SMS and calls are not needed for now** and are not part
  of the 90 % gate for the persistent install (M9): they stay out of scope
  until the owner asks for them.
- Wi-Fi stays the main link; this adds a second one.

## Facts (read-only, 2026-11-03, oma3)

- Kernel: `QCOM_Q6V5_MSS`, `QCOM_SYSMON`, `QCOM_RMTFS_MEM`, `QRTR` and
  `QRTR_SMD` are modules, `RPMSG_QCOM_SMD` and `QCOM_SMSM` built in.
- **The data path is IPA v2.6L, not BAM-DMUX.** MSM8953 has no BAM-DMUX
  node (msm8916, msm8917 and msm8937 do); `msm8953.dtsi` describes
  `ipa@7900000` (`qcom,ipa-lite-v2.6`, `modem-remoteproc = <&mpss>`),
  driven by the msm8953-mainline tree's own `drivers/net/ipa2-lite`
  (`QCOM_IPA2_LITE`, not upstream's `QCOM_IPA`). oma3 already has
  `QCOM_IPA2_LITE=m` and `RMNET=m`; `ipa2_lite` already autoloads and
  binds `7900000.ipa` at every boot, waiting for a modem that never
  starts, so **no new kernel is needed** for data. The in-kernel
  `QCOM_PD_MAPPER` is not set: the userspace pd-mapper is needed. (A first draft of this
  plan asked for `QCOM_BAM_DMUX` and a kernel oma4; that was wrong.)
  postmarketOS's wiki reports the msm8953 modem working since 6.7.2, with
  mobile data not working on every device.
- Device tree: markw's own DTS sets `&mpss` `okay` (with its `mss` and
  `pll` supplies); only our probe's DTB disables it (`initramfs/build`
  keeps the modem off). The reserved regions `mpss@86c00000` and
  `rmtfs@f2d00000` exist.
- eMMC partitions, all `ro=1` under the storage guard: `modem`
  (mmcblk0p1, 84 MiB, vfat, the firmware), `modemst1` and `modemst2`
  (1 MiB each), `fsg` (1 MiB), `fsc`, `sec`, `persist` (32 MiB), `dsp`.
  `modemst1/2`, `fsg` and `fsc` hold the modem's NV, the IMEI among it.
- Userspace: `libqmi` 1.38 is installed; `rmtfs`, `qrtr`, `tqftpserv`,
  `pd-mapper` and ModemManager are not. The pacman database is synced
  but packages aren't upgraded (`omarchy update` waits on Omarchy's
  Hyprland rebuild), so installing them now would be a partial upgrade:
  wait for the update, or build them into `[omamobile]`.

## Rules for this work

- **The eMMC is never written.** `rmtfs` normally writes the modem's NV
  back to `modemst1/2`; here it runs on RAM copies of them (its storage
  directory under `/run`), so whatever the modem writes is lost at
  shutdown. The partitions stay `ro=1`.
- **A backup first** (step 0), off-repo, and a fresh one after any MIUI
  boot (MIUI's modem writes these partitions).
- **Never in the repo or a log excerpt:** IMEI, IMSI, ICCID, the phone
  number, the operator's name with the owner's account, partition images.
  Use placeholders (`<IMEI>`, `<APN>`).
- **The SIM PIN is the owner's.** If the SIM asks for one, the owner
  enters it on the phone; it never passes through the agent.
- One change per boot; the modem's modules stay blacklisted until the
  step that loads them, with the kernel log streamed to the laptop.

## Runbook

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Read-only backup to the laptop (`~/android/reference/markw/modem-backup/`, never committed): `dd` of `modemst1`, `modemst2`, `fsg`, `fsc`, `sec`, `persist` by `PARTNAME`, plus `sha256sum` on the phone and the laptop | sums match on both sides | a read error | none needed | none |
| 1 | Laptop: a probe like `probe-m9k-oma3` whose DTB has `remoteproc@4080000` `okay` again (`fdtput`), with `qcom_q6v5_mss` blacklisted on the phone first (`ipa2_lite` already loads at every boot and stays as it is); no kernel change | `fdtget` reads `okay`; the boot.img differs from m9k only in the DTB | — | — | none |
| 2 | Packages: `rmtfs`, `qrtr`, `tqftpserv`, `pd-mapper`, ModemManager; all services disabled | installed, nothing started | a partial upgrade would be needed | `pacman -R` | low |
| 3 | rmtfs on RAM copies: a unit that copies the four NV partitions from the backup-verified block devices into `/run/omamobile-rmtfs/` (checking the step 0 sums) and runs rmtfs with that directory as its storage; check rmtfs's file-storage option on the phone first | rmtfs starts and waits; partitions still `ro=1` | rmtfs wants the block devices | stop the unit | low |
| 4 | Boot the step 1 probe (one change: the node), modules still blacklisted | boots; no new errors; remoteproc not started | a hang or new errors | boot `probe-m9k-oma3` | low |
| 5 | Log streamed, then load the modem: start rmtfs (step 3), pd-mapper and tqftpserv, then `modprobe qcom_q6v5_mss` | `remoteproc2` "running", sysmon and QRTR services listed (`qrtr-lookup`), no crash loop | the modem crashes or restarts in a loop, or eMMC errors | `rmmod`, reboot | medium |
| 5b | Watch the already bound `ipa2_lite` react to the running modem (its log lines, `ip link`) | the IPA comes up with the modem; an rmnet interface appears | an abort or a modem crash | reboot | medium |
| 6 | ModemManager with a SIM inserted (owner): `mmcli -L`, `mmcli -m 0` (state only; identifiers not copied out) | modem listed, SIM present, registered on a network | no SIM seen, or "sim-missing" | stop ModemManager | low |
| 7 | Data: `nmcli connection add type gsm ifname '*' apn <APN>`, connect, then `ping` over it with Wi-Fi off | an IP on the rmnet interface over IPA, ping answers | no bearer, or no traffic | `nmcli connection down` | low |
| 8 | Package it: device-markw ships the rmtfs-on-RAM unit and the blacklist removal, nothing enabled that isn't hang-safe; a quick settings tile for mobile data later | data comes back after a reboot | — | downgrade | low |

Results go here and in NOTES.md, with the date and `uname -r`.

## Results

**2026-11-03, `7.1.3-msm8953-oma3`:**

- **Step 0: pass.** `modemst1`, `modemst2`, `fsg` (1.5 MiB each), `sec`
  (16 KiB), `fsc` (1 KiB) and `persist` (32 MiB) read by `PARTNAME`, all
  `ro=1`, into `~/android/reference/markw/modem-backup/<UTC time>/` on
  the laptop with the phone's and the laptop's sha256 sums; all six match.
  The USB network dropped twice during the copies (an ssh "Connection
  reset" and then a minute without answers, no reboot, nothing in the
  kernel log); `persist` was copied again through `gzip` and matched. A
  copy loop must give ssh `< /dev/null`, or the first ssh eats the list.
  The sums stay in the backup folder, not here. This backup predates any
  modem start on Linux; take a new one after the next MIUI boot.
- **Step 2: pass** (owner's go for installing from the synced database
  without `omarchy update`). pacman's dry run listed only new packages,
  no upgrades of installed ones; installed `rmtfs-git` r78 and `qrtr-git`
  r126 (Omarchy's `[aur]`), `modemmanager` 1.24.2 and `ppp` (`extra`).
  `tqftpserv` 1.3 and `pd-mapper` 1.1 aren't in any repository: built on
  the phone from `packages/tqftpserv` and `packages/pd-mapper` (`cc`
  directly; the phone has no make). rmtfs, ModemManager, tqftpserv and
  pd-mapper are all disabled and inactive. rmtfs takes `-o DIR` for its
  storage, with the files `modem_fs1`, `modem_fs2`, `modem_fsg` and
  `modem_fsc`, which step 3 needs. Room for the later `omarchy update`:
  the owner had PlatformIO's RISC-V toolchain and its download cache
  removed (12 GiB free of 29 on the card, from 7.6).
- **Step 3: pass** (device-markw 0.1.15, then 0.1.16). The firmware copy
  took `mba.mbn` and `modem.mdt`/`.b??` from the read-only modem partition
  (20 files, 43 MB). `omamobile-markw-rmtfs` copied the four NV
  partitions to root-only files in `/run/omamobile-rmtfs`; the
  partitions stayed `ro=1`. With `-s`, rmtfs exited ("Failed to get
  rprocfd": it controls the modem's remoteproc, which the probe has not
  got); without it, rmtfs ran and `qrtr-lookup` listed its "Remote file
  system service", next to the "IPA control service" ipa2-lite already
  offers. The modem partition has no `.jsn` files, so pd-mapper will
  probably have nothing to serve. rmtfs stopped again; nothing enabled.
- **Step 1: built** (laptop only). `tools/build-markw-probe --modem`
  (new: `MPSS=1` in `initramfs/build`) with m9k's inputs (oma3,
  `markw-keys.dtb`, `--usb-role otg --adsp`, the same root):
  `~/android/markw/probe-m10-modem`, boot.img sha256 `aceff63c…`. Its DTB
  differs from m9k's only in `remoteproc@4080000` `okay`; the initramfs
  contents differ only in the build date in `/etc/shadow`.
  `/etc/modprobe.d/omamobile-modem-bringup.conf` on the phone blacklists
  `qcom_q6v5_mss` for step 4 (remove it when the modem is packaged).
- **2026-11-03, between steps 1 and 4:** the reboot into the probe went
  through MIUI (ABL ignores `reboot-to bootloader`; then `adb reboot
  bootloader`). MIUI's modem changed `modemst1`, `modemst2` and `persist`;
  a fresh read-only backup (`…-after-miui`) was taken by eMMC device type,
  since the SD card and the eMMC swapped numbers in this boot (eMMC
  `mmcblk1`): the scripts find partitions by PARTNAME and device type,
  never by number, and so must any by-hand command.
- **Step 4: pass** (`probe-m10-modem`). System `running`, no failed units,
  `remoteproc@4080000` `okay`, `qcom_q6v5_mss` not loaded (blacklisted),
  Wi-Fi connected; no kernel error that the previous boots lacked.
- **Step 5: pass.** rmtfs (RAM copies), tqftpserv started; pd-mapper
  exits with "no pd maps available" (no `.jsn` on this firmware) and is
  not needed. `modprobe qcom_q6v5_mss`: `remoteproc2`
  (4080000.remoteproc) available but `offline`, no auto-boot. `echo start`
  to its `state`: "Booting fw image mba.mbn", "MBA booted without debug
  policy, loading mpss", "remote processor 4080000.remoteproc is now up"
  1.1 s later; `running` for the next 30 s and on. The modem's QMI
  services appeared on QRTR node 0 (WDS, NAS, UIM, DMS, WMS, voice, IPA
  control, ...). eMMC partitions still `ro=1`. qcom-memshare logged "a
  request from unknown client (id=1)", WCNSS "unexpected response to
  sysmon event"; neither stopped anything.
- **Step 5b: pass.** `rmnet_ipa0` and `ipa_lan0` appeared with the modem.
- **Step 6, without a SIM:** ModemManager 1.24.2 created the modem with
  the `qcom-soc` plugin (`qrtr0` control, `rmnet_ipa0` data) and stopped
  at `failed` / `sim-missing` ("GW primary session index unknown"), as
  expected with no SIM; with one in the tray, step 6 again.

**2026-11-12, `7.1.3-msm8953-oma10`, SIM inserted:**

- **Step 0 again** (MIUI ran this morning, with the SIM): a fresh
  read-only backup (`…-after-miui`), all six sums match on both sides;
  `modemst1`, `modemst2` and `persist` differ from 2026-11-06's, `fsg`
  doesn't.
- **Step 5 again: pass.** rmtfs (RAM copies) and tqftpserv, `modprobe
  qcom_q6v5_mss`, `echo start`: the modem up 1.1 s later; partitions still
  `ro=1`; `rmnet_ipa0` and `ipa_lan0` back.
- **Step 6: pass.** ModemManager: `registered` (home), LTE, signal 71-75 %
  (RSRP -104 dBm, RSRQ -17 dB indoors), packet service `attached`; the
  network handed the initial bearer its APN. Lock `sim-pin2` only (the
  SIM has no PIN1 set).
- **Step 7: pass, slow.** `nmcli connection add type gsm ifname '*'
  con-name omamobile-mobile apn <APN> connection.autoconnect no`, then
  `up`: ModemManager made a multiplexed bearer, so the address is on
  `qmapmux0.0` (on `rmnet_ipa0`), not on `rmnet_ipa0` itself; a ping or
  curl bound to `rmnet_ipa0` gets nothing. Over `qmapmux0.0`: ping
  answers (RTT 43-590 ms, about 10 % lost, jitter with no batching), HTTP
  and HTTPS work, 1 MiB in 23 s (about 45 KB/s), a second try 2.6 KB/s.
  The phone was idle meanwhile (CPU, no drops or errors on the
  interface, no kernel error), so the radio link is the first suspect;
  compare with a speed test in MIUI at the same spot before blaming
  ipa2-lite. Wi-Fi stayed on (its route wins); traffic was bound to the
  interface.
- Next: the MIUI comparison, a test with Wi-Fi off (the default route on
  mobile data), then step 8.
- **ModemManager crashes on a quick reconnect.** The quick settings tile
  (omamobile-shell: NetworkManager's gsm profile when there is no
  omamobile-sit) turned data off and on 3 s apart, and ModemManager
  1.24.2 (libqmi 1.38.0, glib2 2.90.1) died with SIGSEGV right after "net
  link qmapmux0.0 created (mux id 1)"; systemd restarted it. Reproduced:
  a reconnect 1 s and 5 s after the disconnect crashed, 10 s and minutes
  after worked. The old mux link is gone 190 ms after the disconnect, so
  it isn't that. The stack is unreadable without symbols (a frame in
  ModemManager's static code next to `mm_port_mbim_new`). The tile waits
  out 15 s after "off" before "on", and keeps the profile's autoconnect
  with the tile, so NetworkManager reconnects by itself if it crashes
  anyway. Later the same afternoon, with a better signal: ping 30 ms.
- The USB link dropped once, 50 s after the first crash (usb0 "Lost
  carrier", no role change, no kernel error) and came back on a replug;
  not shown to be related.
