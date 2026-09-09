// The QE Live driver: a profile in, QE Live's own export documents out.
//
// Lifted from tools/companion-spike/run-fork.js (WKE-531, S-1), which proved
// the round trip in 27.7 s with no engine surgery. Every selector still names
// the fork file it was read from, because they are HIS files and they move.
// Nothing of QE Live's source is copied into this repo: the companion drives
// the owner's clone at the configured path, on his own machine (§4, §7 - the
// wider question is WKE-528's).
//
// Two changes S-1 asked for:
//  - a persistent browser profile, so the "Welcome to QE Live" dialog is
//    answered once instead of on every run;
//  - the fork is started when nothing answers, rather than assumed up.
'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const configLib = require('./config');

class ForkError extends Error {
    constructor(message, code) {
        super(message);
        this.code = code;
    }
}
// QE Live refusing the import is a different failure from the fork being down:
// the first means the profile is wrong, the second means nothing ran.
const UNREACHABLE = 'fork-unreachable';
const REFUSED = 'qe-refused';
const DRIVE = 'fork-drive';

async function isUp(url, timeoutMs) {
    try {
        const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs || 3000) });
        return response.ok || response.status === 304;
    } catch {
        return false;
    }
}

// `npm start` in the fork clone. Detached and inheriting nothing, so the CRA
// dev server outlives one companion run and the next one finds it already up.
async function ensureUp(config, log) {
    if (await isUp(config.forkUrl)) {
        log.info(`fork already serving ${config.forkUrl}`);
        return { started: false };
    }
    if (!config.startFork) {
        throw new ForkError(`nothing answers ${config.forkUrl} and startFork is false`, UNREACHABLE);
    }
    if (!fs.existsSync(path.join(config.forkPath, 'package.json'))) {
        throw new ForkError(`no QE Live clone at ${config.forkPath} (set forkPath in the config)`, UNREACHABLE);
    }
    log.info(`nothing answers ${config.forkUrl}; starting "npm start" in ${config.forkPath}`);
    const child = spawn('npm.cmd', ['start'], {
        cwd: config.forkPath,
        detached: true,
        stdio: 'ignore',
        env: { ...process.env, BROWSER: 'none' },
        shell: process.platform !== 'win32',
    });
    child.unref();
    const deadline = Date.now() + config.forkStartTimeoutSeconds * 1000;
    while (Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, 2000));
        if (await isUp(config.forkUrl)) {
            log.info('fork answered');
            return { started: true };
        }
    }
    throw new ForkError(
        `the fork did not answer ${config.forkUrl} within ${config.forkStartTimeoutSeconds}s; run "npm start" in ${config.forkPath} yourself and look at its output`,
        UNREACHABLE
    );
}

// A browser with no saved character gets a welcome dialog over the header
// ("Welcome to QE Live! Select an era" / class tiles / BEGIN!). With a
// persistent profile it appears once.
async function dismissWelcome(page, className) {
    const welcome = page.getByText('Welcome to QE Live');
    if (!(await welcome.count())) return false;
    await page
        .getByText(new RegExp('^' + className + '$', 'i'))
        .first()
        .click();
    await page.getByRole('button', { name: /begin/i }).click();
    await welcome.waitFor({ state: 'hidden', timeout: 10000 });
    return true;
}

// The three import checkboxes, by the label each one is rendered with.
//
// SimCraftDialog.js lines 122-133, read 2026-09-08. The issue that asked for
// this expected the labels to come from `locale/en/translate.json`'s
// `SimCInput.*` keys; they do not - that block holds five keys, none of them a
// checkbox, and all three labels are plain JSX string literals
// (`label="Upgrade ALL to Max Level"`). So these ARE the strings in his source,
// and they are matched exactly rather than looked up.
//
// They are still better than the index the S-1 spike used: the vault and
// catalyze boxes render only for `gameType === "Retail"`, so on any other game
// type index 1 is a different box, while a label that is not on the page is a
// named failure.
const CHECKBOX_LABELS = {
    autoUpgradeAll: 'Upgrade ALL to Max Level',
    autoUpgradeVault: 'Upgrade Vault to Max Level',
    autoCatalyze: 'Auto Catalyze',
};

