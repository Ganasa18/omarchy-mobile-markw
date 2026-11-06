<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Redmi 4 Prime (`markw`) Omarchy Port Engineering Plan

Status: **M1 probe built and verified offline ([BRINGUP-M1.md](BRINGUP-M1.md)); microSD root path (M3) tooling written and tested offline ([BRINGUP-M3.md](BRINGUP-M3.md)); nothing booted on a phone yet**  
Target: Xiaomi Redmi 4 Prime / Redmi 4 Pro (`markw`), Qualcomm MSM8953 / Snapdragon 625  
Branch used for this planning pass: `omamobile-markw-plan`  
Last planning update: 2026-10-26

This plan extends Omarchy Mobile. It does not define a new distribution. The intended result is native Arch Linux ARM with `pacman`, systemd, Wayland, and Omarchy running directly on the phone. Android userspace, Termux, PRoot, Android chroots, VNC desktops, and Android compatibility layers are not part of the target.

The document deliberately distinguishes four kinds of statements:

- **Verified-source**: present in code or documentation cited here. This proves source support, not behavior on the owner's phone.
- **Assumption**: plausible but not yet proved.
- **Unknown**: requires inspection, build evidence, or physical hardware.
- **Hardware-gated**: must not be claimed complete until an attended device test passes.

No operation described here has been run on a phone. Every temporary boot, reboot, screen-affecting action, partition write, or permanent installation requires fresh human approval immediately before it is performed.

---

## 1. Executive assessment

A native Omarchy Mobile port to `markw` is **technically plausible, with medium-to-high integration complexity**.

The strongest evidence is not a vendor Android kernel. It is the current close-to-mainline MSM8953 stack:

1. `msm8953-mainline/linux` contains a `markw` board DTS, board config, display, touch, GPU, storage, radio, audio, battery, and sensor descriptions.
2. postmarketOS currently treats `markw` as a user of the generic MSM8953 mainline port rather than its archived device-specific port.
3. lk2nd explicitly lists Xiaomi Redmi 4 Prime and associates it with the mainline `msm8953-xiaomi-markw` DTB.
4. Mainline DRM/MSM and Mesa Freedreno support the Adreno 506 family, so a native Wayland compositor is a credible target.
5. Omarchy Mobile already builds an Arch Linux ARM rootfs, installs systemd and Omarchy, provisions a user, and starts a Hyprland-based phone shell.

The port is not a descriptor-only addition. The current project assumes recent Pixel boot architecture: Android boot header v4, A/B partitions, slot-B-only writes, UFS, `vendor_boot`, and automatic fallback to stock slot A. `markw` is an older, non-A/B eMMC device whose practical mainline path uses lk2nd. That requires a new boot backend and a different recovery contract while preserving all current Pixel guards.

The recommended first deliverable is therefore **not a permanent install**. It is an attended, RAM-booted first-light image with its root filesystem on removable microSD. Success means serial/pstore evidence, display, touch, storage, USB networking, and a basic Wayland session. Omarchy and Hyprland are enabled only after those layers pass independently.

### Go/no-go statement

- **Go for offline implementation and image construction** after this plan is reviewed.
- **Go for temporary boot testing** only after the owner confirms backups, bootloader state, recovery access, and the exact hardware variant.
- **No-go for permanent installation** under the repository's current safety rule, which forbids unsuffixed boot-partition writes. A non-A/B `markw` policy must first be reviewed and explicitly approved by the maintainer.

---

## 2. Goals, success criteria, and non-goals

### 2.1 Goals

1. Boot a close-to-mainline arm64 kernel on `markw` through lk2nd.
2. Use the existing Omarchy Mobile repository, package builder, rootfs builder, first-boot provisioning, and shell wherever architecture-independent.
3. Run native Arch Linux ARM with systemd as PID 1 and `pacman` as the package manager.
4. Bring up display, touch, eMMC read-only inspection, microSD root, USB device networking, Adreno 506 acceleration, Wi-Fi, Bluetooth, battery reporting, charging observation, audio, sensors, keys, LEDs, and haptics in a staged order.
5. Run Omarchy's native Wayland session. Try the existing Hyprland profile first, then an optimized Hyprland configuration, Sway, Labwc, and only then XFCE/X11 if the hardware or driver stack makes the preferred paths unusable.
6. Keep device-specific policy in a `markw` device package and descriptor rather than scattering model checks through shared code.
7. Make every build reproducible enough to identify the exact repository, kernel, firmware provenance, package versions, and device variant used.
8. Preserve a documented recovery path before any permanent write is permitted.

### 2.2 Milestone-level success

The port is not “working” merely because a kernel logo appears. Release-candidate success requires:

- ten attended cold boots and ten warm reboots without a new kernel oops, panic, filesystem error, or bootloader lockout;
- the correct panel and touchscreen selected automatically on every tested hardware variant;
- accelerated Wayland confirmed with DRM render-node use and Freedreno, not llvmpipe;
- touch coordinates, orientation, scale, on-screen keyboard, lock screen, power key, and volume keys usable without a mouse;
- Wi-Fi and Bluetooth usable after repeated radio cycles;
- battery percentage and charger state sane across charge/discharge observations;
- suspend/resume either validated or explicitly disabled with an honest UI status;
- rollback tested from the exact installation method proposed for release;
- no proprietary firmware or identifying device data committed to the repository.

### 2.3 Non-goals for first light

- modem calls, SMS, mobile data, IMS, or emergency calling;
- camera capture;
- fingerprint enrollment or authentication;
- deep suspend;
- daily-driver battery life;
- seamless over-the-air kernel updates;
- Android application compatibility;
- destructive repartitioning;
- overwriting recovery, modem, persist, EFS, calibration, or bootloader partitions.

These may become later plans. They must not delay a recoverable first-light result.

---

## 3. Existing Omarchy Mobile flow and reusable components

### 3.1 Current build-to-login flow

The repository currently implements this pipeline:

```text
packages/*
  -> tools/build-packages
  -> signed/local [omamobile] aarch64 repository under out/repo
  -> tools/build-rootfs
  -> Arch Linux ARM ext4 image
       + Omarchy packages
       + Omarchy Mobile packages
       + selected device package
       + matching kernel modules
       + offline [omamobile] repository
  -> tools/install-phone adds firstboot.conf to a private image copy
  -> Pixel slot-B boot images + userdata are written
  -> initramfs finds userdata, grows omamobile-root, mounts it
  -> systemd
  -> omamobile-firstboot
       + machine identity and pacman keyring
       + user, password, SSH key, Wi-Fi
       + Omarchy system and user provisioning
       + SDDM autologin
  -> Omarchy Wayland session
  -> Hyprland + Omarchy shell + Omarchy Mobile plugins
```

Verified implementation points:

- [`tools/build-packages`](../../tools/build-packages) builds aarch64 packages in an Arch Linux ARM container.
- [`tools/build-rootfs`](../../tools/build-rootfs) selects `PACKAGE` and `ROOTFS_PACKAGES` from a device descriptor.
- [`rootfs/build-inside`](../../rootfs/build-inside) installs Arch, Omarchy, the selected device package, modules, and the offline package repository.
- [`packages/omamobile-firstboot`](../../packages/omamobile-firstboot) creates the user and machine-specific state on the first boot.
- [`packages/omamobile-shell`](../../packages/omamobile-shell) layers phone behavior onto Omarchy's own shell and Hyprland session.
- [`bin/omamobile`](../../bin/omamobile) builds kernels, modules, initramfs, and Pixel-style images.

### 3.2 Components reusable without redesign

- Arch Linux ARM container and package build infrastructure.
- Repository order: `[omamobile]`, then `[omarchy]`, then Arch Linux ARM.
- Rootfs package assembly and manifest generation.
- Per-machine state removal before image publication.
- First-boot user, password, keyring, SSH, Wi-Fi, SDDM, and Omarchy setup.
- Most shell plugins, full-screen app policy, touch-sized UI, squeekboard integration, and lock workflow.
- Package tests and repository checks.

### 3.3 Components that cannot be reused unchanged

- Device descriptor validation in `bin/omamobile`: generic images, flash, push and the installer accept only `BOOT_METHOD=android-v4` and refuse every other method before phone access (see §3.4 for the existing `ram-only` exception).
- Image construction: it always creates Pixel boot header v4 images and requires `boot`, `vendor_boot`, and `dtbo`.
- Installer: it requires A/B metadata and writes only `<image>_b` plus `userdata`.
- Initramfs storage guard: it assumes UFS `/dev/sd*`, a Pixel main LUN, and `PARTNAME=userdata`.
- Recovery model: it assumes stock Android survives on slot A.
- `omamobile-device-cheetah`: it contains Pixel-specific boot success, USB, AoC, firmware, sensors, audio, and storage policy.
- Mesa package: it is currently Mali/Panfrost-oriented.
- `rootfs/packages.omamobile`: it names `vulkan-panfrost`, which is wrong for Adreno.
- User setup: monitor scale `3` is hard-coded and tuned for a 1440p Pixel panel.

