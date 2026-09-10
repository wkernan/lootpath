// Companion spike S-2 (WKE-532): build a SimulationCraft text profile out of
// Lootpath's own SavedVariables, so the companion can feed QE Live without the
// owner running `/simc`.
//
// Everything here mirrors the SimulationCraft addon's exporter
// (`core.lua`, Unlicense - read and mirrored, never copied): the item-string
// field order, the section markers, the header lines. The offsets below are the
// addon's own OFFSET_* constants; the slot table is its `slotNames` /
// `simcSlotNames` / `invTypeToSlotNum` triple. Where this file deliberately
// differs from the addon, the difference is named in a comment and in
// README.md's difference table - never left silent.
//
// The only input is one capture transcript (`WTF\...\SavedVariables\Lootpath.lua`
// or a committed fixture). Nothing is fetched, nothing is guessed: a field the
// transcript does not carry is reported as missing rather than invented.
//
//   node simc-profile.js build <Lootpath.lua> [out.simc] [--no-bank] [--snapshot=N]
//   node simc-profile.js diff  <Lootpath.lua> <real.simc>   [--no-bank] [--snapshot=N]

"use strict";

const fs = require("fs");
const path = require("path");
const { parseSavedVariables, luaArray } = require("./lua-savedvariables");

// --- the SimulationCraft addon's item-link offsets (core.lua lines 36-48) ----
// An item link's payload is `item:` followed by colon-separated fields. These are
// 1-based indices into that list, exactly as the addon numbers them.
const OFFSET_ITEM_ID = 1;
const OFFSET_ENCHANT_ID = 2;
const OFFSET_GEM_ID_1 = 3;
const OFFSET_GEM_ID_4 = 6;
const OFFSET_BONUS_ID = 13;
const OFFSET_GEM_BONUS_FROM_MODS = 2;

// Item modifier pair types (core.lua lines 52-61).
const ITEM_MOD_TYPE_DROP_LEVEL = 9;
const ITEM_MOD_TYPE_CONTENT_TUNING = 28;
const ITEM_MOD_TYPE_CRAFT_STATS_1 = 29;
const ITEM_MOD_TYPE_CRAFT_STATS_2 = 30;
const ITEM_MOD_TYPE_REDIRECTED_BASE_STATS = 64;

// --- slots -------------------------------------------------------------------
// `simcSlotNames` (extras.lua line 168), indexed by the addon's slot NUMBER,
// which is not an inventory slot id.
const SIMC_SLOT_NAMES = [
  null,
  "head",
  "neck",
  "shoulder",
  "back",
  "chest",
  "shirt",
  "tabard",
  "wrist",
  "hands",
  "waist",
  "legs",
  "feet",
  "finger1",
  "finger2",
  "trinket1",
  "trinket2",
  "main_hand",
  "off_hand",
  "ammo",
];

// The addon walks `slotNames` in order and asks `GetInventorySlotInfo` for each
// one, so slot number N is whatever inventory slot that Blizzard name resolves
// to. Lootpath's capture records the inventory slot id instead, so the companion
// needs the inverse map. Thirteen of these nineteen are confirmed against the
// owner's own 2026-09-07 `/simc` string (README.md, "Slot mapping"); the rest are
// Blizzard's documented INVSLOT_* constants.
const INV_SLOT_TO_SIMC_SLOT_NUM = {
  1: 1, // INVSLOT_HEAD      -> head
  2: 2, // INVSLOT_NECK      -> neck
  3: 3, // INVSLOT_SHOULDER  -> shoulder
  4: 6, // INVSLOT_BODY      -> shirt
  5: 5, // INVSLOT_CHEST     -> chest
  6: 10, // INVSLOT_WAIST    -> waist
  7: 11, // INVSLOT_LEGS     -> legs
  8: 12, // INVSLOT_FEET     -> feet
  9: 8, // INVSLOT_WRIST     -> wrist
  10: 9, // INVSLOT_HAND     -> hands
  11: 13, // INVSLOT_FINGER1 -> finger1
  12: 14, // INVSLOT_FINGER2 -> finger2
  13: 15, // INVSLOT_TRINKET1 -> trinket1
  14: 16, // INVSLOT_TRINKET2 -> trinket2
  15: 4, // INVSLOT_BACK     -> back
  16: 17, // INVSLOT_MAINHAND -> main_hand
  17: 18, // INVSLOT_OFFHAND -> off_hand
  18: 19, // INVSLOT_RANGED  -> ammo
  19: 7, // INVSLOT_TABARD   -> tabard
};

