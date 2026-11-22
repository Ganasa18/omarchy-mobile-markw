<!-- SPDX-License-Identifier: MIT -->
# omamobile-storage

Storage shows what fills each drive, frees what is safe to rebuild, and
uninstalls apps, in a phone window drawn in the Omarchy theme.

```
Storage (quickshell -p /usr/share/omamobile-storage/shell.qml)
  ├─ omamobile-storage drives | usage DIR | places | clean-info | apps   (JSON, read-only)
  ├─ omamobile-storage clean cache trash                                 (as the user)
  ├─ omamobile-storage remove-data PATH...                               (an app's own folders)
  └─ pkexec omamobile-storage root clean-logs | clean-packages | remove PKG
```

- **Overview.** Each mounted drive on its own card: the eMMC root and the
  microSD card are never summed (GNOME's Disk Usage scans `/` with the card
  mounted inside it and adds both). The internal drive is split into your
  files, apps and system (`/usr`), system logs, app caches, and the rest.
  A card that still holds a whole system (`usr/lib/systemd/systemd` at its
  top, as markw keeps its previous microSD root as the way back) shows it as
  a backup, and Storage never cleans it. Any row or card opens a folder
  browser that stays on that drive (`du -x`); folders the user can't read
  are left out and said so.
- **Clean up.** Only what is safe to rebuild:
  - app cache files in `~/.cache` neither read nor written for 7 days
    (a cache in use stays);
  - system logs older than 2 weeks (`journalctl --vacuum-time=2weeks`);
  - downloaded packages whose exact version is not installed (the installed
    one stays, for a reinstall or a downgrade);
  - the Trash.

  The figure for logs is an upper bound ("up to"); the others are measured.
  The system items go through `pkexec`, so Omarchy's polkit agent asks for
  the password. After a clean-up the window reports what the drive gained.
- **Apps.** Desktop apps by their package's installed size. An app another
  package needs, or a core package (the shell, the compositor, the kernel,
  Omarchy and Omarchy Mobile), is shown as `system` and can't be removed.
  Uninstall is `pacman -Rns` of the app's package, refused if pacman's plan
  would take a core package with it. "Also delete its data" lists the app's
  own folders (`~/.config/X`, `~/.local/share/X`, `~/.cache/X`, X the
  package, desktop id or window class) before anything goes.

## Use from a terminal

```sh
omamobile-storage                 # the window
omamobile-storage drives          # each drive: size, used, free, kind
omamobile-storage usage /mnt/sd   # a folder's contents by size
omamobile-storage clean-info      # what clean-up would free
omamobile-storage apps            # apps by size, with what locks them
```
