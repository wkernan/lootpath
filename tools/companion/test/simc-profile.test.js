// Guards for the S-2 spike (WKE-532). Run from the repository root with:
//
//     node --test tools/companion-spike/
//
// Node 22's built-in runner, so there is no dependency to install and nothing
// to add to CI's five Lua gates. Every figure asserted here is read from a
// committed fixture, never typed from memory: the SimC checksum is the one the
// owner's own client wrote, and the per-field item comparison is against his
// real `/simc` string of 2026-09-07.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { parseSavedVariables, luaArray, LuaParseError } = require("../lib/lua-savedvariables");
const { adler32, buildProfile, collectItems, diffProfiles, itemKey, itemNameFromLink, itemStringFromLink, parseItemLine, raceToken, readTranscript, splitItemLink, tokenize, QE_LIVE_FIRST_ITEM_LINE, QE_LIVE_HEADER_LINES, INV_SLOT_TO_SIMC_SLOT_NUM } = require("../lib/simc-profile");

const REPO = path.resolve(__dirname, "..", "..", "..");
const TRANSCRIPT = path.join(REPO, "spec", "fixtures", "captures", "Lootpath-20260906-200908.lua");
const REAL_SIMC = path.join(REPO, "spec", "fixtures", "simc", "hotornot-20260907.txt");

const realText = fs.readFileSync(REAL_SIMC, "latin1");
const transcriptText = fs.readFileSync(TRANSCRIPT, "latin1");

function build(options) {
  return buildProfile(readTranscript(transcriptText, options), options);
}

// --- the SavedVariables parser ----------------------------------------------

test("parses the shapes Blizzard's serialiser writes", () => {
  const db = parseSavedVariables(['Root = {', '["s"] = "a\\"b\\\\c\\n",', '["t"] = true,', '["n"] = -1.5,', '["e"] = 2e3,', '["nested"] = {', '"one",', '"two",', '["n"] = 2,', "},", '[3] = "numeric key",', "}"].join("\n"));
  assert.equal(db.Root.s, 'a"b\\c\n');
  assert.equal(db.Root.t, true);
  assert.equal(db.Root.n, -1.5);
  assert.equal(db.Root.e, 2000);
  assert.deepEqual(luaArray(db.Root.nested), ["one", "two"]);
  assert.equal(db.Root["3"], "numeric key");
});

test("a positional entry and a numeric key land in the same 1-based space", () => {
  const db = parseSavedVariables('Root = { "first", [2] = "second", "this is index 2 by position" }');
  // Lua's own behaviour: the positional counter is independent of explicit keys,
  // so the third entry overwrites [2]. The parser must not invent a third slot.
  assert.deepEqual(luaArray(db.Root), ["first", "this is index 2 by position"]);
});

test("an empty bag slot between filled ones is a literal nil in the file, and the bag walk steps over it", () => {
  // Measured 2026-09-09 21:06 in the owner's live SavedVariables: Blizzard's
  // serialiser writes a sparse items list as positional entries with `nil,` in
  // the gaps, so a freed backpack slot became a null entry and the walk read
  // `.link` on it ("Cannot read properties of null"). The parser keeps the null
  // so slot numbers stay right; the walk must skip it.
  const db = parseSavedVariables(['Root = {', '{ ["link"] = { "a", ["n"] = 1 } },', 'nil,', '{ ["link"] = { "c", ["n"] = 1 } },', "}"].join("\n"));
  assert.deepEqual(luaArray(db.Root).map((e) => (e ? e.link["1"] : null)), ["a", null, "c"]);
  const transcript = readTranscript(transcriptText);
  const bag = luaArray(transcript.inventory.data.bags)[0];
  const slots = Object.keys(bag.items);
  bag.items[String(Number(slots[0]) + 100)] = null;
  const equipped = luaArray(transcript.inventory.data.equipped);
  transcript.inventory.data.equipped[String(equipped.length + 1)] = null;
  const profile = buildProfile(transcript);
  assert.ok(profile.text.split("\n").length > 10);
});

test("refuses a malformed table instead of guessing, and names the line", () => {
  // Proven red: without the `expected a value` throw this returns a truncated
  // table and every count downstream is quietly wrong.
  assert.throws(() => parseSavedVariables("Root = {\n\n[\"a\"] = @,\n}"), (error) => error instanceof LuaParseError && error.line === 3);
});

