-- spec/drift_spec.lua (R-6, WKE-578)
-- The nudge and the wait, over the owner's own 2026-09-14 gear.
--
-- Everything the drift check compares is read from a committed capture: the
-- inventory is his 17:13 scan of that afternoon (80 records, 15 worn and 35 in
-- the bags), the arrival is the Great Vault's own Lightgrasp Worldroot out of
-- the same file's vault snapshot 9 - key `251935:6652:12841`, item level 305,
-- named by the client - and the item that must NOT set the nudge off is bag 0
-- slot 1 of that same afternoon, his Hearthstone, the one R-2b's glow capture
-- records as `inMap = false`.
--
-- WHAT THIS FILE DOES NOT HAVE, and why. WKE-578 asks for "the claimed
-- Worldroot appearing at 315". No committed capture holds that: both 2026-09-14
-- captures (11:30 and 17:13) were taken BEFORE he claimed, their two inventory
-- snapshots are byte-identical in key set (measured here on 2026-09-14: 80
-- records each, 0 appeared, 0 gone), and nothing has been pulled back since. So
-- the arrival is played the way a claim actually plays: the vault's own reward
-- link, with the fixture's own key, name and 305, put into a free bag slot. The
-- item, its key, its name and its item level are the client's; only the act of
-- claiming is the test's.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local TODAY = "spec/fixtures/captures/Lootpath-20260914-171359.lua"
local MORNING = "spec/fixtures/captures/Lootpath-20260914-113012.lua"

-- The vault snapshot of that file that carries every reward link the client had
-- named. Snapshots 1-8 were taken before the client answered with them.
local VAULT_SNAPSHOT = 9
local WORLDROOT_KEY = "251935:6652:12841"
local WORLDROOT_NAME = "Lightgrasp Worldroot"

-- His own Hearthstone, read out of the glow capture rather than written here,
-- exactly as spec/tooltip_spec.lua reads it: a real item that is not gear.
local HEARTHSTONE_LINK = (function()
    for _, slot in ipairs(R.snapshot("glow", 1, TODAY).data.slots) do
        if slot.key == "6948" then
            return slot.link
        end
    end
    error("the glow capture no longer carries the Hearthstone slot")
end)()

local function worldrootLink()
    for _, entry in ipairs(R.snapshot("vault", VAULT_SNAPSHOT, TODAY).data.rewardLinks or {}) do
        local link = entry.link and entry.link[1]
        if type(link) == "string" and link:find("|Hitem:251935:", 1, true) then
            return link
        end
    end
    error("vault snapshot " .. VAULT_SNAPSHOT .. " no longer carries the Worldroot")
end

local WORLDROOT_LINK = worldrootLink()

-- Puts a link into the first free bag slot the owner had that afternoon, which
-- is what looting, buying or claiming does. His bags were nearly full, so this
-- walks all five rather than assuming bag 0 has room.
local function intoBag(world, link)
    for bagIndex = 0, 4 do
        local bag = world.bags[bagIndex]
        for slotIndex = 1, (bag and bag.numSlots or 0) do
            if not bag.items[slotIndex] then
                bag.items[slotIndex] = { link = link }
                return bagIndex, slotIndex
            end
        end
    end
    error("every bag is full in this fixture")
end

-- Takes one item out of wherever it is in his bags, by itemID, and hands back
-- its link. Nothing is invented: the link is the client's own.
local function outOfBags(world, itemID)
    local needle = "|Hitem:" .. itemID .. ":"
    for bagIndex = 0, 4 do
        local bag = world.bags[bagIndex]
        for slotIndex, item in pairs((bag and bag.items) or {}) do
            if type(item.link) == "string" and item.link:find(needle, 1, true) then
                bag.items[slotIndex] = nil
                return item.link
            end
        end
    end
    return nil
end

