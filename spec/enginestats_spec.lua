-- spec/enginestats_spec.lua (E-0b, WKE-671)
-- ns.EngineStats over the stub: an item link's stat vector read, cached by the
-- link without its enchant and gems, gems listed beside it and never folded
-- in, an uncached item asked about once, a secret answered as `secret`, and
-- nothing at all in combat.
--
-- PLACEHOLDER: the stub's GetItemStats answers from
-- spec/fixtures/engine/itemstats-placeholder.lua, whose keys are the Warcraft
-- Wiki's shape (grade (ii)) and whose numbers are invented. E-0a's transcript
-- (WKE-675) is not committed yet; what these tests prove is the module's own
-- logic over that shape, nothing about the client.
local H = require("spec.helpers.addon")

local F = dofile("spec/fixtures/engine/itemstats-placeholder.lua")

-- Resolves "C_Item.GetItemStats" / "GetCombatRating" on _G.
local function resolve(name)
    local namespace, member = name:match("^([%w_]+)%.([%w_]+)$")
    if namespace then
        return _G[namespace] and _G[namespace][member], namespace, member
    end
    return _G[name], nil, name
end

-- Wraps every item and rating function the module names with a counter; the
-- combat check and CreateFrame are left out (asked on every call, and only
-- once, respectively), so a count is "what was asked of the client about
-- items and ratings". `calls.log` holds { name, firstArg } in order.
local function countCalls(ns)
    local calls = { total = 0, log = {} }
    for _, name in ipairs(ns.EngineStats.FUNCTION_NAMES) do
        if name ~= "InCombatLockdown" and name ~= "CreateFrame" then
            local fn, namespace, member = resolve(name)
            local wrapped = function(...)
                calls.total = calls.total + 1
                calls.log[#calls.log + 1] = { name, (...) }
                return fn(...)
            end
            if namespace then
                _G[namespace][member] = wrapped
            else
                _G[member] = wrapped
            end
        end
    end
    return calls
end

local function callsTo(calls, name)
    local out = {}
    for _, entry in ipairs(calls.log) do
        if entry[1] == name then
            out[#out + 1] = entry[2]
        end
    end
    return out
end

describe("ns.EngineStats.FUNCTION_NAMES", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("names every client function the file calls, and each resolves on the stub", function()
        assert.same({
            "InCombatLockdown",
            "C_Item.GetItemInfo",
            "C_Item.GetDetailedItemLevelInfo",
            "C_Item.GetItemStats",
            "C_Item.GetItemGem",
            "C_Item.GetItemNumSockets",
            "C_Item.GetItemUniquenessByID",
            "GetCombatRatingBonusForCombatRatingValue",
            "GetCombatRating",
            "GetMasteryEffect",
            "CreateFrame",
        }, ns.EngineStats.FUNCTION_NAMES)
        for _, name in ipairs(ns.EngineStats.FUNCTION_NAMES) do
            assert.is_function((resolve(name)), name)
        end
    end)

    -- The file's own text, comments and strings stripped: every identifier
    -- that resolves to a client function on the stub is in the list. A call
    -- added without naming it turns this red.
    it("calls nothing it does not name", function()
        local source = assert(io.open("Lootpath/Modules/EngineStats.lua")):read("*a")
        source = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
        source = source:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
        local named = {}
        for _, name in ipairs(ns.EngineStats.FUNCTION_NAMES) do
            named[name] = true
        end
        local lua = {
            pairs = true,
            ipairs = true,
            type = true,
            tonumber = true,
            tostring = true,
            pcall = true,
            next = true,
            select = true,
            unpack = true,
            error = true,
            assert = true,
            setmetatable = true,
            print = true,
        }
        local unnamed = {}
        for token in source:gmatch("[%a_][%w_]*%.?[%a_]?[%w_]*") do
            local root = token:match("^[^%.]+")
            if not lua[root] and root ~= "string" and root ~= "table" and root ~= "math" then
                local value = resolve(token)
                if type(value) == "function" and not named[token] and not ns[root] then
                    unnamed[#unnamed + 1] = token
                end
            end
        end
        assert.same({}, unnamed)
    end)
end)

describe("ns.EngineStats.ForLink", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        F.install(world)
    end)

    after_each(function()
        H.unload()
    end)

    it("reads the vector off the link with its enchant and gems blanked", function()
        local calls = countCalls(ns)
        local r = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.is_true(r.ready)
        assert.equal(F.HELM_KEY, r.key)
        assert.equal(F.HELM_ID, r.itemID)
        assert.equal(1001, r.int)
        assert.equal(2002, r.stamina)
        assert.equal(303, r.crit)
        assert.equal(404, r.haste)
        assert.equal(0, r.mastery)
        assert.equal(0, r.vers)
        assert.equal(55, r.leech)
        assert.equal(0, r.avoidance)
        assert.equal(0, r.speed)
        assert.equal(606, r.armor)
        -- The client was asked about the stripped link, never the worn one.
        assert.same({ F.HELM_STRIPPED, F.GEM_LINK }, callsTo(calls, "C_Item.GetItemStats"))
    end)

    it("answers the same base for the worn link and for its stripped link", function()
        local worn = ns.EngineStats.ForLink(F.HELM_LINK)
        local stripped = ns.EngineStats.ForLink(F.HELM_STRIPPED)
        assert.equal(worn.key, stripped.key)
        for _, field in ipairs(ns.EngineStats.VECTOR) do
            assert.equal(worn[field], stripped[field], field)
        end
        assert.equal(worn.sockets, stripped.sockets)
        -- The stripped link carries no gem, so it lists none.
        assert.same({}, stripped.gems)
        -- A bare item string reaches the same key.
        assert.equal(F.HELM_KEY, ns.EngineStats.ForLink(F.HELM_KEY).key)
    end)

    it("lists each gem with its own stats and never folds it into the base", function()
        local r = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.equal(1, #r.gems)
        assert.equal(F.GEM_ID, r.gems[1].id)
        assert.equal(71, r.gems[1].stats.haste)
        assert.equal(29, r.gems[1].stats.mastery)
        -- The base is the item's own: the gem's 71 haste and 29 mastery are not in it.
        assert.equal(404, r.haste)
        assert.equal(0, r.mastery)
        -- Another copy of the item, another gem: the base is shared, the gems are its own.
        local other = ns.EngineStats.ForLink(F.HELM_LINK_OTHER_GEM)
        assert.equal(r.key, other.key)
        assert.equal(F.GEM2_ID, other.gems[1].id)
        assert.equal(83, other.gems[1].stats.int)
        assert.equal(1001, other.int)
    end)

    it("reads sockets, level, set and uniqueness", function()
        local r = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.equal(1, r.sockets)
        assert.equal(318, r.level)
        assert.equal(1990, r.setID)
        assert.same({ category = 515, max = 2, name = "Placeholder Category", isUnique = true }, r.uniqueness)
    end)

    it("keeps a key it does not know under other, and drops nothing", function()
        local r = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.same({ EMPTY_SOCKET_PRISMATIC = 1, ITEM_MOD_SOMETHING_NEW_SHORT = 7 }, r.other)
    end)

    it("says nothing about what is not an item link", function()
        assert.is_nil(ns.EngineStats.ForLink(nil))
        assert.is_nil(ns.EngineStats.ForLink(""))
        assert.is_nil(ns.EngineStats.ForLink("|Hspell:774|h[Rejuvenation]|h"))
    end)

    it("answers an uncached item ready = false after one request, and the item after the load event", function()
        local cold = "|cffa335ee|Hitem:272228:0:0:0:0:0:0:0:90:105:0:0:1:6652:0|h[Placeholder Neck]|h|r"
        local coldStripped = "|cffa335ee|Hitem:272228::::::0:0:90:105:0:0:1:6652:0|h[Placeholder Neck]|h|r"
        local first = ns.EngineStats.ForLink(cold)
        assert.same({ ready = false }, first)
        assert.same({ 272228 }, world.itemDataRequests)
        -- Asked again while the client is still fetching: no second request.
        assert.same({ ready = false }, ns.EngineStats.ForLink(cold))
        assert.same({ 272228 }, world.itemDataRequests)
        -- The client answers.
        local info = { "Placeholder Neck", coldStripped, 4, n = 3 }
        world.items[coldStripped] = { info = info, level = 321 }
        world.items[272228] = { info = info, level = 321 }
        world.itemStats[coldStripped] = { ITEM_MOD_STAMINA_SHORT = 900, ITEM_MOD_HASTE_RATING_SHORT = 500 }
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 272228, true)
        local r = ns.EngineStats.ForLink(cold)
        assert.is_true(r.ready)
        assert.equal(500, r.haste)
        assert.equal(321, r.level)
        assert.same({ 272228 }, world.itemDataRequests)
    end)

    it("answers a second ask from the cache with zero client calls", function()
        local calls = countCalls(ns)
        ns.EngineStats.ForLink(F.HELM_LINK)
        local firstAsk = calls.total
        assert.is_true(firstAsk > 0)
        local again = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.equal(firstAsk, calls.total)
        assert.equal(404, again.haste)
        assert.equal(71, again.gems[1].stats.haste)
        -- A caller writing on its answer does not change the next one.
        again.haste = -1
        assert.equal(404, ns.EngineStats.ForLink(F.HELM_LINK).haste)
    end)

    it("forgets an item on ITEM_DATA_LOAD_RESULT for it, and everything on PLAYER_ENTERING_WORLD", function()
        local calls = countCalls(ns)
        ns.EngineStats.ForLink(F.HELM_LINK)
        assert.equal(1, ns.EngineStats.Count())
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 999999, true)
        assert.equal(1, ns.EngineStats.Count())
        world.fireEvent("ITEM_DATA_LOAD_RESULT", F.HELM_ID, true)
        assert.equal(0, ns.EngineStats.Count())
        local before = #callsTo(calls, "C_Item.GetItemStats")
        ns.EngineStats.ForLink(F.HELM_LINK)
        assert.equal(before + 1, #callsTo(calls, "C_Item.GetItemStats"))
        world.fireEvent("PLAYER_ENTERING_WORLD", false, true)
        assert.equal(0, ns.EngineStats.Count())
    end)

    it("holds at most MAX_ENTRIES, the oldest out first", function()
        ns.EngineStats.MAX_ENTRIES = 3
        local links = {}
        for i = 1, 4 do
            local link = "item:" .. (100 + i) .. "::::::0:0:90:105:0:0:0"
            links[i] = link
            world.items[link] = { info = { "Placeholder " .. i, link, 4, n = 3 }, level = 300 }
            world.itemStats[link] = { ITEM_MOD_STAMINA_SHORT = i }
        end
        for i = 1, 4 do
            assert.is_true(ns.EngineStats.ForLink(links[i]).ready)
        end
        assert.equal(3, ns.EngineStats.Count())
        local calls = countCalls(ns)
        ns.EngineStats.ForLink(links[4])
        ns.EngineStats.ForLink(links[2])
        assert.equal(0, calls.total)
        ns.EngineStats.ForLink(links[1])
        assert.same({ links[1] }, callsTo(calls, "C_Item.GetItemStats"))
    end)

    it("answers secret = true and no vector when a stat is secret, and caches nothing", function()
        world.itemStats[F.HELM_STRIPPED] = { ITEM_MOD_HASTE_RATING_SHORT = world.markSecret(4321) }
        local r = ns.EngineStats.ForLink(F.HELM_LINK)
        assert.same({ secret = true, ready = true }, r)
        assert.equal(0, ns.EngineStats.Count())
    end)

    it("answers secret = true when the whole stat table is secret", function()
        world.itemStats[F.HELM_STRIPPED] = world.secretTable("stats")
        assert.same({ secret = true, ready = true }, ns.EngineStats.ForLink(F.HELM_LINK))
        assert.equal(0, ns.EngineStats.Count())
    end)

    it("answers secret = true when the level is secret", function()
        world.items[F.HELM_STRIPPED].level = world.markSecret(3181)
        assert.same({ secret = true, ready = true }, ns.EngineStats.ForLink(F.HELM_LINK))
    end)

    it("answers nil in combat and asks the client nothing", function()
        local calls = countCalls(ns)
        world.inCombat = true
        assert.is_nil(ns.EngineStats.ForLink(F.HELM_LINK))
        assert.is_nil(ns.EngineStats.ForLink("item:272228"))
        assert.equal(0, calls.total)
        assert.same({}, world.itemDataRequests)
    end)
end)

describe("ns.EngineStats ratings", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        -- PLACEHOLDER rating-per-percent figures, no diminishing returns.
        world.ratingPerPercent[20] = 44
        world.combatRatings = { [11] = 1100, [17] = 170, [20] = 2000, [26] = 2600, [29] = 2900 }
        world.masteryEffect = { 41.5, 1.25 }
    end)

    after_each(function()
        H.unload()
    end)

    it("hands back the client's own conversion for a rating value", function()
        assert.equal(1320 / 44, ns.EngineStats.Rating(20, 1320))
        assert.is_nil(ns.EngineStats.Rating(99, 1320))
    end)

    it("reads the five current ratings and the mastery pair", function()
        assert.same({
            crit = 1100,
            leech = 170,
            haste = 2000,
            mastery = 2600,
            vers = 2900,
            masteryEffect = 41.5,
            masteryCoefficient = 1.25,
        }, ns.EngineStats.CurrentRatings())
    end)

    it("answers a secret rating as secret", function()
        world.combatRatings[20] = world.markSecret(2001)
        assert.same({ secret = true }, ns.EngineStats.CurrentRatings())
        world.ratingPerPercent[26] = 1
        local value, secret = ns.EngineStats.Rating(26, world.markSecret(7777))
        -- 7777 / 1 is the marked 7777 itself: the answer is secret.
        assert.is_nil(value)
        assert.is_true(secret)
    end)

    it("answers nil in combat and asks the client nothing", function()
        local calls = countCalls(ns)
        world.inCombat = true
        assert.is_nil(ns.EngineStats.Rating(20, 1320))
        assert.is_nil(ns.EngineStats.CurrentRatings())
        assert.equal(0, calls.total)
    end)
end)

describe("ns.EngineStats on screen", function()
    it("is read by no UI file", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                local text = assert(io.open("Lootpath/" .. f)):read("*a")
                if text:find("EngineStats", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)
end)
