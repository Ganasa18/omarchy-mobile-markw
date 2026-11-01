#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keys' volume keys: a photo while the Camera app (omacam) is in
# front of an unlocked phone, once per press; the volume otherwise. Stand-ins
# for hyprctl, omacam, omarchy-shell and omarchy-audio-output-volume record
# what was called.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run"
log=$t/calls
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
cat >"$t/bin/omacam" <<STUB
#!/bin/bash
echo "omacam \$*" >>"$log"
STUB
cat >"$t/bin/omarchy-audio-output-volume" <<STUB
#!/bin/bash
echo "volume \$*" >>"$log"
STUB
cat >"$t/bin/omarchy-shell" <<STUB
#!/bin/bash
[[ "\$1 \$2" == "lock status" ]] && { echo '{"secure":true}'; exit 0; }
cat "$t/locked"
STUB
for stub in omarchy-menu omarchy-system-lock omarchy-brightness-display; do
  cat >"$t/bin/$stub" <<STUB
#!/bin/bash
echo "$stub \$*" >>"$log"
STUB
done
echo '#!/bin/bash' >"$t/bin/omarchy-hw-display"
chmod +x "$t"/bin/*
export PATH="$t/bin:$PATH" XDG_RUNTIME_DIR="$t/run"
keys() { bash "$here/bin/omamobile-keys" "$@"; }
fail() { printf 'not ok - %s\n' "$1" >&2; cat "$log" >&2 2>/dev/null; exit 1; }
reset() { : >"$log"; rm -rf "$t/run/omamobile-keys"; }

echo foot >"$t/class"; echo false >"$t/locked"
reset; keys volume-up; [[ $(cat "$log") == "volume raise" ]] || fail "volume up raises the volume"
reset; keys volume-down; sleep 0.4; [[ $(cat "$log") == "volume lower" ]] || fail "volume down lowers the volume"

echo omacam >"$t/class"
reset; keys volume-up; [[ $(cat "$log") == "omacam --remote shutter" ]] || fail "volume up takes a photo in the camera"
reset; keys volume-down; sleep 0.4; [[ $(cat "$log") == "omacam --remote shutter" ]] || fail "volume down takes a photo in the camera"
reset; keys volume-up; keys volume-up; keys volume-up
[[ $(grep -c shutter "$log") == 1 ]] || fail "a held key takes one photo"

echo true >"$t/locked"
reset; keys volume-up; [[ $(cat "$log") == "volume raise" ]] || fail "a locked phone changes the volume, never takes a photo"
echo "ok - volume keys: camera shutter in front, volume otherwise"

# The power key bounces on markw: held, it reports a release and a new press
# about 20 ms apart. That is still one press: a hold opens the system menu
# and doesn't lock; a tap locks.
echo foot >"$t/class"; echo false >"$t/locked"
reset; keys power-down; sleep 0.03; keys power-up & sleep 0.02; keys power-down; sleep 0.9
grep -qx 'omarchy-menu toggle system' "$log" || fail "a bounced hold opens the system menu"
keys power-up; wait
! grep -q 'omarchy-system-lock' "$log" || fail "a bounced hold doesn't lock"
reset; keys power-down; sleep 0.05; keys power-up
grep -q '^omarchy-system-lock' "$log" || fail "a tap locks"
! grep -q 'omarchy-menu' "$log" || fail "a tap doesn't open the menu"
echo "ok - power key: a bounce is the same press"