// `invTypeToSlotNum` (extras.lua line 190), verbatim in content and in the
// duplicates it deliberately carries (a ring in a bag is always `finger1`, a
// trinket in a bag is always `trinket1` - the addon has no second slot for them).
const INV_TYPE_TO_SIMC_SLOT_NUM = {
  INVTYPE_HEAD: 1,
  INVTYPE_NECK: 2,
  INVTYPE_SHOULDER: 3,
  INVTYPE_CLOAK: 4,
  INVTYPE_CHEST: 5,
  INVTYPE_ROBE: 5,
  INVTYPE_BODY: 6,
  INVTYPE_TABARD: 7,
  INVTYPE_WRIST: 8,
  INVTYPE_HAND: 9,
  INVTYPE_WAIST: 10,
  INVTYPE_LEGS: 11,
  INVTYPE_FEET: 12,
  INVTYPE_FINGER: 13,
  INVTYPE_TRINKET: 15,
  INVTYPE_WEAPON: 17,
  INVTYPE_2HWEAPON: 17,
  INVTYPE_RANGED: 17,
  INVTYPE_RANGEDRIGHT: 17,
  INVTYPE_SHIELD: 18,
  INVTYPE_HOLDABLE: 18,
  INVTYPE_WEAPONMAINHAND: 17,
  INVTYPE_WEAPONOFFHAND: 18,
  INVTYPE_THROWN: 17,
};

// --- helpers -----------------------------------------------------------------

// `ns.Probe` packs a pcall's results as `{ [1]=..., n=count }` (or `{absent=true}`
// / `{error=...}`). This reads one positional result and nothing else, so an
// error pack never masquerades as a value.
function probe(pack, index = 1) {
  if (!pack || typeof pack !== "object") return undefined;
  if (pack.absent || pack.error !== undefined) return undefined;
  const value = pack[String(index)];
  return value === undefined || value === null ? undefined : value;
}

// The addon's Tokenize (core.lua line 258): lowercase, spaces to underscores,
// then keep only 0-9, a-z, %, +, ., _ and any multibyte sequence.
function tokenize(str) {
  const lowered = String(str || "")
    .toLowerCase()
    .replace(/ /g, "_");
  let out = "";
  for (const ch of lowered) {
    const code = ch.codePointAt(0);
    if (code > 127) out += ch;
    else if ((code >= 48 && code <= 57) || (code >= 97 && code <= 122) || code === 37 || code === 43 || code === 46 || code === 95) {
      out += ch;
    }
  }
  return out.endsWith("_") ? out.slice(0, -1) : out;
}

// The addon's FormatRace (core.lua line 292): UnitRace's English name is
// CamelCase ("ZandalariTroll"), and SimC's token is the spaced form tokenized
// ("zandalari_troll"), so the words are split before tokenizing. 'Scourge'
// becomes 'Undead' exactly as the addon does.
function raceToken(englishRaceName) {
  if (!englishRaceName) return "";
  const name = englishRaceName === "Scourge" ? "Undead" : englishRaceName;
  const words = name.match(/[A-Z][a-z]*/g);
  return tokenize(words ? words.join(" ") : name);
}

// The addon's adler32 (core.lua line 1020) over the un-doubled-pipe text.
function adler32(text) {
  const prime = 65521;
  let s1 = 1;
  let s2 = 0;
  for (let i = 0; i < text.length; i += 1) {
    s1 += text.charCodeAt(i);
    s2 += s1;
  }
  s1 %= prime;
  s2 %= prime;
  // s2 * 2^16 + s1 exceeds 2^31, so this must not use a 32-bit shift.
  return (s2 * 65536 + s1) >>> 0;
}

// The addon's GetItemSplit (core.lua line 196): the `item:` payload, empty
// fields as 0. `tonumber` of a non-numeric field is nil in Lua, so a field the
// client wrote as text (none do today) becomes undefined here rather than NaN.
function splitItemLink(link) {
  const match = /item:([-?\d:]+)/.exec(String(link));
  if (!match) return null;
  return match[1].split(":").map((field) => {
    if (field === "") return 0;
    const n = Number(field);
    return Number.isFinite(n) ? n : undefined;
  });
}