local function loadToday()
    local ns, world = H.load()
    R.inventory(world, R.snapshot("inventory", 1, TODAY))
    R.vault(world, R.snapshot("vault", VAULT_SNAPSHOT, TODAY))
    -- The scan at load ran before the fixture was in place, so the baseline is
    -- taken again over his real gear: this is the state the plan was written
    -- over.
    ns.Drift.Rebase()
    return ns, world
end

describe("ns.Drift over the owner's 2026-09-14 gear", function()
    local ns, world

    before_each(function()
        ns, world = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    it("says nothing at all while the gear is the gear the plan was written over", function()
        assert.is_nil(ns.Drift.Check())
        assert.is_nil(ns.Drift.Behind())
        assert.is_nil(ns.Drift.Model())
    end)

    it("reads 80 records and takes the 50 worn-and-bagged keys as the baseline", function()
        local scan = ns.Inventory.Scan()
        assert.equal(80, #scan.records)
        local keys = ns.Drift.KeySet(scan.records)
        local count = 0
        for _ in pairs(keys) do
            count = count + 1
        end
        assert.equal(50, count)
    end)

    -- The morning capture and the afternoon one are the same gear. It is worth
    -- an assertion rather than a comment: it is the measurement that says why
    -- this file plays the claim instead of replaying it.
    it("sees no drift between his 11:30 bags and his 17:13 bags", function()
        R.inventory(world, R.snapshot("inventory", 1, MORNING))
        local morning = ns.Drift.Now()
        R.inventory(world, R.snapshot("inventory", 1, TODAY))
        assert.is_nil(ns.Drift.Compare(morning, ns.Drift.Now()))
    end)

    it("sets Behind when the claimed vault Worldroot lands in the bags, and names it", function()
        intoBag(world, WORLDROOT_LINK)
        local behind = ns.Drift.Check()
        assert.is_table(behind)
        assert.equal(1, behind.count)
        assert.equal(WORLDROOT_NAME, behind.name)
        -- and it really is the key the vault named, not some other arrival
        assert.is_not_nil(ns.Drift.Now()[WORLDROOT_KEY])
    end)

    it("says one line about it, word for word", function()
        intoBag(world, WORLDROOT_LINK)
        ns.Drift.Check()
        local model = ns.Drift.Model()
        assert.equal("behind", model.kind)
        assert.equal("your gear changed since this plan (1 item) \194\183 click to refresh", model.text)
        assert.is_truthy(model.tooltip:find(WORLDROOT_NAME, 1, true))
    end)

    it("counts two items as two, and says `items`", function()
        intoBag(world, WORLDROOT_LINK)
        -- The second change is a piece LEAVING: he vendored the Falconer's
        -- Cinch, which his 17:13 bags really did carry at 263.
        assert.is_string(outOfBags(world, 251166))
        local behind = ns.Drift.Check()
        assert.equal(2, behind.count)
        assert.equal("your gear changed since this plan (2 items) \194\183 click to refresh", ns.Drift.Model().text)
    end)

    -- The first of the three guards WKE-578 names.
    it("does not fire for a Hearthstone, a potion or anything else that is not gear", function()
        intoBag(world, HEARTHSTONE_LINK)
        assert.is_nil(ns.Drift.Check())
        assert.is_nil(ns.Drift.Model())
        -- a stack of the same thing moving to another slot is the same silence
        intoBag(world, HEARTHSTONE_LINK)
        assert.is_nil(ns.Drift.Check())
    end)

    -- The second: an item the plan already knew, however it moves.
    it("does not fire when a piece the plan already knew moves from the bags onto the character", function()
        -- His Miststalker's Spaulders, out of the bags and onto the shoulders,
        -- and the Lynx Spaulders he was wearing back into the bags: a swap moves
        -- two items and neither of them is new to the plan.
        local moved = outOfBags(world, 272244)
        assert.is_string(moved)
        local displaced = world.equipped[3].link
        world.equipped[3] = { link = moved }
        intoBag(world, displaced)
        assert.is_nil(ns.Drift.Check())
    end)

    -- The third: the bank is a window opening, not gear moving. Every bank tab
    -- answers its slot counts only while the frame is open (2026-09-05
    -- transcript), so a set that counted them would nudge on a click.
    it("does not fire when the bank frame opens", function()
        local scan = ns.Inventory.Scan()
        local before = ns.Drift.KeySet(scan.records)
        -- the same scan with a bank tab's worth of gear in it
        local stored = { key = "999:1", name = "Something Stored", location = "bank" }
        scan.records[#scan.records + 1] = stored
        local after = ns.Drift.KeySet(scan.records)
        assert.is_nil(after["999:1"])
        assert.is_nil(ns.Drift.Compare(before, after))
    end)

    it("rebases instead of nudging when a new plan arrives", function()
        intoBag(world, WORLDROOT_LINK)
        assert.is_table(ns.Drift.Check())
        -- a plan written after the claim knows about it; the nudge goes
        ns.db.char.qeImports = {}
        ns.Drift.Rebase()
        assert.is_nil(ns.Drift.Behind())
        assert.is_nil(ns.Drift.Check())
    end)
end)

describe("ns.Drift and combat", function()
    local ns, world

    before_each(function()
        ns, world = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    it("does not scan in combat, and runs the check it refused when the fight ends", function()
        intoBag(world, WORLDROOT_LINK)
        world.inCombat = true
        assert.is_nil(ns.Drift.Check())
        assert.is_nil(ns.Drift.Behind())
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        world.runTimers(2)
        assert.is_table(ns.Drift.Behind())
    end)

    it("answers a burst of bag events with one check", function()
        intoBag(world, WORLDROOT_LINK)
        for _ = 1, 5 do
            world.fireEvent("BAG_UPDATE_DELAYED")
        end
        assert.is_nil(ns.Drift.Behind())
        world.runTimers(2)
        assert.equal(1, ns.Drift.Behind().count)
    end)

    it("listens to the four events Blizzard's own documentation names", function()
        assert.same({
            "BAG_UPDATE_DELAYED",
            "PLAYER_EQUIPMENT_CHANGED",
            "WEEKLY_REWARDS_UPDATE",
            "ITEM_UPGRADE_MASTER_UPDATE",
        }, ns.Drift.EVENTS)
        for _, event in ipairs(ns.Drift.EVENTS) do
            world.fireEvent(event)
            world.runTimers(2)
        end
        assert.is_nil(ns.Drift.Behind())
    end)
end)

describe("ns.Drift, the wait after the first reload", function()
    local ns, world
    local STARTED = "2026-09-14T23:10:00Z"

    before_each(function()
        ns, world = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    local function at(iso)
        return ns.EpochFromISO(iso)
    end

    local function waiting(startedAt)
        ns.db.global.drift.refreshStartedAt = startedAt or STARTED
    end

    it("writes the stamp before it reloads, never after", function()
        local order = {}
        local realReload = _G.ReloadUI
        _G.ReloadUI = function()
            order[#order + 1] = ns.db.global.drift.refreshStartedAt
            realReload()
        end
        ns.Companion.Refresh()
        _G.ReloadUI = realReload
        assert.equal(1, world.reloads)
        assert.is_string(order[1])
        assert.equal(order[1], ns.db.global.drift.refreshStartedAt)
    end)

    it("says the rating is being made, counting, and beats the nudge", function()
        intoBag(world, WORLDROOT_LINK)
        ns.Drift.Check()
        waiting()
        local model = ns.Drift.Model(at("2026-09-14T23:10:30Z"))
        assert.equal("wait", model.kind)
        assert.equal(
            "rating your gear, started 30 seconds ago, usually about a minute \194\183 click to load it",
            model.text
        )
    end)

    -- V-4 (WKE-589), and the answer to a question §11 left open: whether the
    -- wait ever showed on the owner's client at all. It could not. The stamp
    -- `RefreshStarting` writes is correct UTC, but the parse it is compared
    -- against ran an hour late while daylight time was in effect, so the
    -- elapsed time came out 3600 seconds larger than it was, cleared
    -- `WAIT_GIVE_UP_SECONDS` (600) on the FIRST check, and the wait deleted
    -- itself before anything could draw it. On the modelled daylight clock the
    -- thirty-second wait is a thirty-second wait.
    it("survives its first check while daylight time is in effect", function()
        H.chicagoClock(world, 1789427400 + 30) -- 2026-09-14T23:10:30Z
        intoBag(world, WORLDROOT_LINK)
        ns.Drift.Check()
        waiting()
        local model = ns.Drift.Model(1789427400 + 30)
        assert.equal("wait", model.kind)
        assert.equal(
            "rating your gear, started 30 seconds ago, usually about a minute \194\183 click to load it",
            model.text
        )
        assert.equal(STARTED, ns.db.global.drift.refreshStartedAt)
    end)

    it("quotes the last finished run, rounded to the nearest 15 seconds", function()
        ns.companionStatus = {
            state = "idle",
            startedAt = "2026-09-14T22:48:00Z",
            finishedAt = "2026-09-14T22:48:41Z",
            verdictWrittenAt = "2026-09-14T22:48:41Z",
        }
        assert.equal(41, ns.Drift.RecordRun())
        waiting()
        assert.equal(
            "rating your gear, started 30 seconds ago, usually ready in about 45 seconds \194\183 click to load it",
            ns.Drift.Model(at("2026-09-14T23:10:30Z")).text
        )
        -- a run over a minute reads in minutes, and 15 s is the whole precision
        ns.db.global.drift.runSeconds = 82
        assert.equal("usually ready in about 1 minute 15 seconds", ns.Drift.ReadyText(82))
        assert.equal("usually ready in about 1 minute", ns.Drift.ReadyText(58))
        assert.equal("usually about a minute", ns.Drift.ReadyText(nil))
    end)

    -- A run that had nothing to do, or that died, took the time it took and
    -- says nothing about how long a RATING takes. Quoting one would put a
    -- measurement of the wrong thing on the strip.
    it("quotes only a run that actually rated something", function()
        for _, state in ipairs({ "skipped", "failed" }) do
            ns.companionStatus = {
                state = state,
                startedAt = "2026-09-14T22:48:00Z",
                finishedAt = "2026-09-14T22:48:02Z",
            }
            assert.is_nil(ns.Drift.RecordRun())
            assert.is_nil(ns.db.global.drift.runSeconds)
        end
        -- ending on the skipped one, because C-9's FAILED takes the strip back
        -- from the wait entirely and this is about the measurement
        ns.companionStatus = {
            state = "skipped",
            startedAt = "2026-09-14T22:48:00Z",
            finishedAt = "2026-09-14T22:48:02Z",
        }
        waiting()
        assert.is_truthy(ns.Drift.Model(at("2026-09-14T23:10:30Z")).text:find("usually about a minute", 1, true))
    end)

    it("takes the measurement from the run that FINISHED, never the one running", function()
        ns.companionStatus = { state = "running", startedAt = "2026-09-14T23:10:05Z" }
        assert.is_nil(ns.Drift.RecordRun())
        waiting()
        local model = ns.Drift.Model(at("2026-09-14T23:10:30Z"))
        -- the elapsed time is the RUN's clock now, not the click's
        assert.equal(
            "rating your gear, started 25 seconds ago, usually about a minute \194\183 click to load it",
            model.text
        )
    end)

    it("stops the moment a plan written since the click is loaded", function()
        waiting()
        local verdict = ns.UI.ActiveVerdict()
        assert.is_nil(verdict)
        ns.db.char.qeImports = {
            Dungeon = {
                spec = "Restoration Druid",
                exportedAt = "2026-09-14T23:11:00Z",
                companionWrittenAt = "2026-09-14T23:11:30Z",
                items = {},
                scenario = ns.QEImport.DEFAULT_SCENARIO,
            },
        }
        assert.is_nil(ns.Drift.Model(at("2026-09-14T23:12:00Z")))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    it("gives the strip back to C-9 when the run FAILED", function()
        waiting()
        ns.companionStatus = { state = "failed", stage = "qe live", finishedAt = "2026-09-14T23:10:20Z" }
        assert.is_nil(ns.Drift.Model(at("2026-09-14T23:10:30Z")))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    it("gives up rather than saying `rating your gear` for the rest of the session", function()
        waiting()
        assert.is_table(ns.Drift.Model(at("2026-09-14T23:19:00Z")))
        assert.is_nil(ns.Drift.Model(at("2026-09-14T23:30:00Z")))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    -- M3-16b (WKE-583): the chat line at the load the refresh's reload
    -- produced. The owner on 2026-09-15: "after I do a refresh and the screen
    -- loads and I'm back in game, I'm assuming the refresh is done." The chat
    -- frame is where he is looking at that moment, so the wait says itself
    -- there once. Proven red by returning nil from `Drift.AnnounceWait` before
    -- it prints: nothing is said at the load that is waiting.
    it("says in chat, once, at the load that is still waiting", function()
        waiting()
        local line = ns.Drift.AnnounceWait(at("2026-09-14T23:10:30Z"))
        assert.equal(
            "your gear is sent; the rating usually takes about a minute. The window says when it's ready.",
            line
        )
        assert.is_truthy(tostring(world.output()):find(line, 1, true))
    end)

    -- And it quotes the same measured run the strip does, in the phrasing that
    -- reads as a sentence.
    it("quotes the last finished run in the chat line too", function()
        ns.db.global.drift.runSeconds = 175
        waiting()
        assert.equal(
            "your gear is sent; the rating usually takes about 3 minutes. The window says when it's ready.",
            ns.Drift.AnnounceWait(at("2026-09-14T23:10:30Z"))
        )
        assert.equal("3 minutes", ns.Drift.RunText(175))
        assert.is_nil(ns.Drift.RunText(nil))
    end)

    -- A load with no refresh out there says nothing at all: the line exists to
    -- answer "is it still happening", and there is nothing to answer.
    it("says nothing at a load that is not waiting", function()
        local before = tostring(world.output())
        assert.is_nil(ns.Drift.AnnounceWait(at("2026-09-14T23:10:30Z")))
        assert.equal(before, tostring(world.output()))
    end)
end)

describe("ns.Drift.Click", function()
    local ns, world

    before_each(function()
        ns, world = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    -- One function, two callers: the click runs `ns.Companion.Refresh`, which
    -- is what `/lootpath refresh` runs, and not a copy of it.
    it("runs the refresh when the gear has moved, capturing all four and reloading once", function()
        intoBag(world, WORLDROOT_LINK)
        ns.Drift.Check()
        assert.equal("refresh", ns.Drift.Click())
        assert.equal(1, world.reloads)
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            assert.is_truthy(ns.db.global.captures[name] and #ns.db.global.captures[name] > 0, name)
        end
        assert.is_string(ns.db.global.drift.refreshStartedAt)
    end)

    it("is a plain reload while the rating is being made, and captures nothing", function()
        ns.db.global.captures = {}
        ns.db.global.drift.refreshStartedAt = "2026-09-14T23:10:00Z"
        assert.equal("reloaded", ns.Drift.Click(ns.EpochFromISO("2026-09-14T23:10:30Z")))
        assert.equal(1, world.reloads)
        assert.same({}, ns.db.global.captures)
    end)
end)

describe("the refresh labels what it captured (R-6)", function()
    local ns

    before_each(function()
        ns = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    it("marks every snapshot the refresh took as the refresh's own", function()
        ns.Companion.Refresh()
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            local list = ns.db.global.captures[name]
            assert.equal("refresh", list[#list].trigger)
        end
    end)

    it("marks a capture typed by hand as a command, before and after a refresh", function()
        ns.HandleSlash("capture env")
        assert.equal("command", ns.db.global.captures.env[1].trigger)
        ns.Companion.Refresh()
        ns.HandleSlash("capture env")
        local list = ns.db.global.captures.env
        assert.equal("command", list[#list].trigger)
    end)
end)
