// S-1 spike (WKE-531): drive the owner's local QE Live fork headless.
//   node run-fork.js <simc.txt> <outdir> [--headed] [--smoke]
// Reads the SimC string, imports it, runs Top Gear and Upgrade Finder for
// Dungeon and Raid, captures each report's "Copy JSON" text, writes four files
// and prints wall-clock time per step. --smoke only proves the page and the
// import dialog are reachable (no string needed).
//
// Every selector below names the fork file it was read from (branch
// lootpath/upgrade-finder-export, 2026-09-07):
//   "Import Gear" button + #simcentry + "Submit"  SetupAndMenus/SimCraftDialog.js, locale/en/translate.json
//   [aria-label="dungeonLabel"|"raidLabel"]        SetupAndMenus/Header/ContentToggle.js
//   /topgear, /upgradefinder                       SetupAndMenus/QEMainMenu.tsx, App.tsx
//   item cards: CardActionArea, class*="selected"  TopGear/MiniItemCard.tsx
//   "Selected Items: n/cap", "Go!"                 TopGear/TopGear.tsx (topGearCap = 30 for non-patrons)
//   /report/, /upgradereport/                      TopGear.tsx:541, UpgradeFinderFront.js:381
//   "Export" button, "Copy JSON" item              TopGear/Report/MenuDropdown.tsx, TopGearReport.js:298, UpgradeFinderReport.js:156
//   dialog TextField with the JSON                 TopGear/Report/GenericDialog.tsx
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.QE_BASE || 'http://localhost:3000';
const [, , simcPath, outDir, ...flags] = process.argv;
const headed = flags.includes('--headed');
const smoke = flags.includes('--smoke');
const times = [];
let t0 = Date.now();
function lap(label) {
  const now = Date.now();
  times.push([label, now - t0]);
  console.log(`${label}: ${now - t0} ms`);
  t0 = now;
}

// A browser with no saved character gets the welcome dialog ("Welcome to QE
// Live! Select an era" / "Next, pick a class" / BEGIN!) over the header; the
// owner's browser never shows it because their characters are in localStorage.
async function dismissWelcome(page, className) {
  const welcome = page.getByText('Welcome to QE Live');
  if (!(await welcome.count())) return false;
  // The tiles are CSS-uppercased; the DOM text is "Druid".
  await page.getByText(new RegExp('^' + className + '$', 'i')).first().click();
  await page.getByRole('button', { name: /begin/i }).click();
  await welcome.waitFor({ state: 'hidden', timeout: 10000 });
  return true;
}

async function importSimc(page, simc) {
  // The header control is a styled MUI button whose accessible name did not
  // resolve as "Import Gear" in the smoke run; the visible text does.
  await page.getByText(/import gear/i).first().click();
  const box = page.locator('#simcentry');
  await box.waitFor({ state: 'visible', timeout: 10000 });
  await box.fill(simc);
  // SimCraftDialog.js checkboxes, in JSX order: autoUpgradeAll (default off),
  // autoUpgradeVault (default ON), autoCatalyze (off). --no-vault-upgrade
  // unchecks the second so vault options are valued at the level the client
  // reports, like owned gear, instead of at their assumed upgrade.
  // Boxes by JSX order: 0 autoUpgradeAll, 1 autoUpgradeVault, 2 autoCatalyze.
  // --scenario asOffered|catalyzed|maxed sets all three (WKE-540); the older
  // --no-vault-upgrade only unchecks the vault box.
  const scenarioFlag = flags.find((f) => f.startsWith('--scenario='));
  if (scenarioFlag || flags.includes('--no-vault-upgrade')) {
    const name = scenarioFlag ? scenarioFlag.split('=')[1] : 'vaultOff';
    const want = { asOffered: [false, false, false], catalyzed: [false, false, true], maxed: [true, true, true], vaultOff: [null, false, null] }[name];
    if (!want) throw new Error('unknown scenario ' + name);
    const boxes = page.getByRole('checkbox');
    for (let i = 0; i < 3; i++) {
      if (want[i] === null) continue;
      const box = boxes.nth(i);
      if ((await box.isChecked()) !== want[i]) await box.click();
      if ((await box.isChecked()) !== want[i]) throw new Error('checkbox ' + i + ' did not take');
    }
    console.log('  scenario ' + name + ': boxes [all, vault, catalyze] = ' + JSON.stringify(want));
  }
  await page.getByRole('button', { name: 'Submit' }).click();
  // The dialog closes on success; #SimCError carries the reason otherwise.
  await Promise.race([
    box.waitFor({ state: 'hidden', timeout: 20000 }),
    page.locator('#SimCError').filter({ hasText: /\S/ }).waitFor({ timeout: 20000 }).then(async () => {
      throw new Error('QE Live refused the import: ' + (await page.locator('#SimCError').innerText()));
    }),
  ]);
}