// The addon's GetItemName (core.lua line 230): the text between |h[ and ]|.
function itemNameFromLink(link) {
  const match = /\|h\[(.*)\]\|/.exec(String(link));
  if (!match) return null;
  const trimmed = match[1].replace(/\|\D.+\|\D/g, "").trim();
  return trimmed === "" ? null : trimmed;
}

// --- the item line -----------------------------------------------------------

// GetItemStringFromItemLink (core.lua line 490), with two named differences:
//
//   * `crafting_quality=` is omitted. It comes from
//     `C_TradeSkillUI.GetItemCraftedQualityByItemInfo`, not from the link, so
//     no transcript carries it. QE Live's importer ignores the field.
//   * `titan_disc_id=` is omitted. It comes from a tooltip spell scan of four
//     specific belts. QE Live's importer DOES read it, so those four items are
//     reported as a gap rather than silently wrong.
//
// Everything else is the link's own content and is emitted in the addon's order.
function itemStringFromLink(simcSlotNum, link) {
  const split = splitItemLink(link);
  if (!split) return null;

  const options = [];
  const itemId = split[OFFSET_ITEM_ID - 1];
  if (!itemId) return null;
  options.push(`,id=${itemId}`);

  const enchantId = split[OFFSET_ENCHANT_ID - 1];
  if (enchantId > 0) options.push(`enchant_id=${enchantId}`);

  const gems = [];
  for (let offset = OFFSET_GEM_ID_1; offset <= OFFSET_GEM_ID_4; offset += 1) {
    const gemId = split[offset - 1];
    gems.push(gemId > 0 ? gemId : 0);
  }
  while (gems.length > 0 && gems[gems.length - 1] === 0) gems.pop();
  if (gems.length > 0) options.push(`gem_id=${gems.join("/")}`);

  const bonusCount = split[OFFSET_BONUS_ID - 1] || 0;
  const bonuses = [];
  for (let index = 1; index <= bonusCount; index += 1) bonuses.push(split[OFFSET_BONUS_ID - 1 + index]);
  if (bonuses.length > 0) options.push(`bonus_id=${bonuses.join("/")}`);

  // Shadowlands onward the link carries a variable list of type/value modifier
  // pairs after the bonus IDs.
  const linkOffset = OFFSET_BONUS_ID + bonuses.length + 1;
  const numPairs = split[linkOffset - 1] || 0;
  const craftedStats = [];
  for (let index = 1; index <= numPairs; index += 1) {
    const pairOffset = 1 + linkOffset + 2 * (index - 1);
    const pairType = split[pairOffset - 1];
    const pairValue = split[pairOffset];
    if (pairType === ITEM_MOD_TYPE_DROP_LEVEL) options.push(`drop_level=${pairValue}`);
    else if (pairType === ITEM_MOD_TYPE_CONTENT_TUNING) options.push(`content_tuning=${pairValue}`);
    else if (pairType === ITEM_MOD_TYPE_CRAFT_STATS_1 || pairType === ITEM_MOD_TYPE_CRAFT_STATS_2) craftedStats.push(pairValue);
    else if (pairType === ITEM_MOD_TYPE_REDIRECTED_BASE_STATS) options.push(`redirected_base_stats=${pairValue}`);
  }
  if (craftedStats.length > 0) options.push(`crafted_stats=${craftedStats.join("/")}`);

  const gemBonusOffset = linkOffset + 2 * numPairs + OFFSET_GEM_BONUS_FROM_MODS;
  const numGemBonuses = split[gemBonusOffset - 1] || 0;
  const gemBonuses = [];
  for (let index = 1; index <= numGemBonuses; index += 1) gemBonuses.push(split[gemBonusOffset - 1 + index]);
  if (gemBonuses.length > 0) options.push(`gem_bonus_id=${gemBonuses.join("/")}`);

  return `${SIMC_SLOT_NAMES[simcSlotNum] || "unknown"}=${options.join(",")}`;
}

// --- reading the transcript --------------------------------------------------