The design rule is to add explicit backends and device data. It must not weaken the Pixel path merely to make an older phone fit it.

### 3.4 Existing Qualcomm precedent: Pixel 4 (`flame`)

The repository already contains a non-Tensor, Qualcomm first-light port that matches the shape `markw` needs:

- [`device/flame/device.conf`](../flame/device.conf) declares `BOOT_METHOD=ram-only` with empty `BOOT_IMAGES` and `UFS_RW`. [`docs/RELEASES.md`](../../docs/RELEASES.md) §3.1 documents that generic image, flash, push and installer paths refuse it.
- [`tools/build-flame-probe`](../../tools/build-flame-probe) is a dedicated builder: it takes a prebuilt kernel, DTB and watchdog module, packs an initramfs with an SSH key, writes only to a fresh `--out` directory, and never connects to a phone.
- [`device/flame/BRINGUP-M1.md`](../flame/BRINGUP-M1.md) consumes a postmarketOS kernel package (`linux-postmarketos-qcom-sm8150`) instead of maintaining a kernel worktree for first light, and boots through a temporary second-stage loader (U-Boot) rather than the stock boot chain.

Consequences for `markw`:

1. First light needs **no change to `bin/omamobile` or the Pixel guards**. A `markw` descriptor with `BOOT_METHOD=ram-only` is already refused by every write-capable tool.
2. The first deliverable is a `tools/build-markw-probe` modeled on `build-flame-probe`, with lk2nd in place of U-Boot and a legacy (header v0/v1) boot image in place of flame's payload.
3. The first kernel can be the postmarketOS `linux-postmarketos-qcom-msm8953` package build of the §4.2 baseline. A kernel worktree is needed only once `markw` carries its own patches.
4. Flame's handset state is a warning, not a template: separate development work later replaced its stock boot slot and Android data, leaving no verified stock fallback. `markw` must keep RAM-only and microSD-only work separate from any persistent experiment (§9.4, M9).

---

## 4. Evidence policy and source baseline

### 4.1 Source priority

Use sources in this order:

1. upstream Linux, Mesa, systemd, and other upstream projects;
2. `msm8953-mainline` code and documentation;
3. lk2nd code and documentation;
4. current postmarketOS MSM8953 packaging as integration evidence;
5. this repository's own code and future captures;
6. vendor Android captures from the owner's phone, kept private;
7. forum posts only as leads, never as sole proof.

A DTS node is evidence that someone modeled the hardware. It is not proof that the driver works, that the node matches every manufactured unit, or that the feature is safe.

### 4.2 Pinned research baseline

| Component | Baseline inspected | Role |
| --- | --- | --- |
| Omarchy Mobile | repository `HEAD` when this plan was written | target integration tree |
| MSM8953 kernel | `msm8953-mainline/linux` tag `v7.1.3-r0`, commit `7213855948c70fd165356526f1de1c3b6bf4d554` | first kernel candidate |
| lk2nd | commit `fd380ac637d1af38598e3f3c5321d4c962b96315` | secondary bootloader candidate |
| pmaports | commit `435205da9604633a7691d3cb9489f3aa89262c82` | current integration/package reference |
| MSM8953 UCM | commit `501bb905f2a34c0a9a4afbf6db190cb9e9cbec91` | audio route reference |
| markw GPU firmware source | commit `8cc7f7d9e56aa9fa0193403b694115d759eafaf2` | provenance reference; not permission to redistribute |

### 4.3 Important source links

