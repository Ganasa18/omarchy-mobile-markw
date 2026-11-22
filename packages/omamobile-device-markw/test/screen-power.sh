#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-markw-screen-power against a fake sysfs: nothing while the
# screen is on; once it has been off SCREEN_OFF_DELAY seconds, the listed
# CPUs go offline (never cpu0) and the clock is capped; the moment it lights,
# every CPU comes back and the cap is what it was; stopping the service
# restores them too.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'not ok - %s\n' "$1" >&2; cat "$t/out" >&2 2>/dev/null || true; exit 1; }
t=$(mktemp -d)
pid=""
trap '[[ -n $pid ]] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT

sys=$t/sys
mkdir -p "$sys/class/backlight/panel" "$sys/devices/system/cpu/cpufreq/policy0"
echo 0 >"$sys/class/backlight/panel/bl_power"
echo 2016000 >"$sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
for n in 0 1 2 3 4 5 6 7; do
  mkdir -p "$sys/devices/system/cpu/cpu$n"
  ((n == 0)) || echo 1 >"$sys/devices/system/cpu/cpu$n/online"
done
cat >"$t/device.conf" <<'EOF'
SCREEN_OFF_DELAY=2
SCREEN_OFF_CPUS=0-1,4-7
SCREEN_OFF_MAX_KHZ=1036800
EOF
run() { OMAMOBILE_SYSFS=$sys OMAMOBILE_DEVICE_CONF=$t/device.conf bash "$here/vendor/omamobile-markw-screen-power" "$@"; }
online() { cat "$sys/devices/system/cpu/cpu$1/online"; }
cap() { cat "$sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"; }
wait_for() { # WHAT CONDITION (evaluated on every try)
  local what=$2 i
  for i in $(seq 50); do eval "$1" && return 0; sleep 0.1; done
  fail "$what"
}

out=$(run --check)
grep -cx 'screen: on' <<<"$out" >/dev/null || fail "--check reads the panel as on"
grep -c 'offline cpu 1 4 5 6 7, cap 1036800' <<<"$out" >/dev/null || fail "--check lists the CPUs (never cpu0) and the cap"
echo "ok - screen power: --check"

# The script itself in the background (not through run(), whose subshell
# would take the signal instead), so a kill reaches its trap.
OMAMOBILE_SYSFS=$sys OMAMOBILE_DEVICE_CONF=$t/device.conf bash "$here/vendor/omamobile-markw-screen-power" >"$t/out" 2>&1 &
pid=$!
sleep 1.2
[[ $(online 4) == 1 && $(cap) == 2016000 ]] || fail "nothing changes while the screen is on"
echo 4 >"$sys/class/backlight/panel/bl_power"
sleep 1.2
[[ $(online 4) == 1 ]] || fail "nothing changes before SCREEN_OFF_DELAY"
wait_for '[[ $(online 7) == 0 ]]' "the CPUs go offline once the screen has been off a while"
[[ $(online 1) == 0 && $(online 3) == 1 && $(cap) == 1036800 ]] || fail "the listed CPUs go and the clock is capped"
echo 0 >"$sys/class/backlight/panel/bl_power"
wait_for '[[ $(online 7) == 1 ]]' "the CPUs come back when the screen lights"
[[ $(online 1) == 1 && $(cap) == 2016000 ]] || fail "every CPU and the old cap come back"
echo "ok - screen power: off a while limits, on restores"

echo 4 >"$sys/class/backlight/panel/bl_power"
wait_for '[[ $(online 5) == 0 ]]' "limited again"
kill "$pid"; wait "$pid" 2>/dev/null || true; pid=""
[[ $(online 5) == 1 && $(cap) == 2016000 ]] || fail "stopping the service restores every CPU and the cap"
echo "ok - screen power: stopping restores"

printf 'SCREEN_OFF_CPUS=\nSCREEN_OFF_MAX_KHZ=0\n' >"$t/device.conf"
run | grep -c 'nothing to do' >/dev/null || fail "unset settings do nothing"
printf 'SCREEN_OFF_CPUS=4-7;reboot\nSCREEN_OFF_MAX_KHZ=fast\n' >"$t/device.conf"
run | grep -c 'nothing to do' >/dev/null || fail "malformed settings are ignored"
echo "ok - screen power: settings are checked"