// Ask for both upgrade settings explicitly, every run (WKE-539, C-5).
//
// His dialog defaults are `autoUpgradeVault = true` / `autoUpgradeAll = false`
// (SimCraftDialog.js lines 36-37), which values a vault option at the top of
// its upgrade track and owned gear at the level the client reports. Submitting
// without touching them inherits that asymmetry, and on 2026-09-08 it told the
// owner to take a 305 vault weapon they already wear at 308 (§9). Whatever the
// configured pair is, it is set here rather than assumed.
//
// Since C-6 (WKE-540) `autoCatalyze` is asked for too, and by the same rule:
// each named scenario states all three boxes and every one of them is set and
// read back. The Catalyst is the whole point of the `catalyzed` scenario, and a
// box left wherever his dialog put it would make the answer depend on his
// default rather than on the question.
async function setUpgradeCheckboxes(page, wanted, log) {
    const applied = {};
    for (const key of Object.keys(CHECKBOX_LABELS)) {
        if (!(key in wanted)) continue;
        const label = CHECKBOX_LABELS[key];
        const want = !!wanted[key];
        const box = page.getByRole('checkbox', { name: label, exact: true });
        if (!(await box.count())) {
            throw new ForkError(
                `QE Live's import dialog has no checkbox labelled "${label}" (SimCraftDialog.js); the companion will not guess at which box is ${key}`,
                DRIVE
            );
        }
        const before = await box.isChecked();
        if (before !== want) await box.click();
        const after = await box.isChecked();
        if (after !== want) {
            throw new ForkError(`clicking "${label}" did not take: it is ${after}, and the run asked for ${want}`, DRIVE);
        }
        applied[key] = { want: want, was: before, clicked: before !== want };
    }
    if (log) {
        log.info(
            '  import settings: ' +
                Object.keys(applied)
                    .map((k) => `${k}=${applied[k].want}${applied[k].clicked ? ' (clicked)' : ''}`)
                    .join(', ')
        );
    }
    return applied;
}

// The two booleans the verdict file records, out of the detail the step above
// keeps for the log. `want` and not `wanted` on purpose: it is only ever set
// after `isChecked` agreed with it, so this is what the page reported, not what
// the run asked for.
function settingsFrom(applied) {
    const settings = {};
    for (const key of Object.keys(applied || {})) settings[key] = !!applied[key].want;
    return settings;
}

// SetupAndMenus/SimCraftDialog.js: the header control is a styled MUI button
// whose accessible name does not resolve as "Import Gear"; its visible text
// does. #SimCError carries the reason when he refuses.
async function importProfile(page, text, wanted, log) {
    await page.getByText(/import gear/i).first().click();
    const box = page.locator('#simcentry');
    await box.waitFor({ state: 'visible', timeout: 10000 });
    await box.fill(text);
    // Before Submit: `runSimC` is handed the checkbox STATE, so a box set after
    // the click would change nothing (SimCraftDialog.js handleSubmit).
    const settings = await setUpgradeCheckboxes(page, wanted, log);
    await page.getByRole('button', { name: 'Submit' }).click();
    await Promise.race([
        box.waitFor({ state: 'hidden', timeout: 20000 }),
        page
            .locator('#SimCError')
            .filter({ hasText: /\S/ })
            .waitFor({ timeout: 20000 })
            .then(async () => {
                throw new ForkError('QE Live refused the profile: ' + (await page.locator('#SimCError').innerText()), REFUSED);
            }),
    ]);
    return settings;
}

// In-app navigation, so React state survives; the app is served under /live/
// (the fork's homepage), so paths are matched by inclusion.
async function goTo(page, route) {
    const link = page.locator(`a[href="${route}"]`).first();
    if (await link.count()) {
        await link.click();
    } else {
        await page.evaluate((r) => window.history.pushState({}, '', r), route);
        await page.evaluate(() => window.dispatchEvent(new PopStateEvent('popstate')));
    }
    await page.waitForURL((u) => u.pathname.includes(route), { timeout: 10000 });
}

// Dungeon/Raid is the "Content" select on CharacterPanel.tsx (~line 432), and
// that panel renders only inside the analysis pages. /embellishments crashed in
// his code with this character on 2026-09-07, so the routes are tried in turn
// and a CRA runtime-error overlay is a page to leave, never one to click
// through.
async function setContent(page, contentType, log) {
    let select = page.getByLabel('Content', { exact: true }).first();
    if (!(await select.isVisible().catch(() => false))) {
        for (const route of ['/circlet', '/omniumfolio', '/embellishments']) {
            await goTo(page, route);
            await page.waitForTimeout(400);
            const overlay = page.frameLocator('iframe').getByText('Uncaught runtime errors');
            if (await overlay.count().catch(() => 0)) {
                log.warn(`${route} raised a runtime error in QE Live's own code; trying the next page`);
                await page.keyboard.press('Escape');
                continue;
            }
            select = page.getByLabel('Content', { exact: true }).first();
            if (await select.isVisible().catch(() => false)) break;
        }
    }
    await select.waitFor({ timeout: 10000 });
    await select.click();
    await page.getByRole('option', { name: contentType, exact: true }).click();
    await page.waitForTimeout(250);
}

