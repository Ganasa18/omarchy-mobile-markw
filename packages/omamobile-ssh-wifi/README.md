<!-- SPDX-License-Identifier: MIT -->
# omamobile-ssh-wifi

SSH to the phone over Wi-Fi when it is needed, and only then. The installer
lets SSH in on the USB link (usb0) only; this opens TCP 22 on the Wi-Fi
interface for a set time and closes it again.

```
quick settings: SSH Wi-Fi tile (tap: on for 30 min / off; hold: the page)
  └─ omamobile-ssh-wifi on 30
       └─ omamobile-ssh-wifi@30.service (root, allowed by polkit)
            ├─ ufw allow in on wlan0 to any port 22 proto tcp comment omamobile-ssh-wifi
            ├─ sleep 30 min
            └─ on stop: delete the rule, end the SSH sessions that came in over Wi-Fi
```

sshd keeps its configuration: keys only, no passwords
(`/etc/ssh/sshd_config.d/10-omamobile.conf`). The rule names the Wi-Fi
interface, so it never opens SSH on mobile data or a hotspot client link.

## Use

```sh
omamobile-ssh-wifi on          # 30 minutes
omamobile-ssh-wifi on 0        # until off
omamobile-ssh-wifi status      # on/off, minutes left, address, the ssh command, sessions
omamobile-ssh-wifi status --json
omamobile-ssh-wifi off         # close the port and end the Wi-Fi sessions
```

The phone's auto-suspend (device packages) stays awake while an SSH session
is open; without one the phone sleeps and can't be reached until the screen
is on, because Wi-Fi doesn't wake it.

## Notes

- Without ufw (or with it inactive) sshd already answers on every
  interface; `status` then still reports the unit, and the tile's page says
  so.
- A rule someone added by hand that allows 22 on Wi-Fi stays; remove it
  (`ufw status numbered`, `ufw delete N`) so the tile is what opens SSH.
- Ending a session kills that connection's `sshd-session` process; the USB
  link's sessions are never touched.