function newestSnapshot(list, index) {
  const snapshots = luaArray(list);
  if (snapshots.length === 0) return null;
  if (index !== undefined) {
    const chosen = snapshots[index];
    if (!chosen) throw new Error(`snapshot ${index} does not exist (${snapshots.length} in the transcript)`);
    return chosen;
  }
  return snapshots.reduce((best, snapshot) => ((snapshot.capturedAt || 0) >= (best.capturedAt || 0) ? snapshot : best));
}

function readTranscript(text, options = {}) {
  const db = parseSavedVariables(text);
  const root = db.LootpathDB;
  if (!root) throw new Error("no LootpathDB table in this file - is it a Lootpath SavedVariables file?");
  const captures = (root.global && root.global.captures) || {};
  return {
    env: newestSnapshot(captures.env, options.envSnapshot),
    inventory: newestSnapshot(captures.inventory, options.snapshot),
    vault: newestSnapshot(captures.vault, options.vaultSnapshot),
  };
}

// --- building the profile ----------------------------------------------------

// A bag index that is a bank tab rather than a carried bag. The capture names
// every bag from `Enum.BagIndex`, so the name is the evidence, not the number:
// the numbering moved in 11.2 and would move again.
function isBankBag(bag) {
  return /bank/i.test(String(bag.name || ""));
}

function equippedLines(inventorySnapshot, missing) {
  const rows = [];
  for (const record of luaArray(inventorySnapshot.data.equipped)) {
    if (!record) continue; // a `nil,` gap in the serialised list (see bagRows)
    const link = probe(record.link);
    if (!link) continue;
    const simcSlotNum = INV_SLOT_TO_SIMC_SLOT_NUM[record.invSlot];
    if (!simcSlotNum) {
      missing.push(`equipped inventory slot ${record.invSlot} has no SimC slot number`);
      continue;
    }
    const line = itemStringFromLink(simcSlotNum, link);
    if (!line) {
      missing.push(`equipped inventory slot ${record.invSlot}: link could not be split`);
      continue;
    }
    const name = itemNameFromLink(link);
    const level = probe(record.item && record.item.detailedLevel);
    rows.push({ simcSlotNum, line, comment: name && level ? `${name} (${level})` : null });
  }
  // The addon emits equipped gear in slot-number order, not inventory-slot order.
  rows.sort((a, b) => a.simcSlotNum - b.simcSlotNum);
  const lines = [];
  for (const row of rows) {
    if (row.comment) lines.push(`# ${row.comment}`);
    lines.push(row.line);
  }
  return lines;
}

function bagRows(inventorySnapshot, includeBank, missing) {
  const rows = [];
  for (const bag of luaArray(inventorySnapshot.data.bags)) {
    if (!includeBank && isBankBag(bag)) continue;
    // The capture stores bag items under their slot number, sparsely.
    const slots = Object.keys(bag.items || {})
      .map(Number)
      .sort((a, b) => a - b);
    for (const slot of slots) {
      const entry = bag.items[String(slot)];
      // Blizzard's serialiser writes a sparse list as positional entries with
      // `nil,` in the gaps, so a freed slot between two filled ones is a null
      // here (measured 2026-09-09 in the owner's backpack). The parser keeps
      // it so the slot numbers stay right; it is not an item.
      if (!entry) continue;
      const link = probe(entry.link);
      if (!link) continue;
      const equipLoc = probe(entry.item && entry.item.instant, 4);
      const simcSlotNum = INV_TYPE_TO_SIMC_SLOT_NUM[equipLoc];
      if (!simcSlotNum) continue; // not gear: the addon skips these too
      const line = itemStringFromLink(simcSlotNum, link);
      if (!line) {
        missing.push(`${bag.name} slot ${slot}: link could not be split`);
        continue;
      }
      const name = itemNameFromLink(link);
      const level = probe(entry.item && entry.item.detailedLevel);
      rows.push({
        simcSlotNum,
        line,
        comment: name && level ? `${name} (${level})` : null,
        bagIndex: bag.bagIndex,
        bagName: bag.name,
        slot,
        fromBank: isBankBag(bag),
      });
    }
  }
  // The addon sorts by paper-doll slot with Lua's `table.sort`, which is not
  // stable, so the order of two items in the same slot is not defined there.
  // This sorts by (slot, bag, bag slot) so the companion's output is
  // reproducible; the difference is ordering only and is reported as such.
  rows.sort((a, b) => a.simcSlotNum - b.simcSlotNum || a.bagIndex - b.bagIndex || a.slot - b.slot);
  return rows;
}

