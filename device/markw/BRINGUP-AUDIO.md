<!-- SPDX-License-Identifier: MIT -->
# markw: audio (runbook)

Status: the DSP and the card come up (steps 0-3) and the loudspeaker path
is known (2026-10-29). The amplifier route and a UCM profile
(device-markw 0.1.8) are written and not yet on the phone (steps 6-9).
The phone runs kernel `7.1.3-msm8953-oma2` from `probe-m7-oma2`.

## Facts

- Audio on MSM8953 goes through the LPASS ADSP (QDSP6): the sound card
  `sound-card@c051000` (`qcom,msm8953-qdsp6-sndcard`, driver
  `snd_soc_apq8016_sbc`, model `xiaomi-markw`) needs the APR services
  q6core, q6afe, q6asm and q6adm, which live on the ADSP's SMD edge
  (`remoteproc@c200000`, `qcom,msm8953-adsp-pil`, driver `qcom_q6v5_pas`).
  The DT also carries the voice services (q6mvm, q6cvs, q6cvp).
- The codec is the PMIC's WCD (`snd_soc_msm8916_analog`, `-digital`); the
  loudspeaker amplifier is an AW8738 (`snd_soc_aw8738`). All these modules
  load today and wait: there is no sound card without the ADSP.
- The ADSP firmware is `adsp.mdt` and `adsp.b00`-`b13` in the modem
  partition's `image/`. `omamobile-markw-firmware` (device-markw 0.1.3)
  copies it read-only into `/usr/lib/firmware/updates`; it never enters the
  repository.
- Until now every probe disabled the ADSP node. `tools/build-markw-probe
  --adsp` enables it; nothing else changes (the modem stays off).
- There is no UCM profile for `xiaomi-markw` in alsa-ucm-conf 1.2.16:
  routing comes after the DSP is proven (step 5).

## Build (laptop only)

```sh
K=~/android/markw/kernel-oma1
tools/build-markw-probe --kernel $K/Image.gz \
  --dtb $K/dtbs/qcom/msm8953-xiaomi-markw.dtb \
  --modules $K/lib/modules/7.1.3-msm8953-oma1 \
  --ssh-key ~/.ssh/id_ed25519.pub --mkbootimg ~/mkbootimg/mkbootimg.py \
  --root-uuid <ROOT-UUID> --usb-role otg --adsp \
  --out ~/android/markw/probe-m6-adsp
```

The USB role stays `otg` as in `probe-m5-oma1`, so the ADSP node is the
only change against the running probe.

## Runbook

Every step is the owner's call. Stop at the first failed Pass. The eMMC is
never written: the probe boots from RAM, the firmware copy mounts the modem
partition read-only, and the only writes are on the microSD root.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Read-only: `omamobile-markw-firmware --check` on the phone; `fdtget markw.dtb /soc@0/remoteproc@c200000 status` on the laptop | "all firmware in place"; `okay` (and `remoteproc@4080000` `disabled`) | firmware missing; modem enabled | â€” | none |
| 1 | Blacklist the ADSP driver for the first boot: `/etc/modprobe.d/omamobile-adsp-bringup.conf` with `blacklist qcom_q6v5_pas` | `modprobe -c` lists it | â€” | delete the file | none |
| 2 | Boot the probe: `MARKW_PROBE=~/android/markw/probe-m6-adsp/boot.img ./DEBUGING_RUN.sh --restart` | lock screen shows; SSH answers; `remoteproc@c200000` status `okay` in `/proc/device-tree`; `qcom_q6v5_pas` not loaded; no sound card yet | no SSH in 3 min | hold Power about 10 s (MIUI), then boot `probe-m5-oma1` | low |
| 3 | Start the DSP by hand under a log stream: `dmesg -w` to the laptop, then `modprobe qcom_q6v5_pas` | `remoteprocâ€¦ is now up`; APR services probe (`q6core`, `q6afe`, `q6asm`, `q6adm`); `/proc/asound/cards` lists `xiaomi-markw` | an oops, a hang, or the remoteproc crashing in a loop | reboot (no `rmmod`); keep the blacklist | medium |
| 4 | Drop the blacklist and boot again | the card comes up on its own at boot; `aplay -l` lists the MultiMedia PCMs | no card | put the blacklist back | low |
| 5 | Routing: a hand-written mixer path for the loudspeaker (`speaker-test -c1 -l1` at low volume), then the earpiece, the headset and the microphones; then a UCM profile and a package | a tone from the loudspeaker; PipeWire sees a sink | no sound with the path set | `alsactl` defaults; mute | low |

Volume stays low through step 5: the AW8738 has no speaker protection, so
no step plays above a quiet level.

## Results

- **Step 0: pass** (2026-10-29, running `7.1.3-msm8953-oma1` from
  `probe-m5-oma1`): the firmware copy took 15 files (`adsp.mdt`,
  `adsp.b00`-`b13`), `--check` reports everything in place. The m6 DTB has
  `remoteproc@c200000` okay, `remoteproc@4080000` disabled,
  `remoteproc@a204000` okay, DWC3 default role peripheral.
