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

-- The honesty phrases, fixed, each meaning one thing, each with its own cure
-- (docs/ROADS-UX.md principle 3 and the canvas's phrase table). A line never
-- says "not rated" without one of the two tails.
Roads.PHRASE_NOT_RATED_NEW = "not rated · new since the last refresh"
Roads.PHRASE_NOT_RATED_LIMIT = "not rated · beyond the rating's item limit"
Roads.PHRASE_NOT_IN_BEST_SET = "not in your best set"
Roads.PHRASE_NO_RATING = "no rating"
-- The fifth, and the one C-11 (WKE-572) exists to make possible: an item the
-- plan's own pass never saw, rated by a LATER pass over the same baseline plus
-- the leftovers, which put it in that pass's best set.
--
-- It does not say "in your best set", and that is the whole care of it. Your
-- best set is pass 1's, built over the vault options and the Catalyst clones as
-- well, and this item was not in the pool that built it. What a later pass
-- proves is exactly what this phrase says and no more: over the gear the
-- character is wearing, QE Live picked this item. No percent goes beside it
-- either - a later pass's differentials are against that pass's own top set,
-- and a number read against one set and printed beside another is a wrong
-- answer that looks right.
Roads.PHRASE_RATED_LATER = "rated · better than what you wear"
Roads.PHRASES = {
    Roads.PHRASE_NOT_RATED_NEW,
    Roads.PHRASE_NOT_RATED_LIMIT,
    Roads.PHRASE_NOT_IN_BEST_SET,
    Roads.PHRASE_NO_RATING,
    Roads.PHRASE_RATED_LATER,
}

-- The phrasing table for a row's last column: every imperative a road can end
-- with, written out here rather than at the place that happens to build it,
-- because principle 16 bounds them all the same way and a phrasing scattered
-- through the builders is a phrasing that escapes the bound.
--
-- The bound (R-3a, WKE-570, after the owner read "do: equip it" on a Head row
-- rated 0.95% behind the helm he was wearing): an imperative belongs only to a
-- road the plan is going forward on. `Roads.TODO_PREFIX` is what marks one, so
-- `Roads.GateImperatives` can find every one of them without knowing which
-- builder wrote it.
Roads.TODO_PREFIX = "do: "
Roads.TODO_TAKE_VAULT = "do: take it"
Roads.TODO_TAKE_VAULT_CREST = "do: take it · rated at %d, crests not readable"
Roads.TODO_TAKE_ONE_VAULT = "do: take one vault reward"
Roads.TODO_CATALYST = "do: Catalyst it"
Roads.TODO_CATALYST_CHARGE = "do: Catalyst it · charge %s"
Roads.TODO_EQUIP = "do: equip it"
Roads.TODO_RAID = "do: raid it · tick when it drops"
Roads.TODO_KEY = "do: run the key · tick when it drops"
Roads.TODO_CRAFT = "do: get the spark, then order it"
-- The step left on a road whose item has already arrived: the document is what
-- is behind now, not the player (R-3b, WKE-576).
Roads.TODO_REFRESH = "do: refresh to rate it"
-- Not imperatives, and so outside the gate. The first is the Keep row's own
-- line; the second is what a road rated behind says instead of a "do:", in the
-- plan's own words (`Roads.SlotSentence` opens with the same clause, from the
-- same string, so the header and the row cannot drift).
Roads.TODO_NOTHING = "nothing to do"
Roads.TODO_KEEP_WORN = "keep what you've got on"

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

-- What the same road says once the reward is in your bags (R-3b, WKE-576). The
-- vault's own state is not read for this and cannot be: the claim happened
-- after the last capture, so the only evidence is the item itself, sitting in
-- the bags with the plan's own item ID. "claimed" is what that evidence says
-- and "in your bags" is where it says it from; after the next refresh the vault
-- section is empty and the road goes away on its own.
Roads.VAULT_CLAIMED = "claimed · in your bags"

-- What the same road says once the pick has moved further than the bags (R-3c,
-- WKE-580). The badge slot is R-3b's; only the state word is new, and it is the
-- state the evidence says: the item is on the character, or it is still in the
-- bags at a level above the one the plan picked it at. "claimed" stays the
-- vault's own word and is said only about a vault reward - a piece out of a
-- dungeon was never claimed from anything, and a badge that said so would be
-- the one thing this lane does not do.
Roads.ARRIVED_NOW_WORN = "now worn"
Roads.ARRIVED_NOW_CRESTED = "now crested"
Roads.ARRIVED_CLAIMED_WORN = "claimed · now worn"
Roads.ARRIVED_CLAIMED_CRESTED = "claimed · now crested"

-- The client's own countdown, in the client's own units, and nothing else: the
-- vault road says how long is left, never what happens when it runs out
-- (principle 5, which is why "before reset" is not a string in this file).
Roads.RESET_TEXT = "reset in %s"