function vaultRows(vaultSnapshot, missing) {
  const rows = [];
  if (!vaultSnapshot) return rows;
  if (probe(vaultSnapshot.data.hasAvailableRewards) !== true) return rows;
  for (const reward of luaArray(vaultSnapshot.data.rewardLinks)) {
    if (!reward) continue; // a `nil,` gap in the serialised list (see bagRows)
    const link = probe(reward.link);
    if (!link) continue;
    const equipLoc = probe(reward.item && reward.item.instant, 4);
    const simcSlotNum = INV_TYPE_TO_SIMC_SLOT_NUM[equipLoc];
    if (!simcSlotNum) {
      missing.push(`vault reward ${reward.itemID}: equipLoc ${equipLoc || "unknown"} has no SimC slot number`);
      continue;
    }
    const line = itemStringFromLink(simcSlotNum, link);
    if (!line) continue;
    const name = itemNameFromLink(link);
    const level = probe(reward.item && reward.item.detailedLevel);
    rows.push({ line, comment: name && level ? `${name} (${level})` : null });
  }
  return rows;
}

const PROFILE_SOURCE_LINE = "# Built by Lootpath's companion from SavedVariables (WKE-532 spike), not by /simc";

// QE Live's `checkSimCValid` reads `lines.slice(0, 8)`, and `processAllLines`
// starts its loop at `i = 8` (SimCImportEngine.ts). Both numbers are QE Live's,
// not ours, and both are load-bearing: the class token has to appear before its
// `=` on one of the first eight lines or the import is refused, and an item
// line inside those eight is silently dropped.
const QE_LIVE_HEADER_LINES = 8;
const QE_LIVE_FIRST_ITEM_LINE = 8;

function buildProfile(transcript, options = {}) {
  const { env, inventory, vault } = transcript;
  if (!inventory) throw new Error("this transcript has no `inventory` capture - run /lootpath capture inventory, then /reload");
  const includeBank = options.includeBank !== false;
  const missing = [];

  const playerName = (env && probe(env.data.player)) || "Unknown";
  const classToken = tokenize((env && probe(env.data.class, 2)) || "");
  const realm = (env && probe(env.data.realm)) || "";
  const specName = (env && probe(env.data.specInfo, 2)) || "unknown";
  // Fields the env capture does not carry yet. Each one is reported, never
  // guessed; `region` is the only one QE Live's importer actually reads.
  const region = env && probe(env.data.region);
  const level = env && probe(env.data.level);
  const race = env && probe(env.data.race, 2);
  if (!classToken) missing.push("class (env capture: UnitClass)");
  if (!realm) missing.push("server (env capture: GetRealmName)");
  if (region === undefined) missing.push("region (env capture does not read GetCurrentRegionName)");
  if (level === undefined) missing.push("level (env capture does not read UnitLevel)");
  if (race === undefined) missing.push("race (env capture does not read UnitRace)");

  const capturedAt = inventory.capturedAtLocal || "";
  const stamp = capturedAt.replace("T", " ").slice(0, 16);
  const build = (env && probe(env.data.build)) || "";
  const buildNumber = (env && probe(env.data.build, 2)) || "";
  const toc = (env && probe(env.data.build, 4)) || "";

  const lines = [];
  lines.push(`# ${playerName} - ${specName} - ${stamp} - ${region || "??"}/${realm}`); // 0
  lines.push(PROFILE_SOURCE_LINE); // 1
  lines.push(`# WoW ${build}.${buildNumber}, TOC ${toc}`); // 2
  lines.push(`# Inventory captured ${capturedAt}`); // 3
  lines.push(""); // 4
  const classLineIndex = lines.length;
  lines.push(`${classToken || "unknown"}="${playerName}"`); // 5
  // A field the transcript does not carry is left out, never written empty: an
  // empty `region=` would set QE Live's player region to the empty string, which
  // reads as a measurement we never took.
  if (level !== undefined) lines.push(`level=${level}`);
  if (race !== undefined) lines.push(`race=${raceToken(race)}`);
  if (region !== undefined) lines.push(`region=${tokenize(region)}`);
  lines.push(`server=${tokenize(realm)}`);
  lines.push(`spec=${tokenize(specName)}`);
  lines.push("");

  lines.push(...equippedLines(inventory, missing));

  const bags = bagRows(inventory, includeBank, missing);
  if (bags.length > 0) {
    lines.push("");
    lines.push("### Gear from Bags");
    for (const row of bags) {
      lines.push("#");
      if (row.comment) lines.push(`# ${row.comment}`);
      lines.push(`# ${row.line}`);
    }
  }

  const vaultItems = vaultRows(vault, missing);
  if (vaultItems.length > 0) {
    lines.push("");
    lines.push("### Weekly Reward Choices");
    for (const row of vaultItems) {
      lines.push("#");
      if (row.comment) lines.push(`# ${row.comment}`);
      lines.push(`# ${row.line}`);
    }
    lines.push("#");
    lines.push("### End of Weekly Reward Choices");
  }

  lines.push("");

  const body = `${lines.join("\n")}\n`;

  // QE Live's two line-index rules, proven on every build rather than assumed.
  // They are checked against the JOINED text, not against the array: a realm or
  // character name carrying a newline would move every later line without
  // changing an array index.
  const textLines = body.split("\n");
  const classLine = textLines[classLineIndex];
  if (classLineIndex >= QE_LIVE_HEADER_LINES || classLine !== lines[classLineIndex]) {
    throw new Error(`the class line is not at index ${classLineIndex} of the finished profile; QE Live only scans lines 0..${QE_LIVE_HEADER_LINES - 1} for it`);
  }
  const firstItemLine = textLines.findIndex((line) => isItemLine(line));
  if (firstItemLine !== -1 && firstItemLine < QE_LIVE_FIRST_ITEM_LINE) {
    throw new Error(`an item line is at index ${firstItemLine}; QE Live starts reading items at index ${QE_LIVE_FIRST_ITEM_LINE}`);
  }

  const text = `${body}# Checksum: ${adler32(body).toString(16)}`;

  return {
    text,
    missing,
    counts: {
      equipped: luaArray(inventory.data.equipped).length,
      bag: bags.filter((row) => !row.fromBank).length,
      bank: bags.filter((row) => row.fromBank).length,
      vault: vaultItems.length,
      lines: text.split("\n").length,
    },
    capturedAtLocal: capturedAt,
  };
}

