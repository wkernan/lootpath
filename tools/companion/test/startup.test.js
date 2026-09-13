// C-9 (WKE-559): the start-with-Windows scripts.
//
// What these three PowerShell scripts DO cannot be tested here - there is no
// Windows, no Task Scheduler and no logon in CI, and the issue says so: the
// owner registers the task once and reboots, and that is the proof. What can be
// tested is the part that breaks silently when a file is renamed or a default
// drifts - that install and uninstall are talking about the SAME task, and that
// the task starts the script that starts the watcher.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const HERE = path.join(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(HERE, name), 'utf8');

const INSTALL = 'install-startup.ps1';
const UNINSTALL = 'uninstall-startup.ps1';
const START = 'start-companion.ps1';

function defaultTaskName(text) {
    const match = text.match(/\[string\]\$TaskName = '([^']+)'/);
    assert.ok(match, 'the script must default its task name in one obvious place');
    return match[1];
}

test('the three scripts are all there, because the README points the owner at them', () => {
    for (const name of [INSTALL, UNINSTALL, START]) {
        assert.ok(fs.existsSync(path.join(HERE, name)), `${name} is missing`);
        assert.match(read('README.md'), new RegExp(name.replace('.', '\\.')));
    }
});

test('install and uninstall name the same task, so one really removes the other', () => {
    assert.strictEqual(defaultTaskName(read(INSTALL)), defaultTaskName(read(UNINSTALL)));
});

test('the registered task starts the script that starts the watcher', () => {
    const install = read(INSTALL);
    assert.match(install, /start-companion\.ps1/, 'the action must run the starter script');
    assert.match(install, /-AtLogOn/, 'at logon is the whole point');
    assert.match(install, /-WindowStyle', 'Hidden'/, 'hidden, so a logon does not put a console on screen');
    assert.match(install, /Register-ScheduledTask[^\n]*-Force/, 'idempotent: registering twice replaces, never doubles');

    const start = read(START);
    assert.match(start, /companion\.js/);
    assert.match(start, /'--watch'/);
    assert.match(start, /npm', 'start'/, 'and brings the fork up when nothing answers it');
});

test('uninstalling a task that is not there is not an error', () => {
    const uninstall = read(UNINSTALL);
    assert.match(uninstall, /Get-ScheduledTask[^\n]*-ErrorAction SilentlyContinue/);
    assert.match(uninstall, /nothing to remove/);
});
