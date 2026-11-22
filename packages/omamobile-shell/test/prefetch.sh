#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-prefetch: the Recent row's apps, found through their desktop
# entries past env and launchers, with the libraries an ELF program links;
# nothing for an unknown id, a bad id or no recent list.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/state/omamobile" "$t/data/applications" "$t/bin"
sh=$(command -v sh)
cp "$sh" "$t/bin/fakeapp"
printf '#!/bin/sh\n' >"$t/bin/fakescript"; chmod +x "$t/bin/fakescript"
cat >"$t/data/applications/org.example.App.desktop" <<EOF
[Desktop Entry]
Name=App
Exec=env FOO=1 uwsm-app -- fakeapp %U
[Desktop Action new]
Exec=other
EOF
printf '[Desktop Entry]\nExec=fakescript --flag\n' >"$t/data/applications/script.desktop"
printf 'org.example.App\nmissing.App\n../evil\nscript\n' >"$t/state/omamobile/recent-apps"

run() { env -i HOME="$t" XDG_STATE_HOME="$t/state" XDG_DATA_HOME="$t/data" XDG_DATA_DIRS="$t/none" \
  PATH="$t/bin:/usr/bin:/bin" python3 -I bin/omamobile-prefetch "$@"; }

out=$(run --dry-run)
grep -cx "$(realpath "$t/bin/fakeapp")" <<<"$out" >/dev/null || fail "the app's program is read ahead"
if command -v ldd >/dev/null && ldd "$sh" 2>/dev/null | grep -c '/' >/dev/null; then
  [[ $(grep -c '\.so' <<<"$out") -gt 0 ]] || fail "an ELF program's libraries come with it"
fi
grep -cx "$(realpath "$t/bin/fakescript")" <<<"$out" >/dev/null || fail "a script is read ahead too"
! grep -c 'evil\|other' <<<"$out" >/dev/null || fail "bad ids and other actions are left alone"
[[ $(sort <<<"$out" | uniq -d | wc -l) == 0 ]] || fail "each file once"
run >/dev/null || fail "a real run exits cleanly"
rm "$t/state/omamobile/recent-apps"
[[ -z $(run --dry-run) ]] || fail "no recent apps: nothing"
run --bogus 2>/dev/null && fail "unknown options are refused"
echo "ok - omamobile-prefetch reads the Recent row's apps ahead"
