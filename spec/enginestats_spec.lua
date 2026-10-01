-- spec/enginestats_spec.lua (E-0b, WKE-671)
-- ns.EngineStats over the stub: an item link's stat vector read, cached by the
-- link without its enchant and gems, gems listed beside it and never folded
-- in, an uncached item asked about once, a secret answered as `secret`, and
-- nothing at all in combat.
--
-- Over the CLIENT'S answers since E-0f (WKE-676): the stub's GetItemStats,
-- gems, sockets, uniqueness and rating conversion answer from
-- spec/fixtures/engine/itemstats-real.lua, extracted unedited from the owner's
-- `capture itemstats` transcript of 2026-10-01 by
-- tools/engine/extract-itemstats.js. Two tests feed a HYPOTHETICAL input on
-- purpose and say so: a gem link that answers stats (none did) and a stat key
-- the client has not named (every one it named is mapped).
local H = require("spec.helpers.addon")

local F = dofile("spec/fixtures/engine/itemstats-real.lua")

-- The worn helm at 318, enchanted and gemmed: the row most tests read.
local HELM = F.rowsFrom("worn")[1]
-- The same helm with the worn neck's Eversong Diamond in its socket and no
-- enchant: another copy of one item, another gem.
local DIAMOND = F.rowsFrom("worn")[2].gems[1]
local OTHER_GEM_LINK = HELM.link:gsub("item:271528:7961:240892:", "item:271528::240983:")
-- The first worn trinket (274495 at 308).
local WORN_TRINKET
for _, row in ipairs(F.rowsFrom("worn")) do
    if row.equipLoc == "INVTYPE_TRINKET" then
        WORN_TRINKET = WORN_TRINKET or row
    end
