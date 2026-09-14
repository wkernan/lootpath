-- Lootpath/Modules/RoadsCache.lua (R-2, WKE-563)
-- One map per verdict, so a hover is a lookup.
--
-- The tooltip post-call fires for EVERY item tooltip in the game. The owner's
-- own client answered 2,566 of them in 133 seconds - 1,156 a minute - on the
-- R-0 spike run of 2026-09-14 (ARCHITECTURE.md §9), so whatever the handler
-- does has to be O(1) or an immediate return. The journal walk behind a slot's
-- roads is 478 drops; walking it on a hover is not a thing this addon does.
--
-- So: `Build` walks every slot ONCE, over the same inputs the Upgrade Map tab
-- is drawn from, and stores the answer for every item key those roads carry.
-- `Lookup` is a table index. `ns.Glow.Wants` is a table index. Neither of them
-- allocates, iterates or reads the client.
--
-- **Nothing is computed here.** Every road, badge, phrase and sentence in the
-- map is `ns.Roads`'s, built from the companion's own documents; this file
-- only decides WHEN to ask, and keeps the answer.
--
-- Rebuilt, debounced, on the events that can change what the answer is:
-- `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`, `WEEKLY_REWARDS_UPDATE`,
-- `CURRENCY_DISPLAY_UPDATE`, the `ItemData` load results and the companion
-- import. Never in combat: `PLAYER_REGEN_ENABLED` is what un-defers it, and
-- until then the map keeps what it had, which is the last thing that was true.

local _, ns = ...

ns.RoadsCache = {}
local Cache = ns.RoadsCache

-- The events that can make the map wrong. Named here rather than discovered,
-- the way every other module names what it listens to.
Cache.EVENTS = {
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "WEEKLY_REWARDS_UPDATE",
    "CURRENCY_DISPLAY_UPDATE",
}

-- How long a burst of those events is allowed to run before one rebuild
-- answers all of them. A bag sort fires BAG_UPDATE_DELAYED once per bag.
Cache.DEBOUNCE_SECONDS = 0.5

local state = { map = nil, pending = false, deferred = false, listener = nil, named = {} }

-- ---------------------------------------------------------------------------
-- Building.

-- The empty answer, so every caller has one shape to read whether or not
-- anything has been built yet.
local function emptyMap(reason)
    return {
        reason = reason,
        byKey = {},
        byItemLevel = {},
        bySlot = {},
        glow = {},
        slots = {},
        counts = { slots = 0, keys = 0, glowing = 0 },
    }
end

