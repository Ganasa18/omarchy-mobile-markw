<!-- SPDX-License-Identifier: MIT -->
# modemmanager (Omarchy Mobile build)

This is Arch Linux's ModemManager 1.24.2-2 (`modemmanager` and
`libmm-glib`), rebuilt with one upstream fix. On a suspend, ModemManager
1.24.2 counts the active bearers and asserts that the count is within
`MaxActiveBearers`. An IPA modem (Qualcomm SoCs such as msm8953) has only
multiplexed bearers, so `MaxActiveBearers` is 0 (`MaxActiveMultiplexedBearers`
is 254). One connected bearer then fails the assertion and ModemManager
aborts:

```
mm-iface-modem.c:6779:mm_iface_modem_count_bearers: assertion failed: (max >= ctx.count)
```

On markw this happened on every auto-suspend with mobile data up. The dead
ModemManager left `qmapmux0.0` behind, and the phone lost mobile data until
the next resume. See `device/markw/BRINGUP-MODEM.md`.

| File | What it is |
| --- | --- |
| `PKGBUILD` | Arch's `PKGBUILD` at `92daa21` (archlinux/packaging/packages/modemmanager), changes in its header |
| `0001-base-manager-fix-cleanup-of-multiplexed-bearers.patch` | Upstream `0edcb916ad2b` by Daniele Palmas, unchanged (`git format-patch`); in 1.25.x, not on `mm-1-24` |

## What differs from Arch's `modemmanager` 1.24.2-2

- The patch above.
- `pkgrel=2.1`, `arch=(aarch64)`.
- No gtk-doc and no `modemmanager-docs` package.
- Arch's Fibocom cherry-pick stays; its gtk-doc build fix goes with gtk-doc.
- The tag is checked by Arch's b2sum of the source tree, not by its PGP
  signature, so a build on the phone needs no imported keys.
- `meson compile` takes its job count from `MAKEFLAGS` (default 4).
- Same package names, dependencies, sonames and split as Arch's, so it
  replaces Arch's build in place.

## Drop it

When Arch (and Arch Linux ARM) ship ModemManager 1.26 or later, which
contains the fix.

## Status

Built for aarch64 on the laptop (tools/build-packages, 16 min under qemu-user): the same 156 + 83 files and dependencies as Arch Linux ARM's 1.24.2-2. Not yet installed on a phone.