// --- diffing against a real /simc string -------------------------------------

// Every field of one SimC item line, keyed so two lines can be compared field by
// field rather than as text.
function parseItemLine(line) {
  const stripped = line.replace(/^#\s*/, "");
  const parts = stripped.split(",");
  const slot = parts[0].split("=")[0];
  const fields = {};
  for (let i = 1; i < parts.length; i += 1) {
    const eq = parts[i].indexOf("=");
    if (eq === -1) continue;
    fields[parts[i].slice(0, eq)] = parts[i].slice(eq + 1);
  }
  return { slot, fields, commented: line.trimStart().startsWith("#"), text: stripped };
}

function isItemLine(line) {
  return /(^|,)id=\d/.test(line.replace(/^#\s*/, ""));
}

// QE Live keys an item by its id and its bonus IDs; so does Lootpath
// (`ns.ItemKey`). Bonus ID ORDER differs between two reads of the same item, so
// the key sorts them - the same rule `ns.ItemKey` uses.
function itemKey(parsed) {
  const bonus = (parsed.fields.bonus_id || "")
    .split("/")
    .filter(Boolean)
    .map(Number)
    .sort((a, b) => a - b)
    .join(":");
  return bonus ? `${parsed.fields.id}:${bonus}` : String(parsed.fields.id);
}

function sectionOf(lines, index) {
  let section = "equipped";
  for (let i = 0; i <= index; i += 1) {
    if (lines[i] === "### Gear from Bags") section = "bags";
    else if (lines[i] === "### Weekly Reward Choices") section = "vault";
    else if (lines[i] === "### End of Weekly Reward Choices") section = "after-vault";
    else if (lines[i] === "### Linked gear") section = "linked";
    else if (lines[i] === "### Additional Character Info") section = "additional";
  }
  return section;
}

function collectItems(text) {
  const lines = text.split(/\r?\n/);
  const items = new Map();
  lines.forEach((line, index) => {
    if (!isItemLine(line)) return;
    const section = sectionOf(lines, index);
    if (section === "additional" || section === "after-vault") return;
    const parsed = parseItemLine(line);
    parsed.section = section;
    parsed.index = index;
    const key = itemKey(parsed);
    if (!items.has(key)) items.set(key, []);
    items.get(key).push(parsed);
  });
  return items;
}

// Fields the SimulationCraft addon emits that QE Live's importer never reads
// (`SimCImportEngine.ts` processItem: its else-if chain has no branch for them).
const FIELDS_QE_LIVE_IGNORES = new Set(["content_tuning", "crafting_quality", "gem_bonus_id"]);
// Fields QE Live's importer reads off an item line.
const FIELDS_QE_LIVE_READS = new Set(["id", "bonus_id", "gem_id", "enchant_id", "titan_disc_id", "redirected_base_stats", "drop_level", "crafted_stats", "ilevel", "ilvl"]);

function headerFields(text) {
  const fields = {};
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith("#") || line === "") continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq);
    if (key.includes(" ")) continue;
    if (isItemLine(line)) break;
    fields[key] = line.slice(eq + 1);
  }
  return fields;
}