- [MSM8953 kernel tag](https://github.com/msm8953-mainline/linux/tree/v7.1.3-r0)
- [`msm8953-xiaomi-markw.dts`](https://github.com/msm8953-mainline/linux/blob/v7.1.3-r0/arch/arm64/boot/dts/qcom/msm8953-xiaomi-markw.dts)
- [`msm8953-xiaomi-common.dtsi`](https://github.com/msm8953-mainline/linux/blob/v7.1.3-r0/arch/arm64/boot/dts/qcom/msm8953-xiaomi-common.dtsi)
- [`xiaomi-markw.config`](https://github.com/msm8953-mainline/linux/blob/v7.1.3-r0/arch/arm64/configs/xiaomi-markw.config)
- [lk2nd supported devices](https://github.com/msm8916-mainline/lk2nd/blob/master/Documentation/devices.md)
- [lk2nd boot methods](https://github.com/msm8916-mainline/lk2nd/blob/master/Documentation/boot.md)
- [postmarketOS generic MSM8953 package](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/master/device/community/device-qcom-msm8953)
- [postmarketOS MSM8953 kernel package](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/master/device/community/linux-postmarketos-qcom-msm8953)
- [postmarketOS MSM8953 firmware package](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/master/device/community/firmware-qcom-msm8953)
- [MSM8953 UCM repository](https://github.com/msm8953-mainline/alsa-ucm-conf)

Before implementation, record fresh commit IDs. Never silently follow a moving branch.

---

## 5. Hardware support matrix

“Source state” below describes the inspected sources. “Acceptance proof” describes what this project still needs.

| Area | Verified-source evidence | Current assessment | Acceptance proof |
| --- | --- | --- | --- |
| SoC/CPU | `qcom,msm8953`; arm64 Snapdragon 625 platform | strong baseline | all CPUs online; cpufreq and thermal zones sane under load |
| RAM | board DTS and working MSM8953 mainline port imply a known memory map | unknown on owner's exact firmware | total RAM, reserved regions, and no overlap warnings from boot log |
| eMMC | shared DTS enables `sdhc_1` | expected | enumerate read-only first; filesystem stress only on a disposable target |
| microSD | shared DTS enables `sdhc_2`; generic package marks external storage | preferred first root target | boot rootfs, repeated I/O, removal behavior documented |
| Display controller | MSM DRM/MDSS nodes enabled | expected | native modeset, no underrun/reset loop, DPMS cycle |
| Panel A | `DRM_PANEL_MDSS_NT35596_EBBG` and lk2nd panel entry | modeled | panel identified and tested on matching unit |
| Panel B | `DRM_PANEL_MDSS_R63350` and lk2nd panel entry | modeled | panel identified and tested on matching unit |
| Early framebuffer | DTS contains simple framebuffer at `0x90001000` | useful fallback, not final GPU proof | console/logo visible without corrupting reserved memory |
| GPU | Adreno 506 node and per-board zap firmware path | likely with Freedreno | `msm` DRM render node, `etnaviv` absent, renderer reports Freedreno/A506, no llvmpipe |
| Touch A | FocalTech FT5336/FT5306 compatible, disabled in base DTS | modeled variant | correct node enabled; multitouch, edges, rotation, suspend/wake |
| Touch B | Atmel maXTouch at `0x4a`, disabled in base DTS | modeled variant | same tests; prove variant selection before enabling |
| Other touch | common DTS also contains disabled Synaptics RMI4 and Goodix nodes for sibling Xiaomi devices | **not evidence that markw uses them** | private stock DT/capture or physical bus evidence before adding support |
| USB | PMI8950 USB Type-B include and USB controller enabled | expected micro-USB device mode | stable enumeration, network gadget, reconnect, charging coexistence |
| Wi-Fi | WCNSS enabled, WCN3660B, `WCN36XX` config | likely | firmware load, NetworkManager scan/connect, throughput, cycles, MAC persistence without publishing it |
| Bluetooth | `qcom,wcnss-bt`, `BT_QCOMSMD` config | likely | BlueZ adapter, scan, pair, reconnect, audio optional |
| Audio codec | QDSP6/APQ8016-style sound card and WCD analog/digital codec | modeled | UCM route, headphones, microphones, speaker muted-by-default |
| Speaker amp | AW8738 node and kernel config | modeled; potentially hardware-sensitive | low-volume staged test, mute path, no DC/pop/overheat |
| Battery gauge | Qualcomm FG node and `BATTERY_QCOM_FG` | modeled | plausible voltage/current/capacity over time |
| Charger | PMI8950 SMB charger and `CHARGER_QCOM_SMBCHG` | modeled; safety-sensitive | observe only first, then attended charge tests with temperature checks |
| Light/proximity | LTR559-compatible node | modeled | IIO events and plausible values |
| IMU | BMI120 node; BMI160 driver config | modeled | axes, mount matrix, autorotation |
| Magnetometer | YAS537 node; YAS530-family driver config | modeled | stable readings and orientation |
| Keys | power/resin and volume-up nodes; GPIO keys | expected | press/release mapping, long press, wake behavior |
| RGB notification LED | AW2013 nodes | modeled | each channel at conservative current |
| Haptics | PMI8950 ERM haptics node | modeled | brief low-strength test after announcement |
| Cameras | S5K3L8 rear and OV5670 front nodes | source support exists | deferred; no first-light requirement |
| Modem | MPSS remoteproc enabled | source support exists but high risk | deferred to a separate modem plan and backup gate |
| Fingerprint | no usable `markw` mainline path established by inspected sources | unsupported/unknown | deferred research; never infer from Android HAL alone |
| GNSS | likely modem-integrated on this platform | unknown in this port | deferred with modem/QRTR work |
| Suspend | platform support not proved on `markw` | unknown | staged s2idle cycles after storage, USB, radios, and wake sources are safe |

### Interpretation

The matrix supports a credible handheld Linux target, but the confidence is uneven. Display, touch selection, boot layout, and recovery dominate feasibility. Cameras and cellular do not.

---

## 6. Physical-device preflight and unknowns

No hardware action starts until this inventory is complete and stored outside the public repository.

### 6.1 Owner confirmations

- Exact retail model and codename shown by the bootloader.
- Bootloader unlock status and whether unlocking has already erased data.
- Whether stock recovery or a known recovery image remains available.
- Battery health and a known-good cable/USB port.
- Whether the owner accepts losing Android data later; the first-light plan does not require this.
- Which stock firmware release is installed.
- Whether the phone has a working microSD slot and a disposable card.

### 6.2 Private read-only captures

Capture into a private directory, never into the repository:

- bootloader variables and partition table;
- partition names, sizes, block sizes, and whether the device is A/B;
- checksums and read-only backups of boot/recovery plus calibration-sensitive partitions permitted by project policy;
- stock device tree and command line;
- panel identifier;
- touchscreen controller identifier and bus address;
- USB IDs/modes;
- Android kernel logs needed to identify regulators, GPIOs, and firmware;
- charging and battery baseline;
- recovery entry key sequence and evidence that it still works.

Redact serials, addresses, account names, SSIDs, and IDs before quoting any line into this plan.

### 6.3 Open questions that block image design

1. Does the stock `markw` bootloader permit a temporary RAM boot of lk2nd on this firmware?
2. Once lk2nd is running in RAM, can it read this unit's microSD reliably?
3. Does lk2nd select both known panel variants correctly?
4. Does current lk2nd identify Atmel as well as FocalTech on `markw`, or does its current board entry force only FocalTech?
5. What legacy Android boot header, page size, kernel compression, DTB packing, and command line does the tested lk2nd build expect?
6. Can the kernel and initramfs remain within lk2nd's documented 50 MiB extlinux boot-memory window?
7. Does USB return after a failed kernel boot, or is a physical key recovery required?
8. Which root-device identifier is stable across lk2nd and the kernel: filesystem UUID, label, or PARTUUID?
9. Is the battery removable only by disassembly, and what hard-reset sequence is reliable?
10. Does the unit have a touch controller not represented by the current `markw` DTS?

Each answer must be written into `PROGRESS.md` and then reflected here as verified evidence.

---

## 7. Feasibility analysis

### 7.1 Kernel feasibility: high enough to proceed

The close-to-mainline tree already has a dedicated board DTS and config. This is substantially better than starting from an Android downstream kernel. The gap is maintenance: the board DTS is not in Torvalds' tree, so the project must carry a pinned kernel fork or curate a small patch series until support lands upstream.

### 7.2 Boot feasibility: plausible, not yet proved on this unit

lk2nd explicitly supports `markw` and supports Android boot images, temporary fastboot boot, and rudimentary extlinux. This provides two reversible first-light candidates. The present Omarchy image tool cannot build either layout, so boot tooling is the first code milestone.

### 7.3 Graphics feasibility: plausible with performance risk

Adreno 506 has a native DRM/Freedreno path. The remaining questions concern old-GPU behavior with current Mesa, Hyprland/wlroots requirements, modifiers, scanout, GTK rendering, and 3 GiB-class memory pressure. postmarketOS carries `GSK_RENDERER=cairo` as an A506 workaround; that is evidence of a GTK rendering issue, not evidence that hardware acceleration or Hyprland is impossible.

### 7.4 Userspace feasibility: strong

The rootfs and first-boot stack are architecture-compatible. Most work is package selection, device policy, and screen calibration. The final system remains normal Arch Linux ARM and can use existing Omarchy update mechanics after kernel/boot updates receive a safe backend.

### 7.5 Daily-driver feasibility: unknown

A desktop session is easier than a safe phone. Charging, idle power, suspend, radio behavior, audio routing, and thermal management determine daily use. They require hardware evidence and cannot be inferred from the DTS.

---

## 8. Target architecture and boundaries

```text
Host build system
├── Omarchy Mobile repository
├── Arch Linux ARM package container
├── pinned msm8953-mainline kernel worktree
├── pinned lk2nd source/build
├── signed/local [omamobile] repository
└── image artifacts + manifest + checksums

Phone boot path
├── Qualcomm ROM / Xiaomi primary boot chain
├── lk2nd-msm8953
├── Linux Image + msm8953-xiaomi-markw.dtb + initramfs
├── rootfs on microSD for first light
└── Arch Linux ARM
    ├── systemd
    ├── udev, NetworkManager, BlueZ, PipeWire/WirePlumber
    ├── Mesa Freedreno
    ├── Wayland compositor
    └── Omarchy + Omarchy Mobile shell
```

### 8.1 Package boundaries

- `linux-omamobile-markw` or a clearly named MSM8953 kernel package: kernel, modules, DTBs; exact naming should align with the release design before implementation.
- `omamobile-device-markw`: device services, module policy, udev, setup-system implementation, firmware checks, display defaults, audio policy, and smoke tests.
- `omamobile-firmware-markw`: only if licensing permits redistribution. Otherwise provide a local extraction tool and package recipe whose output is never committed.
- shared `mesa`: build both Panfrost and Freedreno where practical, rather than replacing one device's driver with another and breaking Pixels.
- shared `omamobile-shell`: consume device-provided scale/capabilities instead of model checks.
- optional MSM8953 audio/UCM package if the data is suitable and licensed.

### 8.2 Capability model

The shell must not show broken controls as if they worked. The device package should expose machine-readable capabilities for items such as:

- torch;
- fingerprint;
- modem/mobile data;
- NFC;
- autorotation;
- haptics;
- battery saver;
- suspend;
- cameras.

Prefer a small data file under `/usr/share/omamobile/` or discoverable system interfaces. Do not hard-code `markw` branches in QML.

---

## 9. Proposed boot flow

### 9.1 First-light flow: no internal-storage writes

Preferred flow:

```text
Xiaomi bootloader/fastboot
  -> temporary lk2nd image loaded into RAM
  -> lk2nd fastboot or lk2nd extlinux loader
  -> Linux Image
  -> msm8953-xiaomi-markw.dtb selected for this board
  -> small diagnostic initramfs
  -> mount disposable microSD root by UUID, initially read-only
  -> switch_root to Arch Linux ARM
  -> systemd multi-user target
  -> USB network + SSH
  -> DRM/KMS test
  -> Weston or cage diagnostic session
  -> Mesa Freedreno test
  -> Hyprland/Omarchy session
```

Fallback if lk2nd cannot read microSD at boot: use lk2nd fastboot to RAM-load a legacy Android boot image containing kernel and initramfs, then let the kernel mount the microSD root.

This sequence is hardware-gated. A temporary boot still affects the phone and requires human approval. It is not run merely because it does not write flash.

### 9.2 Why the diagnostic initramfs comes first

The current initramfs is a Pixel storage and fallback environment. The `markw` first-light initramfs needs a separate backend with these properties:

- no assumption that `/dev/sda` is UFS;
- no writable internal partition;
- root located by an explicit filesystem UUID supplied at image build time;
- shell/SSH available before `switch_root`;
- pstore/ramoops collection;
- finite timeout and a documented halt/reboot behavior;
- no automatic resize on first light;
- no module unload or register access experiments;
- all optional hardware modules blacklisted until their milestone.

### 9.3 Full native runtime flow

After each layer is proved:

```text
systemd
  -> udev and module loading under omamobile-device-markw policy
  -> NetworkManager / systemd-resolved
  -> BlueZ
  -> PipeWire / WirePlumber / ALSA UCM
  -> SDDM autologin
  -> Omarchy session
  -> Hyprland
  -> Mesa Freedreno on /dev/dri/renderD*
  -> Quickshell-based Omarchy shell and mobile plugins
  -> squeekboard input method
```

Android is not present in this chain.

### 9.4 Persistent flow: deferred and policy-blocked

lk2nd normally occupies the non-A/B `boot` partition, while it can load an OS image from an offset in that partition or from extlinux on another ext2 filesystem. Either route requires a recovery design and, for lk2nd installation, an unsuffixed boot-partition write.

The repository currently says never perform an unsuffixed boot flash. Therefore:

- no persistent `markw` installer is implemented in the initial series;
- no current Pixel installer is generalized by deleting its slot checks;
- permanent installation remains blocked until a maintainer-approved `markw` safety policy identifies allowed partitions, mandatory backups, exact restore verification, and recovery buttons;
- the first implementation must fail closed when asked for persistent install.

---

## 10. Boot, storage, installer, and recovery design

### 10.1 Boot backend design

Reuse the descriptor's existing `BOOT_METHOD` boundary rather than spreading conditionals across scripts:

| `BOOT_METHOD` | Existing | Responsibility |
| --- | --- | --- |
| `android-v4` | yes (Pixel path) | current v4 images, slot B, UFS guard, A/B recovery; unchanged |
| `ram-only` | yes (`flame`) | `markw` M1–M8: dedicated `tools/build-markw-probe`, lk2nd and Linux loaded into RAM, no phone writes; refused by generic tools |
| a persistent `markw` method | future, disabled | explicit non-A/B policy after maintainer approval (M9) |

The essential property is that the Pixel guard remains unchanged and the transient path has no write primitive. A new `BOOT_METHOD` value is introduced only at M9, together with its own reviewed installer.

### 10.2 Root filesystem phases

1. **M1–M4:** disposable microSD, separate small ext2 boot filesystem only if extlinux needs it, ext4 `omamobile-root` partition for Arch.
2. **M5:** microSD remains default while radios/audio/power are tested.
3. **Post-M5:** evaluate internal `userdata` only after the owner accepts erasing Android data and recovery has been rehearsed.
4. **Release:** choose one documented layout. Do not support several half-tested layouts.

Use filesystem UUID for first-light root selection. A generic label alone can select the wrong disk if two `omamobile-root` filesystems are present.

### 10.3 Storage guard

The Pixel guard cannot simply be disabled. Add a block-device-neutral policy engine with per-backend inputs:

- transient `markw`: internal eMMC disks and partitions forced read-only; only the designated removable root partition may be writable;
- future persistent `markw`: allowlist exact GPT partition names and verified parent block device; never allow a whole disk;
- Pixel: preserve the present UFS and slot-B behavior byte-for-byte, backed by regression tests.

Root-device discovery must use sysfs/udev identity and `PARTNAME`/UUID, not a guessed `/dev/mmcblk0` number.

### 10.4 Installer policy

The current `tools/install-phone` must continue rejecting every method except `android-v4`, including `ram-only` and any future `markw` method. A future `install-markw` path must not share a generic `flash()` function that accepts arbitrary partition names.

Required gates before a future write-capable installer can exist:

- exact product and board match;
- unlocked bootloader;
- battery threshold;
- private backup manifest and checksum verification;
- original boot image size equals target partition size expectations;
- recovery mode entered successfully during the same session;
- root image and kernel/module release match;
- owner types the codename and the exact partition being replaced;
- read-back checksum after each write;
- no automatic repartitioning;
- no modem, persist, EFS, recovery, or bootloader writes.

### 10.5 Recovery tiers

- **Tier 0:** temporary boot times out or fails; force restart into stock bootloader. No storage change.
- **Tier 1:** microSD root corrupt; remove/reimage the card. Internal storage remains untouched.
- **Tier 2:** future lk2nd boot image bad; restore the checksum-verified original boot image from bootloader/recovery.
- **Tier 3:** USB unavailable; use verified hardware key sequence, another known-good cable/host, and pre-positioned recovery files.
- **Stop:** if product identity, partition map, backup checksum, or recovery entry differs from the recorded baseline.

---

## 11. Kernel strategy

### 11.1 Selected initial baseline

Use `msm8953-mainline/linux` tag `v7.1.3-r0` for the first implementation spike because it is the current packaged close-to-mainline baseline found during research and includes `msm8953-xiaomi-markw.dts`.

As with `flame` (§3.4), M1–M3 may consume the postmarketOS `linux-postmarketos-qcom-msm8953` package built from this tag, recording its package version and checksums, instead of building a worktree. The branch and worktree below become necessary at the first `markw`-specific kernel patch or config change.

Do not call it “mainline Linux.” Call it **close-to-mainline** and record its delta from the corresponding upstream release.

### 11.2 Branch and worktree

Proposed local layout:

```text
kernel branch:  omamobile-markw
worktree:       ~/android/mainline/wt-markw
output:         ~/android/mainline/out-markw
```

Every build command must set both `KERNEL_DIR` and `KERNEL_OUT`. Never share Pixel integration output.

### 11.3 Configuration construction

Start from arm64 `defconfig`, the MSM8953 fragment, and `xiaomi-markw.config`. Convert this into a reviewable Omarchy fragment or reproducible merge sequence. Required areas include:

- Qualcomm clocks, RPM/RPMPD, regulators, pinctrl, remoteproc, RPMSG/GLINK/SMD;
- eMMC and SD;
- USB gadget and configfs;
- DRM/MSM and both `markw` panel drivers;
- Adreno/Freedreno kernel support;
- both verified touch driver families;
- battery gauge and SMB charger;
- WCNSS, wcn36xx, and QCOM SMD Bluetooth;
- QDSP6/WCD/AW8738 audio;
- IIO sensor drivers;
- pstore/ramoops;
- ext2/ext4 and initramfs requirements;
- namespaces/cgroups/security features expected by Arch and Omarchy.

Boot-critical storage, filesystem, regulator, remoteproc dependencies, and USB diagnostics should be built-in until initramfs module loading is proved. Convert them to modules only for a measured reason.

### 11.4 Kernel patch policy

- Keep board fixes in the kernel branch, not as boot-time userspace register writes.
- Prefer DT overlays only for controlled bring-up toggles; permanent hardware description belongs in DTS.
- New risky nodes remain disabled until enabled by one overlay/change per boot.
- Run `dtbs_check`, `dt-validate`, `W=1`, and `checkpatch --strict` for touched files.
- Rebase to a newer MSM8953 tag only between milestones, not while diagnosing hardware.
- Track which patches are already upstream, submitted, or local-only.

### 11.5 Kernel acceptance artifacts

Each tested build records:

- source commit and dirty status;
- compiler and binutils versions;
- merged config checksum;
- kernel release;
- `Image`, DTB, modules, and initramfs checksums;
- boot method and lk2nd commit;
- exact panel/touch variant, represented by non-identifying labels;
- filtered boot log and pstore result.

---

## 12. Device tree, panel, and touch variants

### 12.1 Base board description

The board DTS sets `compatible = "xiaomi,markw", "qcom,msm8953"`, describes both known touch families as disabled, and delegates panel selection through `compatible = "xiaomi,markw-panel"`. This strongly suggests that the boot stage is expected to fix up the final panel and touch node for the detected hardware.

### 12.2 Variant policy

Do not ship separate opaque images named “try1,” “try2,” or by owner. Use explicit variant identifiers:

| Dimension | Known values | Selection target |
| --- | --- | --- |
| Panel | `nt35596-ebbg`, `r63350` | lk2nd hardware identification/fixup |
| Touch | `focaltech-ft5336`, `atmel-maxtouch` | lk2nd or read-only probe with one driver enabled |
| Unknown touch | none proven | fail closed; collect evidence |

If lk2nd only selects FocalTech on the inspected revision, add Atmel identification upstream in lk2nd rather than enabling both Linux nodes and allowing two drivers to probe shared rails/interrupts.

### 12.3 Bring-up rules

- First boot uses simple framebuffer or one selected panel driver, never simultaneous blind panel probes.
- Touch controller probing begins only after display is stable.
- Never toggle reset or supply GPIOs for multiple possible touch controllers in one experiment.
- Record raw touch ranges, physical size, axis inversion, and compositor transform.
- Test all screen edges and at least five simultaneous contacts.
- A rotation fix belongs in DT mount/coordinate data or compositor output config, not an application-specific workaround.

### 12.4 Validation

For each variant:

1. prove lk2nd's reported selection;
2. prove the final flattened DT contains exactly one enabled panel and one enabled touch node;
3. verify the Linux driver binding;
4. verify panel mode and backlight range;
5. verify touch coordinates before starting Omarchy;
6. save a non-identifying variant result in the compatibility table.

---

## 13. Arch Linux ARM rootfs and system integration

### 13.1 Rootfs policy

Reuse `tools/build-rootfs` and `rootfs/build-inside`. Add `omamobile-device-markw` through the descriptor's `PACKAGE`. Add only board-specific packages through `ROOTFS_PACKAGES`.

The image remains:

- ext4;
- built from Arch Linux ARM repositories plus `[omarchy]` and `[omamobile]`;
- without a normal user until first boot;
- without SSH host keys, machine ID, pacman private key, Wi-Fi profile, or per-device identifiers;
- coupled to one kernel module release in its manifest.

### 13.2 First-boot changes

`omamobile-firstboot` is mostly reusable. Required work:

- ensure USB SSH is not assumed to be `usb0`; provide a stable device-package network name or interface match;
- permit first-light without SDDM so debugging reaches `multi-user.target` first;
- enable only services present for the device;
- let device capabilities suppress Pixel-only services;
- make root resize opt-in for the removable test image;
- keep the firewall's SSH rule bound to the actual USB gadget interface.

### 13.3 Device setup-system

`omamobile-device-markw` needs its own `omamobile-setup-system` implementation for:

- locale/time setup shared with the current script where possible;
- enabled units appropriate to MSM8953;
- radio firmware preflight;
- sensor/autorotation enablement only when the IIO device exists;
- no AoC, Trusty, Pixel fingerprint, Pixel GNSS, or Pixel speaker-protection units;
- no boot-slot success marker.

Factor truly common locale/time code into a shared helper only if doing so keeps both package tests simple.

### 13.4 Update policy

Package updates may be enabled after the rootfs is stable. Kernel and bootloader updates remain held until a `markw` boot-update backend has transactional backup and recovery semantics. `omarchy update` must refuse a transaction that would replace the running kernel without a safe installation path.

---

## 14. GPU, Mesa, Wayland, and compositor decision

### 14.1 Mesa packaging

The existing custom Mesa package is Mali/Panfrost-focused. Modify it so the built artifact includes the drivers needed by all supported devices, ideally:

- Gallium: `freedreno` and `panfrost` plus required software fallbacks;
- Vulkan: retain PanVK/Panfrost support needed by Pixels and include Turnip only if A5xx support and package policy justify it;
- platforms: Wayland and X11 as required by Omarchy;
- VA-API/video only when supported and tested.

Do not replace `vulkan-panfrost` globally with an Adreno package. Make GPU packages selected by device or ship a multi-driver Mesa package with clear dependencies.

### 14.2 Graphics bring-up ladder

1. simple framebuffer console;
2. DRM/KMS with a minimal test tool;
3. software-rendered Wayland compositor;
4. Freedreno GLES under Weston or cage;
5. Sway or Labwc with hardware rendering;
6. Hyprland with minimal config;
7. full Omarchy Mobile session.

At every level capture frame timing, memory use, kernel errors, and whether direct scanout/modifiers are involved.

### 14.3 Compositor order and decision gate

| Rank | Candidate | Use |
| --- | --- | --- |
| 1 | existing Hyprland | preserves Omarchy with least user-facing divergence |
| 2 | optimized Hyprland | disable costly effects, reduce animations, tune render behavior |
| 3 | Sway | mature wlroots fallback with predictable resource use |
| 4 | Labwc | lighter stacking compositor fallback |
| 5 | XFCE/X11 | last resort; does not satisfy preferred native Wayland experience |

Hyprland remains default only if it meets all of these on hardware:

- stable startup and DPMS;
- no persistent corruption/flicker in shell and browser tests;
- acceptable input latency;
- idle memory leaves enough headroom for normal applications;
- 30-minute interaction test without GPU recovery, compositor crash, or thermal runaway.

### 14.4 Performance defaults

Start conservatively:

- no blur, shadows, shader effects, or perpetual animations;
- 60 Hz native mode only;
- one full-screen application per workspace;
- modest background service set;
- GTK `GSK_RENDERER=cairo` only if the known A506 issue reproduces; scope it to affected GTK versions/apps if possible;
- no global software rendering workaround that hides a broken Freedreno path.

---

## 15. Mobile UI, input, scaling, and rotation

### 15.1 Reuse

Reuse the existing Omarchy Mobile shell, app launcher, quick settings, lock flow, full-screen policy, and squeekboard integration. These are already designed for touch and small screens.

### 15.2 Required adaptation

- Replace the hard-coded scale `3` in `omamobile-setup-user` with device data or an idempotent calibration result.
- Set a `markw` baseline for a 1080×1920 portrait panel; likely scale must be measured rather than guessed.
- Provide output transform and touch mapping together.
- Ensure touch targets remain at least 44 logical pixels without making dialogs unusable.
- Test the 480-logical-pixel assumptions in existing phone components against the chosen `markw` scale.
- Hide unsupported tiles such as fingerprint, NFC, torch, mobile data, or rotation until their backend is present.
- Keep keyboard, lock screen, portal dialogs, and SDDM usable in portrait.

### 15.3 Input acceptance

- power and volume keys have correct press/release events;
- accidental repeated events do not trigger shutdown or volume runaway;
- touch works at all edges and after compositor restart;
- squeekboard opens and closes for GTK, Qt, Chromium, and terminal fields;
- lock screen can always be dismissed without a hardware keyboard;
- autorotation changes output and touch transform atomically;
- rotation lock survives session restart.

---

## 16. Firmware and licensing plan

### 16.1 Known requirement

The board DTS requests:

```text
/usr/lib/firmware/qcom/msm8953/xiaomi/markw/a506_zap.mdt
```

The current postmarketOS package installs `a506_zap.mdt` and `a506_zap.b02` from a pinned `firmware-xiaomi-markw` source. Additional WCNSS, modem, audio, and calibration data may be loaded through firmware partitions or Qualcomm firmware loaders rather than a redistributable package.

### 16.2 Policy

- Do not commit proprietary blobs.
- Do not assume a public blob repository's existence grants redistribution rights.
- Prefer extraction from the owner's legally obtained Xiaomi firmware or from read-only partitions on the owner's phone.
- Pin expected filenames and hashes in a local manifest, but never publish unique calibration data.
- Keep extracted output under a gitignored private directory.
- Package only files whose license permits it; otherwise build a local package for that owner.
- Never substitute firmware from another MSM8953 device without documentation that the component and calibration are compatible.

### 16.3 Extraction tool requirements

A future `tools/extract-markw-firmware` must:

- accept an owner-supplied factory package or mounted read-only source;
- verify expected product and archive structure;
- extract a strict allowlist;
- print provenance and checksums;
- refuse unknown versions rather than globbing broad directories;
- never extract or package identifiers, Wi-Fi calibration, modem NV, fingerprint data, or user data;
- produce a local package artifact outside git.

### 16.4 Firmware acceptance

Every firmware request in `dmesg` is classified as:

- redistributable package;
- locally extracted generic firmware;
- per-device/calibration data that must stay in place and be accessed read-only;
- unnecessary because the subsystem is disabled;
- unresolved blocker.

“No missing firmware messages” is not sufficient: prove the expected driver and remote processor actually reached its operational state.

---

## 17. Subsystem bring-up order

The order minimizes simultaneous unknowns.

### 17.1 Foundation

1. CPU, clocks, interrupt controller, timer, serial/pstore.
2. eMMC read-only discovery and microSD root.
3. USB device mode, network gadget, and SSH.
4. regulators and thermal monitoring.

### 17.2 Human interface

5. simple framebuffer, then DRM panel.
6. backlight with a conservative ceiling.
7. one identified touchscreen driver.
8. power and volume keys.
9. RGB LED and haptics only after announcement.

### 17.3 Accelerated session

10. Adreno firmware and DRM render node.
11. Mesa Freedreno.
12. minimal Wayland compositor.
13. Hyprland and Omarchy Mobile shell.
14. squeekboard, lock, scaling, rotation.

### 17.4 Connectivity

15. Wi-Fi/WCNSS firmware and NetworkManager.
16. Bluetooth/BlueZ.
17. USB reconnect and coexistence with charging.

### 17.5 Power and media

18. battery gauge read-only observation.
19. charger reporting; attended charging only later.
20. sensors and autorotation.
21. headphone audio.
22. speaker audio at a conservative level.
23. microphone capture.
24. suspend/resume last.

### 17.6 Deferred projects

25. modem/telephony and GNSS, behind backup verification.
26. cameras.
27. fingerprint.

Each numbered step gets its own result in `PROGRESS.md`. Do not combine two new hardware drivers in one test boot.

---

## 18. Omarchy Mobile modification map

This is the required change inventory, not authorization to implement all rows at once.

| Area | Existing state | Planned change for `markw` | Scope/risk |
| --- | --- | --- | --- |
| Rootfs | shared ALARM ext4 image, Pixel-oriented package list | keep builder; select `omamobile-device-markw`; make GPU package selection architecture-neutral | medium |
| Kernel | external Pixel worktrees plus shared fragment | add pinned MSM8953 worktree/config procedure and DT validation | medium |
| Kernel package | release design assumes device builds Pixel images | package MSM8953 Image/modules/DTB without automatic boot write initially | high |
| Device abstraction | generic tools accept only `android-v4`; `ram-only` exists for `flame` | use `BOOT_METHOD=ram-only` for first light; a persistent method and storage class only at M9; Pixel schema unchanged | low (M1), high (M9) |
| Device package | only board-specific packages for existing devices | create `packages/omamobile-device-markw` with minimal staged policy | medium |
| Firmware | Pixel extraction/provisioning paths | add strict local `markw` extractor/package path; no blob commits | high/legal |
| Mesa | custom build focused on Mali/Panfrost | build Freedreno while retaining existing device support; audit package split | medium |
| Vulkan | rootfs names `vulkan-panfrost` | select per-device Vulkan package or omit Vulkan initially; GLES is enough for first light | medium |
| Compositor | custom Hyprland with Pixel-derived DPMS patch | test patch generically; add no `markw` workaround until reproduced | medium |
| Wayland diagnostics | full Omarchy session is primary path | add minimal compositor/test profile for bring-up | low |
| UI | shell assumes phone but exposes some Pixel features | capability-gate unavailable tiles and services | medium |
| Display scale | setup-user hard-codes scale `3` | obtain scale/transform from device package or descriptor | medium |
| Touch | no device variant abstraction in this repo | rely on lk2nd/DT selection; record panel/touch matrix | high |
| Rotation | `omamobile-sensors` expects an accelerometer backend | map BMI120 IIO orientation; enable only after axes are validated | medium |
| Images | `bin/omamobile images` creates header-v4 Pixel images | leave unchanged; add `tools/build-markw-probe` modeled on `tools/build-flame-probe` | medium |
| Initramfs | UFS, userdata, slot-B fallback | add eMMC/microSD transient profile with internal storage read-only | critical |
| Boot | ABL and A/B retry model | support temporary lk2nd chain; persistent path disabled | critical |
| Installer | writes slot-B images and userdata | leave it rejecting `markw`; later add a separate non-A/B installer only after policy approval | critical |
| Flashing | fixed `_b` allowlist | do not relax it; transient backend has no write operation | critical |
| Recovery | stock slot A | document stock bootloader/recovery and original boot restore; rehearse before persistent work | critical |
| Root discovery | fixed userdata partition | root by explicit UUID for removable first-light media | high |
| Power | Pixel battery/USB-C userspace | use standard power_supply interfaces; add no charging writes initially | high |
| Charging | mature Pixel-specific work | observe SMB charger first; attended staged tests with thermal stop conditions | critical |
| Audio | Pixel AoC and CS35L41 packages | use MSM8953 QDSP6/WCD UCM; keep speaker muted until route and amp are understood | high |
| Networking | USB static link plus NetworkManager | define stable USB gadget name; add WCNSS module/firmware ordering | high |
| Wi-Fi | Pixel brcmfmac | use `wcn36xx`, not brcmfmac assumptions | high |
| Bluetooth | Pixel address helper | use QCOM SMD path; preserve address without publishing it | medium |
| Battery | Pixel gauge integration | validate QCOM FG units and shell display | high |
| Sensors | Pixel AoC proxy | use IIO directly or adapt `omamobile-sensors`; no AoC service | medium |
| Updates | Pixel slot-B boot update design | hold kernel/lk2nd packages until transactional non-A/B backend exists | critical |
| Smoke tests | phone-smoke expects mature Pixel features | parameterize expected/unsupported features by device capability | medium |
| Documentation | Pixel safety and device plans | add markw safety addendum before any unsuffixed partition write | critical |
| CI | package tests and repository checks | add descriptor backend tests, image-layout tests, and negative tests proving Pixel guards remain | high |

### Planned repository paths

```text
device/markw/ENGINEERING-PLAN.md        # this document
device/markw/device.conf                # BOOT_METHOD=ram-only, empty BOOT_IMAGES/UFS_RW (M1)
device/markw/BRINGUP-M1.md              # first-light runbook, modeled on device/flame
device/markw/NOTES.md                   # sanitized hardware results
tools/build-markw-probe                 # RAM-only lk2nd payload builder; never touches a phone (M1)
packages/omamobile-device-markw/        # device package
tools/extract-markw-firmware            # if licensing design requires it
kernel/configs/omamobile-msm8953.config # name subject to kernel packaging decision
```

Do not add empty scaffolding merely to make the tree look complete. Each path enters in the milestone that consumes it.

---

## 19. Dependency map

```text
recovery proof ───────────────────────────────┐
bootloader identity ──> temporary lk2nd ─────┼─> kernel first light
panel/touch identity ───────┐                 │
microSD preparation ────────┴─> root mount ──┘

kernel first light
├── USB gadget + SSH ─────────────> safe diagnostics
├── regulators/clocks ────────────> display, touch, radios, audio
├── DRM panel ────────────────────> KMS
│   └── Adreno firmware + GPU ────> Mesa Freedreno
│       └── minimal Wayland ──────> Hyprland
│           └── Omarchy shell ───> mobile UI acceptance
├── touch + keys ─────────────────> no-keyboard operation
├── WCNSS remoteproc ─────────────> Wi-Fi + Bluetooth
├── QDSP6/codec/UCM ──────────────> headphone/mic
│   └── verified mute/gain ───────> speaker amp
├── battery gauge ────────────────> status UI
│   └── thermal + charger model ──> attended charging
└── IIO sensors ──────────────────> autorotation

recovery proof + backup proof + stable M5
└── approved non-A/B policy
    └── persistent lk2nd design
        └── installer
            └── kernel update backend
```

### Critical path

1. Recovery evidence.
2. Temporary lk2nd.
3. Kernel + DTB + initramfs packaging.
4. microSD root and USB SSH.
5. correct panel and touch variant.
6. Freedreno and minimal Wayland.
7. Hyprland/Omarchy.

Audio, radios, and suspend are important but not on the first-light critical path.

---

## 20. Architecture decision records

### ADR-001 — Extend Omarchy Mobile, do not create a parallel distro

- **Options:** separate distribution; postmarketOS-based userland; extend this repository.
- **Tradeoff:** extending this repository requires boot abstraction work but preserves Omarchy packages, shell, updates, and project identity.
- **Risk:** old-phone conditionals could pollute Pixel paths.
- **Decision:** extend the existing `device/<codename>` and package model with explicit backends.
- **Rationale:** it meets the user's native Omarchy goal and minimizes long-term divergence.

### ADR-002 — Use the close-to-mainline MSM8953 kernel first

- **Options:** Xiaomi/vendor Android kernel; Torvalds tree; `msm8953-mainline/linux`.
- **Tradeoff:** vendor has board support but old Android interfaces; Torvalds is cleaner but lacks `markw` DTS; MSM8953 fork has the strongest current board integration but carries patches.
- **Risk:** fork maintenance and uncertain upstream status.
- **Decision:** start from pinned `v7.1.3-r0`; periodically measure its delta and upstream status.
- **Rationale:** shortest credible path to native DRM, input, storage, and radios without Android userspace.

### ADR-003 — Use lk2nd as the secondary bootloader

- **Options:** stock bootloader directly; U-Boot port; lk2nd; recovery-kexec-only design.
- **Tradeoff:** lk2nd is an extra component but already lists `markw` and can boot mainline payloads.
- **Risk:** hardware-variant detection or temporary boot may differ by firmware.
- **Decision:** evaluate lk2nd first; do not install it persistently until recovery is proved.
- **Rationale:** existing MSM8953 ecosystem support outweighs writing a new boot port.

### ADR-004 — Add a boot strategy interface, not relaxed Pixel checks

- **Options:** force `markw` into Android-v4 fields; scatter `if markw`; introduce backend strategies.
- **Tradeoff:** a strategy interface is more code initially but testable and fail-closed.
- **Risk:** accidental shared-code regression.
- **Decision:** separate Pixel A/B and transient `markw` artifact/install behavior. First light reuses the existing `BOOT_METHOD=ram-only` contract and a dedicated probe builder, as `flame` does (§3.4); a persistent method is added only at M9.
- **Rationale:** the two boot/storage models have different safety invariants, and the repository already has a reviewed fail-closed boundary for RAM-only Qualcomm probes.

### ADR-005 — First-light rootfs lives on microSD

- **Options:** initramfs-only; internal userdata; microSD.
- **Tradeoff:** microSD adds removable-media variability but avoids destroying Android data and allows instant rollback.
- **Risk:** lk2nd or kernel SD initialization may fail.
- **Decision:** microSD is first choice; initramfs-only remains a diagnostic fallback.
- **Rationale:** maximizes reversibility.

### ADR-006 — Keep Arch Linux ARM, systemd, and pacman

- **Options:** Alpine/postmarketOS userland; Debian; Arch Linux ARM.
- **Tradeoff:** Arch packages may need aarch64 fixes, but the repository already builds this stack.
- **Risk:** rolling updates can outrun an old GPU/kernel.
- **Decision:** retain Arch Linux ARM and hold boot-critical updates until tested.
- **Rationale:** required by the target and minimizes userspace redesign.

### ADR-007 — Hyprland first, measured fallbacks available

- **Options:** Hyprland; Sway; Labwc; XFCE/X11.
- **Tradeoff:** Hyprland preserves Omarchy but may cost more resources; Sway/Labwc are leaner but need shell/session adaptation.
- **Risk:** A506 rendering bugs or insufficient performance.
- **Decision:** use the ranked compositor ladder and objective acceptance gates.
- **Rationale:** preserve Omarchy where viable without turning preference into an unsupported claim.

### ADR-008 — Freedreno is the native GPU path

- **Options:** Freedreno; software rendering; vendor Android userspace driver.
- **Tradeoff:** Freedreno is native and maintainable; software is diagnostic only; vendor blobs would violate the native-mainline direction and create ABI problems.
- **Risk:** Mesa regression on A506.
- **Decision:** use DRM/MSM + Mesa Freedreno; keep llvmpipe only for diagnosis.
- **Rationale:** only sustainable native Linux graphics architecture for this target.

### ADR-009 — Hardware variants are selected before Linux driver probe

- **Options:** enable every possible touch/panel; ship per-variant images; bootloader/DT fixup selection.
- **Tradeoff:** fixup selection needs identification support but avoids conflicting probes and image proliferation.
- **Risk:** lk2nd may not identify Atmel on current code.
- **Decision:** improve lk2nd/DT selection where necessary; fail closed for unknown variants.
- **Rationale:** probing shared regulators and GPIOs blindly is unsafe and hard to debug.

### ADR-010 — Firmware is extracted locally unless redistribution is proven

- **Options:** commit blobs; download third-party blobs; owner-local extraction.
- **Tradeoff:** local extraction adds setup work but respects licensing and avoids publishing device data.
- **Risk:** firmware version differences.
- **Decision:** strict owner-local extraction by default, pinned provenance and hashes.
- **Rationale:** aligns with project safety and publication rules.

### ADR-011 — Device-specific policy lives in `omamobile-device-markw`

- **Options:** modify shared shell/scripts with model checks; one device package.
- **Tradeoff:** package boundaries require interfaces for capabilities and setup but remain maintainable.
- **Risk:** duplicated small setup logic.
- **Decision:** put module, udev, systemd, audio, firmware, and capability policy in the device package.
- **Rationale:** keeps generic Omarchy Mobile code generic.

### ADR-012 — Persistent installation and kernel updates are separate later milestones

- **Options:** implement installer immediately; manual documented install; temporary-only until stable.
- **Tradeoff:** delayed installation slows daily use but avoids coupling first-light debugging to irreversible writes.
- **Risk:** temporary workflow is less convenient.
- **Decision:** temporary-only through M5; design permanent install only after recovery and safety-policy approval.
- **Rationale:** `markw` lacks the slot-A escape hatch used by the current project.

### ADR-013 — Prioritize handheld fundamentals over cellular/camera/fingerprint

- **Options:** broad parallel bring-up; foundation-first sequence.
- **Tradeoff:** feature count grows slower, but failures remain attributable and the phone stays recoverable.
- **Risk:** cellular may reveal late architectural dependencies.
- **Decision:** display, touch, storage, USB, GPU, UI, Wi-Fi, power, and audio first.
- **Rationale:** these establish a usable native Linux handheld without taking modem or secure-storage risks.

---

## 21. Milestones and gated runbooks

All result updates go to [`../../PROGRESS.md`](../../PROGRESS.md). Hardware results also receive a sanitized entry in a future `device/markw/NOTES.md`.

### M0 — Plan and evidence freeze

**Deliverables**

- reviewed engineering plan;
- pinned source table;
- explicit list of unknowns;
- no implementation files beyond documentation.

**Pass**

- every “works” claim is either removed or tied to hardware evidence;
- source links and commits are recorded;
- repository status contains no identifiers or blobs.

**Stop**

- sources conflict on product identity or partition architecture.

**Rollback**

- documentation-only revert.

**Risk:** low.

### M1 — Offline boot artifact spike

**Deliverables**

- reproducible lk2nd build or verified upstream artifact provenance;
- kernel Image, `qcom/msm8953-xiaomi-markw.dtb`, modules, and diagnostic initramfs;
- transient boot payload and/or extlinux directory;
- size report proving compliance with lk2nd limits;
- no phone write code.

**Offline checks**

- kernel `W=1`, DT validation, config audit;
- boot image unpack/round-trip inspection;
- DT compatible, panel, touch, reserved-memory, and firmware path checks;
- module release matches rootfs manifest.

**Pass**

- a second clean build produces the same meaningful contents and all artifacts have checksums.

**Stop**

- payload exceeds boot memory/partition constraints or depends on an undocumented packing assumption.

**Rollback**

- discard artifacts; no device state changed.

**Risk:** low.

### M2 — Private hardware inventory

**Gate:** owner present; read-only operations only; no reboot without fresh approval.

**Actions**

- verify product, unlock state, partition map, and recovery path;
- create private backups/checksums permitted by policy;
- identify panel/touch variant from trusted read-only evidence;
- prepare and verify a disposable microSD.

**Expect**

- product is `markw`; partition map matches the planned non-A/B model; recovery is reachable.

**Pass**

- backup manifest checks clean and exact restore inputs are available off-device.

**Stop**

- unexpected product, storage layout, failing eMMC, missing recovery, weak battery, or no backup destination.

**Rollback**

- none needed for reads; return to stock without changing storage.

**Risk:** low to medium because the phone is involved.

### M3 — Temporary lk2nd and initramfs first light

**Gate:** ask before the temporary boot and before every reboot. Arm a host log capture and ensure the owner knows the hard-reset/recovery sequence.

**Actions**

1. temporarily load the pinned lk2nd artifact into RAM;
2. verify lk2nd identifies `markw`, panel, and touch variant;
3. temporarily load the diagnostic Linux payload;
4. collect serial/USB/pstore evidence;
5. keep internal eMMC read-only.

No executable hardware command is prescribed here until M2 resolves the exact bootloader behavior.

**Expect**

- kernel starts, pstore is configured, microSD appears, USB diagnostic access becomes available.

**Pass**

- shell access and boot log are obtained with no internal write and no kernel oops.

**Stop**

- identity mismatch, panel mismatch, reserved-memory warning, storage error, repeated remoteproc crash, loss of recovery, or any unexpected internal write.

**Rollback**

- force restart into the stock bootloader; remove microSD if necessary.

**Risk:** medium.

### M4 — Display, touch, and USB

**Gate:** announce every display/backlight/DPMS change.

**Actions**

- enable one panel path;
- test KMS and conservative backlight;
- enable only the identified touch node;
- validate keys and USB reconnect.

**Pass**

- stable native display for 30 minutes, correct touch mapping, and recoverable USB/SSH.

**Stop**

- panel artifacts, overheating, repeated DRM reset, phantom touch, eMMC error, or USB loss without dead-man recovery.

**Rollback**

- boot the prior diagnostic payload with panel/touch drivers disabled.

**Risk:** medium to high.

### M5 — GPU and native Wayland

**Actions**

- install locally extracted A506 firmware;
- verify Freedreno under a minimal compositor;
- test Sway/Labwc baseline;
- test minimal Hyprland;
- start full Omarchy only after the previous tests pass.

**Pass**

- renderer is Freedreno/A506, no GPU recovery, shell remains responsive, and memory/temperature stay within recorded thresholds.

**Stop**

- llvmpipe mistaken for acceleration, display corruption, kernel GPU fault, compositor restart loop, or thermal trend without stabilization.

**Rollback**

- disable GPU module/firmware and return to software-rendered diagnostic session.

**Risk:** medium.

### M6 — Wi-Fi, Bluetooth, sensors, and battery observation

**Actions**

- one subsystem per boot;
- WCNSS/Wi-Fi first, then Bluetooth;
- sensors and autorotation;
- read-only battery/charger state observations.

**Pass**

- repeated radio cycles, stable USB, plausible sensors, and plausible battery values.

**Stop**

- remoteproc crash loop, network address instability, eMMC errors, incorrect battery temperature/voltage, or charging-state oscillation.

**Rollback**

- blacklist the newly enabled module/service and return to the previous image.

**Risk:** medium; charger work is high.

### M7 — Audio

**Gate:** announce speaker/haptic effects; keep speaker muted until headphone and route tests pass.

**Actions**

- validate ALSA card and UCM;
- headphones and microphones;
- speaker amp at conservative gain for a short attended tone.

**Pass**

- clean route changes, mute works, no pop/DC symptom, and no thermal issue.

**Stop**

- unknown route, uncontrolled gain, hot speaker/amp, codec error, or inability to mute immediately.

**Rollback**

- stop audio services, blacklist amp module, boot prior image.

**Risk:** high for speaker, medium otherwise.

### M8 — Suspend and power

**Prerequisites:** storage, USB recovery, radios, wake keys, battery, and thermal readings all stable.

**Pass**

- 25 attended suspend/resume cycles with filesystem and radio checks, then measured idle drain.

**Stop**

- failed wake, eMMC error, charger anomaly, unbounded drain, or inaccessible pstore.

**Rollback**

- disable suspend targets and expose “suspend unavailable” honestly in the UI.

**Risk:** high.

### M9 — Persistent-install design review

**Prerequisites**

- M3–M8 evidence;
- approved amendment to non-A/B safety policy;
- successful restore rehearsal;
- no open critical risk.

**Deliverables**

- exact writable partition allowlist;
- installer threat model and negative tests;
- original boot restore path;
- kernel-update transaction and rollback design.

No persistent write occurs in this milestone.

### M10 — Release candidate

- package, rootfs, installer, and recovery docs complete;
- clean-device installation rehearsal approved and performed by the human;
- full test matrix passes;
- signed artifacts and manifests;
- documentation states unsupported features without euphemism.

---

## 22. Verification, risks, recovery, and completion summary

### 22.1 Test matrix

| Layer | Offline test | Hardware test | Pass condition |
| --- | --- | --- | --- |
| Descriptor | parser positive/negative tests | none | unknown backend/field fails closed; Pixel descriptors unchanged |
| lk2nd | pinned source, artifact checksum, size | temporary identification | correct board/panel/touch reported |
| Kernel | build, `W=1`, config audit | 20 boot cycles by RC | no panic/oops/new warning regression |
| DT | `dtbs_check`, final DT inspection | driver bindings | exactly one panel and touch variant enabled |
| Initramfs | shell tests with fake sysfs/block map | root mount and recovery | internal storage read-only in transient mode |
| Rootfs | `tests/rootfs-smoke`, manifest audit | systemd reaches target | matching modules, no failed critical unit |
| USB | config/unit tests | enumerate/reconnect cycles | SSH returns; no charger conflict |
| Display | mode and config inspection | 30-minute KMS/DPMS test | no underrun/reset/artifact |
| Touch | event parser tests | edge/grid/multitouch/rotation | correct coordinates and contacts |
| GPU | package contents, driver list | renderer, stress, logs | Freedreno A506; no llvmpipe or recovery |
| Hyprland | config parse/package tests | interaction and DPMS | stable and responsive under acceptance workload |
| Fallback compositor | package/session test | Sway then Labwc | at least one usable fallback |
| Shell | existing package tests plus capability tests | portrait usability | no inaccessible essential control |
| Keyboard | config tests | GTK/Qt/Chromium/terminal | reliable show/hide and typing |
| Wi-Fi | module/firmware dependency test | connect/cycle/throughput | stable association and reconnect |
| Bluetooth | unit and BlueZ config | scan/pair/reconnect | adapter survives cycles |
| Battery | parser/UI tests | compare values over time | plausible and monotonic where expected |
| Charging | no write path in early builds | attended temperature/current observations | no unsafe reading or oscillation |
| Sensors | mount-matrix test | axes/rotation | output and touch rotate together |
| Audio | UCM syntax and route tests | headphone/mic/speaker stages | mute and conservative gain proven |
| Suspend | unit dependency review | 25 cycles | every cycle restores storage, USB, display, input, radios |
| Recovery | artifact/backup checksum | bootloader and restore rehearsal | stock/recovery path succeeds |
| Privacy | diff regex and manual audit | captures remain private | no identifiers/blobs in git |

### 22.2 Performance test workload

Use the same workload for compositor comparisons:

- boot to unlocked home screen;
- open terminal, settings, file chooser, browser, and on-screen keyboard;
- switch full-screen workspaces repeatedly;
- play local 720p video only after decode path is known;
- run for 30 minutes while sampling frame time, RSS, CPU frequency, temperature, and kernel logs.

Record numbers. “Feels smooth” is supplementary, not the only criterion.

### 22.3 Risk register

| ID | Risk | Likelihood | Impact | Mitigation | Exit evidence |
| --- | --- | --- | --- | --- | --- |
| R1 | no safe non-A/B rollback after permanent boot write | high until designed | critical | temporary boot only; policy amendment and restore rehearsal required | successful restore rehearsal |
| R2 | wrong panel/touch variant causes blank screen or bus conflict | medium | high | lk2nd/DT selection; one variant enabled | tested variant matrix |
| R3 | current tools accidentally apply Pixel A/B assumptions | high without abstraction | critical | separate backend; negative tests; current installer rejects markw | CI proves no unsuffixed write path |
| R4 | kernel fork diverges or regresses | medium | high | pin tag, track upstream delta, milestone rebases | reproducible tested kernel record |
| R5 | A506 firmware licensing/provenance | medium | high | local extraction, no blobs in git | provenance manifest and license review |
| R6 | Hyprland is unstable or too heavy on A506 | medium | medium/high | compositor ladder, no effects, objective gate | workload results and fallback |
| R7 | charger/battery data is wrong | medium | critical | observation first, conservative attended testing | cross-checked sane values |
| R8 | speaker amp route/gain damages hardware | medium | critical | muted default, headphones first, short low-level tone | controlled mute/gain evidence |
| R9 | USB disappears during bring-up | medium | high | logs first, dead-man where possible, recovery keys | reconnect cycles and recovery proof |
| R10 | microSD boot is unsupported or unreliable | medium | medium | fastboot-loaded kernel fallback; quality card; fs checks | repeated clean root boots |
| R11 | rootfs rolling update outruns kernel/userspace ABI | medium | high | hold boot-critical packages, staged repository | update/rollback test |
| R12 | WCNSS remoteproc or radio firmware crashes | medium | medium/high | one radio at a time, module blacklist rollback | repeated cycle results |
| R13 | suspend corrupts storage or loses wake | medium | critical | suspend last, attended cycles, pstore | 25-cycle gate |
| R14 | proprietary or identifying data reaches git | low with process | critical | private capture directory, diff scan, review | clean privacy audit |
| R15 | implementation scope expands to modem/camera too early | medium | medium | milestone boundaries and separate plans | M5 accepted before deferred work |

### 22.4 Top five risks

1. **Persistent recovery on a non-A/B device.** The existing slot-B safety model does not transfer to `markw`.
2. **Boot-tool mismatch.** Omarchy Mobile currently creates Android-v4 Pixel images, while `markw` needs an lk2nd-compatible legacy/extlinux payload.
3. **Panel and touchscreen variants.** A wrong fixup can yield a blank display or conflicting hardware probes.
4. **Adreno 506 compositor stability.** Freedreno is credible, but current Hyprland/GTK behavior must be measured on this old GPU.
5. **Power/audio safety.** Charger telemetry and speaker amplification require conservative, attended tests.

### 22.5 Stop conditions applying to every hardware milestone

Stop immediately if any of these occurs:

- product or partition identity differs from the plan;
- backup checks do not match;
- kernel oops, panic, remoteproc crash loop, or repeated watchdog reset;
- eMMC timeout, I/O error, or filesystem error;
- battery voltage/temperature is implausible or rises unexpectedly;
- the device becomes unusually hot;
- display shows persistent electrical/artifact symptoms;
- USB is lost and the armed recovery path does not behave as expected;
- any command would write a partition not explicitly approved for that step;
- the result cannot distinguish the one change under test.

Do not continue by guessing. Return to the last known-good image and update the plan.

### 22.6 Definition of done

The engineering port is complete only when:

- source, build, install, recovery, and owner setup are documented;
- supported hardware variants are named and tested;
- unsupported features are explicit;
- the rootfs is native Arch Linux ARM with systemd and `pacman`;
- Omarchy runs without Android userspace;
- a compositor decision is backed by measurements;
- proprietary firmware handling is reproducible and lawful;
- all write paths are allowlisted and covered by negative tests;
- recovery has been performed, not merely described;
- `tools/pr-check`, package tests, rootfs smoke tests, kernel checks, and the hardware matrix pass;
- public diffs contain no identifiers or vendor blobs.

### 22.7 Requested final summary

1. **Feasibility:** feasible enough to begin offline engineering; daily-driver readiness remains unproven until hardware tests cover power, radios, audio, and suspend.
2. **Five largest risks:** non-A/B recovery, boot-image/tooling mismatch, panel/touch variants, Adreno 506 compositor stability, and charging/speaker safety.
3. **Kernel source:** begin with `msm8953-mainline/linux` tag `v7.1.3-r0` at commit `7213855948c70fd165356526f1de1c3b6bf4d554`, while tracking its upstream delta.
4. **Boot strategy:** temporary lk2nd in RAM, then a transient Linux payload with a microSD root; permanent lk2nd is deferred and currently blocked by safety policy.
5. **Compositor:** Hyprland first with effects disabled and measured acceptance gates; Sway, then Labwc, are the native Wayland fallbacks.
6. **First milestone:** reproducibly build and inspect lk2nd, kernel, DTB, modules, diagnostic initramfs, and a no-write transient boot artifact entirely offline.
7. **Complexity:** medium-high overall; kernel board support exists, but boot/recovery abstraction and safe hardware integration are substantial work.