// TopGear/MiniItemCard.tsx: cards are .MuiCardActionArea-root and an active
// card's parent class contains "selected". topGearCap is 30 for a non-patron
// (TopGear.tsx), so "everything in the bags" means the first 30.
async function selectItems(page) {
    const counter = page.getByText(/Selected Items:\s*\d+\/\d+/).first();
    await counter.waitFor({ timeout: 10000 });
    const readCount = async () => {
        const m = (await counter.innerText()).match(/(\d+)\/(\d+)/);
        return { n: +m[1], cap: +m[2] };
    };
    let { n, cap } = await readCount();
    const cards = page.locator('.MuiCardActionArea-root');
    const total = await cards.count();
    let clicked = 0;
    for (let i = 0; i < total && n < cap; i++) {
        const card = cards.nth(i);
        const cls = (await card.locator('..').getAttribute('class')) || '';
        if (/selected/i.test(cls)) continue;
        await card.click();
        clicked++;
        ({ n, cap } = await readCount());
    }
    return { selected: n, cap, cards: total, clicked };
}

// TopGear/Report/MenuDropdown.tsx opens Download JSON / Copy JSON; Copy JSON
// puts the text in a GenericDialog TextField, which needs neither clipboard
// permissions nor download interception.
async function readJson(page) {
    await page.getByRole('button', { name: 'Export' }).first().click();
    await page.getByRole('menuitem', { name: 'Copy JSON' }).click();
    const field = page.locator('.MuiDialog-root textarea').first();
    await field.waitFor({ timeout: 10000 });
    const text = await field.inputValue();
    await page.keyboard.press('Escape');
    return text;
}

async function runTopGear(page, log) {
    await goTo(page, '/topgear');
    const selection = await selectItems(page);
    log.info(`  top gear: ${selection.selected}/${selection.cap} items selected (${selection.cards} cards, ${selection.clicked} clicked)`);
    await page.getByRole('button', { name: 'Go!' }).click();
    await page.waitForURL((u) => /\/report\/[a-z0-9]+/.test(u.pathname), { timeout: 120000 });
    return readJson(page);
}

// -------------------------------------------------------------------------
// The Mythic+ key selector (WKE-543, C-7).
//
// UpgradeFinder/UpgradeFinderFront.js lines 505-530, read 2026-09-08: a row of
// MUI ToggleButtons rendered straight out of `MPLUS_KEY_REWARDS.map`, each one
// labelled `key.label` and calling `setDungeonDifficulty(key.index)`. The
// selected index is what lands in `ufSettings.dungeon`, and that is an INDEX
// into his table, NOT a key level: index 7 is the "+10" button, whose rows come
// back at 311 / 321 / 334 (Databases/MPlusKeyRewards.ts).
//
// His labels are how a player says a key - "M0", "+4", "+8/9" - so the
// companion asks for a key LEVEL and finds the button whose label covers it.
// The level -> index mapping is therefore read off his own page every run and
// never restated here; a key he adds is a button this finds, and a level his
// page does not offer is a named failure rather than a nearest match.
const KEY_LEVEL_SECTION = 'Mythic+ Key Level';

// "M0" -> [0]; "+4" -> [4]; "+8/9" -> [8, 9]. Null for anything that is not one
// of his key labels, which is how the reader below notices it is looking at the
// wrong row of buttons instead of guessing at an index.
function keyLevelsOfLabel(label) {
    const text = String(label).trim();
    if (!/^[M+]\d+(\/\d+)*$/.test(text)) return null;
    return text
        .slice(1)
        .split('/')
        .map((part) => Number(part));
}

// Is this toggle the selected one? MUI's ToggleButton carries `aria-pressed`,
// and the fork restyles it through `classes.selected` while MUI still adds its
// own `Mui-selected`. Either is proof; needing both would break on a restyle.
async function isSelectedToggle(locator) {
    if ((await locator.getAttribute('aria-pressed')) === 'true') return true;
    return /Mui-selected/.test((await locator.getAttribute('class')) || '');
}

