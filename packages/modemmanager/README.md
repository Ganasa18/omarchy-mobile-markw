<!-- SPDX-License-Identifier: MIT -->
# modemmanager (Omarchy Mobile build)

This is Arch Linux's ModemManager 1.24.2-2 (`modemmanager` and
`libmm-glib`), rebuilt with two upstream fixes and a debug package.

**Abort on suspend (0001).** On a suspend, ModemManager
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

**Segfault on reconnect (0002).** `transaction_complete()` in
`src/mm-netlink.c` removes the netlink transaction from its hash table,
which frees it, and then calls `tr->completion_fn`. When the freed memory
has been reused, that is a jump to garbage. On markw it crashed
ModemManager right after "net link qmapmux0.0 created (mux id 1)" when
data came back 1-5 s after a disconnect, and on a resume with data up,
since the monotonic clock stops in suspend. The core showed pc 0x30 from
the `blr` that reads `tr->completion_fn` (mm-netlink.c:242).

| File | What it is |
| --- | --- |
| `PKGBUILD` | Arch's `PKGBUILD` at `92daa21` (archlinux/packaging/packages/modemmanager), changes in its header |
| `0001-base-manager-fix-cleanup-of-multiplexed-bearers.patch` | Upstream `0edcb916ad2b` by Daniele Palmas, unchanged (`git format-patch`); in 1.25.x, not on `mm-1-24` |
| `0002-netlink-fix-use-after-free-calling-completion_fn-on-transaction-completion.patch` | Upstream `9317cbc4702c` by Dan Williams, unchanged (`git format-patch`); on `main`, in no release yet |

## What differs from Arch's `modemmanager` 1.24.2-2

- The two patches above.
- `options=(debug)`: a `modemmanager-debug` package with the symbols, so
  `coredumpctl` names the frames. `-g` doesn't change the code: the
  `.text` of the 2.1 and 2.2 builds is byte for byte the same.
- `pkgrel=2.3`, `arch=(aarch64)`.
- No gtk-doc and no `modemmanager-docs` package.
- Arch's Fibocom cherry-pick stays; its gtk-doc build fix goes with gtk-doc.
- The tag is checked by Arch's b2sum of the source tree, not by its PGP
  signature, so a build on the phone needs no imported keys.
- `meson compile` takes its job count from `MAKEFLAGS` (default 4).
- Same package names, dependencies, sonames and split as Arch's, so it
  replaces Arch's build in place.

## Drop it

When Arch (and Arch Linux ARM) ship a ModemManager release with both
fixes: 1.26 has 0001; check that it has `9317cbc4702c` too.

## Status

Built for aarch64 on the laptop (tools/build-packages, 16 min under qemu-user): the same 156 + 83 files and dependencies as Arch Linux ARM's 1.24.2-2. Installed on markw 2026-11-18 (7.1.3-msm8953-oma19): `ModemManager (version 1.24.2-2.1)`, data reconnected. A `systemctl suspend` with data up then passed: no abort, same PID across the sleep, resume sync done, vmin reached (device/markw/BRINGUP-SUSPEND.md, CC). Arch's build also aborts on a stop with data up, so a restart or shutdown leaves a core dump without this fix.

The 2.1 build then segfaulted on a resume after a 2 h 41 min sleep with data up (2026-11-18); the 2.2 build's symbols placed that core in `transaction_complete()`, which 0002 fixes. 2.3 (both patches, debug package) is built and not installed yet.
