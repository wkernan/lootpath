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
const simcProfile = require('./simc-profile');

// `message` is what the log and the terminal get: QE Live's own words, naming
// QE Live. `playerMessage` is the one the status file carries to the strip's
// tooltip, where no source is ever named (C-14a, WKE-626); absent means the log
// line is good enough for both, which is what every failure before C-14a did.
//
// C-14b (WKE-627) adds `playerFields`: the SAME failure as data - a reason token
// and the facts behind it - so the addon can draw a screen off it instead of
// reading the sentence. A failure that carries none is written exactly as it
// always was.
class ForkError extends Error {
    constructor(message, code, playerMessage, playerFields) {
        super(message);
        this.code = code;
        if (playerMessage) this.playerMessage = playerMessage;
        if (playerFields) this.playerFields = playerFields;
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

// -------------------------------------------------------------------------
// Which character QE Live is on (C-16, WKE-619).
//
// QE Live holds ONE active character at a time and refuses a SimC string whose
// class is not that character's: `checkSimCValid` in his
// `General/Items/GearImport/SimCImportEngine.ts` line 354 tests the header's
// class line against the selected character's spec string and line 360 writes
// "You're currently a <spec> but this SimC string is for a different spec." into
// `#SimCError`. That is the message `importProfile` reads and turns into
// `REFUSED`, and on 2026-09-18 it is what the owner's Restoration Shaman got
// twice, because nothing in this driver had ever set the character.
//
// He names a healer by spec and class in one string - "Restoration Shaman" -
// and his two lists are exactly that: `General/Engine/CONSTANTS.ts` line 24
// (`specs`, the welcome dialog's tiles) and
// `General/Modules/SetupAndMenus/Header/QEHeaderClassSelector.js` lines 15-23
// (the header's own menu). The client hands the companion the two halves
// separately - `identity.class` is `UnitClass`'s TOKEN (`SHAMAN`) and
// `identity.spec` is the spec's own NAME (`Restoration`), C-15 - so the name QE
// Live would print is built from the pair.
//
// This map is the one restatement of his table in this file, and it earns its
// place: a profile whose class he has no character for is refused BEFORE a
// browser is opened, and nothing can be read off a page that is not open. It is
// the class half only; which SPECS he rates is settled against his own menu.
const QE_CLASS_WORD = {
    DRUID: 'Druid',
    PRIEST: 'Priest',
    SHAMAN: 'Shaman',
    PALADIN: 'Paladin',
    MONK: 'Monk',
    EVOKER: 'Evoker',
};

// The class-only fallback (C-16a, WKE-622).
//
// A flush `env` names no spec, and after four flushes the last refresh's `env`
// is off the end of the addon's four-deep history, so a character CAN reach
// here with a class and no spec at all. For all but one class that is still not
// a question: his retail menu (`classNames.Retail`,
// `QEHeaderClassSelector.js` lines 15-23) lists exactly ONE healer for each of
//
//   Restoration Druid · Restoration Shaman · Holy Paladin ·
//   Mistweaver Monk · Preservation Evoker
//
// and TWO for the Priest - `Holy Priest` and `Discipline Priest`. So the five
// have one character each and there is nothing to choose; the Priest has two
// and the companion will not pick one of them. Priest is absent from this table
// on purpose, and `run` below turns that absence into a refusal before a
// browser is opened. The values are the spec halves of HIS OWN list, not a
// table of ours: `character.test.js` derives this table from that list and
// fails if the two ever differ.
const QE_CLASS_SOLE_SPEC = {
    DRUID: 'Restoration',
    SHAMAN: 'Restoration',
    PALADIN: 'Holy',
    MONK: 'Mistweaver',
    EVOKER: 'Preservation',
};

// `{ class: "SHAMAN", spec: "Restoration" }` -> `"Restoration Shaman"`. A
// capture that names the class but no spec falls back to that class's only
// healer (C-16a). Null when the CLASS is missing, which is a capture too old to
// say rather than a character QE Live will not rate, and null for a spec-less
// Priest, whose two characters `run` refuses to choose between; `qeHasClass`
// below is the question that refuses an unrated class.
function qeSpecOf(identity) {
    const word = QE_CLASS_WORD[qeClassToken(identity)];
    const named = identity && identity.spec ? String(identity.spec).trim() : '';
    const spec = named || QE_CLASS_SOLE_SPEC[qeClassToken(identity)] || '';
    if (!word || !spec) return null;
    return `${spec} ${word}`;
}

function qeClassToken(identity) {
    return identity && identity.class ? String(identity.class).trim().toUpperCase() : '';
}

// Does QE Live have a character of this class at all? A token he has no word
// for is a class he does not rate - a Warrior, a Rogue - and H-1 should have
// stopped that profile long before the companion saw it.
function qeHasClass(identity) {
    const token = qeClassToken(identity);
    return !token || !!QE_CLASS_WORD[token];
}

// The welcome dialog's tile caption for one of his spec names.
// `Welcome.tsx`'s `getShortClassName` (lines 72-76) prints "H Priest" for Holy
// Priest, "D Priest" for Discipline Priest and the second word of the spec name
// for everything else - so the tile for "Restoration Shaman" reads "Shaman".
//
// This is the lookup the welcome path and the switch path SHARE: both start
// from `qeSpecOf`, one clicks the tile it names and the other picks the menu
// item it names. Before C-16 the welcome path was handed a class TOKEN and
// defaulted to `DRUID`, which matched his "Druid" tile by luck of the
// case-insensitive regex and matched no tile at all for a Priest.
function welcomeTileLabel(qeSpec) {
    const name = String(qeSpec || '').trim();
    if (name.includes('Holy Priest')) return 'H Priest';
    if (name.includes('Discipline Priest')) return 'D Priest';
    return name.split(' ')[1] || name;
}

// A browser with no saved character gets a welcome dialog over the header
// ("Welcome to QE Live! Select an era" / class tiles / BEGIN!). With a
// persistent profile it appears once.
async function dismissWelcome(page, qeSpec) {
    const welcome = page.getByText('Welcome to QE Live');
    if (!(await welcome.count())) return false;
    const label = welcomeTileLabel(qeSpec);
    await page
        .getByText(new RegExp('^' + label + '$', 'i'))
        .first()
        .click();
    await page.getByRole('button', { name: /begin/i }).click();
    await welcome.waitFor({ state: 'hidden', timeout: 10000 });
    return true;
}

// The header's "Current Spec" control, which is QE Live's OWN way to change
// character: `QEHeaderClassSelector.js` line 37 is its `InputLabel` and lines
// 38-60 the MUI `Select` whose `onChange` is `setSelectedSpec`, wired in
// `QEHeader.js` lines 131-135 to `props.handlePickPlayerSpec` - `App.tsx` lines
// 273-277, which looks the character of that spec up and makes it active. The
// character exists whatever the browser profile held: `PlayerChars.init`
// auto-adds every one of `CONSTANTS.specs` that local storage is missing
// (`General/Modules/Player/PlayerChars.ts` lines 44-54). Nothing here touches
// local storage and nothing here patches his source.
const CURRENT_SPEC_LABEL = 'Current Spec';

// `QEHeader.js` renders its `drawer` TWICE - once inside the mobile `Drawer`,
// which is `keepMounted` (line 297) and so is in the DOM at every width, and
// once in the desktop `Grid` at line 315 - so the label matches two controls and
// one of them is `display: none`. `.first()` would be the hidden one, so the
// visible one is found rather than assumed.
async function specSelect(page) {
    const all = page.getByLabel(CURRENT_SPEC_LABEL, { exact: true });
    const total = await all.count();
    for (let i = 0; i < total; i++) {
        const one = all.nth(i);
        if (await one.isVisible().catch(() => false)) return one;
    }
    throw new ForkError(
        total
            ? `QE Live's header has ${total} "${CURRENT_SPEC_LABEL}" controls and none of them is visible (QEHeader.js renders its drawer twice); the companion will not guess at which one changes the character`
            : `QE Live's header has no "${CURRENT_SPEC_LABEL}" control (QEHeaderClassSelector.js); the companion will not guess at which control changes the character`,
        DRIVE
    );
}

// How long his menu is given to mount before the click is called a failure.
const SPEC_MENU_TIMEOUT = 10000;

// The option in his open menu whose VISIBLE WORDS are the spec, found by the
// words rather than by the accessible name (C-16b, WKE-625).
//
// Each `MenuItem` is `<Box><ClassIcon name={playerClass}/><Typography>...`
// (QEHeaderClassSelector.js lines 51-60), and `ClassIcon` is an `<img>` whose
// `alt` names the spec in full - `alt: "Restoration Shaman"`, ClassIcons.tsx
// lines 27-33. An `<img alt>` inside an element contributes its alt to that
// element's accessible name, so the option's NAME is the spec twice over
// (`Restoration Shaman Restoration Shaman`) and the old
// `getByRole('option', { name: wanted, exact: true })` matched nothing - which
// is the owner's 2026-09-22 `does not offer "Restoration Shaman"` at exit 5.
//
// `hasText` matches an element's text, and an alt is not text, so the doubling
// cannot reach it. The regex is anchored so the match stays exact on the words:
// a spec is never chosen because it is the beginning of another option.
//
// The header read-back (`select.innerText()`) never had this problem: MUI's own
// `renderValue` puts the same icon in the CLOSED control, but `innerText`
// ignores alt.
function specOption(page, wanted) {
    const escaped = String(wanted).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return page.getByRole('option').filter({ hasText: new RegExp('^\\s*' + escaped + '\\s*$') });
}

// Put QE Live on the profile's character before anything is imported, and say
// which way it went. Returns { spec, was, switched, note }.
//
// The driver does NOT loop: the switch is asked for once, read back once, and a
// `different spec` refusal afterwards is still one `REFUSED` with QE Live's own
// message. Two attempts at the same question would only put his words on the
// log twice.
async function ensureCharacter(page, identity) {
    const wanted = qeSpecOf(identity);
    if (!wanted) return null;
    const select = await specSelect(page);
    const was = String(await select.innerText()).trim();
    if (was === wanted) {
        const note = `${wanted} (already)`;
        return { spec: wanted, was: was, switched: false, note: note };
    }
    await select.click();
    // MUI mounts its `Menu` popover a tick after the click, so at the moment
    // `click()` resolves there are no options in the DOM at all. Until C-16b the
    // count ran at once and could read zero before his menu had rendered.
    const listbox = page.getByRole('listbox').first();
    try {
        await listbox.waitFor({ state: 'visible', timeout: SPEC_MENU_TIMEOUT });
    } catch (e) {
        throw new ForkError(
            `QE Live's "${CURRENT_SPEC_LABEL}" control was clicked and no menu opened within ${SPEC_MENU_TIMEOUT}ms; nothing was chosen`,
            DRIVE
        );
    }
    const option = specOption(page, wanted);
    if (!(await option.count())) {
        throw new ForkError(
            `QE Live's "${CURRENT_SPEC_LABEL}" menu does not offer "${wanted}", so it cannot be put on this character; it rates the specs its own menu lists and no others`,
            REFUSED
        );
    }
    await option.first().click();
    const now = String(await (await specSelect(page)).innerText()).trim();
    if (now !== wanted) {
        throw new ForkError(
            `QE Live was asked for "${wanted}" and its header still says "${now}"; refusing to import a profile against a character the driver did not choose`,
            DRIVE
        );
    }
    const note = `${wanted} (switched from ${was})`;
    return { spec: wanted, was: was, switched: true, note: note };
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

// -------------------------------------------------------------------------
// Which items QE Live is allowed to see (WKE-558, C-8).
//
// TopGear.tsx line 177: `topGearCap = patronCaps[patronStatus] || 30`, and
// line 739 lets a card become active only while `selectedItemCount <
// topGearCap`. So a non-patron's Top Gear answers a question about THIRTY
// items, and which thirty is the driver's to decide. Until C-8 it was page
// order - his slot list, Head first - so with 45+ candidates the late slots
// and every Catalyst clone were never in his set builder's pool, and nothing
// in the export said so (2026-09-09 22:48: 57 cards, 30 selected, `catalyzed`
// scoring identically to `asOffered`).
//
// Nothing here is a healer value. This file never scores an item and never
// orders two items by what they are worth; it decides which items QE Live is
// ASKED about, and then says out loud which ones it was not.
//
// The issue that asked for this (WKE-558) expected the vault items to be
// outside the 30 and asked for active bag items to be deselected to make room.
// Both are refuted by his own import engine, read 2026-09-10:
//
//   * `SimCImportEngine.ts` line 712, `item.active = protoItem.itemEquipped ||
//     item.vaultItem` - a vault item is ACTIVE from the moment it is imported,
//     so it was never the cap that kept the Spaulders out of the answer;
//   * `Item.ts` line 174, `clonedItem.active = this.active` - an auto-Catalyst
//     clone (`SimCImportEngine.ts` lines 253-263, cloned out of every
//     catalysable item) inherits its source's flag, which is why the Catalyst
//     passes opened with twenty active cards where `asOffered` opened with
//     nineteen (15 equipped + 4 vault, plus one clone of an active source).
//
// So no card that is active at import is a bag item, and deselecting one would
// drop the character's own gear - or a vault option - out of the pool to make
// room for something from his bags. Nothing here ever deselects. What the cap
// really costs is the clones and the bag items, and that is what the order
// below spends the room on.
const CARD = '.MuiCardActionArea-root';

// Everything the decision needs about one card, read out of the page in one
// pass rather than one locator call at a time (57 cards x three round trips is
// a second of browser on every one of the four imports a run makes).
//
// Read from MiniItemCard.tsx, 2026-09-10:
//   * the Card's own class is `classes[className]` (line 224), one of root /
//     selected / vault / selectedVault / exclusive / selectedExclusive /
//     offspec - so "selected" in the class means active and "vault" in it means
//     a Great Vault item. `classes.catalyst` is declared and never reached by
//     that ternary, so a clone CANNOT be recognised by its class;
//   * every card wraps its icon in `WowheadTooltip` (line 296), which renders
//     `<a data-wowhead="item=<id>&ilvl=<level>&bonus=...&original-item=<id>">`
//     (WHTooltips.tsx line 33). `original-item` is `item.catalyzedID`, which
//     `convertToTier` sets to the pre-Catalyst id (Item.ts line 268) - so it is
//     on a clone and on nothing else;
//   * the slot is not on the card at all. TopGear.tsx line 791 renders one
//     `Typography h6` per slot above that slot's grid of cards, so the slot is
//     the nearest heading above the card, found by walking up.
// The DOM half, and nothing else: one `page.evaluate` that hands back the raw
// strings each card carries - its wrapper's class, its `data-wowhead`
// attribute, its slot heading and its own text lines. Every decision about what
// those strings MEAN is made in Node by `cardFromRow` below, where a test can
// reach it; a regex that only ever runs inside a browser is a regex nothing can
// prove red (C-10, WKE-567).
async function readCardRows(page) {
    return page.evaluate((selector) => {
        const areas = Array.prototype.slice.call(document.querySelectorAll(selector));
        return areas.map((area, index) => {
            const card = area.parentElement;
            let slot = '';
            let node = card;
            while (node && node !== document.body) {
                const heading = node.querySelector(':scope > .MuiTypography-h6');
                if (heading) {
                    slot = (heading.textContent || '').trim();
                    break;
                }
                node = node.parentElement;
            }
            const link = area.querySelector('a[data-wowhead]');
            return {
                index: index,
                slot: slot,
                cls: (card && card.getAttribute('class')) || '',
                wowhead: (link && link.getAttribute('data-wowhead')) || '',
                lines: (area.innerText || '')
                    .split('\n')
                    .map((line) => line.trim())
                    .filter(Boolean),
            };
        });
    }, CARD);
}

// What one `data-wowhead` attribute says about an item: his own item ID, his
// own item level, the bonus IDs the item was imported with, and - on a Catalyst
// clone and on nothing else - the ID of the item the clone was made from.
//
// The bonus IDs are why this exists (C-10, WKE-567). `excluded` used to travel
// as a name and a level, so "was THIS item left out of the pool" could only be
// asked by name, and two same-named items at one level answer it wrongly. With
// the ID and the bonus IDs the addon builds the same `ns.ItemKey` it builds for
// everything else and the question is an identity comparison.
//
// Sorted here, because `ns.ItemKey` sorts and a key that disagrees about order
// is a key that never matches. Numbers only: a bonus list is `1:2:3` on his
// link, and anything that is not a run of digits is not a bonus ID.
function parseWowhead(data) {
    const text = typeof data === 'string' ? data : '';
    const id = /(?:^|[?&])item=(\d+)/.exec(text);
    const ilvl = /[?&]ilvl=(\d+)/.exec(text);
    const bonus = /[?&]bonus=([0-9:.]*)/.exec(text);
    const original = /[?&]original-item=(\d+)/.exec(text);
    const originalItem = original && Number(original[1]) > 0 ? Number(original[1]) : null;
    return {
        itemID: id ? Number(id[1]) : null,
        level: ilvl ? Number(ilvl[1]) : null,
        bonusIDs: bonus
            ? bonus[1]
                  .split(/[^0-9]+/)
                  .filter((part) => part.length)
                  .map(Number)
                  .sort((a, b) => a - b)
            : [],
        originalItem: originalItem,
    };
}

// One raw row -> the card record the rest of this file works in. Pure, so the
// whole read is testable without a browser.
//
// `level` prefers his tooltip's `ilvl` and falls back to the bare number on the
// card, which is the level he prints on it. `catalyst` is `original-item`,
// which `convertToTier` sets on a clone and on nothing else (Item.ts line 268);
// the class cannot say - `classes.catalyst` is declared and unreachable
// (MiniItemCard.tsx line 224).
function cardFromRow(row) {
    const cls = (row && row.cls) || '';
    const lines = (row && Array.isArray(row.lines) ? row.lines : []).filter((line) => typeof line === 'string');
    const number = lines.filter((line) => /^\d+$/.test(line))[0];
    const name = lines.filter((line) => !/^\d+$/.test(line))[0] || '';
    const tooltip = parseWowhead(row && row.wowhead);
    return {
        index: row && row.index,
        slot: (row && row.slot) || '',
        name: name,
        level: tooltip.level !== null ? tooltip.level : number ? Number(number) : null,
        itemID: tooltip.itemID,
        bonusIDs: tooltip.bonusIDs,
        originalItem: tooltip.originalItem,
        active: /selected/i.test(cls),
        vault: /vault/i.test(cls),
        catalyst: tooltip.originalItem !== null,
    };
}

async function readCards(page) {
    return (await readCardRows(page)).map(cardFromRow);
}

// One card as the log and the verdict file name it: "Head - Lynx Spaulders 678".
function cardText(card) {
    const parts = [card.slot || 'unknown slot', '-', card.name || 'item ' + (card.itemID === null ? '?' : card.itemID)];
    if (card.level) parts.push(String(card.level));
    if (card.vault) parts.push('(vault)');
    if (card.catalyst) parts.push('(catalyst)');
    return parts.join(' ');
}

// -------------------------------------------------------------------------
// Which of the items the profile sent QE Live kept (C-14a, WKE-626).
//
// His importer keeps only items it knows: `25 cards from 33 items` on the
// owner's 2026-09-22 Shaman, and nothing in the run said which eight went
// missing. Both lists are already in hand after an import - the profile text
// the run was given, and the cards `probePool` read - so this is a read of two
// lists and not a new interaction with his page.
//
// **Matched by identity, not by name.** The issue asked for a diff "by name and
// item level, which both sides carry"; the profile's item LINES carry no name
// at all (his own read is `feet=,id=235964`), only a `# Mysterious Striders
// (139)` comment above each one, which is the addon's word for the item and not
// QE Live's. So the match is `simc-profile.itemKey` - the item ID and the
// sorted bonus IDs, the same identity `ns.ItemKey` and C-10's `excluded` list
// are built on - and the names are only ever printed, never compared.
//
// Catalyst clones are left out of the pool side: `SimCImportEngine.ts:253-263`
// makes them out of items it already kept, so a clone is a card QE Live
// invented and never one of the 33 the profile sent. Its source card is on the
// page beside it and is what matches.
const PROFILE_NAME_LINE = /^#\s*(.*\S)\s+\((\d+)\)\s*$/;

function profileItems(profileText) {
    const lines = String(profileText || '').split(/\r?\n/);
    const items = [];
    for (const [key, rows] of simcProfile.collectItems(String(profileText || ''))) {
        for (const row of rows) {
            const named = PROFILE_NAME_LINE.exec(lines[row.index - 1] || '');
            items.push({
                key: key,
                slot: row.slot || '',
                section: row.section || '',
                index: row.index,
                name: named ? named[1] : '',
                level: named ? Number(named[2]) : null,
            });
        }
    }
    return items.sort((a, b) => a.index - b.index);
}

// One card's identity in the profile's own key shape.
function cardKey(card) {
    const bonus = Array.isArray(card.bonusIDs) ? card.bonusIDs.slice().sort((a, b) => a - b).join(':') : '';
    const id = card.itemID === null || card.itemID === undefined ? '?' : card.itemID;
    return bonus ? `${id}:${bonus}` : String(id);
}

// { sent, taken, missing } - a multiset difference, because two rings of one ID
// and one bonus list are two items and QE Live may have kept one of them.
function poolDrop(profileText, cards) {
    const sentItems = profileItems(profileText);
    const held = new Map();
    for (const card of (cards || []).filter((card) => !card.catalyst)) {
        const key = cardKey(card);
        held.set(key, (held.get(key) || 0) + 1);
    }
    const missing = [];
    for (const item of sentItems) {
        const left = held.get(item.key) || 0;
        if (left > 0) held.set(item.key, left - 1);
        else missing.push(item);
    }
    return { sent: sentItems.length, taken: sentItems.length - missing.length, missing: missing };
}

// One dropped item as the log names it, from the profile's own comment; an
// item whose line had no comment above it is named by its ID rather than left
// blank.
const DROP_NAMES_LOGGED = 15;

function dropText(item) {
    const name = item.name || `item ${item.key.split(':')[0]}`;
    return item.level ? `${name} (${item.level})` : name;
}

function dropLine(drop) {
    if (!drop || !drop.missing.length) return null;
    const names = drop.missing.slice(0, DROP_NAMES_LOGGED).map(dropText);
    const rest = drop.missing.length - names.length;
    return (
        `QE Live did not take ${drop.missing.length} of ${drop.sent} imported items: ` +
        names.join(', ') +
        (rest ? `, and ${rest} more` : '')
    );
}

// -------------------------------------------------------------------------
// Which pass is which (WKE-572, C-11).
//
// One Top Gear run answers a question about thirty items and the character owns
// more; C-8 chose which thirty and said out loud which ones it did not. That
// left 22 trinket rows and a pile of belts, boots and rings reading "not rated
// - beyond the rating's item limit" on the owner's 2026-09-14 run, which is a
// verdict that cannot speak about gear the player is holding.
//
// So a document is no longer the end of a Top Gear run: a run is a SEQUENCE of
// passes. Pass 1 is exactly what C-8 built. Each later pass keeps the same
// baseline - the cards QE Live made active at import, which his own engine says
// are the equipped set, the vault options and any clone of one of those
// (SimCImportEngine.ts:712, Item.ts:174) - deselects the bag items the previous
// pass activated, and spends the room on the cards no pass has seen yet. Every
// pass is its own document over its own pool. NOTHING is merged and no two
// numbers are ever combined: Lootpath never computes a healer value.
//
// A card's identity across the passes of one import. The index is his grid's
// own order, and the ID and the sorted bonus list are what the card carries;
// all three, because two rings of one ID at one level are two cards and a pass
// that confused them would rate one twice and the other never.
function cardIdent(card) {
    const id = card && (card.itemID === null || card.itemID === undefined) ? '?' : card.itemID;
    const bonus = card && Array.isArray(card.bonusIDs) ? card.bonusIDs.join(':') : '';
    return [card ? card.index : '?', id, bonus].join('|');
}

// Every card's ident in page order, which is what a later pass checks the grid
// against: his page rebuilds it on each navigation, and a pass that clicked by
// position on a grid that had moved would choose a pool nobody named.
function identsOf(cards) {
    return cards.map(cardIdent);
}

// The cards QE Live made active at import. Read once per import, before any
// document, because after the first pass "active" means "pass 1 clicked it".
function baselineOf(cards) {
    return new Set(cards.filter((card) => card.active).map(cardIdent));
}

// The pure half: cards in, { keep, activate, deselect, excluded } out. No page,
// no clicking, no scoring - three named groups and then a fair walk over the
// rest.
//
// The order:
//   1. every card in the baseline stays active. That is the character's
//      equipped set, his vault options, and any clone of one of those - the
//      three things the scenarios exist to ask about. With no baseline given
//      the baseline is "whatever is active", which is what pass 1 reads.
//   2. a vault item that is somehow NOT active. His import engine makes this
//      group empty today; it is first anyway, because if that line ever changes
//      the vault must not be the thing that falls out.
//   3. every Catalyst clone. These are the whole subject of the `catalyzed` and
//      `thisWeek` scenarios (C-6), and a run that spends its room on bags
//      answers those two questions with the `asOffered` answer.
//   4. the bag items, one per slot in turn rather than in page order. Page
//      order is his slot list, so it fills Head to the cap and leaves the
//      weapons unasked; a round over the slots gives every slot its best-placed
//      card before any slot gets a second, and inside a slot his own order is
//      kept. This is not a ranking: it is a queue that cannot starve a slot.
//
// `options.done` is every non-baseline card an earlier pass already considered,
// by ident. They are out of `rest`, so no card is asked about twice and every
// pass moves forward. `deselect` is what the previous pass left active and this
// one does not want: empty on pass 1 of a fresh import by construction, since
// the baseline IS the active set there.
function chooseSelection(cards, cap, options) {
    const opts = options || {};
    const baseline = opts.baseline || null;
    const done = opts.done || null;
    const isBase = (card) => (baseline ? baseline.has(cardIdent(card)) : card.active);
    const keep = cards.filter(isBase);
    const rest = cards.filter((card) => !isBase(card) && !(done && done.has(cardIdent(card))));
    const vault = rest.filter((card) => card.vault);
    const catalyst = rest.filter((card) => !card.vault && card.catalyst);
    const bags = rest.filter((card) => !card.vault && !card.catalyst);

    // One round over the slots at a time, in the order the slots first appear
    // on his page, so a slot with twelve rings cannot take the room a slot with
    // one weapon needs.
    const bySlot = new Map();
    for (const card of bags) {
        const slot = card.slot || '';
        if (!bySlot.has(slot)) bySlot.set(slot, []);
        bySlot.get(slot).push(card);
    }
    const rounds = [];
    let more = true;
    while (more) {
        more = false;
        for (const queue of bySlot.values()) {
            if (!queue.length) continue;
            rounds.push(queue.shift());
            if (queue.length) more = true;
        }
    }

    const wanted = [...vault, ...catalyst, ...rounds];
    const room = Math.max(0, cap - keep.length);
    const activate = wanted.slice(0, room);
    const wantedActive = new Set([...keep, ...activate].map(cardIdent));
    return {
        keep: keep,
        activate: activate,
        // Everything the page has active that this pass's pool does not hold.
        // The room for a later pass's cards has to come from somewhere, and the
        // only cards it may come from are the ones an earlier pass CLICKED: a
        // baseline card is the character's own gear or a vault option and is
        // never deselected here (C-8's reading of SimCImportEngine.ts:712).
        deselect: cards.filter((card) => card.active && !wantedActive.has(cardIdent(card))),
        excluded: wanted.slice(room),
        room: room,
        cap: cap,
    };
}

// What the verdict file and the addon call one left-out card. `level` is QE
// Live's own item level for it, carried like every other number in that file.
//
// Since C-10 (WKE-567) the identity travels too: `itemID` and the sorted
// `bonusIDs` are what `ns.ItemKey` is built from, so the addon can ask "was
// THIS item left out" of an item it is holding rather than of a name. A name
// and a level cannot answer it - two rings of one name at one level are one
// question with two answers - and the road surfaces have to say "not rated -
// beyond the rating's item limit" about one item and not about its twin.
// `originalItem` is the item a Catalyst clone was made from, carried because
// the clone's own ID is a tier piece the character does not own.
//
// Since C-11 (WKE-572) the same shape carries the other half of the pool: the
// cards a pass DID consider. One shape for both, because the addon asks the
// same identity question of each list and a second shape would be a second
// answer to it.
function entriesFrom(cards) {
    return cards.map((card) => ({
        slot: card.slot || '',
        name: card.name || '',
        level: card.level || null,
        itemID: card.itemID === undefined ? null : card.itemID,
        bonusIDs: Array.isArray(card.bonusIDs) ? card.bonusIDs.slice() : [],
        originalItem: card.originalItem === undefined ? null : card.originalItem,
        vault: !!card.vault,
        catalyst: !!card.catalyst,
    }));
}

// The driving half. Clicks exactly the cards `chooseSelection` named, reads the
// counter back after each one, and refuses a click that did not move it: a card
// whose state was misread would otherwise be DEselected here, and the run would
// export a document about a pool nobody chose.
//
// `options.baseline` is the ident set read at import; `options.done` is what
// earlier passes already asked about; `options.expect` is the ident list the
// previous pass read the grid as, checked before anything is clicked because
// every click here is by POSITION and a grid that moved would select the wrong
// cards in silence.
async function selectItems(page, log, options) {
    const opts = options || {};
    const pass = opts.pass || 1;
    const counter = page.getByText(/Selected Items:\s*\d+\/\d+/).first();
    await counter.waitFor({ timeout: 10000 });
    const readCount = async () => {
        const m = (await counter.innerText()).match(/(\d+)\/(\d+)/);
        return { n: +m[1], cap: +m[2] };
    };
    let { n, cap } = await readCount();
    const cards = await readCards(page);
    if (!cards.length) {
        throw new ForkError(
            `QE Live's Top Gear page shows "Selected Items: ${n}/${cap}" and no ${CARD} cards at all (MiniItemCard.tsx); refusing to run Top Gear over a pool it could not read`,
            DRIVE
        );
    }
    const idents = identsOf(cards);
    if (opts.expect && opts.expect.join(',') !== idents.join(',')) {
        throw new ForkError(
            `QE Live's Top Gear grid changed between pass ${pass - 1} and pass ${pass} (${opts.expect.length} cards then, ${idents.length} now);` +
                ` refusing to click by position on a grid that moved`,
            DRIVE
        );
    }
    const plan = chooseSelection(cards, cap, { baseline: opts.baseline || null, done: opts.done || null });
    if (plan.keep.length !== n && log && pass === 1) {
        // Not fatal: his counter is `getSelectedItems().length` over the whole
        // player and the cards are what this page drew, so a difference is
        // worth saying rather than worth stopping for. Only on pass 1: later
        // passes deliberately hold a pool the import-time count never had.
        log.warn(`  QE Live's counter says ${n} selected, and ${plan.keep.length} of the ${cards.length} cards look active`);
    }
    const locators = page.locator(CARD);
    // Deselect first, then select: the cap is a hard stop in his own page
    // (TopGear.tsx line 739 lets a card become active only while
    // `selectedItemCount < topGearCap`), so a click that wants room has to be
    // made after the room exists.
    let dropped = 0;
    for (const card of plan.deselect) {
        const before = n;
        await locators.nth(card.index).click();
        ({ n, cap } = await readCount());
        if (n !== before - 1) {
            throw new ForkError(
                `deselecting "${cardText(card)}" moved QE Live's counter from ${before} to ${n}, not to ${before - 1}; refusing to run Top Gear over a pool the driver did not choose`,
                DRIVE
            );
        }
        dropped++;
    }
    let clicked = 0;
    for (const card of plan.activate) {
        const before = n;
        await locators.nth(card.index).click();
        ({ n, cap } = await readCount());
        if (n !== before + 1) {
            throw new ForkError(
                `clicking "${cardText(card)}" moved QE Live's counter from ${before} to ${n}, not to ${before + 1}; refusing to run Top Gear over a pool the driver did not choose`,
                DRIVE
            );
        }
        clicked++;
    }
    const excluded = entriesFrom(plan.excluded);
    const considered = entriesFrom([...plan.keep, ...plan.activate]);
    if (log) {
        const vaults = excluded.filter((card) => card.vault).length;
        const clones = excluded.filter((card) => card.catalyst).length;
        log.info(
            `  top gear pool (pass ${pass}): ${n}/${cap} selected of ${cards.length} cards` +
                ` (${plan.keep.length} baseline, ${clicked} clicked, ${dropped} deselected, ${excluded.length} still to ask about` +
                `${vaults ? `, ${vaults} of them vault items` : ''}${clones ? `, ${clones} of them Catalyst clones` : ''})`
        );
        for (const card of plan.activate) log.info(`    pass ${pass} considers: ${cardText(card)}`);
        for (const card of plan.excluded) log.info(`    not considered yet: ${cardText(card)}`);
    }
    return {
        pass: pass,
        selected: n,
        cap: cap,
        cards: cards.length,
        clicked: clicked,
        deselected: dropped,
        active: plan.keep.length,
        idents: idents,
        // The idents this pass spent its room on, which is what the NEXT pass
        // adds to `done`. The baseline is not in it: the baseline is in every
        // pass's pool by design, and calling it done would empty the pool.
        activated: plan.activate.map(cardIdent),
        considered: considered,
        excluded: excluded,
    };
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

// C-14 (WKE-603). **The driver never clicks a disabled button.**
//
// On 2026-09-16 the owner's profile was short one worn slot, QE Live disabled
// `Go!` for the pass whose selection did not fill it, and Playwright clicked the
// disabled button for twenty seconds before it gave up - twice, sixty seconds of
// a run each time, ending in `locator.click: Timeout 20000ms exceeded` and a
// page of call log (`Data/companion.log`, 21:26-21:28Z).
//
// A disabled `Go!` is not a timing problem and waiting cannot fix it: QE Live
// has decided it will not rate this pool. So the state is READ first and the
// refusal is one sentence naming what QE Live would not run. `REFUSED`, not
// `DRIVE`: the profile is the thing that is wrong, which is the same class as
// QE Live refusing the import outright.
// -------------------------------------------------------------------------
// C-14a (WKE-626). **The refusal says what QE Live says.**
//
// On 2026-09-22 the owner refreshed on a level-81 Restoration Shaman in fresh
// leveling gear. The profile was whole - all sixteen worn slots, so C-14's
// mirror passed, correctly - and QE Live built 25 cards out of the 33 items it
// was sent, because its importer keeps only items it knows and Midnight
// leveling gear is mostly items it does not. Feet ended at zero, `checkSlots`
// reported it, `Go!` stayed disabled and the run said `QE Live's Go! button is
// disabled for this pool - 25 of 30 selected, 6 baseline` and nothing else.
//
// QE Live prints the answer on the same row as the button, so it is READ rather
// than guessed at: `TopGear.tsx:844-846` renders `getErrorMessage()` in a
// `<Typography variant="subtitle1" color="primary">` immediately before the
// `Go!` button at `:848-856`, whose `disabled` is `checkSlots(gameType).length
// > 0 || !btnActive` (`:852`).
//
// TWO PREMISES REFUTED, both read out of his own source on 2026-09-22:
//
//   * the words are NOT `Error: Add item - feet, finger, weapon`.
//     `t("TopGear.itemMissingError")` (`locale/en/translate.json:595`) is that
//     string, and it is only ever assigned to `checkSlots`'s LOCAL
//     `errorMessage` (`:351`, `:355`) - whose `setErrorMessage` is commented
//     out at `:361`, and whose state is rendered nowhere. What the row actually
//     shows is `getErrorMessage()` (`:367-389`), which builds `"Add "` and
//     appends one slot at a time.
//   * the slots are NOT the SimC tokens. `getTranslatedSlotName`
//     (`locale/slotsLocale.ts`) maps `feet` to **Boots** and `finger` to
//     **Ring**, and the weapon rule (`:381-383`) appends a bare ` Weapon`. So
//     his line reads `Add Boots, Ring,  Weapon` - two spaces and all.
//
// A locator built on the expected prefix would have matched nothing on his
// page, which is the C-16b lesson again. So the element is found by the class
// MUI gives `variant="subtitle1"` and filtered on its VISIBLE words with an
// anchored regex, the same shape `specOption` uses. The only other
// `subtitle1` on `/topgear` is `MiniItemCard.tsx:345`, which renders `""`
// inside a `visibility: hidden` wrapper and cannot start with `Add`.
const GO_ERROR = '.MuiTypography-subtitle1';
const GO_ERROR_WORDS = /^\s*Add\s+\S/;

// `getErrorMessage`'s other branch: more than ten missing slots means nothing
// was imported at all (`TopGear.tsx:370-372`), and "an item in: Import String"
// is not a sentence about slots. It is left to the verbatim half.
const GO_ERROR_NOTHING = /^Add Import String$/i;

// QE Live's line -> the slots it named, in its order and its words. Pure, so
// the parsing is proven without a browser (C-10's rule); the DOM half below is
// one locator and no logic.
function goErrorSlots(text) {
    const words = typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '';
    if (!GO_ERROR_WORDS.test(words) || GO_ERROR_NOTHING.test(words)) return [];
    return words
        .slice('Add'.length)
        .split(',')
        .map((slot) => slot.trim())
        .filter(Boolean);
}

// The words beside the button, verbatim but whitespace-collapsed - his own line
// carries a double space before ` Weapon` and a status file is one sentence.
// A page that has no such element answers the empty string: nothing is read
// twice and no failure here may turn a refusal into a drive error.
async function readGoError(page) {
    try {
        const words = page.locator(GO_ERROR).filter({ hasText: GO_ERROR_WORDS });
        if (!(await words.count())) return '';
        return String(await words.first().innerText())
            .replace(/\s+/g, ' ')
            .trim();
    } catch {
        return '';
    }
}

// What the PLAYER is told, in the addon's voice: no source named, and never a
// word about a plan. The log keeps QE Live's name and QE Live's line.
function goRefusalForPlayer(slots, drop) {
    const sentence = `couldn't rate this gear: no usable item in ${slots.join(', ')}`;
    if (!drop || !drop.sent || !drop.missing || !drop.missing.length) return sentence;
    return `${sentence} - ${drop.missing.length} of the ${drop.sent} pieces sent weren't recognised`;
}

// C-14b (WKE-627). The same refusal as FIELDS, for the status file: the reason
// token the addon switches a screen on, the slots in QE Live's own display
// words and its own order, and the two counts. The counts are only written when
// the import was actually probed - a pass with no `drop` gives the slots alone,
// for the same reason the sentence above stops after them: a figure nobody
// measured is not written.
const REASON_UNKNOWN_GEAR = 'unknown-gear';

function goRefusalFields(slots, drop) {
    const fields = { reason: REASON_UNKNOWN_GEAR, missingSlots: slots.slice() };
    if (drop && drop.sent && drop.missing) {
        fields.sent = drop.sent;
        fields.notTaken = drop.missing.length;
    }
    return fields;
}

// C-14 (WKE-603). **The driver never clicks a disabled button.**
//
// On 2026-09-16 the owner's profile was short one worn slot, QE Live disabled
// `Go!` for the pass whose selection did not fill it, and Playwright clicked the
// disabled button for twenty seconds before it gave up - twice, sixty seconds of
// a run each time, ending in `locator.click: Timeout 20000ms exceeded` and a
// page of call log (`Data/companion.log`, 21:26-21:28Z).
//
// A disabled `Go!` is not a timing problem and waiting cannot fix it: QE Live
// has decided it will not rate this pool. So the state is READ first and the
// refusal is one sentence naming what QE Live would not run. `REFUSED`, not
// `DRIVE`: the profile is the thing that is wrong, which is the same class as
// QE Live refusing the import outright.
//
// Since C-14a that sentence carries his reason too, when his page gives one;
// when it does not, it is exactly the line it has always been.
async function clickGo(page, what, options) {
    const button = page.getByRole('button', { name: 'Go!' });
    if (!(await button.isEnabled())) {
        const words = await readGoError(page);
        const slots = goErrorSlots(words);
        if (!slots.length) {
            throw new ForkError(`QE Live's Go! button is disabled ${what}`, REFUSED);
        }
        throw new ForkError(
            `QE Live's Go! button is disabled ${what} - it wants an item in: ${slots.join(', ')} (its own words: "${words}")`,
            REFUSED,
            goRefusalForPlayer(slots, options && options.drop),
            goRefusalFields(slots, options && options.drop)
        );
    }
    await button.click();
}


// Every Top Gear document one import produces, in pass order (C-11, WKE-572).
//
// The document AND the pool it was produced over (C-8): a Top Gear answer that
// left items out has to be able to say which, so `excluded` travels with the
// JSON from here all the way to the addon's own note - and since C-11 so does
// `considered`, because an item's rating comes from the pass that saw it and a
// document that cannot say what it saw cannot be asked.
//
// The loop stops on the first of three things: nothing left out, no room past
// the baseline to make progress with, or the configured bound. The bound is
// logged when it is reached, because leftovers after the last pass are the one
// case where "not rated - beyond the rating's item limit" is still the truth.
async function runTopGear(page, log, options) {
    const opts = options || {};
    const baseline = opts.baseline || null;
    const maxPasses = Math.max(1, Number(opts.maxPasses) || 1);
    const done = new Set();
    const passes = [];
    let expect = null;
    for (let pass = 1; pass <= maxPasses; pass++) {
        await goTo(page, '/topgear');
        const selection = await selectItems(page, log, { pass, baseline, done, expect });
        expect = selection.idents;
        if (pass > 1 && !selection.activated.length) {
            // The baseline fills the cap on its own, so no later pass can ask
            // about anything new. Saying so beats producing a second document
            // over the first document's pool.
            if (log) {
                log.warn(
                    `  pass ${pass} has no room past the ${selection.active} baseline cards in QE Live's ${selection.cap}-item limit;` +
                        ` ${selection.excluded.length} cards stay unasked`
                );
            }
            break;
        }
        for (const ident of selection.activated) done.add(ident);
        await clickGo(
            page,
            `for this pool - ${selection.selected} of ${selection.cap} selected, ${selection.active} baseline`,
            // C-14a (WKE-626): the import's own drop count, so a refusal can
            // say how much of what was sent QE Live never took.
            { drop: opts.drop || null }
        );
        await page.waitForURL((u) => /\/report\/[a-z0-9]+/.test(u.pathname), { timeout: 120000 });
        passes.push({
            pass: pass,
            json: await readJson(page),
            considered: selection.considered,
            excluded: selection.excluded,
        });
        if (!selection.excluded.length) break;
        if (pass === maxPasses && log) {
            log.warn(
                `  stopping at pass ${maxPasses} (the configured bound) with ${selection.excluded.length} cards still unasked`
            );
        }
    }
    return passes;
}

// The pool one pass's import built, read and nothing else (C-12, WKE-577).
//
// The three what-ifs are gated on their own question now, and the only thing
// that can answer "is there anything here to catalyse" or "is anything here
// below its cap" is QE Live: Catalyst eligibility is his `Item.canBeCatalyzed`
// and an upgrade cap is his `CONSTANTS.itemLevelCaps`, and Lootpath restates
// neither. So after the import the driver opens Top Gear, reads the cards it
// already knows how to read (C-8, C-10) and counts. Nothing is clicked, nothing
// is scored, and no document is produced by this.
async function probePool(page) {
    await goTo(page, '/topgear');
    return readCards(page);
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
    await clickGo(page, `for this Upgrade Finder run${chosen ? ` ("${chosen.label}")` : ''}`);
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
    // Who this run is for (C-16, WKE-619). A class QE Live has no character for
    // is refused HERE, before a browser is opened: nothing downstream could do
    // anything but open a page and read a menu that was never going to name it,
    // and H-1's healing gate should have stopped the profile long before.
    // `REFUSED`, not `DRIVE`, because the profile is the thing that is wrong.
    const identity = opts.identity || null;
    if (!qeHasClass(identity)) {
        throw new ForkError(
            `QE Live rates healers and has no character for a ${qeClassToken(identity)}; nothing was asked of it`,
            REFUSED
        );
    }
    const qeSpec = qeSpecOf(identity);
    // C-16a (WKE-622): a class whose captures name no spec falls back to QE
    // Live's only healer for it - but he has TWO Priests, and which of them a
    // Priest heals in is not something a companion may guess. Refused in one
    // line, here, for the same reason the check above it is: the browser cannot
    // answer it either.
    if (!qeSpec && qeClassToken(identity)) {
        throw new ForkError(
            `no capture names this ${QE_CLASS_WORD[qeClassToken(identity)]}'s spec - /lootpath refresh in the spec you heal in`,
            REFUSED
        );
    }
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
    // Which named scenarios this run asked and which it did not, with the
    // reason either way (C-12, WKE-577). The caller writes it into the log, the
    // status file and the verdict.
    const scenarios = [];
    // The base pass's pool, by item ID, which is what "below its upgrade cap"
    // is measured against. Only read when some pass is gated on it.
    const needBase = passes.some((pass) => pass.gate && (pass.gate.kind === 'upgrade' || pass.gate.kind === 'either'));
    let baseLevels = null;
    // What was actually asked for, read back off the page, so the verdict file
    // records the run rather than the intention.
    let qeSettings = null;
    // The items QE Live's Top Gear was never shown, out of the base pass (C-8).
    let excluded = null;
    try {
        let done = log.stage('  page load');
        // The CRA dev server holds a hot-reload socket open, so "networkidle"
        // never arrives; wait for the header instead.
        await page.goto(config.forkUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
        await page.getByText(/import gear/i).first().waitFor({ timeout: 120000 });
        timings.push(['page load', done()]);

        done = log.stage('  welcome dialog');
        const hadWelcome = await dismissWelcome(page, qeSpec || 'Restoration Druid');
        const welcomeNote = hadWelcome ? 'answered' : 'none, the browser profile remembered the character';
        timings.push([`welcome dialog: ${welcomeNote}`, done(welcomeNote)]);

        // Before ANY import, because the three checkboxes are not the only
        // state an import is made against: QE Live values the character its
        // header names, and refuses a profile for another one (C-16).
        done = log.stage('  character');
        const character = await ensureCharacter(page, identity);
        if (character) {
            timings.push([`character: ${character.note}`, done(character.note)]);
        } else {
            // A capture too old to name a class or a spec. Nothing is switched
            // and nothing is claimed; the import speaks for itself either way.
            timings.push(['character: not named by the capture', done('not named by the capture')]);
        }

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

            // The pool, when this run needs it (C-12): for a gated pass, to
            // settle its own gate; for the base pass, because the upgrade gate
            // is "higher than the base pass valued it at" and that is the only
            // pass that can say what that was.
            //
            // Read for a third reason since C-11 (WKE-572): a pass that
            // produces Top Gear documents needs the cards QE Live made ACTIVE
            // at import, before anything is clicked, because that set is the
            // baseline every later pass keeps and after pass 1 "active" means
            // "pass 1 clicked it".
            let cards = null;
            const topGearHere = pass.documents.some((planned) => planned.kind === 'topgear');
            if (pass.gate || topGearHere || (needBase && pass.scenario === configLib.DEFAULT_SCENARIO)) {
                done = log.stage(`  pool (${asked})`);
                cards = await probePool(page);
                timings.push([`pool (${asked})`, done(`${cards.length} cards`)]);
            }
            // C-14a (WKE-626): which of the items the profile sent this import
            // kept, said once per import. Two lists already in hand; nothing is
            // asked of his page for it.
            const drop = cards ? poolDrop(profileText, cards) : null;
            const dropped = dropLine(drop);
            if (dropped) log.info(`  ${dropped}`);
            const baseline = cards ? baselineOf(cards) : null;
            if (cards && pass.scenario === configLib.DEFAULT_SCENARIO) {
                baseLevels = configLib.levelsByItem(cards);
            }
            if (pass.scenario) {
                const settled = pass.gate
                    ? configLib.gateVerdict(pass.gate.kind, configLib.poolEvidence(cards, baseLevels))
                    : { ran: true, reason: pass.why || 'asked whatever the pool holds' };
                scenarios.push({ name: pass.scenario, ran: settled.ran, reason: settled.reason });
                log.info(`  ${pass.scenario}: ${settled.ran ? 'asked' : 'SKIPPED'} - ${settled.reason}`);
                if (!settled.ran) continue;
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
                // Only a Top Gear run chooses a pool, so only a Top Gear
                // document carries one; an Upgrade Finder document is about
                // drops and has nothing to leave out (C-8). A Top Gear run is a
                // sequence of passes since C-11 and each pass is its own
                // document; an Upgrade Finder run is one document and pass 1.
                const produced =
                    planned.kind === 'topgear'
                        ? await runTopGear(page, log, { baseline, maxPasses: config.topGearPasses, drop })
                        : [{ pass: 1, json: await runUpgradeFinder(page, planned.keyLevel, log), considered: null, excluded: null }];
                const chars = produced.reduce((total, one) => total + one.json.length, 0);
                timings.push([`${label} (${produced.length} pass${produced.length === 1 ? '' : 'es'}, ${chars} chars)`, done(`${chars} chars`)]);
                for (const one of produced) {
                    // The file-level list is the base pass's LAST pass: it is
                    // what nothing in this run was ever asked about, and that is
                    // the only list "not rated - beyond the rating's item limit"
                    // may be read off now (C-11). The file-level checkbox pair
                    // is chosen the same way and for the same reason.
                    if (one.excluded && (!excluded || pass.scenario === configLib.DEFAULT_SCENARIO)) {
                        excluded = one.excluded;
                    }
                    documents.push({
                        kind: planned.kind,
                        contentType: planned.contentType,
                        keyLevel: planned.keyLevel,
                        scenario: planned.scenario,
                        pass: one.pass,
                        considered: one.considered,
                        excluded: one.excluded,
                        // What the page reported after the click, not what the
                        // pass asked for, so a document says how it was really
                        // produced.
                        qeSettings: settings,
                        json: one.json,
                    });
                }
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
    return { documents, timings, qeSettings, excluded, scenarios };
}

module.exports = {
    run,
    ensureUp,
    isUp,
    readCards,
    readCardRows,
    probePool,
    parseWowhead,
    cardFromRow,
    chooseSelection,
    selectItems,
    runTopGear,
    cardIdent,
    identsOf,
    baselineOf,
    entriesFrom,
    cardText,
    clickGo,
    readGoError,
    goErrorSlots,
    goRefusalFields,
    REASON_UNKNOWN_GEAR,
    goRefusalForPlayer,
    profileItems,
    cardKey,
    poolDrop,
    dropLine,
    GO_ERROR,
    GO_ERROR_WORDS,
    setUpgradeCheckboxes,
    settingsFrom,
    importProfile,
    keyLevelsOfLabel,
    readKeyLevelButtons,
    selectKeyLevel,
    exportedKeyIndex,
    runUpgradeFinder,
    qeSpecOf,
    qeHasClass,
    welcomeTileLabel,
    dismissWelcome,
    specSelect,
    ensureCharacter,
    QE_CLASS_WORD,
    QE_CLASS_SOLE_SPEC,
    CURRENT_SPEC_LABEL,
    CARD,
    CHECKBOX_LABELS,
    KEY_LEVEL_SECTION,
    ForkError,
    UNREACHABLE,
    REFUSED,
    DRIVE,
};
