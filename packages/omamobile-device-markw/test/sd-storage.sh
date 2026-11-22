#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-markw-sd-storage against a fake sysfs and stand-in commands:
# which partition it mounts, and when it leaves the card alone. Mounts
# nothing for real.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"

# eMMC mmcblk0 (userdata p49, ext4), card mmcblk1 (p1, ext4).
disk() { # NAME TYPE PART FSTYPE
  mkdir -p "$t/sys/class/block/$1/device" "$t/sys/class/block/$1$3"
  echo "$2" >"$t/sys/class/block/$1/device/type"
  echo "DEVNAME=$1$3" >"$t/sys/class/block/$1$3/uevent"
  echo "$1$3 $4" >>"$t/fstypes"
}
: >"$t/fstypes"
disk mmcblk0 MMC p49 ext4
disk mmcblk1 SD p1 ext4

cat >"$t/bin/findmnt" <<'EOF'
#!/bin/bash
if [[ $* == "-n -o SOURCE /" ]]; then echo "/dev/$FAKE_ROOT"; exit 0; fi
[[ -n ${FAKE_MOUNTED:-} ]]
EOF
cat >"$t/bin/blkid" <<'EOF'
#!/bin/bash
awk -v d="${@: -1}" '{ if ("'"$FAKE_DEV"'/" $1 == d) print $2 }' "$FAKE_FSTYPES"
EOF
cat >"$t/bin/e2fsck" <<'EOF'
#!/bin/bash
echo "e2fsck $*" >>"$FAKE_LOG"; exit "${FAKE_FSCK:-0}"
EOF
cat >"$t/bin/mount" <<'EOF'
#!/bin/bash
echo "mount $*" >>"$FAKE_LOG"
EOF
cat >"$t/bin/timeout" <<'EOF'
#!/bin/bash
shift; exec "$@"
EOF
cat >"$t/bin/getent" <<'EOF'
#!/bin/bash
[[ $* == "passwd 1000" ]] && echo "owner:x:1000:1000::/home/owner:/bin/bash"
EOF
cat >"$t/bin/chown" <<'EOF'
#!/bin/bash
echo "chown $*" >>"$FAKE_LOG"
EOF
chmod +x "$t/bin/"*

run() { # ROOT [env...]: run the script, output to $t/out
  rm -rf "$t/mnt"; : >"$t/log"
  env PATH="$t/bin:$PATH" OMAMOBILE_SYS="$t/sys" OMAMOBILE_DEV=/dev OMAMOBILE_SD_MOUNT="$t/mnt/sd" \
    FAKE_DEV=/dev FAKE_FSTYPES="$t/fstypes" FAKE_LOG="$t/log" FAKE_ROOT="$1" "${@:2}" \
    bash vendor/omamobile-markw-sd-storage >"$t/out" 2>&1 || fail "the script exits 0 (root $1)"
}

run mmcblk1p1
grep -q 'mmcblk1p1 is the root' "$t/out" || fail "a microSD-root boot is recognised"
[[ ! -s $t/log ]] || fail "a microSD-root boot neither checks nor mounts the card"
pass "microSD root: the card is left alone"

run mmcblk0p49
grep -qx 'e2fsck -p /dev/mmcblk1p1' "$t/log" || fail "the card is checked before mounting"
grep -qx "mount -t ext4 -o noatime,nosuid,nodev /dev/mmcblk1p1 $t/mnt/sd" "$t/log" || fail "the card mounts read-write at /mnt/sd"
[[ -d $t/mnt/sd/data ]] && grep -qx "chown 1000:1000 $t/mnt/sd/data" "$t/log" || fail "/mnt/sd/data is made for uid 1000"
! grep -q mmcblk0 "$t/log" || fail "no eMMC partition is touched"
pass "eMMC root: the card's ext4 partition mounts at /mnt/sd, with a data folder for the owner"

run mmcblk0p49 FAKE_FSCK=4
grep -q 'mount -t ext4 -o ro,noatime' "$t/log" || fail "a card e2fsck can't fix mounts read-only"
[[ ! -e $t/mnt/sd/data ]] || fail "nothing is written to a card with errors"
pass "a card with errors e2fsck can't fix: read-only, nothing written"

run mmcblk0p49 FAKE_MOUNTED=1
! grep -q mount "$t/log" || fail "an existing mount is left alone"
pass "an existing /mnt/sd mount is left alone"

echo "mmcblk1p1 vfat" >"$t/fstypes.vfat"; grep -v mmcblk1p1 "$t/fstypes" >>"$t/fstypes.vfat"; mv "$t/fstypes.vfat" "$t/fstypes"
run mmcblk0p49
grep -q 'no ext4 partition on a microSD card' "$t/out" && [[ ! -s $t/log ]] || fail "a card without ext4 is not mounted"
pass "no ext4 card: nothing mounted, the eMMC never picked"
