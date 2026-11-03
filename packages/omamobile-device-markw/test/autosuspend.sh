#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-autosuspend --check against a fake root and stand-in commands:
# what it decides for each screen and stay-awake state. Never suspends.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

r=$t/root
mkdir -p "$r/usr/share/omamobile" "$r/run/user/1000/hypr/sig1" "$r/sys/class/net/usb0" \
         "$r/sys/bus/usb/devices" "$r/proc/asound/card0/pcm0p/sub0" "$r/home/u/.local/state/omarchy/indicators" "$t/bin"
echo 'AUTO_SUSPEND_DELAY=10' >"$r/usr/share/omamobile/device.conf"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$r/run/user/1000/hypr/sig1/.socket.sock"
echo 0 >"$r/sys/class/net/usb0/carrier"
echo 'closed' >"$r/proc/asound/card0/pcm0p/sub0/status"

cat >"$t/bin/runuser" <<'EOF'
#!/bin/bash
while [[ $1 != -- ]]; do shift; done; shift; exec "$@"
EOF
cat >"$t/bin/timeout" <<'EOF'
#!/bin/bash
shift; exec "$@"
EOF
cat >"$t/bin/hyprctl" <<'EOF'
#!/bin/bash
[[ $HYPRLAND_INSTANCE_SIGNATURE == sig1 && $XDG_RUNTIME_DIR == /run/user/* ]] || exit 1
printf 'Monitor DSI-1 (ID 0):\n\tdpmsStatus: %s\n' "$(cat "$FAKE_DPMS")"
EOF
cat >"$t/bin/id" <<'EOF'
#!/bin/bash
echo u
EOF
cat >"$t/bin/systemd-inhibit" <<'EOF'
#!/bin/bash
cat "$FAKE_INHIBIT" 2>/dev/null
EOF
cat >"$t/bin/ss" <<'EOF'
#!/bin/bash
cat "$FAKE_SS" 2>/dev/null
EOF
cat >"$t/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl must not run in --check" >&2; exit 99
EOF
chmod +x "$t"/bin/*
export PATH="$t/bin:$PATH" OMAMOBILE_AUTOSUSPEND_ROOT=$r FAKE_DPMS=$t/dpms FAKE_INHIBIT=$t/inhibit FAKE_SS=$t/ss

check() { bash vendor/omamobile-autosuspend --check | tail -n1; }
expect() { local got; got=$(check); [[ $got == "$1" ]] || fail "$2: got '$got', want '$1'"; pass "$2"; }

bash -n vendor/omamobile-autosuspend || fail "the script parses"
[[ $(bash vendor/omamobile-autosuspend --check | head -n1) == "delay: 10s" ]] || fail "reads AUTO_SUSPEND_DELAY"
pass "reads AUTO_SUSPEND_DELAY"

echo 1 >"$t/dpms";  expect "screen on" "a lit screen keeps it awake"
echo 0 >"$t/dpms";  expect "suspend" "screen off and nothing else: suspend"
echo 1 >"$r/sys/class/net/usb0/carrier"; expect "awake: USB cable in a computer" "a computer on the cable keeps it awake"
echo 0 >"$r/sys/class/net/usb0/carrier"
mkdir "$r/sys/bus/usb/devices/usb1" "$r/sys/bus/usb/devices/1-0:1.0"; expect "suspend" "root hubs and interfaces are not devices"
mkdir "$r/sys/bus/usb/devices/1-1"; expect "awake: USB device plugged in (1-1)" "an OTG device keeps it awake"
rmdir "$r/sys/bus/usb/devices/1-1"
echo 'state: RUNNING' >"$r/proc/asound/card0/pcm0p/sub0/status"; expect "awake: sound playing" "playing sound keeps it awake"
echo 'closed' >"$r/proc/asound/card0/pcm0p/sub0/status"
touch "$r/home/u/.local/state/omarchy/indicators/stay-awake"; expect "awake: Stay awake is on" "Stay awake keeps it awake"
rm "$r/home/u/.local/state/omarchy/indicators/stay-awake"
printf '0 0 192.0.2.17:22 192.0.2.40:51234\n' >"$t/ss"; expect "awake: SSH session open" "an SSH session keeps it awake"
rm "$t/ss"
printf 'mpv  1000 u 123 mpv sleep Playing block\n' >"$t/inhibit"; expect "awake: sleep inhibitor: mpv" "a block sleep inhibitor keeps it awake"
rm "$t/inhibit"
rm "$r/run/user/1000/hypr/sig1/.socket.sock"; expect "screen on" "no Hyprland answering: never suspend"

echo 'AUTO_SUSPEND_DELAY=0' >"$r/usr/share/omamobile/device.conf"
[[ $(bash vendor/omamobile-autosuspend) == "AUTO_SUSPEND_DELAY is 0 or unset: nothing to do" ]] || fail "0 turns it off"
pass "AUTO_SUSPEND_DELAY=0 turns it off"