test("refuses an unknown string escape", () => {
  assert.throws(() => parseSavedVariables('Root = { ["a"] = "b\\qc" }'), LuaParseError);
});

test("reads the committed transcript's four capture kinds", () => {
  const db = parseSavedVariables(transcriptText);
  const captures = db.LootpathDB.global.captures;
  assert.deepEqual(Object.keys(captures).sort(), ["env", "inventory", "journal", "vault"]);
  assert.equal(luaArray(captures.inventory).length, 2);
  assert.equal(luaArray(captures.env).length, 1);
  assert.equal(luaArray(captures.journal).length, 3);
  assert.equal(luaArray(captures.vault).length, 4);
});

// --- the SimulationCraft addon's own string functions -------------------------

test("adler32 reproduces the checksum the owner's client wrote", () => {
  // The strongest available proof of this function: the real `/simc` string
  // carries the addon's own checksum of everything above it.
  const stated = /# Checksum: ([0-9a-f]+)\s*$/.exec(realText)[1];
  const body = realText.slice(0, realText.lastIndexOf("# Checksum: "));
  assert.equal(adler32(body).toString(16), stated);
  assert.equal(stated, "14cbd9e1");
});

test("adler32 does not overflow into a negative 32-bit number", () => {
  // Proven red with `(s2 << 16) + s1`: 23 bytes of "x" already drive the high
  // half past 2^15, and JavaScript's shift is 32-bit signed, so the checksum
  // comes out negative and prints with a "-".
  assert.equal(adler32("x".repeat(23)).toString(16), "81770ac9");
});

test("tokenize matches the tokens in the real /simc string", () => {
  assert.equal(tokenize("DRUID"), "druid");
  assert.equal(tokenize("Arthas"), "arthas");
  assert.equal(tokenize("Restoration"), "restoration");
  assert.equal(tokenize("Zandalari Troll"), "zandalari_troll");
  assert.equal(tokenize("Aerie Peak"), "aerie_peak");
  assert.equal(tokenize("Trailing "), "trailing");
});

test("raceToken splits UnitRace's CamelCase English name the way the addon does", () => {
  // Proven red without FormatRace: "ZandalariTroll" tokenizes to
  // "zandalaritroll", which is not the token in the owner's real string.
  assert.equal(raceToken("ZandalariTroll"), "zandalari_troll");
  assert.equal(realText.includes("race=zandalari_troll"), true);
  assert.equal(raceToken("Scourge"), "undead");
  assert.equal(raceToken("Human"), "human");
  assert.equal(raceToken(undefined), "");
});

test("itemNameFromLink reads the name out of a link", () => {
  assert.equal(itemNameFromLink("|cnIQ4:|Hitem:271528::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"), "Enigmatic Dreamwatcher's Somnolent Stare");
  assert.equal(itemNameFromLink("not a link"), null);
});

test("splitItemLink turns empty link fields into 0, as the addon does", () => {
  const split = splitItemLink("|cnIQ4:|Hitem:151311:7968:240892::::::90:104::33:5:13440:6652:13668:12699:12790:1:28:1279:::::|h[x]|h|r");
  assert.equal(split[0], 151311); // itemID
  assert.equal(split[1], 7968); // enchant
  assert.equal(split[2], 240892); // gem 1
  assert.equal(split[3], 0); // gem 2, written empty
  assert.equal(split[12], 5); // bonus ID count
});

// --- one item line -----------------------------------------------------------

test("an equipped link becomes the line the SimC addon wrote for the same item", () => {
  // 151311 sat in the owner's bags on 2026-09-07 with the same bonus IDs it had
  // equipped on 2026-09-05, so the addon's own line for it is in the fixture.
  const link = "|cnIQ4:|Hitem:151311:7968:240892::::::90:104::33:5:13440:6652:13668:12699:12790:1:28:1279:::::|h[Band of the Triumvirate]|h|r";
  assert.equal(itemStringFromLink(13, link), "finger1=,id=151311,enchant_id=7968,gem_id=240892,bonus_id=13440/6652/13668/12699/12790,content_tuning=1279");
  assert.ok(realText.includes("# finger1=,id=151311,enchant_id=7968,gem_id=240892,bonus_id=13440/6652/13668/12699/12790,content_tuning=1279"));
});

