#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run actual brightness commands against fake panel/compositor endpoints."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

source = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    bins = d / 'bin'
    bins.mkdir()
    panel = d / 'panel'
    panel.mkdir()
    power = panel / 'bl_power'
    conf = d / 'device.conf'
    conf.write_text('POWER_KEY_WAKE_ONLY=1\n')
    entered = d / 'entered'

    def script(name, text):
        p = bins / name
        p.write_text(text)
        p.chmod(0o755)

    script('omarchy-hw-display', '#!/bin/bash\necho panel\n')
    script('omarchy-hyprland-monitor-focused', '#!/bin/bash\necho DSI-1\n')
    script('hyprctl', '''#!/bin/bash
echo "$*" >>"$TEST_DIR/trace"
if [[ $1 == monitors ]]; then printf '[{"disabled":false,"dpmsStatus":%s}]\n' "${DPMS:-true}"; fi
if [[ ${SLOW:-} == 1 && $* == *disable* ]]; then touch "$TEST_DIR/entered"; sleep 0.3; fi
''')
    script('jq', '''#!/usr/bin/env python3
import json,sys
x=json.load(sys.stdin); sys.exit(0 if x and all(i['dpmsStatus'] for i in x if not i['disabled']) else 1)
''')
    env = dict(os.environ, PATH=str(bins)+':'+os.environ['PATH'],
               OMARCHY_BACKLIGHT_PATH=str(d), XDG_RUNTIME_DIR=str(d),
               OMAMOBILE_DEVICE_CONF=str(conf), TEST_DIR=str(d))

    def run(action, **extra):
        p = subprocess.run(['bash', str(source), action], env=dict(env, **extra),
                           capture_output=True, text=True, timeout=5)
        assert p.returncode == 0, (p.returncode, p.stderr)

    power.write_text('4\n')
    run('on', OMAMOBILE_WAKE_FROM_INPUT='1')
    assert power.read_text().strip() == '4', 'touch/idle activity woke dark panel'
    run('on')
    assert power.read_text().strip() == '0', 'explicit Power wake failed'
    run('off')
    assert power.read_text().strip() == '4'
    power.write_text('0\n')
    run('on', OMAMOBILE_WAKE_FROM_INPUT='1')
    assert power.read_text().strip() == '0', 'activity on a lit lock must work'
    (d/'trace').write_text('')
    run('on', OMAMOBILE_WAKE_FROM_INPUT='1', DPMS='false')
    assert not any('enable' in line for line in (d/'trace').read_text().splitlines()), 'input woke DPMS-off panel with bl_power=0'

    proc = subprocess.Popen(['bash', str(source), 'off'], env=dict(env, SLOW='1'))
    try:
        deadline = time.monotonic()+3
        while not entered.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert entered.exists()
        run('on', OMAMOBILE_WAKE_FROM_INPUT='1')
        assert proc.wait(timeout=5) == 0
    finally:
        if proc.poll() is None:
            proc.kill(); proc.wait()
    assert power.read_text().strip() == '4', 'racing input woke a blanking panel'
    assert 'touchdevice' not in (d/'trace').read_text(), 'must not disable global touch'

    conf.write_text('POWER_KEY_WAKE_ONLY=0\n')
    run('on', OMAMOBILE_WAKE_FROM_INPUT='1')
    assert power.read_text().strip() == '0', 'other devices keep input wake'
    conf.unlink()
    run('off')
    run('on', OMAMOBILE_WAKE_FROM_INPUT='1')
    assert power.read_text().strip() == '0', 'missing descriptor keeps normal wake'
    print('ok - input wake blocked only while dark; Power, lit input, races, other devices')
