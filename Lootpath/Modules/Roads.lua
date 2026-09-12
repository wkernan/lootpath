-- Lootpath/Modules/Roads.lua (R-1, WKE-562)
-- One road is one way to get an item into a slot. This module is the model
-- every Roads surface renders and the sentence every surface opens with. It
-- draws nothing, reads no client function and touches no database: every input
-- is handed in, so the tests are pure and a surface can be given a week's
-- worth of the owner's own captures without a game around it.
--
-- THE PRODUCT RULE, above everything here: Lootpath never computes a healer
-- value. Every badge on a road is a number one of the companion's documents
-- carries, every ordering inside a group is that document's own, and the three
-- groups are a fixed order that is NOT a ranking (docs/ROADS-UX.md principle 2:
-- a set rating and a per-item percent are two scales and never sort together).
-- Nothing in this file adds, averages, scales or interpolates a number.
--
-- NO SOURCE IS NAMED IN ANY STRING A PLAYER COULD SEE (owner's decision,
-- 2026-09-11, ARCHITECTURE.md 7). Not "QE Live", not "his", not "he", not "the
-- addon has determined". The screen shows the rating, its age and what to do.
-- Internal identifiers keep their `qe` names; the words below never do.
--
-- What the surfaces are: In place (R-2, the tooltip block and the bag glow),
-- Roads as the Upgrade Map slot's expanded row (R-3), This Week (R-5). None of
-- them exists yet. The cache they need is R-2's; this file is pure over inputs.

local _, ns = ...

ns.Roads = {}
local Roads = ns.Roads

-- ---------------------------------------------------------------------------
-- The vocabulary. Every word a road can carry is a constant here, because a
-- string written twice is two strings that can drift, and three surfaces read
-- these.

-- What kind of road it is - where the item comes from, not how good it is.
Roads.KIND_SET = "set" -- something you own, in the best set, not worn yet
Roads.KIND_VAULT = "vault" -- a Great Vault reward
Roads.KIND_CATALYST = "catalyst" -- a conversion into your tier set
Roads.KIND_DROP = "drop" -- a boss drop the journal knows
Roads.KIND_CREST = "crest" -- upgrading the piece you wear
Roads.KIND_CRAFT = "craft" -- a crafted item
Roads.KIND_DELVE = "delve" -- a delve reward
Roads.KIND_KEEP = "keep" -- what you wear now
Roads.KIND_NONE = "none" -- a road nothing rates

-- The three groups, in the fixed order they are shown in. This order is not a
-- ranking and is never sorted: a whole-set rating ("in your best set") and a
-- per-item percent against what you wear are two scales.
Roads.GROUP_SET = "set"
Roads.GROUP_ITEM = "item"
Roads.GROUP_NONE = "none"
Roads.GROUP_ORDER = { Roads.GROUP_SET, Roads.GROUP_ITEM, Roads.GROUP_NONE }

-- The header each group carries. The middle one names its scale once, so no row
-- inside it has to (docs/ROADS-UX.md, surface 2).
Roads.GROUP_HEADER = {
    [Roads.GROUP_SET] = "Your best set",
    [Roads.GROUP_ITEM] = "Other rated sources · percents are against what you wear"
        .. " · at your key's preview level, per the client",
    [Roads.GROUP_NONE] = "No rating",
}

-- Which scale a road's rating is on. `set` is a whole-set verdict, `item` is a
-- percent against what you wear, `none` is one of the four phrases.
Roads.RATING_SET = "set"
Roads.RATING_ITEM = "item"
Roads.RATING_NONE = "none"

