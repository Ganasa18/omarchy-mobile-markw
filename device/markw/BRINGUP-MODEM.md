<!-- SPDX-License-Identifier: MIT -->
# markw: mobile data over the modem (runbook)

Status: plan only (2026-11-03), nothing run. The phone runs
`7.1.3-msm8953-oma3`; the modem's remoteproc node is disabled.

## Scope (owner's decision, 2026-11-03)

- **Mobile data only**: a SIM in the phone gives an internet connection,
  as Wi-Fi does. **SMS and calls are not needed for now** and are not part
  of the 90 % gate for the persistent install (M9): they stay out of scope
  until the owner asks for them.
- Wi-Fi stays the main link; this adds a second one.

## Facts (read-only, 2026-11-03, oma3)

- Kernel: `QCOM_Q6V5_MSS`, `QCOM_SYSMON`, `QCOM_RMTFS_MEM`, `QRTR` and
  `QRTR_SMD` are modules, `RPMSG_QCOM_SMD` and `QCOM_SMSM` built in.
  **`QCOM_BAM_DMUX` is not set**: on MSM8953 the modem's data path to
  Linux is BAM-DMUX (postmarketOS's msm8953 kernels enable it), so data
  needs a kernel of our own with it (oma4).
- Device tree: `remoteproc@4080000` (MPSS) is `disabled`; the reserved
  regions `mpss@86c00000` and `rmtfs@f2d00000` exist.
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
| 1 | Laptop: kernel oma4 with `CONFIG_QCOM_BAM_DMUX=m` (and the pending touch-key patch 0005); checkpatch-free config fragment, `W=1` clean | build and modules tarball | a build error | — | none |
| 2 | Packages: `rmtfs`, `qrtr`, `tqftpserv`, `pd-mapper`, ModemManager, after `omarchy update` succeeds (or from `[omamobile]`); all services disabled | installed, nothing started | a partial upgrade would be needed | `pacman -R` | low |
| 3 | rmtfs on RAM copies: a unit that copies the four NV partitions from the backup-verified block devices into `/run/omamobile-rmtfs/` (checking the step 0 sums) and runs rmtfs with that directory as its storage; check rmtfs's file-storage option on the phone first | rmtfs starts and waits; partitions still `ro=1` | rmtfs wants the block devices | stop the unit | low |
| 4 | Boot oma4 with an overlay enabling `remoteproc@4080000`, `qcom_q6v5_mss` blacklisted (one change: the node) | boots; no new errors; remoteproc not started | a hang or new errors | boot oma3 | low |
| 5 | Log streamed, then load the modem: `modprobe qcom_q6v5_mss`, start pd-mapper, tqftpserv, rmtfs | `remoteproc2` "running", sysmon and QRTR services listed (`qrtr-lookup`), no crash loop | the modem crashes or restarts in a loop, or UFS/eMMC errors | `rmmod`, reboot | medium |
| 6 | ModemManager with a SIM inserted (owner): `mmcli -L`, `mmcli -m 0` (state only; identifiers not copied out) | modem listed, SIM present, registered on a network | no SIM seen, or "sim-missing" | stop ModemManager | low |
| 7 | Data: `nmcli connection add type gsm ifname '*' apn <APN>`, connect, then `ping` over it with Wi-Fi off | an IP on the BAM-DMUX interface, ping answers | no bearer, or no traffic | `nmcli connection down` | low |
| 8 | Package it: device-markw ships the rmtfs-on-RAM unit and the blacklist removal, nothing enabled that isn't hang-safe; a quick settings tile for mobile data later | data comes back after a reboot | — | downgrade | low |

Results go here and in NOTES.md, with the date and `uname -r`.
