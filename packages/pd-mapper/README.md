<!-- SPDX-License-Identifier: 0BSD -->
# pd-mapper

[pd-mapper](https://github.com/linux-msm/pd-mapper) answers a Qualcomm
modem's protection-domain lookups over QRTR. The Redmi 4 Prime's kernel
doesn't set the in-kernel `QCOM_PD_MAPPER`, so its mobile data needs this
one (`device/markw/BRINGUP-MODEM.md`). Arch Linux ARM doesn't package it;
this is the upstream release, compiled with `cc`. `pd-mapper.service` is
installed and not enabled.