test("a redirected_base_stats modifier is emitted, and content_tuning is not invented", () => {
  const link = "|cnIQ4:|Hitem:271528::::::::90:104::23:7:6652:13439:13696:12838:13692:13698:1561:1:64:251140:::::|h[x]|h|r";
  assert.equal(itemStringFromLink(1, link), "head=,id=271528,bonus_id=6652/13439/13696/12838/13692/13698/1561,redirected_base_stats=251140");
});

test("a link with no bonus IDs and no modifiers emits id alone", () => {
  assert.equal(itemStringFromLink(2, "|Hitem:6948::::::::90:104::86:::::::|h[Hearthstone]|h|r"), "neck=,id=6948");
});

test("a link with no itemID yields no line at all", () => {
  assert.equal(itemStringFromLink(1, "|Hitem:0::::::::90:104::::::::|h[x]|h|r"), null);
  assert.equal(itemStringFromLink(1, "not a link"), null);
});

test("the inventory-slot map covers every slot the client can equip", () => {
  const slots = Object.keys(INV_SLOT_TO_SIMC_SLOT_NUM).map(Number);
  assert.equal(Math.min(...slots), 1);
  assert.equal(Math.max(...slots), 19);
  assert.equal(new Set(Object.values(INV_SLOT_TO_SIMC_SLOT_NUM)).size, 19, "two inventory slots must never share a SimC slot number");
});

// --- the profile -------------------------------------------------------------