// Every key toggle on the page, in DOM order, which is `MPLUS_KEY_REWARDS`
// order and so is `key.index`. That the position really is his index is not
// assumed: every Upgrade Finder run below checks the export's own
// `settings.dungeon` against the position of the button it clicked.
async function readKeyLevelButtons(page) {
    const section = page.locator('.MuiPaper-root').filter({ hasText: KEY_LEVEL_SECTION }).last();
    if (!(await section.count())) {
        throw new ForkError(
            `QE Live's Upgrade Finder page has no "${KEY_LEVEL_SECTION}" section (UpgradeFinderFront.js); the companion will not guess at which buttons are the key selector`,
            DRIVE
        );
    }
    const toggles = section.getByRole('button');
    const total = await toggles.count();
    const buttons = [];
    for (let i = 0; i < total; i++) {
        const locator = toggles.nth(i);
        const label = (await locator.innerText()).trim();
        const levels = keyLevelsOfLabel(label);
        if (!levels) {
            throw new ForkError(
                `the "${KEY_LEVEL_SECTION}" section holds a button labelled ${JSON.stringify(label)}, which is not one of QE Live's key labels (M0, +4, +8/9); the companion will not count positions past a button it cannot read`,
                DRIVE
            );
        }
        buttons.push({ index: buttons.length, label, levels, locator });
    }
    if (!buttons.length) {
        throw new ForkError(`the "${KEY_LEVEL_SECTION}" section holds no key buttons at all`, DRIVE);
    }
    return buttons;
}

// Click the button that covers `level`, then read it back: a click that did not
// take would otherwise export a document filed under a key it was never run at.
async function selectKeyLevel(page, level, log) {
    const buttons = await readKeyLevelButtons(page);
    const chosen = buttons.find((button) => button.levels.includes(level));
    if (!chosen) {
        throw new ForkError(
            `QE Live's key selector offers ${buttons.map((b) => b.label).join(', ')}, so it cannot be asked about a +${level} key`,
            DRIVE
        );
    }
    const was = await isSelectedToggle(chosen.locator);
    if (!was) await chosen.locator.click();
    if (!(await isSelectedToggle(chosen.locator))) {
        throw new ForkError(`clicking "${chosen.label}" did not select it, so the run would be at the wrong key level`, DRIVE);
    }
    if (log) log.info(`  mythic+ key ${chosen.label} (his index ${chosen.index})${was ? '' : ' (clicked)'}`);
    return chosen;
}

// `settings.dungeon` out of an export, or null when it does not say. The addon
// is the parser for everything else in these documents; this reads one integer
// so a run can refuse to file a document under a key it was not run at.
function exportedKeyIndex(json) {
    try {
        const settings = JSON.parse(json).settings || {};
        return Number.isInteger(settings.dungeon) ? settings.dungeon : null;
    } catch {
        return null;
    }
}

// One Upgrade Finder document. `keyLevel` is the key the run is for; the
// selector is set before Go! and the export is checked against it afterwards,
// because a document filed under the wrong key level is a wrong answer that
// looks right.
async function runUpgradeFinder(page, keyLevel, log) {
    await goTo(page, '/upgradefinder');
    let chosen = null;
    if (keyLevel !== null && keyLevel !== undefined) {
        chosen = await selectKeyLevel(page, keyLevel, log);
    }
    await page.getByRole('button', { name: 'Go!' }).click();
    await page.waitForURL((u) => u.pathname.includes('/upgradereport'), { timeout: 120000 });
    const json = await readJson(page);
    if (chosen) {
        const said = exportedKeyIndex(json);
        if (said !== chosen.index) {
            throw new ForkError(
                `this run asked for a +${keyLevel} key ("${chosen.label}", his index ${chosen.index}) but the export says settings.dungeon = ${said}; refusing to file a document under a key level it was not run at`,
                DRIVE
            );
        }
    }
    return json;
}