function diffProfiles(generated, real) {
  const mine = collectItems(generated);
  const theirs = collectItems(real);

  const shared = [];
  const onlyMine = [];
  const onlyTheirs = [];

  for (const [key, rows] of mine) {
    if (theirs.has(key)) shared.push({ key, mine: rows, theirs: theirs.get(key) });
    else onlyMine.push({ key, rows });
  }
  for (const [key, rows] of theirs) {
    if (!mine.has(key)) onlyTheirs.push({ key, rows });
  }

  const fieldMismatches = [];
  const ignoredOnly = [];
  const slotDifferences = [];
  const sectionDifferences = [];

  for (const pair of shared) {
    const a = pair.mine[0];
    const b = pair.theirs[0];
    const keys = new Set([...Object.keys(a.fields), ...Object.keys(b.fields)]);
    for (const field of keys) {
      if (a.fields[field] === b.fields[field]) continue;
      const record = { key: pair.key, field, generated: a.fields[field], real: b.fields[field] };
      if (FIELDS_QE_LIVE_IGNORES.has(field)) ignoredOnly.push(record);
      else fieldMismatches.push(record);
    }
    if (a.slot !== b.slot) slotDifferences.push({ key: pair.key, generated: a.slot, real: b.slot });
    if (a.section !== b.section) sectionDifferences.push({ key: pair.key, generated: a.section, real: b.section });
  }

  const mineHeader = headerFields(generated);
  const realHeader = headerFields(real);
  const headerKeys = new Set([...Object.keys(mineHeader), ...Object.keys(realHeader)]);
  const headerDifferences = [];
  for (const field of headerKeys) {
    if (mineHeader[field] === realHeader[field]) continue;
    headerDifferences.push({ field, generated: mineHeader[field], real: realHeader[field] });
  }

  return {
    shared,
    onlyMine,
    onlyTheirs,
    fieldMismatches,
    ignoredOnly,
    slotDifferences,
    sectionDifferences,
    headerDifferences,
  };
}

// --- CLI ---------------------------------------------------------------------

function flagValue(argv, name) {
  const found = argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : undefined;
}

