// SPDX-License-Identifier: MIT
// Execute the actual lock's JS bodies with Process stubs, not a copy of them.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
function body(marker) {
  const start = source.indexOf(marker);
  assert(start >= 0, marker);
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0);
  return source.slice(open + 1, end - 1);
}
const ctx = {
  wakeProcess: {running: false, command: []}, powerWakePending: false,
  lockRequested: true, armBlankTimer() {}, currentlyLocked() { return true; },
  wakeFocusRequested() {},
};
ctx.root = ctx;
vm.createContext(ctx);
vm.runInContext('function runWake(fromInput) {' + body('function runWake(') + '}', ctx);
ctx.runWake();
assert.match(ctx.wakeProcess.command[2], /OMAMOBILE_WAKE_FROM_INPUT=1/);
ctx.runWake(false);
assert.equal(ctx.powerWakePending, true);
ctx.wakeProcess.running = false;
const proc = source.slice(source.indexOf('id: wakeProcess'));
const exited = proc.slice(proc.indexOf('onExited:'));
const exitStart = exited.indexOf('{');
let depth = 1, end = exitStart + 1;
while (depth && end < exited.length) { if (exited[end] === '{') depth++; if (exited[end] === '}') depth--; end++; }
vm.runInContext(exited.slice(exitStart + 1, end - 1), ctx);
assert.equal(ctx.powerWakePending, false);
assert.equal(ctx.wakeProcess.running, true);
assert.equal(ctx.wakeProcess.command[2], 'omarchy-system-wake');
ctx.wakeProcess.running = false;
vm.runInContext('(function(){' + body('function wakeInput()') + '})()', ctx);
assert.match(ctx.wakeProcess.command[2], /OMAMOBILE_WAKE_FROM_INPUT=1/);
ctx.wakeProcess.running = false;
vm.runInContext('(function(){' + body('function wake()') + '})()', ctx);
assert.equal(ctx.wakeProcess.command[2], 'omarchy-system-wake');
console.log('ok - actual QML wake JS: input/Power IPC separation and queued Power replay');