-- Every slot a road could lead into, read off the same three places
-- `ns.Roads` reads a key's slot from: what you hold, what the vault offers,
-- and what the journal walk found. Sorted, so a rebuild produces the same map
-- twice and a test can say which slots were walked.
local function slotsFor(inputs)
    local seen, slots = {}, {}
    local function note(slot)
        if type(slot) == "string" and slot ~= "" and not seen[slot] then
            seen[slot] = true
            slots[#slots + 1] = slot
        end
    end
    local inventory = type(inputs.inventory) == "table" and inputs.inventory or {}
    for _, record in ipairs(inventory.records or {}) do
        note(record.slot)
    end
    local vault = type(inputs.vault) == "table" and inputs.vault or {}
    for _, option in ipairs(vault.options or {}) do
        for _, reward in ipairs(type(option) == "table" and option.rewards or {}) do
            note(type(reward) == "table" and reward.slot or nil)
        end
    end
    local journal = type(inputs.journal) == "table" and (inputs.journal.sources or inputs.journal) or {}
    for _, list in pairs(journal) do
        for _, source in ipairs(type(list) == "table" and list or {}) do
            note(type(source) == "table" and source.slot or nil)
        end
    end
    table.sort(slots)
    return slots
end

-- The glow's one question, answered off a road rather than off an item: the
-- plan rated this, or something it can become, as in your best set or a
-- positive percent (principle 12). A rated-but-worse road does not glow, a
-- phrase does not glow, and a zero is not a direction.
--
-- It is `ns.Roads.IsForward`, not a second copy of it. R-3a (WKE-570) made that
-- test one function precisely so the glow and the rows' "do:" lines cannot come
-- apart: a road the Upgrade Map will not tell you to take is a road the bag
-- will not mark.
function Cache.RoadWantsGlow(road)
    return ns.Roads.IsForward(road)
end

-- The map, over the Upgrade Map tab's own model. Pure: no client call, no
-- database read, no frame. Everything expensive happens here, once.
--
-- It is built from the MODEL rather than from the road inputs directly so that
-- a slot the tab draws and a slot the tooltip answers for are the same object:
-- `Panel.Model` has already called `ns.Roads.ForSlot` for every slot it shows,
-- and a second call would be a second answer to one question. The slots the
-- model does not reach - a vault option in a slot with nothing worn and no
-- drop walked - are built here from the same inputs, so the map is complete
-- either way and the tab is never contradicted.
function Cache.Build(model)
    if type(model) ~= "table" or type(model.roadInputs) ~= "table" then
        return emptyMap("no plan stored")
    end
    local inputs = model.roadInputs
    local map = emptyMap(nil)
    map.previewMythicPlusLevel = model.previewMythicPlusLevel
    local entry = ns.Roads.Plan(inputs)
    map.scenario = entry and entry.scenario or nil
    map.planName = entry and ns.Roads.PlanName(entry.scenario) or nil
    map.exportedAt = entry and entry.verdict and entry.verdict.exportedAt or nil

    local fromModel = {}
    for _, section in ipairs(model.slots or {}) do
        if type(section.slot) == "string" and type(section.roads) == "table" then
            fromModel[section.slot] = section.roads
        end
    end
    for _, slot in ipairs(slotsFor(inputs)) do
        if fromModel[slot] == nil then
            fromModel[slot] = false
        end
    end
    local slots = {}
    for slot in pairs(fromModel) do
        slots[#slots + 1] = slot
    end
    table.sort(slots)
    map.slots = slots

    for _, slot in ipairs(slots) do
        local slotRoads = fromModel[slot] or ns.Roads.ForSlot(slot, inputs)
        map.bySlot[slot] = slotRoads
        map.counts.slots = map.counts.slots + 1
        for _, group in ipairs(ns.Roads.GROUP_ORDER) do
            for _, road in ipairs(slotRoads.groups[group] or {}) do
                local wants = Cache.RoadWantsGlow(road)
                for _, key in ipairs(road.keys or {}) do
                    if map.byKey[key] == nil then
                        local answer = ns.Roads.ForItemIn(slotRoads, key, inputs)
                        answer.sentence = ns.Roads.ItemSentence(answer)
                        -- The age every surface has to show (principle 2). It
                        -- is the plan's own document time, not this build's.
                        answer.exportedAt = map.exportedAt
                        map.byKey[key] = answer
                        map.counts.keys = map.counts.keys + 1
                    end
                    -- The glow is the ITEM's, not one road's: it is marked when
                    -- any road into it is wanted, because taking any of them is
                    -- what the mark is about.
                    if wants and not map.glow[key] then
                        map.glow[key] = true
                        map.counts.glowing = map.counts.glowing + 1
                    end
                end
                -- The Upgrade Finder's own key. A hover in the Adventure Guide
                -- hands a link whose bonus IDs are not the walk's, so the item
                -- ID at the level it arrives at is the second way in, exactly
                -- as the loot map already joins a drop to a rating (M3-10).
                local itemID = road.item and road.item.itemID or nil
                if itemID and road.arrivesAt and road.keys and road.keys[1] then
                    local at = string.format("%d@%d", itemID, road.arrivesAt)
                    if map.byItemLevel[at] == nil then
                        map.byItemLevel[at] = road.keys[1]
                    end
                end
            end
        end
    end

    -- Every piece you are actually carrying, whether or not a road carries it.
    -- A bag item no document mentions still gets an answer, and the answer is
    -- the honesty phrase with the tail its own cure has: `ForItemIn` asks
    -- `ns.Roads.NotRatedPhrase`, which knows the leftover list, so "beyond the
    -- rating's item limit" and "new since the last refresh" are told apart here
    -- rather than guessed at on the hover path (principle 3, C-10).
    local inventory = type(inputs.inventory) == "table" and inputs.inventory or {}
    for _, record in ipairs(inventory.records or {}) do
        local key = record.key
        if type(key) == "string" and map.byKey[key] == nil and map.bySlot[record.slot] then
            local answer = ns.Roads.ForItemIn(map.bySlot[record.slot], key, inputs)
            answer.sentence = ns.Roads.ItemSentence(answer)
            answer.exportedAt = map.exportedAt
            map.byKey[key] = answer
            map.counts.keys = map.counts.keys + 1
        end
    end
    return map
end

-- ---------------------------------------------------------------------------
-- Asking.

-- What the map has, or nil. One table index and nothing else: this is the
-- hover path, and the R-0 numbers are what it has to stay inside.
function Cache.Lookup(key)
    local map = state.map
    if not map or type(key) ~= "string" then
        return nil
    end
    return map.byKey[key]
end

-- The same, by the item ID and the level it arrives at, for a hover whose link
-- carries bonus IDs no document does (the Adventure Guide).
function Cache.LookupAtLevel(itemID, level)
    local map = state.map
    local id, at = tonumber(itemID), tonumber(level)
    if not map or not id or not at then
        return nil
    end
    local key = map.byItemLevel[string.format("%d@%d", id, at)]
    return key and map.byKey[key] or nil
end

function Cache.Map()
    return state.map
end

function Cache.Ready()
    return state.map ~= nil
end

-- ---------------------------------------------------------------------------
-- The one thing the core says about bags (the owner's question, 2026-09-14).
--
-- Every bag adapter asks this and nothing else. The core knows no bag frame,
-- no addon and no texture; an adapter knows no road, no rating and no plan.
ns.Glow = ns.Glow or {}

function ns.Glow.Wants(key)
    local map = state.map
    if not map or type(key) ~= "string" then
        return false
    end
    return map.glow[key] == true
end

-- The same question from a bag that only has the link. Kept beside `Wants` so
-- an adapter never has to know how a key is made.
function ns.Glow.WantsLink(link)
    local safe = ns.Safe(link)
    if type(safe) ~= "string" then
        return false
    end
    local parsed = ns.ParseItemLink(safe)
    return parsed ~= nil and parsed.key ~= nil and ns.Glow.Wants(parsed.key)
end

-- ---------------------------------------------------------------------------
-- When it is rebuilt.

-- The Upgrade Map tab's own model, built from the client the way the tab
-- builds it, so the tooltip and the tab can never be about two different
-- weeks. No difficulty filter is passed: the tab's dropdown narrows what the
-- READER asked to see, and a bag hover is not that question.
--
-- Out of combat only: `Inventory.Scan` refuses in combat, and a half-scanned
-- map is worse than yesterday's whole one.
function Cache.Gather()
    if not (ns.UpgradeMapPanel and ns.UpgradeMapPanel.Gather and ns.UpgradeMapPanel.Model) then
        return nil, "no panel"
    end
    local gathered = ns.UpgradeMapPanel.Gather({ db = ns.db })
    if type(gathered.scenarios) ~= "table" or #gathered.scenarios == 0 then
        return nil, "no plan stored"
    end
    return ns.UpgradeMapPanel.Model(gathered)
end

-- Build now, from the client. Answers the map, or nil with the reason.
function Cache.Rebuild()
    if InCombatLockdown and InCombatLockdown() then
        state.deferred = true
        return nil, "combat"
    end
    local model, reason = Cache.Gather()
    if not model then
        state.map = emptyMap(reason or "nothing to read")
        return state.map, reason
    end
    state.map = Cache.Build(model)
    state.map.builtAt = time()
    Cache.RequestNames(state.map)
    -- A bag that is already open is showing the old map until something tells
    -- it otherwise. Which bag that is, this file does not know.
    if ns.UI and ns.UI.Bags then
        ns.UI.Bags.Refresh()
    end
    return state.map
end

-- A road whose item the client has not named yet (R-2a, WKE-571: the owner read
-- "item 244572 (331)" on a Crafted road, 2026-09-14). The surfaces cannot be
-- told the name because nothing asked the client for it: a crafted row's item
-- ID comes out of the export, never off a link the player has held, so it was
-- never in the client's cache. `ns.ItemData.Request` is the one-shot the drawn
-- rows already use; here it fires once per item ID for the session and rebuilds
-- the map when the name lands, which is what puts the name on the tooltip.
--
-- Not in `Build`: that function is pure and stays so. This is the one place
-- that reads the client on the cache's behalf, and it runs after the build.
function Cache.RequestNames(map)
    if not (ns.ItemData and ns.ItemData.Request) then
        return 0
    end
    local asked = 0
    for _, slot in ipairs(map.slots or {}) do
        for _, group in ipairs(ns.Roads.GROUP_ORDER) do
            for _, road in ipairs(((map.bySlot[slot] or {}).groups or {})[group] or {}) do
                local item = road.item
                local itemID = type(item) == "table" and item.itemID or nil
                if itemID and not item.name and not state.named[itemID] then
                    state.named[itemID] = true
                    asked = asked + 1
                    ns.ItemData.Request(itemID, function()
                        Cache.Changed()
                    end)
                end
            end
        end
    end
    return asked
end

-- Ask for a rebuild. Several events in one burst produce one build, because a
-- bag sort fires one per bag and a login fires most of them at once.
function Cache.Invalidate()
    if state.pending then
        return false
    end
    state.pending = true
    local function run()
        state.pending = false
        Cache.Rebuild()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(Cache.DEBOUNCE_SECONDS, run)
    else
        run()
    end
    return true
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if state.deferred then
            state.deferred = false
            Cache.Invalidate()
        end
        return
    end
    Cache.Invalidate()
end

function Cache.Listen()
    if state.listener then
        return state.listener
    end
    local frame = CreateFrame("Frame")
    for _, event in ipairs(Cache.EVENTS) do
        frame:RegisterEvent(event)
    end
    -- Not one of the four: it is what un-defers a rebuild combat refused.
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", onEvent)
    state.listener = frame
    return frame
end

-- The item-data episodes and the companion import are not events; they are the
-- two other things that change the answer, and each calls this when it lands.
function Cache.Changed()
    return Cache.Invalidate()
end

-- Test seam: the map, set directly, so a spec can prove a lookup without
-- driving a client. Nothing in the addon calls it.
function Cache.SetMap(map)
    state.map = map
    return map
end

function Cache.Reset()
    state.map = nil
    state.pending = false
    state.deferred = false
    state.named = {}
end

ns.onReady[#ns.onReady + 1] = function()
    Cache.Listen()
    Cache.Invalidate()
end