function main(argv) {
  const command = argv[0];
  const positional = argv.slice(1).filter((arg) => !arg.startsWith("--"));
  const includeBank = !argv.includes("--no-bank");
  const snapshotFlag = flagValue(argv, "snapshot");
  const options = { includeBank, snapshot: snapshotFlag === undefined ? undefined : Number(snapshotFlag) };

  if (command !== "build" && command !== "diff") {
    process.stderr.write(
      ["usage:", "  node simc-profile.js build <Lootpath.lua> [out.simc] [--no-bank] [--snapshot=N]", "  node simc-profile.js diff  <Lootpath.lua> <real.simc> [--no-bank] [--snapshot=N]", ""].join("\n"),
    );
    return 2;
  }

  const transcriptPath = positional[0];
  if (!transcriptPath) {
    process.stderr.write("a Lootpath SavedVariables file is required\n");
    return 2;
  }
  // WoW writes SavedVariables in the client's own 8-bit encoding, not UTF-8;
  // reading it as latin1 keeps every byte and never throws on an item name.
  const transcript = readTranscript(fs.readFileSync(transcriptPath, "latin1"), options);
  const built = buildProfile(transcript, options);

  if (command === "build") {
    const outPath = positional[1];
    if (outPath) {
      fs.mkdirSync(path.dirname(path.resolve(outPath)), { recursive: true });
      fs.writeFileSync(outPath, built.text, "latin1");
      process.stdout.write(`${outPath}: ${built.counts.lines} lines, ${built.counts.equipped} equipped, ${built.counts.bag} bag, ${built.counts.bank} bank, ${built.counts.vault} vault\n`);
    } else {
      process.stdout.write(built.text);
    }
    if (built.missing.length > 0) {
      process.stderr.write(`\nFields this transcript does not carry (${built.missing.length}):\n`);
      for (const item of built.missing) process.stderr.write(`  - ${item}\n`);
    }
    return 0;
  }

  const realPath = positional[1];
  if (!realPath) {
    process.stderr.write("diff needs a real /simc string to compare against\n");
    return 2;
  }
  const real = fs.readFileSync(realPath, "latin1");
  const diff = diffProfiles(built.text, real);
  process.stdout.write(formatDiff(built, diff));
  return diff.fieldMismatches.length === 0 ? 0 : 1;
}

function formatDiff(built, diff) {
  const out = [];
  out.push(`Generated from the inventory capture of ${built.capturedAtLocal}: ${built.counts.equipped} equipped, ${built.counts.bag} bag, ${built.counts.bank} bank, ${built.counts.vault} vault items.`);
  out.push("");
  out.push(`Items in both profiles (same itemID and same bonus IDs): ${diff.shared.length}`);
  out.push(`  field mismatches QE Live would read:  ${diff.fieldMismatches.length}`);
  for (const m of diff.fieldMismatches) out.push(`    ${m.key}  ${m.field}: generated=${m.generated ?? "(absent)"} real=${m.real ?? "(absent)"}`);
  out.push(`  differences in fields QE Live ignores: ${diff.ignoredOnly.length}`);
  const byField = new Map();
  for (const m of diff.ignoredOnly) byField.set(m.field, (byField.get(m.field) || 0) + 1);
  for (const [field, count] of byField) out.push(`    ${field}: ${count}`);
  out.push(`  slot-token differences:               ${diff.slotDifferences.length}`);
  for (const s of diff.slotDifferences) out.push(`    ${s.key}: generated=${s.generated} real=${s.real}`);
  out.push(`  section differences (equipped/bags):  ${diff.sectionDifferences.length}`);
  for (const s of diff.sectionDifferences) out.push(`    ${s.key}: generated=${s.generated} real=${s.real}`);
  out.push("");
  out.push(`Items only the generated profile has: ${diff.onlyMine.length}`);
  for (const o of diff.onlyMine) out.push(`    ${o.key} (${o.rows[0].section}) ${o.rows[0].slot}`);
  out.push(`Items only the real /simc string has: ${diff.onlyTheirs.length}`);
  for (const o of diff.onlyTheirs) out.push(`    ${o.key} (${o.rows[0].section}) ${o.rows[0].slot}`);
  out.push("");
  out.push("Header fields:");
  for (const h of diff.headerDifferences) out.push(`    ${h.field}: generated=${h.generated ?? "(absent)"} real=${h.real ?? "(absent)"}`);
  out.push("");
  out.push(`Fields this transcript does not carry: ${built.missing.length}`);
  for (const item of built.missing) out.push(`    ${item}`);
  out.push("");
  return out.join("\n");
}

module.exports = {
  adler32,
  buildProfile,
  collectItems,
  diffProfiles,
  itemKey,
  isItemLine,
  itemNameFromLink,
  itemStringFromLink,
  parseItemLine,
  raceToken,
  QE_LIVE_FIRST_ITEM_LINE,
  QE_LIVE_HEADER_LINES,
  readTranscript,
  splitItemLink,
  tokenize,
  FIELDS_QE_LIVE_IGNORES,
  FIELDS_QE_LIVE_READS,
  INV_SLOT_TO_SIMC_SLOT_NUM,
  INV_TYPE_TO_SIMC_SLOT_NUM,
  SIMC_SLOT_NAMES,
};

if (require.main === module) process.exit(main(process.argv.slice(2)));
