-- spec/helpers/replay.lua
-- Loads a committed capture transcript (a SavedVariables file) and replays one
-- of its snapshots into the stub world, so the fake C_Container / C_Item /
-- C_Bank answer exactly what the owner's client said. Tests over a replayed
-- snapshot are tests over the client's real returns, not over the stub's
-- placeholders.
local R = {}

R.DEFAULT = "spec/fixtures/captures/Lootpath-20260905-133449.lua"

-- The 2026-09-06 visit (WKE-523): the journal walk in Restoration spec 105,
-- plus the before-reset vault pair. R.DEFAULT stays the 09-05 file because
-- that is the one the inventory goldens were generated from.
R.JOURNAL = "spec/fixtures/captures/Lootpath-20260906-161213.lua"

local cache = {}

-- Returns the LootpathDB table from a transcript, loaded in a sandbox so the
-- file's global assignment never leaks into the test process.
function R.load(path)
    path = path or R.DEFAULT
    if cache[path] then
        return cache[path]
    end
    local chunk = assert(loadfile(path))
    local env = {}
    setfenv(chunk, env)
    chunk()
    assert(env.LootpathDB, "transcript did not define LootpathDB: " .. path)
    cache[path] = env.LootpathDB
    return env.LootpathDB
end

function R.captures(path)
    local db = R.load(path)
    return (db.global and db.global.captures) or db.captures
end

-- The n-th snapshot of a capture (1-based, in the order they were taken).
function R.snapshot(name, index, path)
    local list = R.captures(path)[name]
    assert(list and list[index], "no snapshot " .. tostring(index) .. " for capture " .. name)
    return list[index]
end

local function registerItem(world, link, item)
    if type(link) ~= "string" or not item then
        return
    end
    world.items[link] = {
        level = item.detailedLevel and item.detailedLevel[1] or nil,
        detailed = item.detailedLevel,
        info = item.info,
        instant = item.instant,
    }
end

-- Replays an inventory snapshot's raw data into the stub world.
function R.inventory(world, snapshot)
    local data = snapshot.data
    world.equipped = {}
    world.bags = {}
    for _, e in ipairs(data.equipped or {}) do
        local link = e.link and e.link[1]
        world.equipped[e.invSlot] = { link = link, id = e.itemID and e.itemID[1] }
        registerItem(world, link, e.item)
    end
    for _, bag in ipairs(data.bags or {}) do
        local entry = { numSlots = (bag.numSlots and bag.numSlots[1]) or 0, items = {} }
        for slot, it in pairs(bag.items or {}) do
            local link = it.link and it.link[1]
            entry.items[slot] = { info = it.info and it.info[1], link = link, id = it.itemID and it.itemID[1] }
            registerItem(world, link, it.item)
        end
        world.bags[bag.bagIndex] = entry
    end
    local viewable = data.bank and data.bank.predicates and data.bank.predicates.CanViewBank
    world.bankOpen = viewable and viewable.Character and viewable.Character[1] == true or false
    return world
end

-- Replays a vault snapshot's raw data into the stub world, so C_WeeklyRewards
-- answers exactly what the owner's client said (M3-3). The activities go back
-- verbatim, empty `rewards` lists included: what the vault says before its
-- rewards are generated is a fact the panel has to handle, not a gap to fill.
function R.vault(world, snapshot)
    local data = snapshot.data
    world.vault.activities = (data.activities and data.activities[1]) or {}
    world.vault.hasAvailable = (data.hasAvailableRewards and data.hasAvailableRewards[1]) == true
    world.vault.canClaim = (data.canClaimRewards and data.canClaimRewards[1]) == true
    world.vault.links = {}
    for _, entry in ipairs(data.rewardLinks or {}) do
        local link = entry.link and entry.link[1]
        if entry.itemDBID ~= nil and type(link) == "string" then
            world.vault.links[entry.itemDBID] = link
            registerItem(world, link, entry.item)
        end
    end
    world.secondsUntilReset = (data.secondsUntilWeeklyReset and data.secondsUntilWeeklyReset[1]) or 0
    return world
end

-- Every item link the snapshot carries, deduplicated, with the raw probes.
function R.links(snapshot)
    local seen, out = {}, {}
    local function add(link, item)
        if type(link) == "string" and not seen[link] then
            seen[link] = true
            out[#out + 1] = { link = link, item = item }
        end
    end
    for _, e in ipairs(snapshot.data.equipped or {}) do
        add(e.link and e.link[1], e.item)
    end
    for _, bag in ipairs(snapshot.data.bags or {}) do
        for _, it in pairs(bag.items or {}) do
            add(it.link and it.link[1], it.item)
        end
    end
    return out
end

return R