// profileText in, [{ kind, contentType, json }] out. The caller owns the
// failure: nothing here writes a file.
async function run(config, profileText, log, options) {
    const opts = options || {};
    // The passes this run makes: one import per named scenario, each with its
    // own three checkboxes, then the documents that import can answer (C-6,
    // WKE-540). The caller owns the plan, because whether the two what-ifs are
    // worth asking depends on the PROFILE - a vault section with gear in it -
    // and this file has only the text.
    const passes = opts.passes || configLib.plannedPasses(config, {});
    let chromium;
    try {
        ({ chromium } = require('playwright'));
    } catch {
        throw new ForkError('playwright is not installed; run "npm install" in tools/companion', DRIVE);
    }
    await ensureUp(config, log);

    const userDataDir = path.resolve(opts.stateDir || path.join(__dirname, '..', config.stateDir), 'browser');
    fs.mkdirSync(userDataDir, { recursive: true });
    const context = await chromium.launchPersistentContext(userDataDir, {
        headless: !config.headed,
        viewport: { width: 1400, height: 1000 },
    });
    const page = context.pages()[0] || (await context.newPage());
    page.setDefaultTimeout(20000);
    const documents = [];
    const timings = [];
    // What was actually asked for, read back off the page, so the verdict file
    // records the run rather than the intention.
    let qeSettings = null;
    try {
        let done = log.stage('  page load');
        // The CRA dev server holds a hot-reload socket open, so "networkidle"
        // never arrives; wait for the header instead.
        await page.goto(config.forkUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
        await page.getByText(/import gear/i).first().waitFor({ timeout: 120000 });
        timings.push(['page load', done()]);

        done = log.stage('  welcome dialog');
        const hadWelcome = await dismissWelcome(page, opts.className || 'DRUID');
        const welcomeNote = hadWelcome ? 'answered' : 'none, the browser profile remembered the character';
        timings.push([`welcome dialog: ${welcomeNote}`, done(welcomeNote)]);

        for (const pass of passes) {
            const asked = pass.scenario || 'the configured Upgrade Finder settings';
            // Re-imported per pass, because the three boxes act at import:
            // `runSimC` is handed their state, so a box flipped after Submit
            // changes nothing and the same player would be scored again.
            done = log.stage(`  profile import (${asked})`);
            const settings = settingsFrom(await importProfile(page, profileText, pass.boxes, log));
            timings.push([`profile import (${asked})`, done()]);
            // The pair the FILE records stays the pair C-5 named, and it is the
            // base pass's: the per-document settings below are what each answer
            // was actually produced under.
            if (!qeSettings || pass.scenario === configLib.DEFAULT_SCENARIO) {
                qeSettings = { autoUpgradeAll: !!settings.autoUpgradeAll, autoUpgradeVault: !!settings.autoUpgradeVault };
            }

            // The content select is re-read per pass rather than remembered
            // across one: the import dialog rebuilds the player, and what the
            // page showed before an import is not proof of what it shows after.
            let content = null;
            for (const planned of pass.documents) {
                const at = planned.keyLevel === undefined ? '' : ` +${planned.keyLevel}`;
                if (planned.contentType !== content) {
                    done = log.stage(`  content ${planned.contentType}`);
                    await setContent(page, planned.contentType, log);
                    content = planned.contentType;
                    timings.push([`content ${planned.contentType}`, done()]);
                }
                const label = `${planned.kind} ${planned.contentType}${at}${planned.scenario ? ` (${planned.scenario})` : ''}`;
                done = log.stage(`  ${label}`);
                const json =
                    planned.kind === 'topgear'
                        ? await runTopGear(page, log)
                        : await runUpgradeFinder(page, planned.keyLevel, log);
                timings.push([`${label} (${json.length} chars)`, done(`${json.length} chars`)]);
                documents.push({
                    kind: planned.kind,
                    contentType: planned.contentType,
                    keyLevel: planned.keyLevel,
                    scenario: planned.scenario,
                    // What the page reported after the click, not what the pass
                    // asked for, so a document says how it was really produced.
                    qeSettings: settings,
                    json,
                });
            }
        }
    } catch (e) {
        if (opts.screenshotDir) {
            fs.mkdirSync(opts.screenshotDir, { recursive: true });
            await page.screenshot({ path: path.join(opts.screenshotDir, 'failure.png') }).catch(() => {});
        }
        if (e instanceof ForkError) throw e;
        throw new ForkError(`driving QE Live failed: ${e.message}`, DRIVE);
    } finally {
        await context.close().catch(() => {});
    }
    return { documents, timings, qeSettings };
}

module.exports = {
    run,
    ensureUp,
    isUp,
    setUpgradeCheckboxes,
    settingsFrom,
    importProfile,
    keyLevelsOfLabel,
    readKeyLevelButtons,
    selectKeyLevel,
    exportedKeyIndex,
    runUpgradeFinder,
    CHECKBOX_LABELS,
    KEY_LEVEL_SECTION,
    ForkError,
    UNREACHABLE,
    REFUSED,
    DRIVE,
};