-- The four honesty phrases, fixed, each meaning one thing, each with its own
-- cure (docs/ROADS-UX.md principle 3 and the canvas's phrase table). A line
-- never says "not rated" without one of the two tails.
Roads.PHRASE_NOT_RATED_NEW = "not rated · new since the last refresh"
Roads.PHRASE_NOT_RATED_LIMIT = "not rated · beyond the rating's item limit"
Roads.PHRASE_NOT_IN_BEST_SET = "not in your best set"
Roads.PHRASE_NO_RATING = "no rating"
Roads.PHRASES = {
    Roads.PHRASE_NOT_RATED_NEW,
    Roads.PHRASE_NOT_RATED_LIMIT,
    Roads.PHRASE_NOT_IN_BEST_SET,
    Roads.PHRASE_NO_RATING,
}

-- The whole verb table (docs/ROADS-UX.md principle 9). A road whose next step
-- is not something the addon may open - the Catalyst, a crafting order, a
-- vendor, a delve - carries no verb at all: the client offers no call for those
-- and a dead button is worse than none.
Roads.VERB_SHOW_ITEM = "Show item"
Roads.VERB_SHOW_RUN = "Show run"
Roads.VERB_SHOW_IN_VAULT = "Show in vault"
Roads.VERB_OPTIONS = "Options"
Roads.VERB_REFRESH = "Refresh"
Roads.VERBS = {
    Roads.VERB_SHOW_ITEM,
    Roads.VERB_SHOW_RUN,
    Roads.VERB_SHOW_IN_VAULT,
    Roads.VERB_OPTIONS,
    Roads.VERB_REFRESH,
}

-- Plan names on screen are plain, and none of them names what produced them.
-- (`ns.VaultPanel.SCENARIO_LABEL` says more than these because its line is read
-- on its own; a road's plan is read beside a badge and a step.)
Roads.PLAN_LABEL = {
    asOffered = "as offered",
    catalyzed = "catalyzed",
    thisWeek = "this week's plan",
    maxed = "everything upgraded",
}

-- The tag a row leads with: where this road comes from, in the game's words.
Roads.TAG_VAULT = "Vault"
Roads.TAG_CATALYST = "Catalyst"
Roads.TAG_MYTHIC_PLUS = "Mythic+"
Roads.TAG_RAID = "Raid"
Roads.TAG_CRAFTED = "Crafted"
Roads.TAG_DELVES = "Delves"
Roads.TAG_UPGRADE = "Upgrade"
Roads.TAG_KEEP = "Keep (what you wear)"
Roads.TAG_EQUIP = "In your bags"

-- The vault is open now and no capture confirms whether this week's offer
-- survives the reset, so the only time word a vault road carries is the
-- client's own countdown (principle 5). "before reset" is never written.
Roads.VAULT_OPEN_NOW = "open now"

-- A crest step says the cost or says it is not read, and never promises one.
-- `C_ItemUpgrade.GetItemUpgradeItemInfo` answers only for an owned item placed
-- in the open vendor window, which is an action rather than a read, so for a
-- vault reward or a drop the cost is not readable AT ALL and the wording says
-- so permanently; for a piece you own it is merely not read yet (the engineering
-- pass, docs/ROADS-UX.md Buildability).
Roads.CREST_NOT_READABLE = "crest type and cost not readable"
Roads.CREST_NOT_READ = "crest type and cost not read"

-- Neither of these is readable either: the delve key's currency ID is in no
-- capture and which delves are Bountiful is exposed by no `C_DelvesUI`
-- function; crafting materials need the crafter's own open window.
Roads.CRAFT_NOT_READ = "spark and materials not read"
Roads.DELVE_NOT_READ = "not read"

-- Who ticks a step. Anything the client can confirm is the client's; only the
-- unknowable is the player's (principle 8).
Roads.DONE_CLIENT = "client"
Roads.DONE_PLAYER = "player"

-- What a player calls the slot. Used by the plan sentence and by "skip the
-- vault shoulders"; never shown as a label of its own.
Roads.SLOT_WORD = {
    Head = "helm",
    Neck = "necklace",
    Shoulder = "shoulders",
    Back = "cloak",
    Chest = "chest",
    Wrist = "bracers",
    Hands = "gloves",
    Waist = "belt",
    Legs = "legs",
    Feet = "boots",
    Finger = "ring",
    Trinket = "trinket",
    ["1H Weapon"] = "weapon",
    ["2H Weapon"] = "weapon",
    Offhand = "offhand",
    Shield = "shield",
}

function Roads.SlotWord(slot)
    return Roads.SLOT_WORD[slot] or (type(slot) == "string" and slot:lower() or nil)
end

-- ---------------------------------------------------------------------------
-- What a player calls an item.
--
-- The plan sentence is the words a guildmate would type in chat, and nobody
-- types "Venom-Cursed Lynx's Spaulders (295)". The rule is small on purpose and
-- every branch of it is tested against the owner's own item names:
--
--   * a `subType` the caller happens to have (the client's own word for the
--     item's type) wins: "the staff".
--   * a possessive keeps the possessor and takes the slot's word from there:
--     "Venom-Cursed Lynx's Spaulders" -> "the Lynx shoulders".
--   * "<A> of <B>" keeps A and does the same: "Hide of Pestilence" ->
--     "the Hide chest".
--   * anything else is its last word: "Lightgrasp Worldroot" ->
--     "the Worldroot".
--   * with no name at all there is nothing to shorten, so the slot's own word
--     is all there is to say: "the shoulders".
--
-- The full name is never wrong, only long, so it is the fallback whenever the
-- rule above cannot find anything shorter to say.
function Roads.ShortName(item)
    if type(item) ~= "table" then
        return nil
    end
    local slotWord = Roads.SlotWord(item.slot)
    if type(item.subType) == "string" and item.subType ~= "" then
        return "the " .. item.subType:lower()
    end
    local name = type(item.name) == "string" and item.name ~= "" and item.name or nil
    if not name then
        return slotWord and ("the " .. slotWord) or nil
    end
    local possessor = name:match("^(.-)'s%s")
    if possessor and slotWord then
        -- "Venom-Cursed Lynx's" is two words and only the last of them is the
        -- one a player says.
        local last = possessor:match("([^%s]+)$") or possessor
        return string.format("the %s %s", last, slotWord)
    end
    local head = name:match("^(.-)%s+of%s+")
    if head and slotWord then
        return string.format("the %s %s", head, slotWord)
    end
    local lastWord = name:match("([^%s]+)$")
    if lastWord and lastWord ~= name then
        return "the " .. lastWord
    end
    return "the " .. name
end

-- ---------------------------------------------------------------------------
-- Badges. Every one of them is a document's own number or one of the four
-- phrases; there is no third kind of thing a badge can say.

-- A whole-set verdict. "in your best set" carries the level the rating assumed
-- whenever that is above the level the item actually arrives at, because the
-- verdict is only true at that level (principle 4).
function Roads.SetBadge(rating)
    if type(rating) ~= "table" then
        return nil
    end
    if rating.inTopSet then
        if rating.level and rating.arrivesAt and rating.level > rating.arrivesAt then
            return string.format("in your best set at %d", rating.level)
        end
        return "in your best set"
    end
    local percent = tonumber(rating.scorePercent)
    if not percent then
        return nil
    end
    return string.format("%.2f%% behind", math.abs(percent))
end

-- A per-item percent, against what you wear. Zero is not a direction, and a
-- zero or a negative is exactly what "not in your best set" means, so that is
-- what the badge says there rather than "worse by 0.00%".
function Roads.ItemBadge(percent)
    local value = tonumber(percent)
    if not value then
        return nil
    end
    if value == 0 then
        return Roads.PHRASE_NOT_IN_BEST_SET
    end
    return string.format("%+.2f%%", value)
end

-- ---------------------------------------------------------------------------
-- Inputs.
--
-- `inputs` is everything the surfaces have already gathered:
--   verdicts             per scenario: a list of { verdict, scenario } (what
--                        ns.UI.ActiveVerdictScenarios hands over) or a plain
--                        map of scenario -> verdict
--   highlightedScenario  which plan the screen is following; the caller
--                        resolves it (ns.VaultPanel.HighlightScenario), so the
--                        tooltip and the Vault tab cannot disagree
--   ufDocuments          ns.UFImport.Documents(contentType)
--   inventory            ns.Inventory.Scan()
--   vault                ns.Vault.Options()
--   currencies           ns.Currencies.Read()
--   journal              ns.Journal:Build()'s sources, or { sources, summary }
--   difficultyLabels     difficultyID -> the client's own word for it; the
--                        walk records only the ID, and asking the client here
--                        would be this module reading the client
--   excluded             ns.Companion.Excluded's list
--   now                  epoch seconds, for the caller that wants an age
local function scenarioEntries(inputs)
    local given = type(inputs) == "table" and inputs.verdicts or nil
    if type(given) ~= "table" then
        return {}
    end
    if #given > 0 then
        return given
    end
    local entries = {}
    for scenario, verdict in pairs(given) do
        if type(scenario) == "string" and type(verdict) == "table" then
            entries[#entries + 1] = { scenario = scenario, verdict = verdict }
        end
    end
    table.sort(entries, function(left, right)
        return left.scenario < right.scenario
    end)
    return entries
end

-- The plan every road on this screen is read under. The caller names it; when
-- it named one there is no answer for, the first stored plan answers instead
-- rather than nothing at all, and `fellBack` says so.
function Roads.Plan(inputs)
    local entries = scenarioEntries(inputs)
    local wanted = type(inputs) == "table" and inputs.highlightedScenario or nil
    for _, entry in ipairs(entries) do
        if entry.scenario == wanted then
            return entry, false
        end
    end
    local first = entries[1]
    if not first then
        return nil, false
    end
    return first, wanted ~= nil
end

-- The plain name of a plan. A name this build does not know is shown as itself
-- rather than translated into one of the four.
function Roads.PlanName(scenario)
    return Roads.PLAN_LABEL[scenario] or (scenario ~= nil and tostring(scenario) or nil)
end

local function records(inventory)
    if type(inventory) ~= "table" then
        return {}
    end
    return inventory.records or (inventory[1] ~= nil and inventory) or {}
end

local function vaultRewards(vault)
    local options = type(vault) == "table" and (vault.options or vault) or nil
    local rewards = {}
    if type(options) ~= "table" then
        return rewards
    end
    for _, option in ipairs(options) do
        for _, reward in ipairs(type(option) == "table" and option.rewards or {}) do
            -- A keystone or a token is a vault reward with no gear slot, and a
            -- road is a way into a SLOT. They stay on the Vault tab, which
            -- draws every option the client offers.
            if type(reward) == "table" and reward.slot then
                rewards[#rewards + 1] = { reward = reward, option = option }
            end
        end
    end
    return rewards
end

local function journalSources(inputs)
    local given = type(inputs) == "table" and inputs.journal or nil
    if type(given) ~= "table" then
        return {}
    end
    return given.sources or given
end

-- ---------------------------------------------------------------------------
-- Steps and what to do next.

local function step(text, done)
    return { text = text, done = done }
end

-- The footer names the next step nobody has ticked, never a count
-- (principle 8).
function Roads.NextStep(road)
    for _, entry in ipairs(type(road) == "table" and road.steps or {}) do
        if entry.done == nil then
            return entry
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The weekly resources.

-- The Catalyst charge as the client says it: two numbers side by side, no
-- arithmetic between them. nil when no currency read answered, which is not
-- the same as zero and is never shown as one.
function Roads.Charge(currencies)
    if type(currencies) ~= "table" or currencies.ok ~= true then
        return nil
    end
    if currencies.catalystCharges == nil then
        return nil
    end
    return {
        name = (type(currencies.catalyst) == "table" and currencies.catalyst.name) or nil,
        held = currencies.catalystCharges,
        max = currencies.catalystMax,
    }
end

-- "1 held, 8 max", the client's own two numbers (principle 6).
function Roads.ChargeText(charge)
    if type(charge) ~= "table" or charge.held == nil then
        return nil
    end
    if charge.max == nil then
        return string.format("%d held", charge.held)
    end
    return string.format("%d held, %d max", charge.held, charge.max)
end

-- What the client says you are carrying in crests, in its own order and its own
-- names, for a step that cannot say what an upgrade costs. Nothing is added up.
function Roads.CrestHoldingText(currencies)
    if type(currencies) ~= "table" or currencies.ok ~= true then
        return nil
    end
    local parts = {}
    for _, crest in ipairs(currencies.crests or {}) do
        if crest.quantity and crest.quantity > 0 and crest.name then
            parts[#parts + 1] = string.format("%d %s", crest.quantity, crest.name)
        end
    end
    if #parts == 0 then
        return nil
    end
    return "you hold " .. table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Building one road.

-- The shape of a road, written out because three surfaces read it and because
-- every optional field on it means something precise. Everything after `keys`
-- is filled in by the builder below according to what the road IS.
---@class LootpathRoad
---@field kind string            one of the KIND_ constants: where it comes from
---@field group string           which of the three groups it is shown in
---@field slot string            the gear slot this road leads into
---@field item table             the item as it would arrive
---@field steps table            { text, done = "client"|"player"|nil }
---@field keys table             the item keys a hover on this road matches
---@field tag string|nil         the row's leading word
---@field rating table|nil       { kind, badge, referent, level, arrivesAt, ... }
---@field arrivesAt number|nil   the item level it actually arrives at
---@field plan string|nil        the plain name of the plan it was read under
---@field age string|nil         the exportedAt of the document that rated it
---@field phrase string|nil      one of the four phrases, when there is no rating
---@field todo string|nil        the "do: ..." line, absent on an unrated road
---@field verb string|nil        one of the verb table, when one goes somewhere
---@field resource table|nil     { name, held, max, rival }
---@field rivalText string|nil   the other road that wants the same resource
---@field nextStep table|nil     the first step nobody has ticked
---@field source table|nil       the boss and instance a drop comes from
---@field owned table|nil        the record the conversion was made from
---@field becomes table|nil      his tier clone, when the road spends a charge
---@field catalyzed boolean|nil  true when the road spends a Catalyst charge
---@field planPick boolean|nil   true when this is the plan's own pick
---@field openNow string|nil     "open now", for a vault road
---@field resetSeconds number|nil the client's own countdown to the reset
---@field rankedAtAnotherLevel table|nil the levels it IS rated at, when not this one
local function newRoad(kind, group, slot, item)
    ---@type LootpathRoad
    return {
        kind = kind,
        group = group,
        slot = slot,
        item = item,
        steps = {},
        keys = {},
    }
end

local function itemFacts(source, extra)
    local item = {
        itemID = source and tonumber(source.itemID) or nil,
        key = source and source.key or nil,
        name = source and source.name or nil,
        level = source and (source.level or source.itemLevel) or nil,
        quality = source and source.quality or nil,
        icon = source and source.icon or nil,
        slot = source and source.slot or nil,
        subType = source and source.subType or nil,
    }
    for field, value in pairs(extra or {}) do
        item[field] = value
    end
    return item
end

-- ---------------------------------------------------------------------------
-- The set group: everything the highlighted plan's document says about a slot.

-- The top set as slot -> list of its items, in the document's own order (a
-- matched pair of rings is two entries, because `order` repeats the key).
local function topSetBySlot(verdict)
    local topSet = type(verdict) == "table" and type(verdict.topSet) == "table" and verdict.topSet or {}
    local items = type(topSet.items) == "table" and topSet.items or {}
    local bySlot, list = {}, {}
    for _, key in ipairs(topSet.order or {}) do
        local item = items[key]
        if item then
            list[#list + 1] = item
            if item.slot then
                local slotList = bySlot[item.slot] or {}
                bySlot[item.slot] = slotList
                slotList[#slotList + 1] = item
            end
        end
    end
    return bySlot, list
end

-- His conversions, indexed by the very item table they were found on, so a
-- top-set item can be told from a clone without asking the join twice.
local function conversionsByItem(verdict, inputs)
    local index = {}
    for _, entry in ipairs(ns.QEImport.CatalyzedOwned(verdict, inputs.inventory) or {}) do
        index[entry.item] = entry
    end
    for _, entry in ipairs(ns.QEImport.CatalyzedVault(verdict, inputs.vault) or {}) do
        index[entry.item] = entry
    end
    return index
end

-- The one vault reward the plan takes. His own `ItemSet.ts:205` allows one
-- vault option per set, so there is at most one, and it is what tells "take it"
-- from "take one vault reward" on every other vault road.
local function planVaultItem(items)
    for _, item in ipairs(items) do
        if item.isVault then
            return item
        end
    end
    return nil
end

local function ownedByKey(inputs)
    local byKey = {}
    for _, record in ipairs(records(inputs.inventory)) do
        if record.key and byKey[record.key] == nil then
            byKey[record.key] = record
        end
    end
    return byKey
end

-- Which kind of road a set item is: where it would come FROM.
local function setItemKind(item, conversion, owned)
    if conversion then
        return Roads.KIND_CATALYST
    end
    if item.isVault then
        return Roads.KIND_VAULT
    end
    if owned and owned.location == "equipped" then
        return Roads.KIND_KEEP
    end
    return Roads.KIND_SET
end

-- Two bonus ID lists that are the same list. Both sides come out of
-- ns.ParseItemLink, so both are sorted; an item with no bonus IDs at all is not
-- identified by them, which is the same guard QEImport's own join carries.
local function sameBonusIDs(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right or #left == 0 then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

-- The item a vault road is really about: the reward the vault is offering, so
-- the row shows the client's own name, level and icon rather than his clone's
-- item ID. Three ways to it, in order of how much they claim:
--   * the conversion join already found it (a clone in the TOP set);
--   * the exact key (the option as the vault hands it over);
--   * his clone of the option, recognised the way CatalyzedCoverage recognises
--     one - the same slot and the same bonus IDs on a different item ID,
--     because `Item.convertToTier` copies everything but the item ID. This is
--     the path an ALTERNATIVE's catalyzed vault item takes, and without it a
--     row would read "nil 321" instead of "Scavenger's Spaulders 308".
-- Returns the reward and whether the set item is his clone of it.
local function vaultRewardFor(item, conversion, vaultByKey, vaultRecords)
    if conversion and conversion.fromVault and conversion.owned then
        return conversion.owned, conversion.owned.itemID ~= item.itemID
    end
    local direct = item.key and vaultByKey[item.key] or nil
    if direct then
        return direct, false
    end
    for _, reward in ipairs(vaultRecords) do
        if reward.slot == item.slot and reward.itemID == item.itemID then
            return reward, false
        end
    end
    for _, reward in ipairs(vaultRecords) do
        if reward.slot == item.slot and sameBonusIDs(reward.bonusIDs, item.bonusIDs) then
            return reward, true
        end
    end
    return nil, false
end

-- ---------------------------------------------------------------------------
-- The item group: percents against what you wear, from the Upgrade Finder
-- documents the companion writes.

-- QE Live's own word for what a listing IS at its level, turned into the words
-- a row says about a second figure. `max` is the track's cap for that run and
-- `bonus` is the upgraded listing; neither is Lootpath's reading of a number,
-- both are his own `dropType` carried through.
local function extraLevelLabel(dropType)
    if dropType == "max" then
        return "at its cap"
    end
    if dropType == "bonus" then
        return "upgraded"
    end
    return nil
end

-- The other item levels a road can reach, read from THE ONE DOCUMENT the row's
-- own figure came from and no other: the "upgraded 321 at +0.38%" and "at its
-- cap 334 +4.71%" figures. All of a row's numbers come from one run, because
-- two runs asked different questions and a row that mixed them would be a
-- number the reader cannot check (docs/ROADS-UX.md surface 2, [R5 7]).
--
-- Only levels above the one it arrives at, and only the ones his own `dropType`
-- has a word for: a level that is another run's `drop` is the same item on a
-- different key, not something this road becomes.
local function otherLevels(document, itemID, arrivesAt)
    local out = {}
    local verdict = type(document) == "table" and document.verdict or nil
    local levels = ns.UFImport.LevelsFor(verdict, itemID)
    for _, level in ipairs(levels or {}) do
        if arrivesAt and level > arrivesAt then
            local entry = ns.UFImport.Lookup(verdict, itemID, level)
            local label = entry and extraLevelLabel(entry.dropType) or nil
            if entry and label then
                out[#out + 1] = {
                    level = level,
                    percent = entry.upgradePercent,
                    badge = Roads.ItemBadge(entry.upgradePercent),
                    label = label,
                    keyLevel = document.keyLevel,
                    dropType = entry.dropType,
                }
            end
        end
    end
    return out
end

-- The document a lookup's answer came out of, so the row can read its other
-- levels and its age off the same run.
local function documentAt(documents, keyLevel)
    for _, document in ipairs(documents or {}) do
        if document.keyLevel == keyLevel then
            return document
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Excluded items: the second tail of "not rated".
--
-- The leftover list the verdict file carries is `ns.Companion`'s, and since
-- C-10 (WKE-567) an entry carries the item's own identity - item ID and sorted
-- bonus IDs - with the name and level as the fallback for every file written
-- before it. `ns.Companion.IsExcluded` is that join and it is the only one:
-- writing a second here would be the road model answering "was this item left
-- out" differently from the tab that prints the note, which is exactly the
-- drift this tail exists to avoid. `how` says which of the two recognised it.
function Roads.Excluded(excluded, item, key)
    if type(item) ~= "table" and key == nil then
        return nil
    end
    local level = type(item) == "table" and tonumber(item.level or item.itemLevel) or nil
    local name = type(item) == "table" and item.name or nil
    return ns.Companion.IsExcluded(excluded, key or (type(item) == "table" and item.key or nil), {
        name = name,
        level = level,
    })
end

-- Which of the two "not rated" tails applies to an item nothing rated: the one
-- whose cure is a refresh, or the one whose cure is the cap decision. They are
-- told apart by the leftover list and by nothing else.
function Roads.NotRatedPhrase(excluded, item, key)
    if Roads.Excluded(excluded, item, key) then
        return Roads.PHRASE_NOT_RATED_LIMIT
    end
    return Roads.PHRASE_NOT_RATED_NEW
end

-- ---------------------------------------------------------------------------
-- Roads for one slot.

local function finishSetRoad(road, entry, inputs, planVault, charge)
    local rating = road.rating
    road.plan = Roads.PlanName(entry.scenario)
    road.age = entry.verdict and entry.verdict.exportedAt or nil

    if road.kind == Roads.KIND_VAULT then
        road.tag = Roads.TAG_VAULT
        road.openNow = Roads.VAULT_OPEN_NOW
        road.resetSeconds = type(inputs.vault) == "table" and inputs.vault.secondsUntilWeeklyReset or nil
        road.steps[#road.steps + 1] = step("the vault is offering it", Roads.DONE_CLIENT)
        if rating and rating.level and rating.arrivesAt and rating.level > rating.arrivesAt then
            road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READABLE)
        end
        road.steps[#road.steps + 1] = step("take it from the Great Vault")
        road.verb = Roads.VERB_SHOW_IN_VAULT
        -- The vault hands over one reward, so a road for an option the plan did
        -- not pick must not read as a second thing to take. It never names the
        -- other road either (the copy rule): the options are in the badges.
        road.todo = (planVault and road.planPick) and "do: take it" or "do: take one vault reward"
        if
            road.todo == "do: take it"
            and rating
            and rating.level
            and rating.arrivesAt
            and rating.level > rating.arrivesAt
        then
            road.todo = string.format("do: take it · rated at %d, crests not readable", rating.level)
        end
    elseif road.kind == Roads.KIND_CATALYST then
        road.tag = Roads.TAG_CATALYST
        if road.owned and road.owned.name then
            road.steps[#road.steps + 1] = step("you own " .. road.owned.name, Roads.DONE_CLIENT)
        end
        local chargeText = Roads.ChargeText(charge)
        if chargeText then
            road.steps[#road.steps + 1] = step("charge " .. chargeText, charge.held > 0 and Roads.DONE_CLIENT or nil)
        end
        road.steps[#road.steps + 1] = step("convert it at the Catalyst")
        road.todo = chargeText and ("do: Catalyst it · charge " .. chargeText) or "do: Catalyst it"
        road.resource = charge
                and {
                    name = charge.name,
                    held = charge.held,
                    max = charge.max,
                }
            or nil
    elseif road.kind == Roads.KIND_KEEP then
        road.tag = Roads.TAG_KEEP
        road.todo = "nothing to do"
    else
        road.tag = Roads.TAG_EQUIP
        road.steps[#road.steps + 1] = step("it is in your bags", Roads.DONE_CLIENT)
        road.steps[#road.steps + 1] = step("put it on")
        road.todo = "do: equip it"
    end
    road.nextStep = Roads.NextStep(road)
    return road
end

-- The referent of a "behind": what the plan does instead, read off the
-- alternative's OWN item list rather than inferred. An alternative names every
-- slot it changes completely (his `TopGearEngine.ts:491-513`), so the slots it
-- mentions other than this one are exactly what taking this road costs.
local function referentOf(alternative, slot, bySlot, conversions)
    local names = {}
    for _, item in ipairs(alternative.items or {}) do
        if item.slot and item.slot ~= slot then
            for _, planItem in ipairs(bySlot[item.slot] or {}) do
                local word = Roads.SlotWord(planItem.slot) or "item"
                local what = "the " .. word
                if planItem.isVault then
                    what = "the vault " .. word
                elseif conversions[planItem] then
                    what = "the catalyzed " .. word
                end
                names[#names + 1] = what
            end
        end
    end
    if #names == 0 then
        return nil
    end
    return string.format("taking %s instead", table.concat(names, " and "))
end

-- Roads for one slot, in three groups. Inside a group the order is the
-- document's own; the groups themselves are a fixed order and not a ranking.
function Roads.ForSlot(slot, inputs)
    inputs = type(inputs) == "table" and inputs or {}
    local result = {
        slot = slot,
        groups = { [Roads.GROUP_SET] = {}, [Roads.GROUP_ITEM] = {}, [Roads.GROUP_NONE] = {} },
        counts = { set = 0, item = 0, none = 0 },
    }
    if type(slot) ~= "string" then
        return result
    end

    local entry = Roads.Plan(inputs)
    local charge = Roads.Charge(inputs.currencies)
    local owned = ownedByKey(inputs)
    local documents = type(inputs.ufDocuments) == "table" and inputs.ufDocuments or {}

    local vaultByKey, vaultRecords = {}, {}
    for _, held in ipairs(vaultRewards(inputs.vault)) do
        if held.reward.key and vaultByKey[held.reward.key] == nil then
            vaultByKey[held.reward.key] = held.reward
        end
        vaultRecords[#vaultRecords + 1] = held.reward
    end

    local function add(road)
        local group = result.groups[road.group]
        group[#group + 1] = road
        result.counts[road.group] = result.counts[road.group] + 1
        return road
    end

    -- ---- the set group ----
    local takenVault = {}
    if entry then
        local bySlot, allItems = topSetBySlot(entry.verdict)
        local conversions = conversionsByItem(entry.verdict, inputs)
        local planVault = planVaultItem(allItems)
        local seen = {}

        local function setRoad(item, alternative)
            local conversion = conversions[item]
            local ownedRecord = item.key and owned[item.key] or nil
            local kind = setItemKind(item, conversion, ownedRecord)
            local source, catalyzed = item, false
            if kind == Roads.KIND_VAULT then
                local reward, isClone = vaultRewardFor(item, conversion, vaultByKey, vaultRecords)
                source, catalyzed = reward or item, isClone
            elseif kind == Roads.KIND_CATALYST and conversion.owned then
                source = conversion.owned
            elseif ownedRecord then
                source = ownedRecord
            end
            local facts = itemFacts(source, { slot = slot })
            local arrivesAt = facts.level or item.level
            local road = newRoad(kind, Roads.GROUP_SET, slot, facts)
            road.planPick = alternative == nil
            road.owned = conversion and conversion.owned or ownedRecord
            -- What the item becomes on the way in: his tier clone. Set for a
            -- conversion of something you own and for a vault reward he
            -- catalyzed alike, because both spend the same one charge.
            road.becomes = (conversion or catalyzed) and item or nil
            road.catalyzed = catalyzed or (conversion ~= nil) or nil
            road.rating = {
                kind = Roads.RATING_SET,
                inTopSet = alternative == nil,
                scorePercent = alternative and alternative.scorePercent or nil,
                hpsDifference = alternative and alternative.hpsDifference or nil,
                level = item.level,
                arrivesAt = arrivesAt,
                referent = alternative and referentOf(alternative, slot, bySlot, conversions) or nil,
            }
            road.rating.badge = Roads.SetBadge(road.rating)
            road.arrivesAt = arrivesAt
            if facts.key then
                road.keys[#road.keys + 1] = facts.key
            end
            if item.key and item.key ~= facts.key then
                road.keys[#road.keys + 1] = item.key
            end
            if kind == Roads.KIND_VAULT then
                takenVault[facts.key or item.key] = true
            end
            return finishSetRoad(road, entry, inputs, planVault, charge)
        end

        for _, item in ipairs(bySlot[slot] or {}) do
            add(setRoad(item, nil))
            seen[item.key] = true
        end
        -- The alternatives in his own order, which is the order the exporter
        -- wrote them in: nothing is re-sorted here.
        for _, alternative in ipairs(entry.verdict and entry.verdict.alternatives or {}) do
            for _, item in ipairs(alternative.items or {}) do
                if item.slot == slot and not seen[item.key] then
                    seen[item.key] = true
                    add(setRoad(item, alternative))
                end
            end
        end
    end

    -- A vault reward in this slot the plan's document never mentions was in the
    -- run and was not chosen: 558 read in his own importer that every vault
    -- option is active from the moment it is imported
    -- (`SimCImportEngine.ts:712`), so it cannot have fallen outside the item
    -- limit. "Rated, and not in the best set" is exactly the third phrase.
    for _, held in ipairs(vaultRewards(inputs.vault)) do
        local reward = held.reward
        if reward.slot == slot and not takenVault[reward.key] then
            local road =
                newRoad(Roads.KIND_VAULT, entry and Roads.GROUP_SET or Roads.GROUP_NONE, slot, itemFacts(reward))
            road.tag = Roads.TAG_VAULT
            road.openNow = Roads.VAULT_OPEN_NOW
            road.resetSeconds = type(inputs.vault) == "table" and inputs.vault.secondsUntilWeeklyReset or nil
            road.arrivesAt = reward.itemLevel
            road.plan = entry and Roads.PlanName(entry.scenario) or nil
            road.age = entry and entry.verdict and entry.verdict.exportedAt or nil
            road.phrase = entry and Roads.PHRASE_NOT_IN_BEST_SET or Roads.PHRASE_NO_RATING
            road.rating = { kind = Roads.RATING_NONE, badge = road.phrase, arrivesAt = reward.itemLevel }
            road.steps[#road.steps + 1] = step("the vault is offering it", Roads.DONE_CLIENT)
            road.steps[#road.steps + 1] = step("take it from the Great Vault")
            road.verb = Roads.VERB_SHOW_IN_VAULT
            road.todo = "do: take one vault reward"
            road.nextStep = Roads.NextStep(road)
            if reward.key then
                road.keys[#road.keys + 1] = reward.key
            end
            add(road)
        end
    end

    -- ---- the no-rating group: upgrading what you wear ----
    -- Built before the drops so that the first row of the group is the one the
    -- tooltip would show: the piece in this slot, not an unrated drop from a
    -- difficulty nobody is running.
    for _, record in ipairs(records(inputs.inventory)) do
        if record.location == "equipped" and record.slot == slot then
            local road = newRoad(Roads.KIND_CREST, Roads.GROUP_NONE, slot, itemFacts(record))
            road.tag = Roads.TAG_UPGRADE
            road.arrivesAt = record.itemLevel
            road.phrase = Roads.PHRASE_NO_RATING
            road.rating = { kind = Roads.RATING_NONE, badge = Roads.PHRASE_NO_RATING, arrivesAt = record.itemLevel }
            road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READ)
            local holding = Roads.CrestHoldingText(inputs.currencies)
            if holding then
                road.steps[#road.steps + 1] = step(holding, Roads.DONE_CLIENT)
            end
            road.nextStep = Roads.NextStep(road)
            if record.key then
                road.keys[#road.keys + 1] = record.key
            end
            add(road)
        end
    end

    -- ---- the item group: drops the journal knows ----
    local sources = journalSources(inputs)
    local labels = type(inputs.difficultyLabels) == "table" and inputs.difficultyLabels or {}
    local itemIDs = {}
    for itemID in pairs(sources) do
        itemIDs[#itemIDs + 1] = itemID
    end
    table.sort(itemIDs)
    local drops = {}
    for _, itemID in ipairs(itemIDs) do
        for _, source in ipairs(sources[itemID] or {}) do
            if source.slot == slot and source.itemLevel then
                local rated, keyLevel, how = ns.UFImport.LookupAcrossLevels(documents, itemID, source.itemLevel)
                local road = newRoad(
                    Roads.KIND_DROP,
                    rated and Roads.GROUP_ITEM or Roads.GROUP_NONE,
                    slot,
                    itemFacts(source, { itemID = itemID, key = source.itemKey, level = source.itemLevel })
                )
                road.tag = source.isRaid and Roads.TAG_RAID or Roads.TAG_MYTHIC_PLUS
                road.arrivesAt = source.itemLevel
                road.source = {
                    instanceID = source.instanceID,
                    instanceName = source.instanceName,
                    encounterID = source.encounterID,
                    encounterName = source.encounterName,
                    difficultyID = source.difficultyID,
                    difficultyLabel = labels[source.difficultyID],
                    isRaid = source.isRaid == true,
                }
                if rated then
                    local document = documentAt(documents, keyLevel)
                    road.rating = {
                        kind = Roads.RATING_ITEM,
                        percent = rated.upgradePercent,
                        badge = Roads.ItemBadge(rated.upgradePercent),
                        arrivesAt = source.itemLevel,
                        level = source.itemLevel,
                        keyLevel = keyLevel,
                        how = how,
                        alsoAt = otherLevels(document, itemID, source.itemLevel),
                    }
                    road.age = document and document.verdict and document.verdict.exportedAt or nil
                    if (tonumber(rated.upgradePercent) or 0) <= 0 then
                        road.phrase = Roads.PHRASE_NOT_IN_BEST_SET
                    end
                else
                    road.phrase = Roads.PHRASE_NO_RATING
                    road.rating = { kind = Roads.RATING_NONE, badge = Roads.PHRASE_NO_RATING }
                    road.rankedAtAnotherLevel = ns.UFImport.LevelsAcrossLevels(documents, itemID)
                end
                road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READABLE)
                road.steps[#road.steps + 1] = step("it drops for you", Roads.DONE_PLAYER)
                road.verb = Roads.VERB_SHOW_RUN
                if rated then
                    -- The difficulty is on the row's own source line, so the
                    -- imperative does not repeat it: the client's own label for
                    -- this walk is "Mythic raid", and "do: raid Mythic raid" is
                    -- not a sentence anybody types.
                    road.todo = source.isRaid and "do: raid it · tick when it drops"
                        or "do: run the key · tick when it drops"
                end
                road.nextStep = Roads.NextStep(road)
                if source.itemKey then
                    road.keys[#road.keys + 1] = source.itemKey
                end
                drops[#drops + 1] = road
            end
        end
    end
    -- His order inside the group: the percent he gave, best first, and the
    -- document's own order behind it so the same screen renders the same way.
    local dropRank = {}
    for position, road in ipairs(drops) do
        dropRank[road] = position
    end
    table.sort(drops, function(left, right)
        local leftPercent = left.rating and tonumber(left.rating.percent) or nil
        local rightPercent = right.rating and tonumber(right.rating.percent) or nil
        if (leftPercent ~= nil) ~= (rightPercent ~= nil) then
            return leftPercent ~= nil
        end
        if leftPercent and rightPercent and leftPercent ~= rightPercent then
            return leftPercent > rightPercent
        end
        return dropRank[left] < dropRank[right]
    end)
    for _, road in ipairs(drops) do
        add(road)
    end

    -- ---- the item group: the Crafted and Delves rows the export carries ----
    local crafted, delves = {}, {}
    for _, document in ipairs(documents) do
        local verdict = type(document) == "table" and document.verdict or nil
        if type(verdict) == "table" then
            for _, item in pairs(type(verdict.items) == "table" and verdict.items or {}) do
                if item.slot == slot then
                    local list = (item.dropLoc == "Crafted" and crafted) or (item.dropLoc == "Delves" and delves) or nil
                    if list and list[item.key] == nil then
                        list[item.key] = { item = item, keyLevel = document.keyLevel, exportedAt = verdict.exportedAt }
                    end
                end
            end
        end
    end
    local function addExportRows(list, kind, tag)
        local rows = {}
        for _, held in pairs(list) do
            rows[#rows + 1] = held
        end
        table.sort(rows, function(left, right)
            local leftPercent, rightPercent = tonumber(left.item.upgradePercent), tonumber(right.item.upgradePercent)
            if (leftPercent or 0) ~= (rightPercent or 0) then
                return (leftPercent or 0) > (rightPercent or 0)
            end
            return left.item.key < right.item.key
        end)
        for _, held in ipairs(rows) do
            local item = held.item
            local road = newRoad(kind, Roads.GROUP_ITEM, slot, itemFacts(item))
            road.tag = tag
            road.arrivesAt = item.level
            road.age = held.exportedAt
            road.rating = {
                kind = Roads.RATING_ITEM,
                percent = item.upgradePercent,
                badge = Roads.ItemBadge(item.upgradePercent),
                arrivesAt = item.level,
                level = item.level,
                keyLevel = held.keyLevel,
            }
            if (tonumber(item.upgradePercent) or 0) <= 0 then
                road.phrase = Roads.PHRASE_NOT_IN_BEST_SET
            end
            if kind == Roads.KIND_CRAFT then
                road.steps[#road.steps + 1] = step(Roads.CRAFT_NOT_READ)
                road.todo = "do: get the spark, then order it"
            else
                -- No delve step until a delve capture exists: the key's
                -- currency ID is in no capture and no client call says which
                -- delves are Bountiful. The row says so, without a "do:".
                road.steps[#road.steps + 1] = step(Roads.DELVE_NOT_READ)
            end
            road.nextStep = Roads.NextStep(road)
            if item.key then
                road.keys[#road.keys + 1] = item.key
            end
            add(road)
        end
    end
    addExportRows(crafted, Roads.KIND_CRAFT, Roads.TAG_CRAFTED)
    addExportRows(delves, Roads.KIND_DELVE, Roads.TAG_DELVES)

    -- One group, one scale, one order: the rated sources are every road the
    -- Upgrade Finder documents value, in the order of the percent HE gave, best
    -- first, with the order they were built in behind it so the same screen
    -- renders the same way twice. This is not a ranking across scales - the set
    -- group is not in it - and no number here is Lootpath's.
    local rated = result.groups[Roads.GROUP_ITEM]
    local ratedPosition = {}
    for position, road in ipairs(rated) do
        ratedPosition[road] = position
    end
    table.sort(rated, function(left, right)
        local leftPercent = tonumber(left.rating and left.rating.percent) or 0
        local rightPercent = tonumber(right.rating and right.rating.percent) or 0
        if leftPercent ~= rightPercent then
            return leftPercent > rightPercent
        end
        return ratedPosition[left] < ratedPosition[right]
    end)

    -- ---- the resources two roads on this screen both want ----
    Roads.NameRivals(result, charge)

    result.plan = Roads.SlotSentence(result)
    return result
end

-- Any road that spends a weekly resource names the other road that wants it,
-- and that road names it back (principle 6). Only ever within one screen: a
-- reference to a road the reader cannot see is worse than none.
-- How a road refers to another road in one clause: the tag, with the item's own
-- last word behind it when there are two roads of a kind on the screen. "the
-- vault Spaulders road" is what the reader is looking at; "the vault road" is
-- not, once the vault is offering two things in the slot.
local function rivalLabel(road)
    if road.kind == Roads.KIND_VAULT then
        local name = type(road.item) == "table" and type(road.item.name) == "string" and road.item.name or nil
        local last = name and name:match("([^%s]+)$") or nil
        return last and ("vault " .. last) or "vault"
    end
    return road.tag
end

function Roads.NameRivals(slotRoads, charge)
    if type(slotRoads) ~= "table" or type(charge) ~= "table" or charge.held == nil then
        return slotRoads
    end
    local spenders = {}
    for _, group in ipairs(Roads.GROUP_ORDER) do
        for _, road in ipairs(slotRoads.groups[group] or {}) do
            if road.kind == Roads.KIND_CATALYST or (road.kind == Roads.KIND_VAULT and road.becomes) then
                spenders[#spenders + 1] = road
            end
        end
    end
    if #spenders < 2 or charge.held >= #spenders then
        return slotRoads
    end
    for index, road in ipairs(spenders) do
        local other = spenders[index == 1 and 2 or 1]
        local label = rivalLabel(other)
        road.resource = road.resource or { name = charge.name, held = charge.held, max = charge.max }
        road.resource.rival = label
        -- The road the plan takes names the other one; the other one names it
        -- back and says out loud that they are exclusive, because that is the
        -- row a reader is about to spend the charge on by mistake.
        road.rivalText = index == 1 and string.format("the same charge as the %s road", label)
            or string.format("the same charge as the %s road: one of these, not both", label)
    end
    return slotRoads
end

-- ---------------------------------------------------------------------------
-- Roads for one item: the tooltip's at-most-three (R-2 draws it).

-- The slot an item key belongs to, read off whatever the caller already has.
local function slotForKey(key, inputs)
    for _, record in ipairs(records(inputs.inventory)) do
        if record.key == key then
            return record.slot
        end
    end
    for _, held in ipairs(vaultRewards(inputs.vault)) do
        if held.reward.key == key then
            return held.reward.slot
        end
    end
    local entry = Roads.Plan(inputs)
    local verdict = entry and entry.verdict or nil
    local topSet = type(verdict) == "table" and type(verdict.topSet) == "table" and verdict.topSet or {}
    local item = type(topSet.items) == "table" and topSet.items[key] or nil
    if item then
        return item.slot
    end
    for _, alternative in ipairs(type(verdict) == "table" and verdict.alternatives or {}) do
        for _, alternativeItem in ipairs(alternative.items or {}) do
            if alternativeItem.key == key then
                return alternativeItem.slot
            end
        end
    end
    local sources = journalSources(inputs)
    for _, list in pairs(sources) do
        for _, source in ipairs(list) do
            if source.itemKey == key then
                return source.slot
            end
        end
    end
    return nil
end

-- The hovered item's own road, then the top row of each remaining group in
-- order until three roads are shown, and the phrase when nothing rated it.
-- `others` is at most two, because the block is at most three roads
-- (docs/ROADS-UX.md surface 1).
Roads.TOOLTIP_ROADS = 3

function Roads.ForItem(key, inputs)
    inputs = type(inputs) == "table" and inputs or {}
    local answer = { others = {} }
    if type(key) ~= "string" then
        return answer
    end
    local slot = slotForKey(key, inputs)
    if not slot then
        answer.phrase = Roads.PHRASE_NOT_RATED_NEW
        return answer
    end
    local slotRoads = Roads.ForSlot(slot, inputs)
    answer.slot = slot
    answer.slotRoads = slotRoads

    ---@type LootpathRoad|nil
    local own
    local ownGroup
    for _, group in ipairs(Roads.GROUP_ORDER) do
        for _, road in ipairs(slotRoads.groups[group] or {}) do
            if not own then
                for _, held in ipairs(road.keys) do
                    if held == key then
                        own, ownGroup = road, group
                        break
                    end
                end
            end
        end
    end
    answer.own = own

    for _, group in ipairs(Roads.GROUP_ORDER) do
        if group ~= ownGroup and #answer.others < Roads.TOOLTIP_ROADS - 1 then
            local first = (slotRoads.groups[group] or {})[1]
            if first then
                answer.others[#answer.others + 1] = first
            end
        end
    end

    if not own then
        local item = nil
        for _, record in ipairs(records(inputs.inventory)) do
            if record.key == key then
                item = record
            end
        end
        answer.phrase = Roads.NotRatedPhrase(inputs.excluded, item, key)
    elseif own.phrase then
        answer.phrase = own.phrase
    end
    return answer
end

-- ---------------------------------------------------------------------------
-- The plan, in the words a guildmate would type in chat (principle 16).
--
-- Every phrasing below is written by hand, one per verb, and none of them is
-- assembled from a field name. What the sentence is allowed to contain is the
-- test: no labels, no colons, no percentages, no item levels, no "rated", no
-- "in your best set", and no source. Those live in the roads underneath it.
--
-- Nothing here decides anything. The pick is his top set's own vault item, the
-- conversions are his own clones in his own top-set order, and the skip names
-- the option his own alternatives say you could take instead.
Roads.NO_PLAN_SENTENCE = "Nothing this week beats what you've got on."

local function sentence(parts)
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " ")
end

-- "a", "a and b", "a, b and c" - the way a person writes a list, because a
-- clause joined by "and" four times is the giveaway that a machine wrote it.
local function joinList(items)
    if #items <= 1 then
        return items[1]
    end
    if #items == 2 then
        return items[1] .. " and " .. items[2]
    end
    local head = {}
    for index = 1, #items - 1 do
        head[index] = items[index]
    end
    return table.concat(head, ", ") .. " and " .. items[#items]
end

local function conversionPlace(conversion)
    local record = conversion.owned
    if type(record) ~= "table" then
        return nil
    end
    if conversion.fromVault then
        return "in the vault"
    end
    if record.location == "bag" then
        return "in your bag"
    end
    if record.location == "bank" then
        return "in your bank"
    end
    return nil
end

local function conversionName(conversion)
    local record = conversion.owned
    if type(record) == "table" then
        return Roads.ShortName({ name = record.name, slot = record.slot or conversion.slot })
    end
    return Roads.ShortName({ slot = conversion.slot })
end

-- PlanSentence(week) -> { sentence, footnote }. `week` is the same inputs table
-- every other function here takes: the whole week, which is what the Vault tab's
-- headline is about.
function Roads.PlanSentence(week)
    week = type(week) == "table" and week or {}
    local entry = Roads.Plan(week)
    if not entry then
        return { sentence = nil, footnote = nil }
    end
    local verdict = entry.verdict
    local bySlot, allItems = topSetBySlot(verdict)
    local owned = ownedByKey({ inventory = week.inventory })
    local charge = Roads.Charge(week.currencies)

    local vaultByKey = {}
    for _, held in ipairs(vaultRewards(week.vault)) do
        if held.reward.key then
            vaultByKey[held.reward.key] = held.reward
        end
    end

    local parts = {}

    -- 1. what to take out of the vault, and whether the rating assumed crests
    --    went into it.
    local vaultItem = planVaultItem(allItems)
    if vaultItem then
        local reward = vaultItem.key and vaultByKey[vaultItem.key] or nil
        local name = Roads.ShortName({
            name = reward and reward.name or nil,
            slot = vaultItem.slot,
            subType = reward and reward.subType or nil,
        })
        local clause = string.format("Grab %s from the vault", name or "it")
        local arrivesAt = reward and reward.itemLevel or nil
        if vaultItem.level and arrivesAt and vaultItem.level > arrivesAt then
            -- WHICH crest an upgrade takes is not readable from the client, so
            -- the sentence says to crest it and never names a track.
            clause = clause .. " and crest it"
        end
        parts[#parts + 1] = clause .. "."
    end

    -- 2. what you already own that the plan puts on.
    local equips = {}
    for _, item in ipairs(allItems) do
        local record = item.key and owned[item.key] or nil
        if record and record.location ~= "equipped" then
            equips[#equips + 1] = Roads.ShortName(record) or record.name
        end
    end
    if #equips > 0 then
        parts[#parts + 1] = string.format("Put on %s.", joinList(equips))
    end

    -- 3. where the one weekly charge goes. His top-set order decides which
    --    conversion the sentence names when he spends more charges than the
    --    client says you hold; the rest are the footnote. Nothing is chosen
    --    here and nothing is ranked: it is his own order, said out loud.
    local conversions = {}
    for _, conversion in ipairs(ns.QEImport.CatalyzedOwned(verdict, week.inventory) or {}) do
        conversions[#conversions + 1] = conversion
    end
    for _, conversion in ipairs(ns.QEImport.CatalyzedVault(verdict, week.vault) or {}) do
        conversions[#conversions + 1] = conversion
    end
    local footnote
    if #conversions > 0 then
        local named, rest = {}, {}
        if charge and charge.held and charge.held < #conversions then
            for index, conversion in ipairs(conversions) do
                if index <= math.max(charge.held, 1) then
                    named[#named + 1] = conversion
                else
                    rest[#rest + 1] = conversion
                end
            end
        else
            named = conversions
        end
        local clauses = {}
        for _, conversion in ipairs(named) do
            local place = conversionPlace(conversion)
            local text = string.format("%s", conversionName(conversion) or "it")
            if place then
                text = text .. " " .. place
            end
            clauses[#clauses + 1] = text
        end
        parts[#parts + 1] = string.format("Catalyst %s.", joinList(clauses))
        if #rest > 0 then
            local names = {}
            for _, conversion in ipairs(rest) do
                names[#names + 1] = conversionName(conversion) or "the other one"
            end
            local held = charge and charge.held or 0
            footnote = string.format(
                "The plan would catalyst %s too, but you've only got %s.",
                joinList(names),
                held == 1 and "one charge" or string.format("%d charges", held)
            )
        end
    end

    -- 4. what to leave. A vault option his own alternatives name, that his best
    --    set does not take, is the one the reader is tempted by; an option no
    --    set of his mentions is not a decision and is not in the sentence.
    local skips, seenSkip = {}, {}
    for _, alternative in ipairs(verdict and verdict.alternatives or {}) do
        for _, item in ipairs(alternative.items or {}) do
            if item.isVault and item.slot and not seenSkip[item.slot] then
                local inSet = false
                for _, planItem in ipairs(bySlot[item.slot] or {}) do
                    inSet = inSet or planItem.isVault == true
                end
                if not inSet then
                    seenSkip[item.slot] = true
                    skips[#skips + 1] = "the vault " .. (Roads.SlotWord(item.slot) or "reward")
                end
            end
        end
    end
    if #skips > 0 then
        parts[#parts + 1] = string.format("Skip %s.", joinList(skips))
    end

    if #parts == 0 then
        return { sentence = Roads.NO_PLAN_SENTENCE, footnote = nil, plan = Roads.PlanName(entry.scenario) }
    end
    return { sentence = sentence(parts), footnote = footnote, plan = Roads.PlanName(entry.scenario) }
end

-- The slot's own line, in the same voice: what this slot's part of the plan is.
-- Built from the slot's roads, so the header and the rows under it cannot
-- disagree.
function Roads.SlotSentence(slotRoads)
    if type(slotRoads) ~= "table" or type(slotRoads.groups) ~= "table" then
        return nil
    end
    local setRoads = slotRoads.groups[Roads.GROUP_SET] or {}
    local pick
    for _, road in ipairs(setRoads) do
        pick = pick or (road.planPick and road or nil)
    end
    if not pick then
        return nil
    end

    local clauses = {}
    local name = Roads.ShortName(pick.item)
    if pick.kind == Roads.KIND_VAULT then
        local clause = string.format("Grab %s from the vault", name or "it")
        if pick.rating and pick.rating.level and pick.arrivesAt and pick.rating.level > pick.arrivesAt then
            clause = clause .. " and crest it"
        end
        clauses[#clauses + 1] = clause
    elseif pick.kind == Roads.KIND_CATALYST then
        clauses[#clauses + 1] = string.format("Catalyst your %s", (name or "item"):gsub("^the ", ""))
    elseif pick.kind == Roads.KIND_KEEP then
        clauses[#clauses + 1] = "Keep what you've got on"
    else
        clauses[#clauses + 1] = string.format("Put on %s", name or "it")
    end

    local otherVault = false
    for _, road in ipairs(setRoads) do
        otherVault = otherVault or (road.kind == Roads.KIND_VAULT and not road.planPick)
    end
    if otherVault then
        clauses[#clauses + 1] = "skip the vault ones"
    end

    local crested = pick.kind == Roads.KIND_VAULT
        and pick.rating
        and pick.rating.level
        and pick.arrivesAt
        and pick.rating.level > pick.arrivesAt
    if not crested then
        clauses[#clauses + 1] = "no crests here"
    end

    return table.concat(clauses, ", ") .. "."
end