function Roads.ResetText(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then
        return nil
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then
        return string.format(Roads.RESET_TEXT, string.format("%dd %dh", days, hours))
    end
    if hours > 0 then
        return string.format(Roads.RESET_TEXT, string.format("%dh", hours))
    end
    return string.format(Roads.RESET_TEXT, string.format("%dm", math.floor((seconds % 3600) / 60)))
end

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

-- What a crafted road's rating assumed about the item: the stats line the
-- export was run with (`settings.craftedStats`, R-4). It is said because a
-- crafted item's stats are the crafter's choice and the number on the badge is
-- about one pair of them; it is never guessed, and the crafted LEVEL beside it
-- in the same settings is an INDEX rather than an item level and is never
-- shown at all (ns.UFImport.CraftedSettings).
Roads.CRAFT_STATS = "the rating assumes %s"

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
-- The one gate, asked twice.
--
-- Principle 12 is the glow's rule: it means "rated as in your best set or a
-- positive percent, under the highlighted plan", and a rated-but-worse item
-- does not glow. Principle 16 bounds the imperative to the road's own next
-- step, and a road rated behind what you wear has no next step - the plan is
-- to keep what you wear. That is the same test, so it is one function; the
-- glow (R-2) and `Roads.GateImperatives` below both call it and cannot drift.
--
-- True only for a rating. A road nothing rated is not "forward": not knowing
-- is not a verdict.
function Roads.IsForward(road)
    local rating = type(road) == "table" and road.rating or nil
    if type(rating) ~= "table" then
        return false
    end
    if rating.kind == Roads.RATING_SET then
        return rating.inTopSet == true
    end
    if rating.kind == Roads.RATING_ITEM then
        return (tonumber(rating.percent) or 0) > 0
    end
    return false
end

-- Whether anything rated this road at all, which is a different question from
-- which way the rating points. "Rated, and not in the best set" is a rating
-- (it is the third honesty phrase); the two "not rated" tails are not, and
-- neither is "no rating".
function Roads.IsRated(road)
    if type(road) ~= "table" then
        return false
    end
    local rating = road.rating
    if type(rating) == "table" and (rating.kind == Roads.RATING_SET or rating.kind == Roads.RATING_ITEM) then
        return true
    end
    return road.phrase == Roads.PHRASE_NOT_IN_BEST_SET
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

-- A step is either something to DO or something that is KNOWN. `fact` marks
-- the second kind - what the client says you hold, and what is not readable at
-- all - because a surface shows those beside the badge as muted facts while the
-- doing steps belong to the footer and the "do:" line (R-3, docs/ROADS-UX.md
-- surface 2). Nothing else about a step changes with the flag.
--
-- `cost` marks the one fact a tooltip may not carry: the vendor window's gate
-- (principle 7). `C_ItemUpgrade.GetItemUpgradeItemInfo` answers only for an
-- owned item placed in the OPEN vendor window, so on a vault reward or a drop
-- the cost is not readable at all and never will be. On the Upgrade Map row
-- that clause is the answer to "what will this cost me"; on a tooltip, where
-- nobody asked and there is no room, it is noise (R-2a, WKE-571: the owner read
-- it on both Head roads of one hover, 2026-09-14).
local function step(text, done, fact, cost)
    return { text = text, done = done, fact = fact or nil, cost = cost or nil }
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

-- The steps that state what is known rather than what to do: what the client
-- says you hold, and what is not readable at all. A surface shows these beside
-- the badge (R-3's muted facts); the doing steps belong to the footer. In the
-- order the road built them, because that order is the order of the road.
function Roads.Facts(road)
    local facts = {}
    for _, entry in ipairs(type(road) == "table" and road.steps or {}) do
        if entry.fact then
            facts[#facts + 1] = entry.text
        end
    end
    return facts
end

-- The subset of those that state what a road COSTS, which is the vendor
-- window's gate and nothing else. A surface with the vendor row on it says
-- them; the tooltip does not (R-2a, WKE-571). It is a subset of `Roads.Facts`
-- rather than a list beside it, so a fact cannot be in one and not the other.
function Roads.CostFacts(road)
    local facts = {}
    for _, entry in ipairs(type(road) == "table" and road.steps or {}) do
        if entry.fact and entry.cost then
            facts[#facts + 1] = entry.text
        end
    end
    return facts
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
        -- A document's item entry carries no name at all - a QE Live export
        -- is item IDs, keys and levels - so a road built from one is nameless
        -- until something names it. A LINK names it for free: the bracketed
        -- name is right there in the vault reward's own hyperlink and in every
        -- inventory record's (R-3b, WKE-576; the owner read `a vault reward
        -- (321)` eight hours after the build, 2026-09-14). What no link
        -- carries, `ns.RoadsCache` asks the client for.
        name = (source and source.name) or (source and ns.LinkName(source.link)) or nil,
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
--
-- The vault comes first, and the rule is the source's own (R-3e, WKE-585): **a
-- vault reward is a vault road whether or not his run upgraded it.** An upgrade
-- keeps the item ID and a conversion does not - `Item.convertToTier` copies
-- everything but the item ID - so a vault-flagged set item is a Catalyst road
-- only when the piece it was made FROM is a DIFFERENT item. That is the vault
-- clone M3-15 counts a charge for (the Scavenger's Spaulders going in, the tier
-- shoulder coming out), and it is not the owner's Legs pick of 2026-09-15: the
-- vault offered his tier leggings at 315, the run carried them at 321, and the
-- road called it a Catalyst conversion "into the tier legs" - of the tier legs.
--
-- With no vault snapshot to name the source, the conversion join still hands
-- one over so that a charge is never called free (QEImport's own comment). That
-- conservatism is about COUNTING a charge, not about where a reward comes from,
-- and it does not get to rename the road: unnamed means unknown, and a reward
-- the plan takes out of the vault is a vault road either way.
local function setItemKind(item, conversion, owned)
    if item.isVault then
        local from = conversion and conversion.owned or nil
        if from and tonumber(from.itemID) ~= tonumber(item.itemID) then
            return Roads.KIND_CATALYST
        end
        return Roads.KIND_VAULT
    end
    if conversion then
        return Roads.KIND_CATALYST
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
-- Upgrading what you wear: the `maxed` document's own answer (R-3c, WKE-580).
--
-- The crest road used to be `no rating` with `arrivesAt` set to the level the
-- piece is ALREADY at, which is a row that says "upgrade the 321 to 321" and
-- says nothing about whether that is worth doing. The `maxed` scenario exists
-- to rate exactly this question - it is QE Live's own run with every owned item
-- raised to its cap (C-6) - and on the owner's 2026-09-14 run its Dungeon top
-- set carries the crested staff. So the road reads that document, and the one
-- thing it never does is project a level of its own.
--
-- The join is `ns.QEImport.Coverage`, the same lookup both M3-3 panels use, and
-- it is by KEY. That is exact rather than nearly exact: the upgrade boxes move
-- an item's `level` without touching a bonus ID (QEImport.lua's own note on
-- CatalyzedOwned), so the piece on the character keeps its key under `maxed`
-- and only the level moves. What comes back is the document's own word - in the
-- top set, or the best alternative's percent - and the level it projected.
--
-- Returns nil when `maxed` is not stored at all, which is a different answer
-- from "stored and silent about this item" and is what lets the road say why.
Roads.SCENARIO_MAXED = "maxed"

function Roads.MaxedAnswer(inputs, record)
    if type(record) ~= "table" then
        return nil
    end
    local verdict
    for _, entry in ipairs(scenarioEntries(inputs)) do
        if entry.scenario == Roads.SCENARIO_MAXED then
            verdict = entry.verdict
        end
    end
    if type(verdict) ~= "table" then
        return nil
    end
    local answer = { verdict = verdict }
    local coverage = record.key and ns.QEImport.Coverage(verdict, record.key) or nil
    if not coverage then
        return answer
    end
    answer.level = tonumber(type(coverage.item) == "table" and coverage.item.level or nil)
    answer.inTopSet = coverage.where == "topSet"
    answer.scorePercent = coverage.scorePercent
    answer.hpsDifference = coverage.hpsDifference
    return answer
end

-- The companion's own sentence about the questions its run never asked (C-12),
-- read off the stored documents rather than written here. Every document of one
-- run carries the same note, because it is the run that skipped the question.
function Roads.ScenarioNote(inputs)
    for _, entry in ipairs(scenarioEntries(inputs)) do
        local note = type(entry.verdict) == "table" and entry.verdict.scenarioNote or nil
        if type(note) == "string" and note ~= "" then
            return note
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

-- Which later pass rated this item, and what it said (C-11, WKE-572).
--
-- `passes` is `ns.QEImport.Passes(contentType, scenario)`: the pass-2 and later
-- documents of the plan's own run, in pass order, each with the pool it was
-- shown. A pass answers about an item only if it CONSIDERED it, and the join is
-- `ns.Companion.IsConsidered`, which is C-10's identity join and not a second
-- one. The first pass that saw the item is the one that speaks for it: no pass
-- sees it twice, so there is never more than one.
--
-- `inTopSet` is `ns.QEImport.Coverage`'s own answer and nothing derived: that
-- pass's top set held the item, or it did not. No number travels with it, for
-- the reason written on `Roads.PHRASE_RATED_LATER`.
function Roads.LaterPass(passes, item, key)
    if type(passes) ~= "table" then
        return nil
    end
    if type(item) ~= "table" and key == nil then
        return nil
    end
    local itemKey = key or (type(item) == "table" and item.key or nil)
    local facts = {
        name = type(item) == "table" and item.name or nil,
        level = type(item) == "table" and tonumber(item.level or item.itemLevel) or nil,
    }
    for _, entry in ipairs(passes) do
        local verdict = type(entry) == "table" and entry.verdict or nil
        local considered = type(verdict) == "table" and verdict.considered or nil
        local found, how = ns.Companion.IsConsidered(considered, itemKey, facts)
        if found then
            local coverage = itemKey and ns.QEImport.Coverage(verdict, itemKey) or nil
            return {
                pass = entry.pass,
                verdict = verdict,
                entry = found,
                how = how,
                inTopSet = coverage ~= nil and coverage.where == "topSet",
            }
        end
    end
    return nil
end

-- Which tail applies to an item the plan's own pass did not rate.
--
-- Three answers now, not two (C-11). A later pass may have rated it, and then
-- the line says so: in that pass's best set is `rated · better than what you
-- wear`, and out of it is the third phrase, `not in your best set` - a pool
-- that held everything the character is wearing and did not pick this item is a
-- pool the fuller one could not have picked it out of either. Only an item NO
-- pass was ever shown is beyond the rating's item limit, and after C-11 that is
-- only what the pass bound left behind. Everything else is new since the last
-- refresh.
--
-- The second return is the pass number, for the surface that wants to say which
-- look rated it; callers that only want the phrase ignore it.
function Roads.NotRatedPhrase(excluded, item, key, passes)
    local later = Roads.LaterPass(passes, item, key)
    if later then
        return later.inTopSet and Roads.PHRASE_RATED_LATER or Roads.PHRASE_NOT_IN_BEST_SET, later.pass
    end
    if Roads.Excluded(excluded, item, key) then
        return Roads.PHRASE_NOT_RATED_LIMIT
    end
    return Roads.PHRASE_NOT_RATED_NEW
end

-- Did the run behind this plan ever SEE this vault reward (R-3d, WKE-584)?
--
-- The premise C-8 left on the vault road was that it always did: his importer
-- makes every vault option active the moment it is imported
-- (`SimCImportEngine.ts:712`), so a reward the plan's document never mentions
-- was rated and passed over, which is exactly the third phrase. That holds only
-- when the profile the companion built CARRIED a vault section. On reset day
-- before the player opens the Great Vault - and any week the client withheld
-- the links and no login restored them - the profile has none, QE Live was
-- shown no vault card at all, and "not in your best set" is the addon taking a
-- position on an item nothing ever rated (principle 3; the owner read it on
-- 2026-09-15, ARCHITECTURE.md §9).
--
-- Three answers, because the file may not be able to say:
--   false  the run is on record as having built its profile with no vault
--          items, or the pools its passes recorded do not hold this key;
--   true   a pass recorded a pool and the reward's key is in it;
--   nil    no pool and no count on record - every file written before C-11 and
--          every paste - so the question cannot be asked and C-8 stands.
--
-- The join is C-10's identity, through `ns.Companion.IsConsidered`, because
-- "was this item in the pool" already has one answer and a second one here
-- would be a second answer to it.
function Roads.VaultConsidered(entry, inputs, reward)
    local verdict = type(entry) == "table" and entry.verdict or nil
    if type(verdict) ~= "table" then
        return nil
    end
    -- The companion's own count of the vault section it built from (C-13).
    -- Zero outranks every pool below, because a pool that held no vault card
    -- and a pool nobody recorded look exactly alike from here.
    if verdict.profileVaultCount == 0 then
        return false
    end
    local key = type(reward) == "table" and reward.key or nil
    local facts = {
        name = type(reward) == "table" and reward.name or nil,
        level = type(reward) == "table" and tonumber(reward.itemLevel) or nil,
    }
    -- The plan's own document first, then its later passes: a vault option is a
    -- baseline card, so it is in every pass's pool or in none of them, and
    -- asking all of them costs nothing and cannot be wrong either way.
    local pools = { verdict }
    for _, pass in ipairs(type(inputs) == "table" and type(inputs.passes) == "table" and inputs.passes or {}) do
        if type(pass) == "table" and type(pass.verdict) == "table" then
            pools[#pools + 1] = pass.verdict
        end
    end
    local asked = false
    for _, pool in ipairs(pools) do
        local considered = pool.considered
        if type(considered) == "table" then
            asked = true
            if ns.Companion.IsConsidered(considered, key, facts) then
                return true
            end
        end
    end
    if not asked then
        return nil
    end
    return false
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
            road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READABLE, nil, true, true)
        end
        road.steps[#road.steps + 1] = step("take it from the Great Vault")
        road.verb = Roads.VERB_SHOW_IN_VAULT
        -- The vault hands over one reward, so a road for an option the plan did
        -- not pick must not read as a second thing to take. It never names the
        -- other road either (the copy rule): the options are in the badges.
        road.todo = (planVault and road.planPick) and Roads.TODO_TAKE_VAULT or Roads.TODO_TAKE_ONE_VAULT
        if
            road.todo == Roads.TODO_TAKE_VAULT
            and rating
            and rating.level
            and rating.arrivesAt
            and rating.level > rating.arrivesAt
        then
            road.todo = string.format(Roads.TODO_TAKE_VAULT_CREST, rating.level)
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
        road.todo = chargeText and string.format(Roads.TODO_CATALYST_CHARGE, chargeText) or Roads.TODO_CATALYST
        road.resource = charge
                and {
                    name = charge.name,
                    held = charge.held,
                    max = charge.max,
                }
            or nil
    elseif road.kind == Roads.KIND_KEEP then
        road.tag = Roads.TAG_KEEP
        road.todo = Roads.TODO_NOTHING
    else
        road.tag = Roads.TAG_EQUIP
        road.steps[#road.steps + 1] = step("it is in your bags", Roads.DONE_CLIENT)
        road.steps[#road.steps + 1] = step("put it on")
        road.todo = Roads.TODO_EQUIP
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
            -- catalyzed alike, because both spend the same one charge - and for
            -- neither of them when the road is the vault's own (R-3e, WKE-585).
            -- `setItemKind` has already read the source, so a KIND_VAULT road
            -- here is a reward that goes in and comes out the same item: it
            -- becomes nothing, it spends no charge, and its row says neither.
            local converts = kind ~= Roads.KIND_VAULT and (conversion ~= nil) or catalyzed
            road.becomes = converts and item or nil
            road.catalyzed = converts or nil
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

    -- A vault reward in this slot the plan's document never mentions. 558 read
    -- in his own importer that every vault option is active from the moment it
    -- is imported (`SimCImportEngine.ts:712`), so a reward the run IMPORTED
    -- cannot have fallen outside the item limit, and "rated, and not in the
    -- best set" is exactly the third phrase.
    --
    -- Narrowed by R-3d (WKE-584): that premise is about a reward the run
    -- imported, and the run imports nothing the profile did not carry. Where
    -- the file says the pool never held this reward, the honest line is the
    -- other one - nothing rated it, so the road joins the no-rating group and
    -- says so. `Roads.VaultConsidered` is the one place that decides which.
    for _, held in ipairs(vaultRewards(inputs.vault)) do
        local reward = held.reward
        if reward.slot == slot and not takenVault[reward.key] then
            local unseen = entry ~= nil and Roads.VaultConsidered(entry, inputs, reward) == false
            local group = (entry and not unseen) and Roads.GROUP_SET or Roads.GROUP_NONE
            local road = newRoad(Roads.KIND_VAULT, group, slot, itemFacts(reward))
            road.tag = Roads.TAG_VAULT
            road.openNow = Roads.VAULT_OPEN_NOW
            road.resetSeconds = type(inputs.vault) == "table" and inputs.vault.secondsUntilWeeklyReset or nil
            road.arrivesAt = reward.itemLevel
            road.plan = entry and Roads.PlanName(entry.scenario) or nil
            road.age = entry and entry.verdict and entry.verdict.exportedAt or nil
            if not entry then
                road.phrase = Roads.PHRASE_NO_RATING
            elseif unseen then
                road.phrase = Roads.PHRASE_NOT_RATED_NEW
            else
                road.phrase = Roads.PHRASE_NOT_IN_BEST_SET
            end
            road.rating = { kind = Roads.RATING_NONE, badge = road.phrase, arrivesAt = reward.itemLevel }
            road.steps[#road.steps + 1] = step("the vault is offering it", Roads.DONE_CLIENT)
            road.steps[#road.steps + 1] = step("take it from the Great Vault")
            road.verb = Roads.VERB_SHOW_IN_VAULT
            road.todo = Roads.TODO_TAKE_ONE_VAULT
            road.nextStep = Roads.NextStep(road)
            if reward.key then
                road.keys[#road.keys + 1] = reward.key
            end
            add(road)
        end
    end

    -- ---- upgrading what you wear ----
    -- Built before the drops so that the first row of its group is the one the
    -- tooltip would show: the piece in this slot, not an unrated drop from a
    -- difficulty nobody is running.
    --
    -- Since R-3c (WKE-580) the road carries the `maxed` document's answer when
    -- that document has one, which moves it into the SET group: it is a
    -- whole-set verdict, on the same scale and in the same words as every other
    -- set road, and the group it sat in said "no rating" about the one question
    -- `maxed` was asked. With no answer it stays where R-1 put it.
    for _, record in ipairs(records(inputs.inventory)) do
        if record.location == "equipped" and record.slot == slot then
            local maxed = Roads.MaxedAnswer(inputs, record)
            local projected = maxed and maxed.level or nil
            local wornLevel = tonumber(record.itemLevel)
            -- Nothing to crest: the document projected the level the piece
            -- already wears, so there is no road at all rather than a road
            -- that leads where the reader is standing.
            local nothingToCrest = projected ~= nil and wornLevel ~= nil and projected <= wornLevel
            if not nothingToCrest then
                local road = newRoad(
                    Roads.KIND_CREST,
                    projected and Roads.GROUP_SET or Roads.GROUP_NONE,
                    slot,
                    itemFacts(record)
                )
                road.tag = Roads.TAG_UPGRADE
                road.arrivesAt = projected or record.itemLevel
                if maxed and projected then
                    road.plan = Roads.PlanName(Roads.SCENARIO_MAXED)
                    road.age = maxed.verdict.exportedAt
                    road.rating = {
                        kind = Roads.RATING_SET,
                        inTopSet = maxed.inTopSet,
                        scorePercent = maxed.scorePercent,
                        hpsDifference = maxed.hpsDifference,
                        level = projected,
                        arrivesAt = projected,
                    }
                    road.rating.badge = Roads.SetBadge(road.rating)
                else
                    road.phrase = Roads.PHRASE_NO_RATING
                    road.rating =
                        { kind = Roads.RATING_NONE, badge = Roads.PHRASE_NO_RATING, arrivesAt = record.itemLevel }
                    -- Why there is no rating, in the companion's own words,
                    -- whenever the run said why (C-12). A bare "no rating" on
                    -- the one road `maxed` exists to rate is what the owner
                    -- read on 2026-09-14 and could do nothing with.
                    local why = not maxed and Roads.ScenarioNote(inputs) or nil
                    if why then
                        road.steps[#road.steps + 1] = step(why, nil, true)
                    end
                end
                road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READ, nil, true)
                -- What the client says you hold in crests is the vendor row's
                -- business, beside the cost it would pay: marked `cost` so the
                -- panel keeps it and the tooltip drops it (R-2a's rule, applied
                -- in R-3c to the longest clause on the owner's own block).
                local holding = Roads.CrestHoldingText(inputs.currencies)
                if holding then
                    road.steps[#road.steps + 1] = step(holding, Roads.DONE_CLIENT, true, true)
                end
                road.nextStep = Roads.NextStep(road)
                if record.key then
                    road.keys[#road.keys + 1] = record.key
                end
                add(road)
            end
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
                road.steps[#road.steps + 1] = step(Roads.CREST_NOT_READABLE, nil, true, true)
                road.steps[#road.steps + 1] = step("it drops for you", Roads.DONE_PLAYER)
                road.verb = Roads.VERB_SHOW_RUN
                if rated then
                    -- The difficulty is on the row's own source line, so the
                    -- imperative does not repeat it: the client's own label for
                    -- this walk is "Mythic raid", and "do: raid Mythic raid" is
                    -- not a sentence anybody types.
                    road.todo = source.isRaid and Roads.TODO_RAID or Roads.TODO_KEY
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
    --
    -- `ns.UFImport.SourceRows` is the one place these rows are found, ordered
    -- and deduplicated (R-4): every document's rows for the kind, his own
    -- percent best first, the first document that carries a row winning. This
    -- file used to walk the documents itself; the walk moved there when the
    -- Upgrade Map's by-run view needed the same list, so one shape of row
    -- cannot be read two ways.
    --
    -- A road carries no key level for one of these: measured over the
    -- committed companion run, all five key-level documents value the same 51
    -- Crafted and Delves rows identically and only a Raid export differs, so
    -- naming a key would claim a dependency his own files deny. `disagrees` is
    -- the case where two stored documents really do differ, and then the row
    -- names the document it took (ARCHITECTURE.md 7, 2026-09-13).
    local function addExportRows(kind, tag)
        for _, held in ipairs(ns.UFImport.SourceRows(documents, kind, slot)) do
            local item = held.entry
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
                keyLevel = held.disagrees and held.keyLevel or nil,
            }
            if (tonumber(item.upgradePercent) or 0) <= 0 then
                road.phrase = Roads.PHRASE_NOT_IN_BEST_SET
            end
            if kind == Roads.KIND_CRAFT then
                -- What the number assumed, when the export says: the stats a
                -- crafting order would have to ask for to be the item he
                -- ranked. A fact, not a step - there is nothing to tick.
                local stats = held.crafted and held.crafted.stats or nil
                if stats then
                    road.steps[#road.steps + 1] = step(string.format(Roads.CRAFT_STATS, stats), nil, true)
                end
                road.steps[#road.steps + 1] = step(Roads.CRAFT_NOT_READ, nil, true)
                road.todo = Roads.TODO_CRAFT
            else
                -- No delve step until a delve capture exists: the key's
                -- currency ID is in no capture and no client call says which
                -- delves are Bountiful. The row says so, without a "do:".
                road.steps[#road.steps + 1] = step(Roads.DELVE_NOT_READ, nil, true)
            end
            road.nextStep = Roads.NextStep(road)
            if item.key then
                road.keys[#road.keys + 1] = item.key
            end
            add(road)
        end
    end
    addExportRows(Roads.KIND_CRAFT, Roads.TAG_CRAFTED)
    addExportRows(Roads.KIND_DELVE, Roads.TAG_DELVES)

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

    -- ---- the pick that is already in the bags (R-3b) ----
    Roads.MarkArrived(result, inputs)
    result.staleBags = Roads.StaleBags(result, inputs)

    -- ---- principle 16's bound on the imperative ----
    Roads.GateImperatives(result)

    result.plan = Roads.SlotSentence(result)
    return result
end

-- ---------------------------------------------------------------------------
-- The pick that has already arrived (R-3b, WKE-576).
--
-- The owner did what the plan said - took the Lightgrasp Worldroot out of the
-- vault and put crests into it - and the plan then told him to skip it, because
-- the claimed copy carries its own bonus IDs and its own level and so its own
-- KEY, which no document mentions. Every line on that tooltip was honest about
-- the document and the sentence was wrong about the world.
--
-- **The item ID is what decides "this is the pick", never the key.** A key is
-- the item at one level with one set of bonus IDs, which is exactly what
-- claiming and cresting changes; the item ID is what survives both. So this is
-- a deliberately narrow identity test and not a join: it answers one question,
-- "is the thing in my bags the thing the plan picked", and it answers it about
-- the plan's OWN pick and nothing else.
--
-- **R-3c (WKE-580) widened it to every placement and every kind.** R-3b read
-- the bags and knew two picks; the owner then crested the bag pick and put it
-- on, and the tooltip told him to skip the staff in favour of itself. A pick
-- can move slot as well as key, and every kind of pick can: what the plan
-- picked out of your bags you are told to EQUIP, and doing that is exactly what
-- the plan asked for. So the placement is not what decides this - the item ID
-- is - and the sentence says which of the two things the player has done.
--
-- What it refuses to call arrived, and why:
--
--   * an item whose key the pick's road already carries - the vault reward
--     itself, or the bag piece a Catalyst road converts. Those are the road's
--     own item, and the road speaks for them.
--   * a WORN copy, when the pick is a vault reward or a Catalyst clone. That
--     is the 308 Worldroot he has worn all along, which shares the vault
--     copy's item ID, and NOTHING the client says tells the two apart: the
--     vault offered that staff at 305 while he wore 308, and cresting replaces
--     the upgrade bonus ID rather than adding to it, so neither the level nor
--     the bonus IDs can say which copy is on the character. R-3b's refusal
--     stands exactly where the evidence runs out and no further. For a pick the
--     plan took out of your own BAGS or off your character there is no such
--     doubt: a bag pick was not on the character when the plan was written, and
--     a worn twin above its level would have been the pick instead, so a worn
--     copy is the pick, put on.
--
-- **R-3e (WKE-585) took the LEVEL out of the identity.** The owner claimed the
-- Legs pick from his vault, crested it one step of the two the run had
-- projected - 318 of 321, because he had crests for one - and the tooltip over
-- it said `Skip this one, the plan uses your Dreamwatcher legs.` A reward
-- crested part-way has a new key (cresting replaces the upgrade bonus ID), the
-- pick's own item ID, and a level under the one the plan picked it at, and the
-- level gate sent it to the generic skip. The plan's pick told him to skip
-- itself. So: **identity is the item ID plus "not one of the pick's own keys",
-- and the LEVEL only words the sentence.** What that gives up is the one thing
-- the gate bought - a genuinely worse second copy of the pick's item ID now
-- reads as the pick, under-crested - and that is the better of the two wrong
-- answers: it tells the player to crest a piece the plan does want, where the
-- gate told him to skip the piece the plan sent him for.
--
-- A Catalyst pick is matched on what it BECOMES and on nothing else: the clone
-- that comes out of the Catalyst carries the tier item ID, and the item that
-- went in is still the road's own item. Every other kind is matched on the
-- pick's item ID, and a vault pick his export catalyzed on both, because that
-- reward can arrive either side of the conversion.
function Roads.IsArrivedPick(held, pick)
    if type(held) ~= "table" or type(pick) ~= "table" or pick.planPick ~= true then
        return false
    end
    local itemID = tonumber(held.itemID)
    if not itemID then
        return false
    end
    for _, key in ipairs(pick.keys or {}) do
        if key ~= nil and key == held.key then
            return false
        end
    end
    local becomes = type(pick.becomes) == "table" and tonumber(pick.becomes.itemID) or nil
    local wanted = type(pick.item) == "table" and tonumber(pick.item.itemID) or nil
    local matches = becomes ~= nil and becomes == itemID
    if not matches and pick.kind ~= Roads.KIND_CATALYST then
        matches = wanted ~= nil and wanted == itemID
    end
    if not matches then
        return false
    end
    if held.location == "equipped" and pick.kind ~= Roads.KIND_SET and pick.kind ~= Roads.KIND_KEEP then
        return false
    end
    return true
end

-- Whether the pick has arrived short of the level the plan picked it at: the
-- crest the plan assumed has not all been spent yet (R-3e, WKE-585). The other
-- half of `ArrivedCrested`, read off the same two figures - the held item's own
-- link and the road's own `arrivesAt` - and never off a document.
function Roads.ArrivedShort(held, pick)
    local level = tonumber(type(held) == "table" and (held.itemLevel or held.level) or nil)
    local arrivesAt = tonumber(type(pick) == "table" and pick.arrivesAt or nil)
    return level ~= nil and arrivesAt ~= nil and level < arrivesAt
end

-- Whether the pick has been crested since the plan: the held level is above the
-- level the plan picked it at. Read off the held item's own link and the road's
-- own `arrivesAt`, and never from a document - the whole point of this lane is
-- that no document mentions the copy in the player's hands.
function Roads.ArrivedCrested(held, pick)
    local level = tonumber(type(held) == "table" and (held.itemLevel or held.level) or nil)
    local arrivesAt = tonumber(type(pick) == "table" and pick.arrivesAt or nil)
    return level ~= nil and arrivesAt ~= nil and level > arrivesAt
end

-- The slot's pick, which is the one road the whole set group is arranged
-- around. At most one exists: his own `ItemSet.ts:205` allows one vault option
-- per set and `setRoad` marks exactly the top-set entries.
function Roads.PlanPick(slotRoads)
    if type(slotRoads) ~= "table" or type(slotRoads.groups) ~= "table" then
        return nil
    end
    for _, road in ipairs(slotRoads.groups[Roads.GROUP_SET] or {}) do
        if road.planPick then
            return road
        end
    end
    return nil
end

-- Marks the slot when the pick has already arrived - in the bags, or on the
-- character since R-3c - and says so on the road the reader would otherwise be
-- told to walk again. Run over the finished slot,
-- beside the other two sweeps, so no builder can produce a vault road that
-- escapes it.
--
-- Nothing here reads the vault. The claim is in no capture until the next
-- refresh, so what the road says changes on the evidence of the bags alone -
-- and when the refresh lands, the vault section is empty, the road is not built
-- at all, and this says nothing because there is nothing to say.
function Roads.MarkArrived(slotRoads, inputs)
    if type(slotRoads) ~= "table" then
        return slotRoads
    end
    inputs = type(inputs) == "table" and inputs or {}
    local pick = Roads.PlanPick(slotRoads)
    if not pick then
        return slotRoads
    end
    -- Every key the set group already speaks for, not just the pick's own
    -- (R-3c). Two worn rings of one item ID are two rated roads on this screen,
    -- and the second of them has not "arrived" anywhere: the document knows it
    -- by its own key and says so on its own row.
    local spokenFor = {}
    for _, road in ipairs(slotRoads.groups[Roads.GROUP_SET] or {}) do
        for _, key in ipairs(road.keys or {}) do
            spokenFor[key] = true
        end
    end
    -- The furthest-along copy is the one the sentence is about: a piece on the
    -- character is a step past the same piece in the bags, so a player who has
    -- claimed, crested and equipped is not told to equip it again.
    local arrived
    for _, record in ipairs(records(inputs.inventory)) do
        if record.slot == slotRoads.slot and not spokenFor[record.key] and Roads.IsArrivedPick(record, pick) then
            if not arrived or (record.location == "equipped" and arrived.location ~= "equipped") then
                arrived = record
            end
        end
    end
    if not arrived then
        return slotRoads
    end
    slotRoads.arrived = arrived
    pick.arrived = arrived
    local worn = arrived.location == "equipped"
    -- The badge slot R-3b gave the vault road, now on the pick of every kind:
    -- a row that still reads "open now · do: take it · Show in vault", or "do:
    -- equip it" about a piece already on the character, is the same wrong
    -- sentence in three more places.
    local crested = Roads.ArrivedCrested(arrived, pick)
    if pick.kind == Roads.KIND_VAULT then
        -- The vault reward is out of the vault whatever else has happened to
        -- it, so this road always has something to say.
        pick.claimed = (worn and Roads.ARRIVED_CLAIMED_WORN)
            or (crested and Roads.ARRIVED_CLAIMED_CRESTED)
            or Roads.VAULT_CLAIMED
    else
        -- Nothing was claimed from anywhere, so the badge is the state alone -
        -- and with neither state true (a same-level twin of the pick sitting in
        -- the bags) there is no state to report and the road keeps its words.
        pick.claimed = (worn and Roads.ARRIVED_NOW_WORN) or (crested and Roads.ARRIVED_NOW_CRESTED) or nil
    end
    -- What is left to do. On the character there is nothing but the refresh the
    -- document is waiting for; still in the bags, the step the road already
    -- carries is the right one and stays.
    if worn or pick.kind == Roads.KIND_VAULT then
        pick.verb = Roads.VERB_REFRESH
        pick.todo = Roads.TODO_REFRESH
    end
    return slotRoads
end

-- Whether anything the player is carrying in this slot is newer than the plan:
-- a held piece no road of the slot rates, whose tail is the one a refresh
-- cures. That is the fact a stale plan can say out loud about itself (R-3b,
-- WKE-576, defect 4), and it is read off the same records and the same phrase
-- function every honesty tail is read off.
function Roads.StaleBags(slotRoads, inputs)
    if type(slotRoads) ~= "table" or type(slotRoads.groups) ~= "table" then
        return false
    end
    inputs = type(inputs) == "table" and inputs or {}
    local rated = {}
    for _, group in ipairs(Roads.GROUP_ORDER) do
        for _, road in ipairs(slotRoads.groups[group] or {}) do
            for _, key in ipairs(road.keys or {}) do
                rated[key] = true
            end
        end
    end
    for _, record in ipairs(records(inputs.inventory)) do
        if record.slot == slotRoads.slot and not rated[record.key] then
            if
                Roads.NotRatedPhrase(inputs.excluded, record, record.key, inputs.passes) == Roads.PHRASE_NOT_RATED_NEW
            then
                return true
            end
        end
    end
    return false
end

-- Takes the "do:" off every road of a slot the plan is not going forward on,
-- over the finished slot rather than inside each builder, so that no phrasing
-- can be added in one of them and escape the bound (R-3a, WKE-570).
--
-- The gate is `Roads.IsForward`, which is the glow's own rule. What a gated
-- road says instead is the plan's next step for THIS slot, and the plan has
-- words for that in exactly one case: when its pick is the piece already on
-- the character, the answer is "keep what you've got on". When the plan picks
-- some other road in the slot, the row does not get an imperative pointing at
-- it - principle 16 forbids an imperative that is a choice between roads, and
-- the badge's own referent ("taking the vault weapon instead") has already
-- said where the plan went. The row then ends after its facts.
--
-- A road nothing rated keeps no imperative either and gains no phrase: not
-- knowing is not a verdict, so it cannot tell anyone to keep what they wear.
function Roads.GateImperatives(slotRoads)
    if type(slotRoads) ~= "table" or type(slotRoads.groups) ~= "table" then
        return slotRoads
    end
    local keepsWorn = false
    for _, road in ipairs(slotRoads.groups[Roads.GROUP_SET] or {}) do
        keepsWorn = keepsWorn or (road.planPick == true and road.kind == Roads.KIND_KEEP)
    end
    for _, group in ipairs({ Roads.GROUP_SET, Roads.GROUP_ITEM, Roads.GROUP_NONE }) do
        for _, road in ipairs(slotRoads.groups[group] or {}) do
            if not Roads.IsForward(road) then
                local imperative = type(road.todo) == "string"
                    and road.todo:sub(1, #Roads.TODO_PREFIX) == Roads.TODO_PREFIX
                if keepsWorn and Roads.IsRated(road) and road.kind ~= Roads.KIND_KEEP then
                    -- Every rated-behind road of the slot says the one thing,
                    -- whether or not the builder gave it an imperative: two
                    -- rows carrying the same verdict must not end differently.
                    road.todo = Roads.TODO_KEEP_WORN
                elseif imperative then
                    road.todo = nil
                end
            end
        end
    end
    return slotRoads
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
    return Roads.ForItemIn(Roads.ForSlot(slot, inputs), key, inputs)
end

-- The same answer, over a slot's roads that have already been built. R-2's
-- cache builds every slot once per verdict and then asks this for every key it
-- holds, so a hover is a table lookup and never a walk: `ForItem` above is the
-- one-shot caller and this is the body both of them share. Nothing here reads
-- `inputs` except to name the phrase for an item no road carries.
function Roads.ForItemIn(slotRoads, key, inputs)
    inputs = type(inputs) == "table" and inputs or {}
    local answer = { others = {} }
    if type(slotRoads) ~= "table" or type(slotRoads.groups) ~= "table" or type(key) ~= "string" then
        return answer
    end
    local slot = slotRoads.slot
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

    -- The other roads this answer offers, one per remaining group, and RATED
    -- ONLY (R-2a, WKE-571). The Upgrade Map lists the no-rating group because a
    -- reader who opened a slot asked for everything it opens onto; a tooltip
    -- has three lines and the reader asked about one item, so a road nothing
    -- rated cannot take one of them. A "no rating" road under a best-set pick
    -- is the shape the owner read on 2026-09-14 and it told him nothing.
    -- Principle 10's three is a cap, not a quota.
    for _, group in ipairs(Roads.GROUP_ORDER) do
        if group ~= ownGroup and #answer.others < Roads.TOOLTIP_ROADS - 1 then
            local forward, rated
            for _, road in ipairs(slotRoads.groups[group] or {}) do
                if Roads.IsForward(road) then
                    forward = forward or road
                elseif Roads.IsRated(road) then
                    rated = rated or road
                end
            end
            local pick = forward or rated
            if pick then
                answer.others[#answer.others + 1] = pick
            end
        end
    end

    -- Whether the player is carrying this item, which is what decides that the
    -- plan owes it a sentence (R-2a, WKE-571; `Roads.ItemSentence`). It is read
    -- off the same records the honesty phrase is read off, so "held" and "the
    -- item the phrase is about" can never be two different questions.
    local item = nil
    for _, record in ipairs(records(inputs.inventory)) do
        if record.key == key then
            item = record
        end
    end
    answer.held = item ~= nil
    -- The record itself, not just the fact of it: "is this the pick, arrived"
    -- is a question about the item's own identity (R-3b, WKE-576).
    answer.heldItem = item
    -- Whether the plan is behind the bags in this slot, which is what lets a
    -- stale plan name its own remedy (defect 4).
    answer.stale = slotRoads.staleBags == true

    if not own then
        -- Which pass rated it travels with the phrase (C-11): the line says
        -- what is true of the item and the sentence above it says why the plan
        -- does not mention it.
        answer.phrase, answer.laterPass = Roads.NotRatedPhrase(inputs.excluded, item, key, inputs.passes)
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
--
-- `week.scenarioNote` is the companion's own sentence about the questions its
-- last run did not ask (C-12, WKE-577). It becomes the FOOTNOTE whenever the
-- plan the screen is following has no document behind it, because that is the
-- exact case the owner hit on 2026-09-14: the Vault tab followed `thisWeek`,
-- the companion had skipped `thisWeek` for want of vault gear, and the tab fell
-- back to `asOffered` without a word. A plan read off a different question than
-- the one on the label is worth saying out loud.
function Roads.PlanSentence(week)
    week = type(week) == "table" and week or {}
    local note = type(week.scenarioNote) == "string" and week.scenarioNote ~= "" and week.scenarioNote or nil
    local entry, fellBack = Roads.Plan(week)
    if not entry then
        return { sentence = nil, footnote = note }
    end
    local verdict = entry.verdict
    -- R-3d (WKE-584): the run built its profile with no vault section, so every
    -- pick below was chosen without this week's vault in front of it. A plan
    -- read out on the Vault tab is read as a decision about the vault, and this
    -- one is not one. The cure is the whole sentence.
    if type(verdict) == "table" and verdict.profileVaultCount == 0 then
        return {
            sentence = Roads.VAULT_UNRATED_SENTENCE,
            footnote = fellBack and note or nil,
            plan = Roads.PlanName(entry.scenario),
        }
    end
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

    -- The companion's sentence, said only when the plan on screen is not the
    -- plan the screen asked for: with the highlighted scenario's own document
    -- stored, the note is about questions this sentence never claimed to
    -- answer, and the tab has other places to say it.
    if fellBack and note then
        footnote = footnote and (footnote .. " " .. note) or note
    end
    if #parts == 0 then
        return { sentence = Roads.NO_PLAN_SENTENCE, footnote = footnote, plan = Roads.PlanName(entry.scenario) }
    end
    return { sentence = sentence(parts), footnote = footnote, plan = Roads.PlanName(entry.scenario) }
end

-- The sentence for the pick that has already arrived (R-3b, WKE-576). Two
-- clauses: what the thing in the bag IS, and the one thing the reader can do
-- about it right now. It names no rating and invents none - the line under it
-- still says "not rated · new since the last refresh", which is the truth about
-- the document - and the level in it is the item's own, off the link the player
-- is hovering, never the level the document projected.
--
-- The noun comes from the same place the "skip" sentence's does, so the two
-- sentences call one item one thing: `Roads.ShortName` for a vault reward, and
-- the slot's own word for a tier piece, which is what the Catalyst produces and
-- what the row beside it already calls "the tier shoulders".
Roads.ARRIVED_VAULT = "This is the vault %s the plan wanted."
Roads.ARRIVED_TIER = "This is the tier %s the plan wanted."
Roads.ARRIVED_HELD = "This is %s the plan wanted."
Roads.ARRIVED_REFRESH_AT = "Refresh to rate it at %d."
Roads.ARRIVED_REFRESH = "Refresh to rate it."

-- R-3c (WKE-580): the same two clauses for the two states further along the
-- road. On the character there is no need to name the item at all - the reader
-- is hovering it - so the first clause is what the player DID, which is what
-- tells "you put this on" from "you crested it and put it on". Still in the
-- bags and crested, the first clause names the item as it did before and the
-- second one carries both steps that are left, in the order they happen.
--
-- The level in every one of them is the held item's own, off the link the player
-- is hovering, and the crest is read as "above the level the plan picked it at"
-- and nothing more.
Roads.ARRIVED_CRESTED_TO = "%s, crested to %d."
Roads.ARRIVED_WORN = "You've put this on."
Roads.ARRIVED_WORN_CRESTED = "You've crested this and put it on."
Roads.ARRIVED_PUT_ON = "Put it on; refresh to rate it."

-- R-3e (WKE-585): the pick arrived with the crest half spent. The owner's Legs
-- pick came out of the vault at 315, he crested it to 318 of the 321 his run
-- had projected, and the two clauses say the same two things they always say -
-- what the thing IS, at the level the link says, and the one step left. The
-- second clause names the plan's own level and nothing else: which crest that
-- step takes and what it costs are not read from the client (principle 4).
Roads.ARRIVED_AT = "%s, at %d."
Roads.ARRIVED_WORN_AT = "You've put this on at %d."
Roads.ARRIVED_CREST_TO = "Crest it to %d; refresh to rate it."

-- The sentence for a piece the plan was built without and a later pass picked
-- over what the character wears (C-11, WKE-572). Two clauses, like every other
-- sentence here: what the thing IS, and why the plan says nothing about it. It
-- names no number, no pass and no source, and it does not tell the reader to
-- put it on - the plan has not weighed this item against the vault, and an
-- imperative would be the addon deciding what QE Live was never asked.
Roads.BEATS_WORN_SENTENCE = "This beats what you've got on. The plan was built before anything had rated it."

-- The sentence for something the vault is OFFERING that the rating never
-- imported (R-3d, WKE-584). Principle 16 owes every held-or-offered item a
-- sentence and principle 3 forbids this one a position, so it says the one true
-- thing and names the cure - the same cure the header's "/lootpath refresh"
-- already names (R-3b). It is not "Skip this one": the plan has no grounds to
-- skip an item no document ever saw.
Roads.NOT_RATED_YET_SENTENCE = "The plan hasn't rated this yet. Refresh, then look again."

-- The Vault tab's whole headline when the run that produced the plan built its
-- profile with no vault section at all (R-3d, WKE-584). Not a pick, because
-- every pick this plan could name was chosen without the week's vault in front
-- of it, and a pick drawn from that run reads as a decision about the vault.
-- One imperative, the only one there is.
Roads.VAULT_UNRATED_SENTENCE = "The plan was rated before your vault was generated. Refresh."

function Roads.ArrivedSentence(held, pick)
    if type(held) ~= "table" or type(pick) ~= "table" then
        return nil
    end
    local level = tonumber(held.itemLevel or held.level)
    local crested = Roads.ArrivedCrested(held, pick)
    local short = Roads.ArrivedShort(held, pick)
    local arrivesAt = tonumber(pick.arrivesAt)

    -- On the character. The hover is the item, so the sentence spends both
    -- clauses on what has happened and what is left.
    if held.location == "equipped" then
        if short and level and arrivesAt then
            -- Worn, but not crested as far as the plan picked it (R-3e): what
            -- is left is the rest of the crest, not the refresh alone.
            return string.format(Roads.ARRIVED_WORN_AT, level)
                .. " "
                .. string.format(Roads.ARRIVED_CREST_TO, arrivesAt)
        end
        local first = crested and Roads.ARRIVED_WORN_CRESTED or Roads.ARRIVED_WORN
        local second = level and string.format(Roads.ARRIVED_REFRESH_AT, level) or Roads.ARRIVED_REFRESH
        return first .. " " .. second
    end

    local becomes = type(pick.becomes) == "table" and tonumber(pick.becomes.itemID) or nil
    local name = Roads.ShortName(pick.item) or ("the " .. (Roads.SlotWord(pick.slot) or "reward"))
    local bare = name:gsub("^the ", "")
    local first
    if becomes and becomes == tonumber(held.itemID) then
        first = string.format(Roads.ARRIVED_TIER, Roads.SlotWord(pick.slot) or "piece")
    elseif pick.kind == Roads.KIND_VAULT then
        first = string.format(Roads.ARRIVED_VAULT, bare)
    else
        -- A pick the plan took out of your own bags, or off your character: it
        -- came from nowhere new, so the clause names no source.
        first = string.format(Roads.ARRIVED_HELD, name)
    end
    if short and level and arrivesAt then
        -- Still short of the plan's level (R-3e). The first clause names the
        -- item as it always does and carries the level off the link; the second
        -- is the crest that is left, and it does not also say to put the piece
        -- on - the plan's own level is the thing to reach first.
        return string.format(Roads.ARRIVED_AT, first:gsub("%.$", ""), level)
            .. " "
            .. string.format(Roads.ARRIVED_CREST_TO, arrivesAt)
    end
    if crested and level then
        -- The crest is the news, and the step left is not the refresh alone:
        -- the plan still wants this piece on the character.
        return string.format(Roads.ARRIVED_CRESTED_TO, first:gsub("%.$", ""), level) .. " " .. Roads.ARRIVED_PUT_ON
    end
    local second = level and string.format(Roads.ARRIVED_REFRESH_AT, level) or Roads.ARRIVED_REFRESH
    return first .. " " .. second
end

-- The hovered item's own part of the plan, in the same chat voice as the week's
-- sentence and the slot's (principle 16). One or two clauses, never a label, a
-- percentage or an item level: those are on the road line under it.
--
-- **Every piece you HOLD gets one, rated or not** (R-2a, WKE-571; the owner
-- read a bag helmet that opened on "not rated - beyond the rating's item limit"
-- and no sentence at all, 2026-09-14, against principle 16). The plan takes a
-- position on everything you own: use it, catalyst it, or skip it. So there are
-- two ways in - the set group (a Catalyst clone, a vault option, what you wear)
-- and your bags.
--
-- What stays sentence-less is a road to something you do NOT have: a journal
-- drop, a crafted row, a delve row. The plan takes no position on those at all,
-- and "Skip this one" on a dungeon drop would read as "skip the dungeon", which
-- is a thing to do that no document said. Those hovers open on their road line
-- instead (R-2, 2026-09-14; ARCHITECTURE.md §7).
function Roads.ItemSentence(answer)
    if type(answer) ~= "table" then
        return nil
    end
    local own = answer.own
    -- R-3d (WKE-584): a vault reward the rating never imported. The vault is
    -- offering it, so principle 16 owes it a sentence; nothing rated it, so
    -- principle 3 forbids it the one every other unpicked road gets. Asked
    -- before the groups below because the road sits in the no-rating group and
    -- the reward is in the vault rather than in the bags, which is the pair of
    -- facts that would otherwise leave it sentence-less.
    if type(own) == "table" and own.kind == Roads.KIND_VAULT and own.phrase == Roads.PHRASE_NOT_RATED_NEW then
        return Roads.NOT_RATED_YET_SENTENCE
    end
    if type(own) == "table" and own.group == Roads.GROUP_SET then
        if own.planPick then
            if own.kind == Roads.KIND_VAULT then
                if own.rating and own.rating.level and own.arrivesAt and own.rating.level > own.arrivesAt then
                    return "Grab this from the vault and crest it."
                end
                return "Grab this from the vault."
            elseif own.kind == Roads.KIND_CATALYST then
                return "Catalyst this one."
            elseif own.kind == Roads.KIND_KEEP then
                return "Keep this on."
            end
            return "Put this on."
        end
    elseif answer.held ~= true then
        return nil
    end

    -- Not the pick. What the plan does instead is the other half of the
    -- sentence, and it is named only when the pick is on the same screen -
    -- principle 6's rule, applied to the plan: a reference to a road the
    -- reader cannot see is not a reference.
    local pick
    for _, road in ipairs((answer.slotRoads and answer.slotRoads.groups or {})[Roads.GROUP_SET] or {}) do
        pick = pick or (road.planPick and road or nil)
    end

    -- Unless it IS the pick, arrived since the last refresh. The document has
    -- no key for the claimed copy, so no road here carries it and everything
    -- below would tell the reader to skip the very thing the plan sent him for
    -- (R-3b, WKE-576). No rating is invented: the line says what the item is
    -- and what would rate it, and the honesty phrase under it still says the
    -- item is not rated.
    --
    -- Asked even when the item HAS a road of its own, because since R-3c the
    -- arrived copy can be the one on the character, and every worn piece has an
    -- Upgrade road whether anything rated it or not (WKE-580: the owner's
    -- crested-and-worn Worldroot opened on that road and was told to skip
    -- itself). The one road that speaks louder is a set-group road: a road in
    -- that group carries this very key, which means the document rates this
    -- copy as itself, and then the plan's own words for it are the answer.
    local ownsSetRoad = type(own) == "table" and own.group == Roads.GROUP_SET
    if not ownsSetRoad and pick and Roads.IsArrivedPick(answer.heldItem, pick) then
        return Roads.ArrivedSentence(answer.heldItem, pick)
    end
    -- A piece the plan's own pass never saw, which a later pass put in its best
    -- set (C-11, WKE-572). "Skip this one" would be the plan taking a position
    -- it has no grounds for: the pool that built the plan did not hold this
    -- item, and the pool that did hold it preferred it to what the character is
    -- wearing. So the sentence says both halves and invents neither, and the
    -- line under it carries `Roads.PHRASE_RATED_LATER`.
    if not own and answer.phrase == Roads.PHRASE_RATED_LATER then
        return Roads.BEATS_WORN_SENTENCE
    end
    local name = pick and Roads.ShortName(pick.item) or nil
    if not name then
        return "Skip this one."
    end
    -- Whose the pick is decides the possessive, and nothing else does: a
    -- Catalyst road converts a piece you hold and a Keep road is what you have
    -- on, so both are "your"; a vault option is not yours until you take it, so
    -- it is "the vault ...".
    local bare = name:gsub("^the ", "")
    if pick.kind == Roads.KIND_VAULT then
        return string.format("Skip this one, the plan uses the vault %s.", bare)
    end
    if pick.kind == Roads.KIND_KEEP then
        return string.format("Skip this one, the plan keeps your %s on.", bare)
    end
    return string.format("Skip this one, the plan uses your %s.", bare)
end

-- A clause that opens a sentence, built from the same string the row's last
-- column uses. One string, two places, so the slot's header and the rows under
-- it cannot say the plan two different ways.
local function capitalised(text)
    return text:sub(1, 1):upper() .. text:sub(2)
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
        clauses[#clauses + 1] = capitalised(Roads.TODO_KEEP_WORN)
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
