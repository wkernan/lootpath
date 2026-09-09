-- Lootpath/Modules/ItemData.lua (M5-1, WKE-550)
-- The one item loader. Every row on every tab asks the same two questions of
-- an item - "what can the client tell me right now, without a server round
-- trip" and "tell me when the rest arrives" - and this file is where both are
-- answered, so a Vault reward and an Equip Now row wait the same way.
--
-- Lifted out of Modules/Vault.lua, where M3-12 (WKE-547) first built it for
-- the vault rewards that come back as `|h[]|h` right after a client restart.
-- Vault keeps its own record bookkeeping (what is pending, when to re-read,
-- when to redraw) and asks this file for the mechanism; nothing about the
-- vault's behaviour changed in the move, which is what its spec holds.
--
-- Why C_Item.RequestLoadItemDataByID and the two load events, rather than the
-- ItemMixin (`Item:CreateFromItemID(id):ContinueOnItemLoad(fn)`): read under
-- .luals/, the mixin is that same call - `ItemEventListener:AddCallback` runs
-- `C_Item.RequestLoadItemDataByID(id)` once per id and fires the callback on
-- ITEM_DATA_LOAD_RESULT when `success` is true (Blizzard_ObjectAPI's
-- AsyncCallbackSystem.lua and Item.lua). Calling the exported function
-- directly keeps every client call in FUNCTION_NAMES as a literal name, keeps
-- the bound and the combat check in this file where a test can drive them,
-- and takes no dependency on a FrameXML object whose global (`Item`) the
-- headless harness does not model.
--
-- Two entry points, because two callers want different things:
--   * `Watch(itemID, onCheck, onGiveUp)` is the mechanism: one request per
--     itemID per episode, both load events, and a bounded timer behind them.
--     `onCheck` runs on every occasion and says whether IT is done; the
--     episode ends when every watcher is done, when the client says the load
--     failed, or when the bound runs out (`onGiveUp` then, once).
--   * `Request(itemID, callback)` is the one-shot a drawn row wants: the
--     callback fires at most once, when the client can name the item, and
--     never after `handle:Cancel()` - which is what stops a re-used row from
--     being filled in with the item it used to hold.
--
-- Every value read from the client passes ns.Safe. Nothing runs in combat:
-- a load event that arrives during a pull is ignored and the item stays
-- unresolved until the caller asks again.

local _, ns = ...

ns.ItemData = {}
local ItemData = ns.ItemData

-- Every client function this file calls, named rather than discovered, for
-- the same reason JournalAdapter.FUNCTION_NAMES is a list of strings.
ItemData.FUNCTION_NAMES = {
    "C_Item.GetItemInfoInstant",
    "C_Item.GetItemInfo",
    "C_Item.GetDetailedItemLevelInfo",
    "C_Item.RequestLoadItemDataByID",
}

-- The bound, the journal's shape (Adapter.ITEM_DATA_WAIT_SECONDS x
-- ITEM_DATA_MAX_ATTEMPTS, 8 x 0.25 s) and M3-12's before it: after asking the
-- client for an item, the watchers are run on each of the two load events for
-- that itemID and, failing those, on a timer up to this many times.
ItemData.WAIT_SECONDS = 0.25
ItemData.MAX_ATTEMPTS = 8

-- Both events Blizzard's docs list with `itemID, success` payloads
-- (Event.lua under .luals/): ITEM_DATA_LOAD_RESULT is what the mixin's
-- AsyncCallbackSystem listens for after RequestLoadItemDataByID;
-- GET_ITEM_INFO_RECEIVED is what a plain GetItemInfo miss produces.
ItemData.EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

-- What the client is being asked about: [itemID] = { itemID, attempts,
-- requested, watchers = { <handle> ... } }. One request per itemID per
-- episode; a second caller asking about the same item joins the episode
-- rather than asking the client again.
ItemData.episodes = {}

local listener

