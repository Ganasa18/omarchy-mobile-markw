#!/bin/sh
# SPDX-License-Identifier: MIT
# tile-action.sh TILE on|off: switch one of the quick-settings tiles that
# tile-state.sh reads. Run as the session user; nothing here needs root
# except what polkit already guards (systemctl for mobile data).
set -u

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omamobile"
tile=${1:-}
want=${2:-}
case $want in on | off) ;; *) echo "usage: tile-action.sh TILE on|off" >&2; exit 2 ;; esac

case $tile in
  airplane)
    # Wi-Fi, Bluetooth and WWAN switches only: NFC keeps its own tile, as on
    # Android. Turning airplane mode off unblocks what was on before it, so a
    # radio the user had switched off stays off.
    restore="$state_dir/airplane-restore"
    if [ "$want" = on ]; then
      mkdir -p "$state_dir"
      rfkill -rn -o TYPE,SOFT | awk '($1 == "wlan" || $1 == "bluetooth" || $1 == "wwan") && $2 == "unblocked" { print $1 }' \
        | sort -u >"$restore"
      for type in wlan bluetooth wwan; do rfkill block "$type" 2>/dev/null; done
    else
      types=$(cat "$restore" 2>/dev/null)
      [ -n "$types" ] || types="wlan bluetooth"
      for type in $types; do rfkill unblock "$type" 2>/dev/null; done
      rm -f "$restore"
    fi
    exit 0
    ;;
  hotspot)
    # NetworkManager makes (or reuses) a connection named "Hotspot" with a
    # generated password; the Wi-Fi client link drops while it is up.
    if [ "$want" = on ]; then
      nmcli radio wifi on
      exec nmcli device wifi hotspot con-name Hotspot
    else
      exec nmcli connection down Hotspot
    fi
    ;;
  battery-saver)
    # Through Omarchy's setter, which remembers the choice for AC or battery.
    if [ "$want" = on ]; then
      exec omarchy-powerprofiles-set autodetect power-saver
    else
      exec omarchy-powerprofiles-set autodetect balanced
    fi
    ;;
  dark-theme)
    # Swap between the user's last light and last dark Omarchy theme. The
    # theme being left is remembered as that mode's choice, so picking a
    # theme in Omarchy's own menu also becomes the tile's next swap target.
    mkdir -p "$state_dir"
    current=$(head -n1 "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
    mode=$(omarchy-theme-color mode 2>/dev/null)
    [ -n "$current" ] && [ -n "$mode" ] && printf '%s\n' "$current" >"$state_dir/theme-$mode"
    if [ "$want" = on ]; then
      target=$(head -n1 "$state_dir/theme-dark" 2>/dev/null)
      [ -n "$target" ] || target=tokyo-night
    else
      target=$(head -n1 "$state_dir/theme-light" 2>/dev/null)
      [ -n "$target" ] || target=catppuccin-latte
    fi
    [ "$target" = "$current" ] && exit 0
    exec omarchy-theme-set "$target"
    ;;
  night-light)
    # Omarchy's toggle flips between its on and off temperatures.
    on=$(omarchy-toggle-nightlight --status 2>/dev/null | grep -c '"enabled":true')
    if { [ "$want" = on ] && [ "$on" = 0 ]; } || { [ "$want" = off ] && [ "$on" != 0 ]; }; then
      exec omarchy-toggle-nightlight
    fi
    exit 0
    ;;
  stay-awake)
    if [ "$want" = on ]; then exec omarchy-toggle-idle stay-awake; else exec omarchy-toggle-idle allow-idle; fi
    ;;
  screen-record)
    # omamobile-screenrecord: Omarchy's gpu-screen-recorder can't drive the
    # phone's Mali (Mesa) GPU; this records with wf-recorder instead.
    if [ "$want" = on ]; then
      exec omamobile-screenrecord start ${3:-}
    else
      exec omamobile-screenrecord stop
    fi
    ;;
  mobile-data)
    command -v omamobile-sit >/dev/null 2>&1 && exec omamobile-sit data "$want"
    # NetworkManager's mobile broadband profile (ModemManager's modem). Its
    # autoconnect follows the tile, so data stays as the user left it after
    # a reboot, as on Android. Without a profile, "on" makes one with no
    # APN: ModemManager takes the network's own (the initial bearer's).
    #
    # ModemManager 1.24.2 on markw (qcom-soc, a multiplexed bearer) crashed
    # when a bearer was connected again within about 10 s of its disconnect
    # (5 s: crashed, 10 s: fine; device/markw/BRINGUP-MODEM.md), so "on"
    # waits until 15 s have passed since "off".
    name=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 == "gsm" { print $1; exit }')
    off_stamp="$state_dir/mobile-data-off"
    if [ "$want" = on ]; then
      off_at=$(cat "$off_stamp" 2>/dev/null)
      now=$(date +%s)
      case $off_at in
        '' | *[!0-9]*) ;;
        *) wait=$((off_at + ${OMAMOBILE_DATA_RECONNECT_DELAY:-15} - now))
           [ "$wait" -gt 0 ] && [ "$wait" -le 15 ] && sleep "$wait" ;;
      esac
      if [ -z "$name" ]; then
        name="Mobile data"
        nmcli connection add type gsm ifname '*' con-name "$name" connection.autoconnect yes >/dev/null || exit 1
      else
        nmcli connection modify "$name" connection.autoconnect yes
      fi
      exec nmcli connection up "$name"
    fi
    [ -n "$name" ] || exit 0
    nmcli connection modify "$name" connection.autoconnect no
    nmcli connection down "$name"
    rc=$?
    mkdir -p "$state_dir" && date +%s >"$off_stamp"
    exit "$rc"
    ;;
  ssh-wifi)
    # omamobile-ssh-wifi opens port 22 on Wi-Fi for 30 minutes (the page
    # behind the tile picks other times); polkit lets the user start it.
    if [ "$want" = on ]; then exec omamobile-ssh-wifi on; else exec omamobile-ssh-wifi off; fi
    ;;
  desktop)
    # omamobile-desktop-mode turns the screen landscape for a keyboard and
    # mouse; off reloads Hyprland's configuration (the phone's rules).
    exec omamobile-desktop-mode "$want"
    ;;
  *)
    echo "tile-action.sh: unknown tile $tile" >&2
    exit 2
    ;;
esac