end

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
        world.itemGems[OTHER_GEM_LINK] = { { name = DIAMOND.name, link = DIAMOND.link, id = DIAMOND.id } }
    end)

    after_each(function()
        H.unload()
    end)

    it("reads the vector off the link with its enchant and gems blanked", function()
        local calls = countCalls(ns)
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.is_true(r.ready)
        assert.equal(HELM.key, r.key)
        assert.equal(271528, r.itemID)
        -- The transcript's worn helm at 318.
        assert.equal(162, r.int)
        assert.equal(3254, r.stamina)
        assert.equal(110, r.crit)
        assert.equal(78, r.haste)
        assert.equal(0, r.mastery)
        assert.equal(0, r.vers)
        assert.equal(0, r.leech)
        assert.equal(0, r.avoidance)
        assert.equal(0, r.speed)
        assert.equal(132, r.armor)
        assert.equal(1, r.prismaticSockets)
        assert.is_nil(r.other)
        -- The client was asked about the stripped link, then the gem's link.
        assert.same({ HELM.strippedLink, HELM.gems[1].link }, callsTo(calls, "C_Item.GetItemStats"))
    end)

    it("maps every key the client named on all 80 items, and drops none", function()
        local seen = {}
        for _, row in ipairs(F.ROWS) do
            local r = ns.EngineStats.ForLink(row.link)
            assert.is_true(r.ready, row.link)
            assert.is_nil(r.other, row.link)
            for key, value in pairs(row.stats) do
                local field = ns.EngineStats.STAT_KEYS[key]
                assert.is_string(field, key)
                assert.equal(value, r[field], row.link .. " " .. key)
                seen[key] = true
            end
        end
        local keys = {}
        for key in pairs(seen) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        assert.same({
            "EMPTY_SOCKET_PRISMATIC",
            "ITEM_MOD_CRIT_RATING_SHORT",
            "ITEM_MOD_CR_LIFESTEAL_SHORT",
            "ITEM_MOD_CR_SPEED_SHORT",
            "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
            "ITEM_MOD_HASTE_RATING_SHORT",
            "ITEM_MOD_INTELLECT_SHORT",
            "ITEM_MOD_MASTERY_RATING_SHORT",
            "ITEM_MOD_MODIFIED_CRAFTING_STAT_1",
            "ITEM_MOD_STAMINA_SHORT",
            "ITEM_MOD_VERSATILITY",
            "RESISTANCE0_NAME",
        }, keys)
        -- Versatility's key has no _SHORT; the socket key counts sockets.
        assert.equal("vers", ns.EngineStats.STAT_KEYS.ITEM_MOD_VERSATILITY)
        assert.is_nil(ns.EngineStats.STAT_KEYS.ITEM_MOD_VERSATILITY_SHORT)
        for _, row in ipairs(F.ROWS) do
            if row.stats.EMPTY_SOCKET_PRISMATIC then
                assert.equal(row.sockets, ns.EngineStats.ForLink(row.link).prismaticSockets, row.link)
            end
        end
    end)

    it("answers the same base for the worn link and for its stripped link", function()
        local worn = ns.EngineStats.ForLink(HELM.link)
        local stripped = ns.EngineStats.ForLink(HELM.strippedLink)
        assert.equal(worn.key, stripped.key)
        for _, field in ipairs(ns.EngineStats.VECTOR) do
            assert.equal(worn[field], stripped[field], field)
        end
        assert.equal(worn.sockets, stripped.sockets)
        -- The stripped link carries no gem, so it lists none.
        assert.same({}, stripped.gems)
        -- A bare item string reaches the same key.
        assert.equal(HELM.key, ns.EngineStats.ForLink(HELM.key).key)
    end)

    it("lists each gem, and an empty answer for it is unknown, never zeros", function()
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.equal(1, #r.gems)
        assert.equal(240892, r.gems[1].id)
        -- The client answered the Flawless Masterful Peridot's link with {}.
        assert.is_true(r.gems[1].unknown)
        assert.same({}, r.gems[1].stats)
        -- Another copy of the item, another gem: the base is shared, the gems are its own.
        local other = ns.EngineStats.ForLink(OTHER_GEM_LINK)
        assert.equal(r.key, other.key)
        assert.equal(240983, other.gems[1].id)
        assert.is_true(other.gems[1].unknown)
        assert.equal(162, other.int)
    end)

    -- HYPOTHETICAL: no gem link answered stats on 12.1.0. If one ever does, its
    -- stats are listed beside the base and never folded into it.
    it("lists a gem's stats when the client names some, and never folds them in", function()
        world.itemStats[HELM.gems[1].link] = { ITEM_MOD_HASTE_RATING_SHORT = 71, ITEM_MOD_MASTERY_RATING_SHORT = 29 }
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.is_nil(r.gems[1].unknown)
        assert.equal(71, r.gems[1].stats.haste)
        assert.equal(29, r.gems[1].stats.mastery)
        assert.equal(78, r.haste)
        assert.equal(0, r.mastery)
    end)

    it("reads sockets, level, set and uniqueness", function()
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.equal(1, r.sockets)
        assert.equal(318, r.level)
        assert.equal(2057, r.setID)
        -- Armour: GetItemUniquenessByID answers false and three nils.
        assert.is_nil(r.uniqueness)
        -- A worn trinket: true and three nils, no category.
        local trinket = ns.EngineStats.ForLink(WORN_TRINKET.link)
        assert.same({ isUnique = true }, trinket.uniqueness)
        assert.is_nil(trinket.setID)
        assert.equal(308, trinket.level)
    end)

    -- HYPOTHETICAL key: every key the transcript carried is mapped, so a new
    -- one is invented here to hold the rule.
    it("keeps a key it does not know under other, and drops nothing", function()
        local stats = {}
        for k, v in pairs(HELM.stats) do
            stats[k] = v
        end
        stats.ITEM_MOD_SOMETHING_NEW_SHORT = 7
        world.itemStats[HELM.strippedLink] = stats
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.same({ ITEM_MOD_SOMETHING_NEW_SHORT = 7 }, r.other)
        assert.equal(162, r.int)
    end)

    it("says nothing about what is not an item link", function()
        assert.is_nil(ns.EngineStats.ForLink(nil))
        assert.is_nil(ns.EngineStats.ForLink(""))
        assert.is_nil(ns.EngineStats.ForLink("|Hspell:774|h[Rejuvenation]|h"))
    end)

    it("answers an uncached item ready = false after one request, and the item after the load event", function()
        local cold = "|cffa335ee|Hitem:272228:0:0:0:0:0:0:0:90:105:0:0:1:6652:0|h[Test Neck]|h|r"
        local coldStripped = "|cffa335ee|Hitem:272228::::::0:0:90:105:0:0:1:6652:0|h[Test Neck]|h|r"
        world.itemUniquenessByID[272228] = nil
        local first = ns.EngineStats.ForLink(cold)
        assert.same({ ready = false }, first)
        assert.same({ 272228 }, world.itemDataRequests)
        -- Asked again while the client is still fetching: no second request.
        assert.same({ ready = false }, ns.EngineStats.ForLink(cold))
        assert.same({ 272228 }, world.itemDataRequests)
        -- The client answers.
        local info = { "Test Neck", coldStripped, 4, n = 3 }
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
        ns.EngineStats.ForLink(HELM.link)
        local firstAsk = calls.total
        assert.is_true(firstAsk > 0)
        local again = ns.EngineStats.ForLink(HELM.link)
        assert.equal(firstAsk, calls.total)
        assert.equal(78, again.haste)
        assert.is_true(again.gems[1].unknown)
        -- A caller writing on its answer does not change the next one.
        again.haste = -1
        assert.equal(78, ns.EngineStats.ForLink(HELM.link).haste)
    end)

    it("forgets an item on ITEM_DATA_LOAD_RESULT for it, and everything on PLAYER_ENTERING_WORLD", function()
        local calls = countCalls(ns)
        ns.EngineStats.ForLink(HELM.link)
        assert.equal(1, ns.EngineStats.Count())
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 999999, true)
        assert.equal(1, ns.EngineStats.Count())
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 271528, true)
        assert.equal(0, ns.EngineStats.Count())
        local before = #callsTo(calls, "C_Item.GetItemStats")
        ns.EngineStats.ForLink(HELM.link)
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
            world.items[link] = { info = { "Test " .. i, link, 4, n = 3 }, level = 300 }
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
        world.itemStats[HELM.strippedLink] = { ITEM_MOD_HASTE_RATING_SHORT = world.markSecret(4321) }
        local r = ns.EngineStats.ForLink(HELM.link)
        assert.same({ secret = true, ready = true }, r)
        assert.equal(0, ns.EngineStats.Count())
    end)

    it("answers secret = true when the whole stat table is secret", function()
        world.itemStats[HELM.strippedLink] = world.secretTable("stats")
        assert.same({ secret = true, ready = true }, ns.EngineStats.ForLink(HELM.link))
        assert.equal(0, ns.EngineStats.Count())
    end)

    it("answers secret = true when the level is secret", function()
        world.items[HELM.strippedLink] = {
            info = world.items[HELM.strippedLink].info,
            level = world.markSecret(3181),
        }
        assert.same({ secret = true, ready = true }, ns.EngineStats.ForLink(HELM.link))
    end)

    it("answers nil in combat and asks the client nothing", function()
        local calls = countCalls(ns)
        world.inCombat = true
        assert.is_nil(ns.EngineStats.ForLink(HELM.link))
        assert.is_nil(ns.EngineStats.ForLink("item:272228"))
        assert.equal(0, calls.total)
        assert.same({}, world.itemDataRequests)
    end)
