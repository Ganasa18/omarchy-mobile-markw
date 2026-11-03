<!-- SPDX-License-Identifier: 0BSD -->
# tqftpserv

[tqftpserv](https://github.com/linux-msm/tqftpserv) serves the files a
Qualcomm modem asks for over QRTR's TFTP. The Redmi 4 Prime's modem needs it
for mobile data (`device/markw/BRINGUP-MODEM.md`). Arch Linux ARM doesn't
package it; this is the upstream release, compiled with `cc` so the phone
builds it without make or meson. `tqftpserv.service` is installed and not
enabled: the modem bring-up starts it.