// Dungeon/Raid is the "Content" select on the character panel
// (CharacterPanel.tsx ~line 432: TextField select, label t("Content"),
// MenuItems "Dungeon" / "Raid"); Header/ContentToggle.js is not rendered
// anywhere in this build (grep, 2026-09-07).
async function setContent(page, which) {
  const label = which === 'dungeon' ? 'Dungeon' : 'Raid';
  // CharacterPanel is rendered only inside the analysis pages
  // (EmbellishmentAnalysis.js:252, CircletAnalysis.js:225, OmniumFolioAnalysis.js),
  // so the select lives at /embellishments; the dispatch is global.
  // /embellishments crashed in his code with this character (2026-09-07:
  // EmbellishmentAnalysis -> runGenericPPMTrinket -> getDiminishedValue,
  // "Cannot read properties of undefined (reading 'length')"), so the pages
  // are tried in turn and a CRA runtime-error overlay is dismissed.
  let select = page.getByLabel('Content', { exact: true }).first();
  if (!(await select.isVisible().catch(() => false))) {
    for (const route of ['/circlet', '/omniumfolio', '/embellishments']) {
      await goTo(page, route);
      await page.waitForTimeout(400);
      const overlay = page.frameLocator('iframe').getByText('Uncaught runtime errors');
      if (await overlay.count().catch(() => 0)) {
        console.log(`  ${route}: runtime error overlay, skipping`);
        await page.keyboard.press('Escape');
        continue;
      }
      select = page.getByLabel('Content', { exact: true }).first();
      if (await select.isVisible().catch(() => false)) {
        console.log(`  content select found on ${route}`);
        break;
      }
    }
  }
  await select.waitFor({ timeout: 10000 });
  await select.click();
  await page.getByRole('option', { name: label, exact: true }).click();
  await page.waitForTimeout(250);
}

async function goTo(page, route) {
  // In-app navigation keeps React state; a full page load would not.
  const link = page.locator(`a[href="${route}"]`).first();
  if (await link.count()) {
    await link.click();
  } else {
    await page.evaluate((r) => window.history.pushState({}, '', r), route);
    await page.evaluate(() => window.dispatchEvent(new PopStateEvent('popstate')));
  }
  // The app is served under /live/ (homepage), so paths are matched by inclusion.
  await page.waitForURL((u) => u.pathname.includes(route), { timeout: 10000 });
}

async function selectItems(page) {
  // Click every card that is not already active until the cap is reached.
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

async function readCopyJson(page) {
  await page.getByRole('button', { name: 'Export' }).first().click();
  await page.getByRole('menuitem', { name: 'Copy JSON' }).click();
  const field = page.locator('.MuiDialog-root textarea').first();
  await field.waitFor({ timeout: 10000 });
  const text = await field.inputValue();
  await page.keyboard.press('Escape');
  return text;
}

async function runTopGear(page, tag) {
  await goTo(page, '/topgear');
  const sel = await selectItems(page);
  lap(`${tag} top gear: selected ${sel.selected}/${sel.cap} (${sel.cards} cards, ${sel.clicked} clicked)`);
  await page.getByRole('button', { name: 'Go!' }).click();
  await page.waitForURL((u) => /\/report\/[a-z0-9]+/.test(u.pathname), { timeout: 60000 });
  lap(`${tag} top gear: report ready`);
  const json = await readCopyJson(page);
  lap(`${tag} top gear: JSON read (${json.length} chars)`);
  return json;
}

async function runUpgradeFinder(page, tag) {
  await goTo(page, '/upgradefinder');
  await page.getByRole('button', { name: 'Go!' }).click();
  await page.waitForURL((u) => u.pathname.includes('/upgradereport'), { timeout: 60000 });
  lap(`${tag} upgrade finder: report ready`);
  const json = await readCopyJson(page);
  lap(`${tag} upgrade finder: JSON read (${json.length} chars)`);
  return json;
}

(async () => {
  const browser = await chromium.launch({ headless: !headed });
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
  page.setDefaultTimeout(15000);
  try {
    // The CRA dev server holds a hot-reload socket open, so "networkidle"
    // never arrives; wait for the header instead.
    await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.getByText(/import gear/i).first().waitFor({ timeout: 60000 });
    lap('page loaded (header rendered)');
    const hadWelcome = await dismissWelcome(page, 'DRUID');
    lap(hadWelcome ? 'welcome dialog: chose Midnight/Druid, BEGIN!' : 'no welcome dialog (character already saved)');
    if (smoke) {
      await page.getByText(/import gear/i).first().click();
      await page.locator('#simcentry').waitFor({ state: 'visible' });
      lap('smoke: Import Gear dialog opened, #simcentry visible');
      await page.getByRole('button', { name: 'Cancel' }).click();
      for (const which of ['dungeon', 'raid']) {
        await setContent(page, which);
      }
      lap('smoke: Content select switches Dungeon and Raid');
      await goTo(page, '/topgear');
      lap('smoke: /topgear reachable, cards=' + (await page.locator('.MuiCardActionArea-root').count()));
      await goTo(page, '/upgradefinder');
      lap('smoke: /upgradefinder reachable');
      return;
    }
    const simc = fs.readFileSync(simcPath, 'utf8');
    fs.mkdirSync(outDir, { recursive: true });
    await importSimc(page, simc);
    lap('simc imported');
    const out = {};
    for (const content of ['dungeon', 'raid']) {
      await setContent(page, content);
      out[`topgear-${content}`] = await runTopGear(page, content);
      out[`upgradefinder-${content}`] = await runUpgradeFinder(page, content);
    }
    for (const [name, text] of Object.entries(out)) {
      const file = path.join(outDir, `${name}.json`);
      fs.writeFileSync(file, text);
      let parsed;
      try { parsed = JSON.parse(text); } catch (e) { console.log(`${file}: NOT JSON (${e.message})`); continue; }
      console.log(`${file}: schema=${parsed.schema} version=${parsed.version} contentType=${parsed.contentType} items=${(parsed.topSet && parsed.topSet.items && parsed.topSet.items.length) || (parsed.items && parsed.items.length)} differentials=${parsed.differentials ? parsed.differentials.length : '-'}`);
    }
    console.log('total ms:', times.reduce((a, [, ms]) => a + ms, 0));
  } catch (e) {
    console.error('FAILED:', e.message);
    await page.screenshot({ path: path.join(outDir || '.', 'failure.png') }).catch(() => {});
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
