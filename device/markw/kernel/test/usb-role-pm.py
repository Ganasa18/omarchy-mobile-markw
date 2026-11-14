#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise real DWC3 role ingress and worker prefix with hardware stubs.

Usage: python3 usb-role-pm.py /path/to/kernel/source [--cc cc]
This host test cannot prove suspend/resume works on a phone.
"""

import argparse
import pathlib
import re
import subprocess
import tempfile


def function(source, name):
    match = re.search(r"^(?:static )?(?:int|void) " + name + r"\(", source, re.M)
    if not match:
        raise ValueError(f"missing function: {name}")
    start = source.index("{", match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=pathlib.Path)
parser.add_argument("--cc", default="cc")
args = parser.parse_args()
core = (args.source / "drivers/usb/dwc3/core.c").read_text()
drd = (args.source / "drivers/usb/dwc3/drd.c").read_text()
worker = function(core, "__dwc3_set_mode")
# Exercise the actual prefix, before mode-specific PHY/xHCI/gadget handling.
worker = worker[:worker.index("\tif (dwc->current_dr_role ==")]
worker += "\t(void)desired_dr_role;\n\tmutex_unlock(&dwc->mutex);\n}"
helpers = []
if "static void __dwc3_queue_mode(" in core:
    helpers.append(function(core, "__dwc3_queue_mode"))
helpers.append(function(core, "dwc3_set_mode"))
if re.search(r"^void dwc3_set_role\(", core, re.M):
    helpers.append(function(core, "dwc3_set_role"))

stubs = r"""
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef unsigned int u32;
enum usb_role { USB_ROLE_NONE, USB_ROLE_HOST, USB_ROLE_DEVICE };
enum { USB_DR_MODE_OTG = 3, USB_DR_MODE_HOST = 1 };
enum { DWC3_GCTL_PRTCAP_HOST = 1, DWC3_GCTL_PRTCAP_DEVICE = 2 };
struct dwc3;
struct work_struct { struct dwc3 *owner; };
struct usb_role_switch { struct dwc3 *owner; };
struct notifier_block { int unused; };
#define NOTIFY_DONE 0
#define container_of(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
struct dwc3 {
    int mutex, lock, dev, dr_mode, role_switch_default_mode;
    u32 desired_dr_role;
    enum usb_role requested_role;
    bool requested_role_pending;
    struct work_struct drd_work;
    struct notifier_block edev_nb;
};
static int frozen, queued, notifications;
static enum usb_role last_role;
static void *system_freezable_wq = (void *)1;
#define spin_lock_irqsave(lock, flags) ((void)(flags))
#define spin_unlock_irqrestore(lock, flags) ((void)(flags))
#define mutex_lock(lock) ((void)0)
#define mutex_unlock(lock) ((void)0)
#define pm_runtime_get_sync(dev) ((void)0)
#define work_to_dwc(work) ((work)->owner)
#define usb_role_switch_get_drvdata(sw) ((sw)->owner)
static void dwc3_pre_set_role(struct dwc3 *dwc, enum usb_role role)
{
    if (frozen) {
        fputs("FAIL: glue notifier ran while the role worker was frozen\n", stderr);
        assert(!frozen);
    }
    notifications++;
    last_role = role;
}
static void queue_work(void *queue, struct work_struct *work)
{
    assert(queue == system_freezable_wq);
    queued = 1;
}
"""
checks = r"""
static void drain(struct dwc3 *dwc)
{
    assert(!frozen && queued);
    queued = 0;
    __dwc3_set_mode(&dwc->drd_work);
}
int main(void)
{
    struct dwc3 dwc = { .dr_mode = USB_DR_MODE_OTG };
    struct usb_role_switch sw = { .owner = &dwc };
    dwc.drd_work.owner = &dwc;

    /* A disconnect must not call the glue while system sleep freezes work. */
    frozen = 1;
    assert(dwc3_usb_role_switch_set(&sw, USB_ROLE_NONE) == 0);
    assert(notifications == 0 && queued);
    /* Several changes during sleep coalesce to the final role, even NONE. */
    dwc3_usb_role_switch_set(&sw, USB_ROLE_HOST);
    dwc3_usb_role_switch_set(&sw, USB_ROLE_DEVICE);
    dwc3_usb_role_switch_set(&sw, USB_ROLE_NONE);
    assert(notifications == 0);
    frozen = 0;
    drain(&dwc);
    assert(notifications == 1 && last_role == USB_ROLE_NONE);
    assert(dwc.desired_dr_role == DWC3_GCTL_PRTCAP_DEVICE);

    /* Reconnect still notifies when the controller mode stays peripheral. */
    dwc3_usb_role_switch_set(&sw, USB_ROLE_DEVICE);
    assert(notifications == 1);
    drain(&dwc);
    assert(notifications == 2 && last_role == USB_ROLE_DEVICE);

    /* An internal mode-only request must not invent a NONE notification. */
    dwc3_set_mode(&dwc, DWC3_GCTL_PRTCAP_HOST);
    drain(&dwc);
    assert(notifications == 2);

    /* Nor may it erase a pending role request from a connector. */
    dwc3_usb_role_switch_set(&sw, USB_ROLE_HOST);
    dwc3_set_mode(&dwc, DWC3_GCTL_PRTCAP_HOST);
    drain(&dwc);
    assert(notifications == 3 && last_role == USB_ROLE_HOST);

    /* Extcon ingress must be deferred too, not only usb_role_switch. */
    frozen = 1;
    assert(dwc3_drd_notifier(&dwc.edev_nb, 1, NULL) == NOTIFY_DONE);
    assert(notifications == 3 && queued);
    dwc3_drd_notifier(&dwc.edev_nb, 0, NULL);
    frozen = 0;
    drain(&dwc);
    assert(notifications == 4 && last_role == USB_ROLE_DEVICE);
    puts("PASS: frozen role/extcon ingress, coalescing, NONE/DEVICE, mode-only, pending role");
}
"""
with tempfile.TemporaryDirectory(prefix="dwc3-role-pm-") as tmp:
    tmp = pathlib.Path(tmp)
    test = tmp / "test.c"
    binary = tmp / "test"
    test.write_text("\n\n".join([stubs, worker, *helpers,
                                function(drd, "dwc3_usb_role_switch_set"),
                                function(drd, "dwc3_drd_notifier"), checks]))
    subprocess.run([args.cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-variable", "-Wno-unused-parameter",
                    str(test), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
