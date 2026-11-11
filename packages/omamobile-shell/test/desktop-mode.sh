#!/bin/bash
# SPDX-License-Identifier: MIT
# Tests for omamobile-desktop-mode against fake hyprctl, gsettings and busctl:
# on writes the Lua file phone.lua loads and reloads, off removes it, reloads
# and puts the on-screen keyboard setting back.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake=$tmp/bin; log=$tmp/log; mkdir -p "$fake" "$tmp/run" "$tmp/home"
: >"$log"; echo true >"$tmp/osk"
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$fake/$1"; chmod +x "$fake/$1"; }
stub hyprctl 'case "$1 $2" in
  "-j monitors") echo "[{\"name\": \"DSI-1\"}]" ;;
  "-j clients") cat '"$tmp"'/clients ;;
  "-j activeworkspace") echo "{\"id\": 1}" ;;
  "-j activewindow") echo "{}" ;;
  *) echo "hyprctl $*" >>'"$log"' ;;
esac'
stub gsettings '[ "$1" = get ] && cat '"$tmp"'/osk; [ "$1" = set ] && echo "$4" >'"$tmp"'/osk; exit 0'
stub busctl 'echo "busctl $*" >>'"$log"
stub notify-send 'exit 0'
stub omamobile-launch 'echo "launch $*" >>'"$log"
# One app filling its own screen, as the phone leaves it.
echo '[{"address": "0xa1", "class": "foot", "workspace": {"id": 2}, "floating": false, "focusHistoryID": 0}]' >"$tmp/clients"
stub omarchy-shell 'echo "shell $*" >>'"$log"

mode() { env -i HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" PATH="$fake:/usr/bin:/bin" bash bin/omamobile-desktop-mode "$@"; }
lua=$tmp/run/omamobile-desktop-mode/desktop.lua

[[ $(mode status) == off ]] || fail "desktop mode starts off"
[[ $(mode status --kv) == desktop=off ]] || fail "status --kv prints desktop=off"
mode on
[[ $(mode status) == on ]] || fail "on turns it on"
grep -cF 'hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 1.5, transform = 3 })' "$lua" >/dev/null \
  || fail "on writes the landscape monitor rule"
grep -cF 'touchdevice = { transform = 3, output = "DSI-1" }' "$lua" >/dev/null || fail "touch turns with the panel"
grep -cF 'size = { 860, 540 }' "$lua" >/dev/null || fail "new windows float at the default size"
grep -cx "hyprctl reload" "$log" >/dev/null || fail "on reloads Hyprland"
[[ $(cat "$tmp/osk") == false ]] || fail "on turns the on-screen keyboard off"
for target in omamobile.bar omamobile.desktop omamobile.home omamobile.launcher; do
  grep -cx "shell $target setDesktopMode on" "$log" >/dev/null || fail "on tells $target"
done
grep -cF 'hl.dsp.window.move({ window = "address:0xa1", workspace = "1", follow = false })' "$log" >/dev/null   || fail "on gathers open windows on the current workspace"
grep -cF 'hl.dsp.window.float({ window = "address:0xa1", action = "toggle" })' "$log" >/dev/null   || fail "on floats the open windows"
grep -cF 'hl.dsp.window.resize({ window = "address:0xa1", x = 860, y = 540 })' "$log" >/dev/null   || fail "on sizes the open windows"
pass "on writes desktop.lua, reloads, folds the on-screen keyboard and floats open windows"

# Two floating windows sharing the desktop's workspace.
echo '[{"address": "0xa1", "class": "foot", "workspace": {"id": 1}, "floating": true, "focusHistoryID": 0},
       {"address": "0xb2", "class": "chromium", "workspace": {"id": 1}, "floating": true, "focusHistoryID": 1}]' >"$tmp/clients"
: >"$log"
mode off
[[ $(mode status) == off ]] || fail "off turns it off"
[[ $(grep -cF 'action = "toggle" })' "$log") == 2 ]] || fail "off tiles the floating windows"
[[ $(grep -cF 'fullscreen_state({ internal = 1, client = 0 })' "$log") == 2 ]] || fail "off fills the screen with each window"
grep -cx "launch own-screen 0xb2" "$log" >/dev/null || fail "off gives a window sharing a workspace its own"
grep -cx "launch own-screen 0xa1" "$log" >/dev/null && fail "the first window keeps its workspace"
[[ ! -e $lua ]] || fail "off removes desktop.lua"
[[ $(grep -cx "hyprctl reload" "$log") == 1 ]] || fail "off reloads Hyprland"
[[ $(cat "$tmp/osk") == true ]] || fail "off puts the on-screen keyboard setting back"
pass "off removes desktop.lua, reloads, restores the on-screen keyboard and tiles windows one per screen"
echo '[]' >"$tmp/clients"

mkdir -p "$tmp/home/.config/omamobile"
printf 'TRANSFORM=1\nSCALE=2;os.exit()\nWIDTH=1000\n' >"$tmp/home/.config/omamobile/desktop-mode.conf"
mode on
grep -cF 'scale = 1.5, transform = 1 })' "$lua" >/dev/null || fail "TRANSFORM is read and a bad SCALE falls back"
grep -cF 'size = { 1000, 540 }' "$lua" >/dev/null || fail "WIDTH is read"
mode off
pass "settings are read as data and checked"

if mode sideways 2>/dev/null; then fail "unknown commands are refused"; fi
pass "unknown commands are refused"