end)

describe("ns.EngineStats ratings", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- The client applies diminishing returns itself (E-0f): the stub answers
    -- the transcript's own thirty points, and EngineStats hands them back.
    it("hands back the client's own conversion, diminishing returns applied", function()
        assert.equal(30, ns.EngineStats.Rating(20, 1320))
        assert.equal(54, ns.EngineStats.Rating(20, 2640))
        assert.is_nil(ns.EngineStats.Rating(99, 1320))
        -- Haste, crit, mastery and versatility to single precision (3e-6 at
        -- most); leech reads 1.43e-5 relative below 69 rating per percent at
        -- every one of its seven points (2.6e-4 at most), a constant factor
        -- the published table does not carry.
        local tolerance = { haste = 1e-5, crit = 1e-5, mastery = 1e-5, versatility = 1e-5, leech = 3e-4 }
        for key, r in pairs(F.RATING) do
            local points = { { value = r.current, bonus = r.bonus } }
            for _, point in ipairs(r.at) do
                points[#points + 1] = point
            end
            for _, point in ipairs(points) do
                local value = ns.EngineStats.Rating(r.index, point.value)
                assert.is_true(math.abs(value - point.bonus) < tolerance[key], key .. " at " .. point.value)
            end
        end
        -- Mastery answered crit's figure at every point for spec 105.
        for i, point in ipairs(F.RATING.mastery.at) do
            assert.equal(F.RATING.crit.at[i].bonus, point.bonus)
        end
    end)

    it("reads the five current ratings and the mastery pair", function()
        assert.same({
            crit = 524,
            leech = 296,
            haste = 921,
            mastery = 985,
            vers = 338,
            masteryEffect = 38.56050109863281,
            masteryCoefficient = 1.310999989509583,
        }, ns.EngineStats.CurrentRatings())
    end)

    it("answers a secret rating as secret", function()
        world.combatRatings[20] = world.markSecret(2001)
        assert.same({ secret = true }, ns.EngineStats.CurrentRatings())
        local value, secret = ns.EngineStats.Rating(26, world.markSecret(7777))
        -- A secret rating in is a secret percent out.
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

-- E-0g (WKE-677): a journal link reads at its OWN level, so a row is scored at
-- its level only through a link rebuilt for it - and only here. No rule is
-- installed until the `capture linklevel` transcript proves one, so every ask
-- answers nil and "no rule yet"; the rules below are the tests' own.
describe("ns.EngineStats at a level", function()
    local R = require("spec.helpers.replay")
    local TRANSCRIPT = "spec/fixtures/captures/Lootpath-20261001-092631.lua"
    -- The keystone row 250254 listed at 305 (Seed of Radiant Hope, the walk's
    -- difficulty 8 link), and its client answer of 292.
    local KEYSTONE
    for _, row in ipairs(F.rowsFrom("journal")) do
        if row.itemID == 250254 and row.difficultyID == 8 then
            KEYSTONE = row
        end
    end
    local ns, world

    before_each(function()
        ns, world = H.load()
        F.install(world)
    end)

    after_each(function()
        H.unload()
    end)

    -- The rebuilt link registered on the stub as drawing `level` with `int`.
    local function register(link, level, int)
        world.items[link] = {
            info = { KEYSTONE.name, link, 4, level, n = 18 },
            level = level,
            detailed = { level, false, 108, n = 3 },
        }
        world.itemStats[link] = { ITEM_MOD_INTELLECT_SHORT = int, ITEM_MOD_STAMINA_SHORT = 1 }
    end

    it("reads the keystone row the issue names: listed at 305, drawn at 292", function()
        assert.equal(305, KEYSTONE.journalItemLevel)
        assert.equal(292, KEYSTONE.level)
        assert.equal(
            "|cnIQ4:|Hitem:250254::::::::90:105::16:1:3524:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
            KEYSTONE.link
        )
    end)

    it("answers nil and `no rule yet` with no rule installed, and asks the client nothing", function()
        assert.is_nil(ns.EngineStats.linkLevelRule)
        world.itemStatsCalls = {}
        local link, why = ns.EngineStats.LinkAtLevel(KEYSTONE.link, 305)
        assert.is_nil(link)
        assert.equal("no rule yet", why)
        assert.equal(ns.EngineStats.NO_RULE, why)
        local read, why2 = ns.EngineStats.ForLinkAtLevel(KEYSTONE.link, 305)
        assert.is_nil(read)
        assert.equal("no rule yet", why2)
        assert.same({}, world.itemStatsCalls)
    end)

    it("rebuilds the bonus-ID list and touches nothing else", function()
        local link = KEYSTONE.link
        assert.equal(
            "|cnIQ4:|Hitem:250254::::::::90:105::16:1:12837:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
            ns.EngineStats.RebuildLink(link, { 12837 })
        )
        assert.equal(
            "|cnIQ4:|Hitem:250254::::::::90:105::16:2:3524:12837:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
            ns.EngineStats.RebuildLink(link, { 3524, 12837 })
        )
        -- A world row: one bonus ID, no modifier after it.
        assert.equal(
            "item:250462::::::::90:105::5:2:3524:12820::::::",
            ns.EngineStats.RebuildLink("item:250462::::::::90:105::5:1:3524::::::", { 3524, 12820 })
        )
        -- The worn helm: an enchant, a gem, six bonus IDs and a modifier.
        assert.equal(
            "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:1:12846:1:64:239033:::::"
                .. "|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r",
            ns.EngineStats.RebuildLink(HELM.link, { 12846 })
        )
        assert.is_nil(ns.EngineStats.RebuildLink("not a link", { 1 }))
        assert.is_nil(ns.EngineStats.RebuildLink(link, { "12837" }))
        assert.is_nil(ns.EngineStats.RebuildLink(link, { 12837.5 }))
        assert.is_nil(ns.EngineStats.RebuildLink(link, nil))
    end)

    it("reads a link's bonus IDs in the client's order, unsorted", function()
        local fields = ns.EngineStats.LinkFields(HELM.link)
        assert.equal(271528, fields.itemID)
        assert.equal(35, fields.context)
        assert.same({ 6652, 13440, 13695, 13692, 13698, 12845 }, fields.bonusIDs)
        assert.same({ 3524 }, ns.EngineStats.LinkFields(KEYSTONE.link).bonusIDs)
        assert.is_nil(ns.EngineStats.LinkFields("not a link"))
    end)

    it("names every track step at a level, both tracks where they overlap", function()
        local at305 = ns.EngineStats.TrackBonusesAt(305)
        assert.equal(2, #at305)
        assert.same({ bonusID = 12837, track = "Champion", step = 5, itemLevel = 305, client = false }, at305[1])
        assert.same({ bonusID = 12841, track = "Hero", step = 1, itemLevel = 305, client = false }, at305[2])
        assert.same(
            { { bonusID = 12854, track = "Myth", step = 6, itemLevel = 334, client = true } },
            ns.EngineStats.TrackBonusesAt(334)
        )
        -- The world rows' 44: no step draws it.
        assert.same({}, ns.EngineStats.TrackBonusesAt(44))
        assert.same({}, ns.EngineStats.TrackBonusesAt(nil))
    end)

    it("ships the season's five tracks, six steps each, to their tops, with source and build", function()
        local data = ns.trackBonusIDs
        assert.equal("lootpath-track-bonus-ids", data.schema)
        assert.equal("12.1.0.69933", data.build)
        assert.truthy(data.source:find("ddbd93b4b1494a5791b2db5ad1c90f550dc6e327", 1, true))
        local names, tops, seen = {}, {}, {}
        for i, track in ipairs(data.tracks) do
            names[i] = track.name
            assert.equal(6, #track.steps, track.name)
            for s = 2, 6 do
                assert.is_true(track.steps[s].itemLevel > track.steps[s - 1].itemLevel, track.name)
            end
            for _, step in ipairs(track.steps) do
                assert.is_nil(seen[step.bonusID], step.bonusID)
                seen[step.bonusID] = true
            end
            tops[i] = track.steps[6].itemLevel
        end
        assert.same({ "Adventurer", "Veteran", "Champion", "Hero", "Myth" }, names)
        assert.same({ 282, 295, 308, 321, 334 }, tops)
        -- The file is data: no function, no loop (the QEVerdict.lua pattern).
        local text = assert(io.open("Lootpath/Data/TrackBonusIDs.lua")):read("*a")
        local code = text:gsub("%-%-[^\n]*", "")
        assert.is_nil(code:find("function", 1, true))
        assert.is_nil(code:find("for ", 1, true))
    end)

    -- The owner's own client against the table: every step marked `client`
    -- is a level an item he owned answered for a link carrying that bonus ID
    -- on 2026-10-01 (`capture itemstats` worn and bag rows, `capture upgrade`'s
    -- currentLevel), and no owned link carrying ANY ID in the table answered
    -- another level.
    it("agrees with every owned link of the 2026-10-01 transcript, and each `client` mark is one", function()
        local stepOf = {}
        for _, track in ipairs(ns.trackBonusIDs.tracks) do
            for _, step in ipairs(track.steps) do
                stepOf[step.bonusID] = step
            end
        end
        local answered = {}
        local checked = 0
        local function check(link, level)
            local fields = ns.EngineStats.LinkFields(link)
            if not fields or type(level) ~= "number" then
                return
            end
            for _, id in ipairs(fields.bonusIDs) do
                local step = stepOf[id]
                if step then
                    checked = checked + 1
                    assert.equal(step.itemLevel, level, link)
                    answered[id] = true
                end
            end
        end
        for _, source in ipairs({ "worn", "bag" }) do
            for _, row in ipairs(F.rowsFrom(source)) do
                check(row.link, row.level)
            end
        end
        for _, snapshot in ipairs(R.captures(TRANSCRIPT).upgrade) do
            for _, item in ipairs(snapshot.data.items or {}) do
                check(item.link, item.currentLevel and item.currentLevel[1])
            end
        end
        assert.is_true(checked > 0)
        for id, step in pairs(stepOf) do
            assert.equal(step.client == true, answered[id] == true, "bonus " .. id)
        end
    end)

    it("rebuilds through the rule handed in, or the one installed", function()
        local rule = function(_, level, parsed)
            assert.same({ 3524 }, parsed.bonusIDs)
            return { ns.EngineStats.TrackBonusesAt(level)[1].bonusID }
        end
        local rebuilt = ns.EngineStats.LinkAtLevel(KEYSTONE.link, 305, rule)
        assert.equal(ns.EngineStats.RebuildLink(KEYSTONE.link, { 12837 }), rebuilt)
        ns.EngineStats.linkLevelRule = rule
        assert.equal(rebuilt, ns.EngineStats.LinkAtLevel(KEYSTONE.link, 305))
        ns.EngineStats.linkLevelRule = nil
    end)

    it("says why when the rule has no answer, fails, or answers no list", function()
        local link, why = ns.EngineStats.LinkAtLevel(KEYSTONE.link, 44, function()
            return nil, "no track step draws 44"
        end)
        assert.is_nil(link)
        assert.equal("no track step draws 44", why)
        link, why = ns.EngineStats.LinkAtLevel(KEYSTONE.link, 305, function()
            error("boom")
        end)
        assert.is_nil(link)
        assert.equal("the rule failed", why)
        link, why = ns.EngineStats.LinkAtLevel(KEYSTONE.link, 305, function()
            return { "x" }
        end)
        assert.is_nil(link)
        assert.equal("the rule's bonus IDs are not a list", why)
        link, why = ns.EngineStats.LinkAtLevel("not a link", 305, function()
            return {}
        end)
        assert.is_nil(link)
        assert.equal("not an item link at a level", why)
    end)

    it("reads the rebuilt link and keeps it only when the client draws the asked level", function()
        local rebuilt = ns.EngineStats.RebuildLink(KEYSTONE.link, { 12837 })
        register(rebuilt, 305, 600)
        local read, link = ns.EngineStats.ForLinkAtLevel(KEYSTONE.link, 305, function()
            return { 12837 }
        end)
        assert.equal(rebuilt, link)
        assert.is_true(read.ready)
        assert.equal(305, read.level)
        assert.equal(600, read.int)
        -- The link read as it was kept answers 292: never the row's 305.
        assert.equal(292, ns.EngineStats.ForLink(KEYSTONE.link).level)
    end)

    it("refuses a rebuilt link the client draws at another level", function()
        local rebuilt = ns.EngineStats.RebuildLink(KEYSTONE.link, { 12841 })
        register(rebuilt, 292, 567)
        local read, why = ns.EngineStats.ForLinkAtLevel(KEYSTONE.link, 305, function()
            return { 12841 }
        end)
        assert.is_nil(read)
        assert.equal("read at 292, not 305", why)
        assert.is_nil(ns.EngineStats.AtLevel({ ready = true, level = 292 }, 305))
        assert.is_table(ns.EngineStats.AtLevel({ ready = true, level = 305 }, 305))
        assert.is_nil(ns.EngineStats.AtLevel({ ready = false }, 305))
        assert.is_nil(ns.EngineStats.AtLevel({ ready = true, secret = true }, 305))
    end)

    it("answers ready = false and the rebuilt link while the client fetches it", function()
        local rebuilt = ns.EngineStats.RebuildLink(KEYSTONE.link, { 12837 })
        local read, link = ns.EngineStats.ForLinkAtLevel(KEYSTONE.link, 305, function()
            return { 12837 }
        end)
        assert.same({ ready = false }, read)
        assert.equal(rebuilt, link)
    end)

    it("answers nil in combat and asks the client nothing", function()
        world.inCombat = true
        world.itemStatsCalls = {}
        assert.is_nil(ns.EngineStats.ForLinkAtLevel(KEYSTONE.link, 305, function()
            return { 12837 }
        end))
        assert.same({}, world.itemStatsCalls)
    end)

    -- The one place: no other file defines a link rebuilder.
    it("is the only file that rebuilds a link", function()
        local writers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("%.lua$") and not f:match("^Libs/") and f ~= "Modules/EngineStats.lua" then
                local text = assert(io.open("Lootpath/" .. f)):read("*a")
                local code = text:gsub("%-%-[^\n]*", "")
                if code:find("function [%w_.:]*RebuildLink") or code:find("RebuildLink%s*=") then
                    writers[#writers + 1] = f
                end
            end
        end
        assert.same({}, writers)
    end)
end)