- **Step 1: pass** (2026-10-29): `modprobe -c` lists the blacklist.
- **Step 2: pass** (2026-10-29, `probe-m6-adsp`, `7.1.3-msm8953-oma1`):
  node `okay`, `qcom_q6v5_pas` not loaded, no card. Only the known
  `clk-rcg2` boot warning (postmarketOS's kernel has it too).
- **Step 3: pass** (2026-10-29): `modprobe qcom_q6v5_pas` gave `remote
  processor adsp is now up`, seven APR services, and the card
  `xiaomi-markw` (PCMs MultiMedia1, MultiMedia3, VoiceMMode1, a Headset
  Jack input). No oops; Wi-Fi stayed up, although WCNSS logged
  `unexpected response to sysmon event` as the ADSP came up. Log:
  `logs/markw-adsp-step3.log`.
- **Step 5, loudspeaker path found** (2026-10-29, ahead of step 4, at
  -14 dB digital): the AW8738 is fed from the codec's **LINEOUT** (RX3):

  ```
  PRI_MI2S_RX Audio Mixer MultiMedia1  1
  RX3 MIX1 INP1                        RX1
  LINEOUT                              Switch
  LINEOUT Ext                          Switch
  RX3 Digital Volume                   70   (84 = 0 dB)
  ```

  then `aplay -D hw:0,0`, S16_LE 48 kHz stereo. The owner heard path A
  (LINEOUT) and not B (`SPK DAC Switch`, RX3) or C (HPHR via `RDAC2 MUX`
  RX2), each tested alone; every path powered its own PA in DAPM. Quiet
  at this level, as expected.
- **DT gap:** the card's `audio-routing` has no `"Speaker Amp IN",
  "LINEOUT_OUT"` pair, so DAPM keeps `Speaker Amp DRV` (the AW8738's
  enable GPIO) on all the time, playing or not. Add the route before the
  UCM profile, so the amplifier follows playback.

## Speaker route and UCM profile (device-markw 0.1.8)

- **Route.** `device/markw/kernel/patches/0002-…` adds `"Speaker Amp IN",
  "LINEOUT_OUT"` to the card's `audio-routing`, so the AW8738's enable
  GPIO follows the line output. Until a kernel carries the patch,
  `device/markw/initramfs/build` adds the same pair to the probe's DTB when
  the ADSP is on (`--adsp`). It leaves a DTB that already has the route
  alone and stops on any other list. Checked on 2026-11-01 against the oma2
  DTB in Alpine's `dtc`.
- **UCM.** `/usr/share/alsa/ucm2/conf.d/xiaomi-markw/xiaomi-markw.conf`
  (the card's driver and long name are both its DT model) points to
  `Xiaomi/markw/HiFi.conf`. Here is what each part rests on:
  - The verb routes MultiMedia1 (PCM 0) to Primary MI2S and Tertiary MI2S
    to MultiMedia2 (PCM 1).
  - Speaker: the step 5 path; proven by ear.
  - Headphones: the msm8916 codec's HPH path, `JackControl "Headphone
    Jack"`; untested.
  - Mic: AMIC1 (ADC1) and Headset AMIC2 (ADC2 INP2) at ADC volume 8,
    `JackControl "Mic Jack"`; untested.

  The control names come from the card's mixer list (2026-10-29). Every
  digital gain is fixed at 70 (-14 dB). No device names a volume control,
  so PipeWire's volume stays in software and can't push the AW8738 past
  that level. The earpiece waits for its own test.

Steps 6-9 come after step 4 (the blacklist gone). Each step is the owner's
call and plays only at the fixed -14 dB, or quieter.

| # | Step | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 6 | Laptop: rebuild the probe with `--adsp` (route in the DTB). Phone, read-only: `cat /proc/asound/card0/id`, `tr '\0' '\n' < /proc/device-tree/soc@0/sound-card@c051000/audio-routing \| tail -2`, `arecord -l` | `xiaomimarkw`; `Speaker Amp IN`, `LINEOUT_OUT`; MultiMedia2 is capture device 1 | no route; MultiMedia2 isn't device 1 | fix the profile's PCM before step 7 | none |
| 7 | Boot the rebuilt probe; install device-markw 0.1.8. Then `alsaucm -c hw:0 list _verbs` and `alsaucm -c hw:0 list _devices/HiFi` | `HiFi`; Speaker, Headphones, Mic, Headset | "no such file" (wrong driver name: read `/proc/asound/card0/…` and the alsa-lib debug output) | remove the two UCM files | low |
| 8 | Speaker through UCM: `alsaucm -c hw:0 set _verb HiFi set _enadev Speaker`, then `speaker-test -D hw:0,0 -c2 -t sine -f 440 -l1`. Read `Speaker Amp DRV` in `/sys/kernel/debug/asoc/xiaomi-markw/dapm/` during and after | a quiet tone; `DRV` On while playing and Off after | silence; DRV stays on after | `alsaucm … set _disdev Speaker`; `alsactl init` | low |
| 9 | PipeWire: `systemctl --user restart wireplumber pipewire`, then `wpctl status` and a short `pw-play` from the user session | a sink named after the card with a Speaker port; the tone plays | no sink, or a sink with no ports | remove the UCM files and restart PipeWire | low |

Headphones and both microphones are checked after step 9, one at a time,
with `arecord -D hw:0,1 -f S16_LE -r 48000 -d 3` and playing the file back.
Any device that fails comes out of the profile until it's fixed.