test("the profile keeps QE Live's two line-index rules", () => {
  const { text } = build();
  const lines = text.split("\n");
  const classLine = lines.findIndex((line) => /^druid="/.test(line));
  assert.ok(classLine < QE_LIVE_HEADER_LINES, `class line at ${classLine}`);
  const firstItem = lines.findIndex((line) => /(^|,)id=\d/.test(line.replace(/^#\s*/, "")));
  assert.ok(firstItem >= QE_LIVE_FIRST_ITEM_LINE, `first item line at ${firstItem}`);
});

test("the build refuses to emit a profile that breaks those rules", () => {
  // Proven red by deleting the two throws in buildProfile: the profile is then
  // written happily and QE Live silently drops every item in it.
  const transcript = readTranscript(transcriptText);
  const originalName = transcript.env.data.player["1"];
  transcript.env.data.player["1"] = `${originalName}\n\n\n\n`;
  assert.throws(() => buildProfile(transcript), /class line is not at index/);
});

test("a transcript with no inventory capture is refused, not half-built", () => {
  assert.throws(() => buildProfile({ env: null, inventory: null, vault: null }), /no `inventory` capture/);
});

test("a field the transcript does not carry is reported, never written empty", () => {
  const built = build();
  assert.deepEqual(
    built.missing.map((m) => m.split(" ")[0]),
    ["region", "level", "race"],
  );
  assert.ok(!/^region=$/m.test(built.text));
  assert.ok(!/^level=$/m.test(built.text));
  assert.ok(!/^race=$/m.test(built.text));
});

test("the committed profile is exactly what this script produces today", () => {
  // The fixture under spec/fixtures/simc/ is the artifact the spike's diff was
  // measured against; if the builder changes and the fixture is not regenerated,
  // every figure in tools/companion-spike/README.md stops being true.
  const committed = fs.readFileSync(path.join(REPO, "spec", "fixtures", "simc", "hotornot-from-savedvariables.simc"), "latin1");
  assert.equal(build().text, committed);
});

test("the profile's own checksum verifies", () => {
  const { text } = build();
  const stated = /# Checksum: ([0-9a-f]+)$/.exec(text)[1];
  assert.equal(adler32(text.slice(0, text.lastIndexOf("# Checksum: "))).toString(16), stated);
});

test("--no-bank drops bank items and nothing else", () => {
  const withBank = build({ snapshot: 0 });
  const withoutBank = build({ snapshot: 0, includeBank: false });
  assert.equal(withBank.counts.bank, 31);
  assert.equal(withoutBank.counts.bank, 0);
  assert.equal(withBank.counts.bag, withoutBank.counts.bag);
  assert.equal(withBank.counts.equipped, withoutBank.counts.equipped);
});

test("the bank-closed snapshot has no bank items to begin with", () => {
  // The two 2026-09-05 snapshots were taken with the bank open and then closed;
  // the client answers 0 slots for a bank tab while the frame is shut.
  assert.equal(build({ snapshot: 0 }).counts.bank, 31);
  assert.equal(build({ snapshot: 1 }).counts.bank, 0);
});

test("equipped gear is emitted in the addon's slot order", () => {
  const { text } = build();
  const order = text
    .split("\n")
    .filter((line) => /^[a-z_0-9]+=,id=/.test(line))
    .map((line) => line.split("=")[0]);
  assert.deepEqual(order, ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger1", "finger2", "trinket1", "trinket2", "main_hand"]);
  const realOrder = realText
    .split("\n")
    .filter((line) => /^[a-z_0-9]+=,id=/.test(line))
    .map((line) => line.split("=")[0]);
  assert.deepEqual(order, realOrder);
});

test("bag and bank items are commented so QE Live reads them as not equipped", () => {
  const { text } = build({ snapshot: 0 });
  const bagsAt = text.split("\n").indexOf("### Gear from Bags");
  assert.ok(bagsAt > 0);
  for (const line of text.split("\n").slice(bagsAt)) {
    if (/(^|,)id=\d/.test(line.replace(/^#\s*/, ""))) assert.ok(line.startsWith("# "), line);
  }
});

// --- the comparison against the owner's real /simc string --------------------

test("every item both profiles carry is byte-identical in every field", () => {
  // The core claim of the spike. 26 items appear in the 2026-09-05 capture and
  // in the 2026-09-07 `/simc` string with the same itemID and bonus IDs; for
  // each, the line Lootpath builds from the link and the line the
  // SimulationCraft addon built from the same link agree on every field,
  // including the ones QE Live ignores.
  const built = build();
  const diff = diffProfiles(built.text, realText);
  assert.equal(diff.shared.length, 26);
  assert.deepEqual(diff.fieldMismatches, []);
  assert.deepEqual(diff.ignoredOnly, []);
});

test("the diff separates gear drift from a defect", () => {
  const diff = diffProfiles(build().text, realText);
  // Two days apart, so items moved between equipped and bags and between ring
  // and trinket positions. None of that is a mismatch in a field.
  assert.equal(diff.sectionDifferences.length, 8);
  assert.equal(diff.slotDifferences.length, 3);
  for (const s of diff.slotDifferences) assert.match(s.generated, /^(finger|trinket)[12]$/);
  assert.equal(diff.onlyMine.length, 24);
  assert.equal(diff.onlyTheirs.length, 17);
});

test("a single wrong bonus ID is caught as a field mismatch", () => {
  // Proven red: with the field comparison removed, this passes silently.
  const built = build();
  const damaged = built.text.replace("bonus_id=13440/6652/13668/12699/12790", "bonus_id=13440/6652/13668/12699/12790,enchant_id=1");
  const diff = diffProfiles(damaged, realText);
  assert.ok(diff.fieldMismatches.some((m) => m.field === "enchant_id"));
});

test("itemKey sorts bonus IDs so read order never splits one item in two", () => {
  const a = parseItemLine("head=,id=1,bonus_id=3/1/2");
  const b = parseItemLine("# head=,id=1,bonus_id=1/2/3");
  assert.equal(itemKey(a), itemKey(b));
  assert.equal(itemKey(a), "1:1:2:3");
  assert.equal(itemKey(parseItemLine("head=,id=1")), "1");
});

test("collectItems reads the real string's own sections", () => {
  const items = collectItems(realText);
  const sections = new Set();
  for (const rows of items.values()) for (const row of rows) sections.add(row.section);
  assert.deepEqual([...sections].sort(), ["bags", "equipped"]);
  // 15 equipped + 29 bag item lines in the fixture. Two of them are the same
  // pair of boots by itemID and bonus IDs and differ only in content_tuning, so
  // they share a key: 43 keys over 44 rows.
  let lineCount = 0;
  for (const rows of items.values()) lineCount += rows.length;
  assert.equal(lineCount, 44);
  assert.equal(items.size, 43);
});

test("the `### Additional Character Info` block is never mistaken for gear", () => {
  // `# slot_high_watermarks=0:308:308/...` has no `id=`, but
  // `# upgrade_currencies=...i:274476:3...` would look like one to a looser test.
  const items = collectItems(realText);
  for (const rows of items.values()) for (const row of rows) assert.ok(row.index < realText.split("\n").indexOf("### Additional Character Info"));
});