local function after(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    -- Parenthesised: ns.Safe answers (value, isSecret), and a bare tail call
    -- would hand that second value on to whatever this feeds.
    return (ns.Safe(result))
end

-- What the client knows about an item without a server round trip: its icon
-- and its equip slot come out of the static data GetItemInfoInstant reads
-- (itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID -
-- Blizzard's exported ItemDocumentation, read under .luals/). Answers for an
-- itemID or for a link. Returns nil when the client says nothing at all.
function ItemData.Instant(itemInfo)
    if itemInfo == nil or not (C_Item and C_Item.GetItemInfoInstant) then
        return nil
    end
    local ok, a, b, c, d, e, f, g = pcall(C_Item.GetItemInfoInstant, itemInfo)
    if not ok or a == nil then
        return nil
    end
    -- Every ns.Safe is parenthesised: it answers (value, isSecret), and the
    -- flag riding along into tonumber's second argument is a base, not a guard.
    local equipLoc = (ns.Safe(d))
    return {
        itemID = tonumber((ns.Safe(a))),
        itemType = (ns.Safe(b)),
        itemSubType = (ns.Safe(c)),
        equipLoc = equipLoc,
        -- QE Live's slot vocabulary, so an item line and a verdict agree about
        -- which slot they are talking about. nil for anything that is not gear.
        slot = ns.Inventory and ns.Inventory.SlotForEquipLoc(equipLoc) or nil,
        icon = tonumber((ns.Safe(e))),
        classID = tonumber((ns.Safe(f))),
        subclassID = tonumber((ns.Safe(g))),
    }
end

-- What the client knows once the item's data has arrived: name, link, quality
-- and the detailed item level. Returns nil while the client cannot name it,
-- which is Blizzard's own gate for "not loaded yet" (its journal draws
-- RETRIEVING_ITEM_INFO when `itemInfo.name` is missing).
function ItemData.Cached(itemInfo)
    if itemInfo == nil or not (C_Item and C_Item.GetItemInfo) then
        return nil
    end
    -- Never wrapped in parentheses: quality is the third return.
    local ok, name, link, quality = pcall(C_Item.GetItemInfo, itemInfo)
    if not ok then
        return nil
    end
    name = (ns.Safe(name))
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local itemLevel
    if C_Item.GetDetailedItemLevelInfo then
        itemLevel = tonumber(safeCall(C_Item.GetDetailedItemLevelInfo, itemInfo))
    end
    return {
        name = name,
        link = (ns.Safe(link)),
        quality = tonumber((ns.Safe(quality))),
        itemLevel = itemLevel,
    }
end

function ItemData.IsCached(itemInfo)
    return ItemData.Cached(itemInfo) ~= nil
end

local function episodeCount()
    local count = 0
    for _ in pairs(ItemData.episodes) do
        count = count + 1
    end
    return count
end

function ItemData.EpisodeCount()
    return episodeCount()
end

local function stopListening()
    if listener then
        for _, event in ipairs(ItemData.EVENTS) do
            listener:UnregisterEvent(event)
        end
    end
end

-- Ends an episode. `resolved` says whether the item arrived: when it did not,
-- every watcher still on it is told so, once, and never told anything again.
local function endEpisode(itemID, resolved)
    local episode = ItemData.episodes[itemID]
    if not episode then
        return
    end
    ItemData.episodes[itemID] = nil
    if not resolved then
        for _, handle in ipairs(episode.watchers) do
            if not handle.cancelled and handle.onGiveUp then
                handle.cancelled = true
                handle.onGiveUp(itemID)
            end
            handle.cancelled = true
        end
    end
    if episodeCount() == 0 then
        stopListening()
    end
end

-- Runs every live watcher of one episode and drops the ones that say they are
-- done. Returns true when nothing is waiting on this item any more.
local function runWatchers(itemID, event, success)
    local episode = ItemData.episodes[itemID]
    if not episode then
        return true
    end
    local checked = {}
    for _, handle in ipairs(episode.watchers) do
        if not handle.cancelled then
            if handle.onCheck(itemID, event, success) == true then
                handle.cancelled = true
            else
                checked[#checked + 1] = handle
            end
        end
    end
    -- Filtered again after the loop: a watcher's own onCheck is free to cancel
    -- handles (its own, or another row's), and a cancelled one is not waiting.
    local remaining = {}
    for _, handle in ipairs(checked) do
        if not handle.cancelled then
            remaining[#remaining + 1] = handle
        end
    end
    episode.watchers = remaining
    if #remaining == 0 then
        endEpisode(itemID, true)
        return true
    end
    return false
end

-- One occasion: a load event, or a tick of the bound timer (event nil).
-- Returns true when a watcher was actually run.
function ItemData.Check(itemID, event, success)
    if not ItemData.episodes[itemID] then
        return false
    end
    if InCombatLockdown() then
        -- Nothing runs in combat. The episode is kept, so the item is still
        -- waited on once the pull is over.
        return false
    end
    if success == false and event == "ITEM_DATA_LOAD_RESULT" then
        -- What Blizzard's AsyncCallbackSystem does with a failed load: drop
        -- the callbacks. Nothing is filled in and nothing is guessed at.
        endEpisode(itemID, false)
        return false
    end
    runWatchers(itemID, event, success)
    return true
end

local function ensureListener()
    if listener then
        return listener
    end
    listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", function(_, event, itemID, success)
        ItemData.Check(itemID, event, success)
    end)
    return listener
end

function ItemData.Listener()
    return listener
end

local function startListening()
    local frame = ensureListener()
    for _, event in ipairs(ItemData.EVENTS) do
        frame:RegisterEvent(event)
    end
    return frame
end

-- The bound: one timer per episode, re-armed until the item resolves or
-- MAX_ATTEMPTS have passed. The events are the fast path; this is what stops
-- a row from waiting forever on a client that never answers. An attempt is
-- spent even in combat, and only the check itself is skipped, so a pull
-- cannot make a row wait longer than the bound says.
local function scheduleCheck(episode)
    after(ItemData.WAIT_SECONDS, function()
        if ItemData.episodes[episode.itemID] ~= episode then
            return -- resolved, given up on, or replaced by a later episode
        end
        episode.attempts = episode.attempts + 1
        if not InCombatLockdown() then
            runWatchers(episode.itemID, nil, nil)
        end
        if ItemData.episodes[episode.itemID] == episode then
            if episode.attempts >= ItemData.MAX_ATTEMPTS then
                episode.gaveUp = true
                endEpisode(episode.itemID, false)
            else
                scheduleCheck(episode)
            end
        end
    end)
end

-- Watch(itemID, onCheck, onGiveUp) -> handle, or nil for a non-item.
--
-- `onCheck(itemID, event, success)` runs on every load event for the item and
-- on every tick of the bound, out of combat only, and returns true when this
-- watcher wants nothing more. `onGiveUp(itemID)` runs once if the episode
-- ends without the item ever arriving. The handle carries `requested`, which
-- says whether THIS call is the one that asked the client, and `Cancel()`.
function ItemData.Watch(itemID, onCheck, onGiveUp)
    itemID = tonumber(itemID)
    if not itemID or type(onCheck) ~= "function" then
        return nil
    end
    local handle = { itemID = itemID, onCheck = onCheck, onGiveUp = onGiveUp, cancelled = false }
    function handle:Cancel()
        self.cancelled = true
        local episode = ItemData.episodes[self.itemID]
        if not episode then
            return
        end
        local remaining = {}
        for _, other in ipairs(episode.watchers) do
            if other ~= self and not other.cancelled then
                remaining[#remaining + 1] = other
            end
        end
        episode.watchers = remaining
        if #remaining == 0 then
            -- Nobody is waiting any more: the episode is over, and the
            -- watchers that are gone are told nothing.
            ItemData.episodes[self.itemID] = nil
            if episodeCount() == 0 then
                stopListening()
            end
        end
    end

    local episode = ItemData.episodes[itemID]
    if not episode then
        episode = { itemID = itemID, attempts = 0, watchers = {}, requested = false }
        ItemData.episodes[itemID] = episode
        startListening()
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            episode.requested = pcall(C_Item.RequestLoadItemDataByID, itemID) == true
        end
        handle.requested = episode.requested
        episode.watchers[1] = handle
        scheduleCheck(episode)
        return handle
    end
    -- Joining an episode that is already running: the client was asked once
    -- and is not asked again.
    handle.requested = false
    episode.watchers[#episode.watchers + 1] = handle
    return handle
end

-- Request(itemID, callback) -> handle, or nil for a non-item.
--
-- The one-shot a drawn row wants: `callback(itemID)` fires exactly once, the
-- first time the client can name the item, and never fires at all if the
-- bound runs out or the handle is cancelled first. A row that has been handed
-- another item cancels its handle, which is what keeps a late answer from
-- landing on the wrong line.
function ItemData.Request(itemID, callback)
    if type(callback) ~= "function" then
        return nil
    end
    return ItemData.Watch(tonumber(itemID), function(id)
        if not ItemData.IsCached(id) then
            return false
        end
        callback(id)
        return true
    end)
end

function ItemData.Cancel(handle)
    if type(handle) == "table" and type(handle.Cancel) == "function" then
        handle:Cancel()
    end
end

-- Ends every episode without telling anybody. Only for a test between runs:
-- nothing in the addon forgets an item it asked about.
function ItemData.Reset()
    for itemID, episode in pairs(ItemData.episodes) do
        for _, handle in ipairs(episode.watchers) do
            handle.cancelled = true
        end
        ItemData.episodes[itemID] = nil
    end
    stopListening()
end
