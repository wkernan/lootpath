// One line per stage, with the milliseconds it took. The companion runs
// unattended in a terminal behind the game, so the log is the only place a
// failure can be seen: it names the stage, never a stack trace alone.
'use strict';

function now() {
    return new Date().toTimeString().slice(0, 8);
}

function make(sink) {
    const write = sink || ((line) => process.stdout.write(line + '\n'));
    const log = {
        info(message) {
            write(`[${now()}] ${message}`);
        },
        warn(message) {
            write(`[${now()}] warning: ${message}`);
        },
        error(message) {
            write(`[${now()}] FAILED: ${message}`);
        },
        // stage("profile") -> done("15 equipped, 35 in bags") prints the note
        // and the elapsed milliseconds on one line.
        stage(name) {
            const started = Date.now();
            return (note) => {
                const ms = Date.now() - started;
                write(`[${now()}] ${name}: ${note ? note + ' ' : ''}(${ms} ms)`);
                return ms;
            };
        },
    };
    return log;
}

module.exports = { make };
