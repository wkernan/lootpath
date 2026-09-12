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

// The pure half: cards in, { keep, activate, excluded } out. No page, no
// clicking, no scoring - three named groups and then a fair walk over the rest.
//
// The order:
//   1. every card that is already active stays active. That is the character's
//      equipped set, his vault options, and any clone of one of those - the
//      three things the scenarios exist to ask about.
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
function chooseSelection(cards, cap) {
    const keep = cards.filter((card) => card.active);
    const rest = cards.filter((card) => !card.active);
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
    return { keep: keep, activate: wanted.slice(0, room), excluded: wanted.slice(room), room: room, cap: cap };
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
function excludedFrom(cards) {
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
async function selectItems(page, log) {
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
    const plan = chooseSelection(cards, cap);
    if (plan.keep.length !== n && log) {
        // Not fatal: his counter is `getSelectedItems().length` over the whole
        // player and the cards are what this page drew, so a difference is
        // worth saying rather than worth stopping for.
        log.warn(`  QE Live's counter says ${n} selected, and ${plan.keep.length} of the ${cards.length} cards look active`);
    }
    const locators = page.locator(CARD);
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
    const excluded = excludedFrom(plan.excluded);
    if (log) {
        const vaults = excluded.filter((card) => card.vault).length;
        const clones = excluded.filter((card) => card.catalyst).length;
        log.info(
            `  top gear pool: ${n}/${cap} selected of ${cards.length} cards` +
                ` (${plan.keep.length} active on import, ${clicked} clicked, ${excluded.length} left out` +
                `${vaults ? `, ${vaults} of them vault items` : ''}${clones ? `, ${clones} of them Catalyst clones` : ''})`
        );
        for (const card of plan.excluded) log.info(`    not considered: ${cardText(card)}`);
    }
    return { selected: n, cap: cap, cards: cards.length, clicked: clicked, active: plan.keep.length, excluded: excluded };
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

// The document AND the pool it was produced over (C-8): a Top Gear answer that
// left items out has to be able to say which, so `excluded` travels with the
// JSON from here all the way to the addon's own note.
async function runTopGear(page, log) {
    await goTo(page, '/topgear');
    const selection = await selectItems(page, log);
    await page.getByRole('button', { name: 'Go!' }).click();
    await page.waitForURL((u) => /\/report\/[a-z0-9]+/.test(u.pathname), { timeout: 120000 });
    return { json: await readJson(page), excluded: selection.excluded };
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
                // Only a Top Gear run chooses a pool, so only a Top Gear
                // document carries one; an Upgrade Finder document is about
                // drops and has nothing to leave out (C-8).
                const produced =
                    planned.kind === 'topgear'
                        ? await runTopGear(page, log)
                        : { json: await runUpgradeFinder(page, planned.keyLevel, log), excluded: null };
                const json = produced.json;
                timings.push([`${label} (${json.length} chars)`, done(`${json.length} chars`)]);
                // The file-level list is the base pass's, for the same reason
                // the file-level checkbox pair is: it is the pool the answer
                // the Equip Now tab draws was produced over.
                if (produced.excluded && (!excluded || pass.scenario === configLib.DEFAULT_SCENARIO)) {
                    excluded = produced.excluded;
                }
                documents.push({
                    kind: planned.kind,
                    contentType: planned.contentType,
                    keyLevel: planned.keyLevel,
                    scenario: planned.scenario,
                    excluded: produced.excluded,
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
    return { documents, timings, qeSettings, excluded };
}

module.exports = {
    run,
    ensureUp,
    isUp,
    readCards,
    readCardRows,
    parseWowhead,
    cardFromRow,
    chooseSelection,
    selectItems,
    cardText,
    setUpgradeCheckboxes,
    settingsFrom,
    importProfile,
    keyLevelsOfLabel,
    readKeyLevelButtons,
    selectKeyLevel,
    exportedKeyIndex,
    runUpgradeFinder,
    CARD,
    CHECKBOX_LABELS,
    KEY_LEVEL_SECTION,
    ForkError,
    UNREACHABLE,
    REFUSED,
    DRIVE,
};
