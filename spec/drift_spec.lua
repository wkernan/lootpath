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
        assert.equal("your gear changed since this rating (1 item) \194\183 click to refresh", model.text)
        assert.is_truthy(model.tooltip:find(WORLDROOT_NAME, 1, true))
    end)

    it("counts two items as two, and says `items`", function()
        intoBag(world, WORLDROOT_LINK)
        -- The second change is a piece LEAVING: he vendored the Falconer's
        -- Cinch, which his 17:13 bags really did carry at 263.
        assert.is_string(outOfBags(world, 251166))
        local behind = ns.Drift.Check()
        assert.equal(2, behind.count)
        assert.equal("your gear changed since this rating (2 items) \194\183 click to refresh", ns.Drift.Model().text)
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

    -- H-1 (WKE-596) added the fifth, and it is not a gear event: it is what
    -- takes a standing nudge, the minimap badge and the bag marks down when the
    -- player changes spec, through the one function that owns all three.
    it("listens to the four gear events Blizzard's documentation names, and the spec change", function()
        assert.same({
            "BAG_UPDATE_DELAYED",
            "PLAYER_EQUIPMENT_CHANGED",
            "WEEKLY_REWARDS_UPDATE",
            "ITEM_UPGRADE_MASTER_UPDATE",
            "PLAYER_SPECIALIZATION_CHANGED",
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

    -- A wait stands only where a companion has been SEEN (R-6a, WKE-590): with
    -- no status file at all the load line answers `the companion hasn't been
    -- seen` and the strip stops counting, so the default here is the state the
    -- owner's machine is actually in - a companion that has run before and has
    -- been idle since. A test that wants another state sets it first; this
    -- never overwrites one.
    local function waiting(startedAt)
        ns.companionStatus = ns.companionStatus
            or { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
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
            "rating your gear, started 30 seconds ago, usually about a minute "
                .. "\194\183 Refresh loads it when it's ready",
            model.text
        )
    end)

    -- R-8b (WKE-623): the clause names the button on its own row. The owner,
    -- 2026-09-21: "I don't like this copy that just says 'click to load it'...
    -- click what?" Proven red by putting M3-16b's `click to load it` back into
    -- `Drift.WAIT_LINE`: `Refresh` is nowhere in the line and `click` is in it.
    it("names the Refresh button instead of telling the player to click something", function()
        waiting()
        local model = ns.Drift.Model(at("2026-09-14T23:10:30Z"))
        assert.is_truthy(model.text:find("Refresh loads it when it's ready", 1, true))
        for _, text in ipairs({ ns.Drift.WAIT_LINE, ns.Drift.WAIT_TOOLTIP, model.text, model.tooltip }) do
            assert.is_truthy(text:find("Refresh", 1, true), text)
            assert.is_nil(text:lower():find("click", 1, true), text)
        end
        -- the button the words point at carries the same promise on its hover
        local ready = ns.Drift.RefreshTooltip(at("2026-09-14T23:10:30Z"))
        assert.equal("load the rating that's ready - takes a reload", ready)
        -- and the chat line, read where no button is, is untouched
        assert.equal("your gear is sent; the rating %s. The window says when it's ready.", ns.Drift.WAIT_CHAT_LINE)
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
            "rating your gear, started 30 seconds ago, usually about a minute "
                .. "\194\183 Refresh loads it when it's ready",
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
            "rating your gear, started 30 seconds ago, usually ready in about 45 seconds "
                .. "\194\183 Refresh loads it when it's ready",
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
        -- ending on a run that is genuinely going, because since R-6a both a
        -- FAILED run and a SKIPPED one take the strip back from the wait
        -- entirely and this is about the measurement, not the decision.
        ns.companionStatus = { state = "running", startedAt = "2026-09-14T23:10:05Z" }
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
            "rating your gear, started 25 seconds ago, usually about a minute "
                .. "\194\183 Refresh loads it when it's ready",
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
    -- there once. Proven red by returning nil from `Drift.LoadLine` before it
    -- prints: nothing is said at the load that is waiting.
    it("says in chat, once, at the load that is still waiting", function()
        waiting()
        local line = ns.Drift.LoadLine(at("2026-09-14T23:10:30Z"))
        assert.equal(
            "your gear is sent; the rating usually takes about a minute. The window says when it's ready.",
            line
        )
        assert.is_truthy(tostring(world.output()):find(line, 1, true))
        -- and the stamp SURVIVES this one, because the strip counts from it
        assert.equal(STARTED, ns.db.global.drift.refreshStartedAt)
    end)

    -- And it quotes the same measured run the strip does, in the phrasing that
    -- reads as a sentence.
    it("quotes the last finished run in the chat line too", function()
        ns.db.global.drift.runSeconds = 175
        waiting()
        assert.equal(
            "your gear is sent; the rating usually takes about 3 minutes. The window says when it's ready.",
            ns.Drift.LoadLine(at("2026-09-14T23:10:30Z"))
        )
        assert.equal("3 minutes", ns.Drift.RunText(175))
        assert.is_nil(ns.Drift.RunText(nil))
    end)

    -- A load with no refresh out there says nothing at all: the line exists to
    -- answer a question the player asked, and he asked nothing.
    it("says nothing at a load that is not waiting", function()
        local before = tostring(world.output())
        assert.is_nil(ns.Drift.LoadLine(at("2026-09-14T23:10:30Z")))
        assert.equal(before, tostring(world.output()))
    end)
end)

-- ---------------------------------------------------------------------------
-- R-6a (WKE-590): the load after a refresh always says something.
--
-- The owner's screen, 2026-09-15 17:22 local: he reloaded, ran
-- `/lootpath refresh`, landed back in game, and saw NO chat line. C-4's
-- fingerprint had skipped the run in under a second, the status file said
-- `skipped` before the reload had finished, and M3-16b's line - which fired
-- only while the wait was on - correctly had nothing to wait for and said
-- nothing. Correct, and silent at exactly the moment the player asked for
-- feedback.
--
-- Proven red by deleting every branch but the wait's from `Drift.LoadLine`:
-- four of the five states below then say nothing, and the strip keeps counting
-- through a run that has already ended.
describe("ns.Drift.LoadLine, the five things the load after a refresh can say", function()
    local ns, world
    local STARTED = "2026-09-14T23:10:00Z"
    local NOW = "2026-09-14T23:10:30Z"

    before_each(function()
        ns, world = loadToday()
        ns.db.global.drift.refreshStartedAt = STARTED
    end)

    after_each(function()
        H.unload()
    end)

    local function at(iso)
        return ns.EpochFromISO(iso)
    end

    -- Said in chat, and said with the addon's own prefix - it is the addon
    -- speaking, not a raw string appearing.
    local function said(line)
        assert.is_truthy(tostring(world.output()):find(ns.PREFIX .. line, 1, true))
    end

    it("says the plan is current when C-4 skipped the run as unchanged", function()
        ns.companionStatus = {
            state = "skipped",
            startedAt = "2026-09-14T23:10:05Z",
            finishedAt = "2026-09-14T23:10:06Z",
            message = "profile unchanged since 2026-09-14T23:09:00Z; the rating is current",
        }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal("your gear hasn't changed since the last rating, so what you have is current.", line)
        said(line)
        -- and the strip agrees: it stops counting a run that has already ended
        assert.is_nil(ns.Drift.Model(at(NOW)))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    -- R-7b (WKE-591). The second `skipped`, and the opposite news. The
    -- companion's own message is prose, so the exit code is what the line is
    -- chosen by. Proven red by dropping the `exitCode` test from `LoadLine`:
    -- the load says "your gear hasn't changed since the last rating" about a
    -- run that was never given any gear at all.
    it("says the gear never reached the companion when that is why it skipped", function()
        ns.companionStatus = {
            state = "skipped",
            startedAt = "2026-09-14T23:10:05Z",
            finishedAt = "2026-09-14T23:10:06Z",
            exitCode = ns.Companion.EXIT_EMPTY_GEAR,
            message = "refusing to rate a profile with no equipped gear (the newest inventory read is empty); "
                .. "the previous verdict is untouched",
        }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal(
            "your gear didn't reach the companion - the last read of it was empty - so what you have is "
                .. "untouched. Try /lootpath refresh.",
            line
        )
        assert.not_equal(ns.Drift.LOAD_SKIPPED, line)
        said(line)
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    -- C-14 (WKE-603). The THIRD `skipped`, and the one with a cure the player
    -- can carry out in ten seconds: the gear was read and read correctly, and a
    -- slot in it was bare. Chosen by its own exit code, never by the message.
    -- Proven red by dropping the `EXIT_EMPTY_SLOT` branch from `LoadLine`: the
    -- load says "your gear hasn't changed since the last rating" about a run
    -- that was refused before the browser was opened.
    it("says a slot was empty when that is why it skipped", function()
        ns.companionStatus = {
            state = "skipped",
            startedAt = "2026-09-14T23:10:05Z",
            finishedAt = "2026-09-14T23:10:06Z",
            exitCode = ns.Companion.EXIT_EMPTY_SLOT,
            message = "refusing to rate a profile with an empty slot (legs); the previous verdict is untouched",
        }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal(
            "a gear slot was empty when your gear was read, so it couldn't be rated. "
                .. "Put something in that slot and /lootpath refresh.",
            line
        )
        assert.not_equal(ns.Drift.LOAD_SKIPPED, line)
        assert.not_equal(ns.Drift.LOAD_SKIPPED_EMPTY, line)
        said(line)
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    it("names the stage when C-9 says the run died", function()
        ns.companionStatus = {
            state = "failed",
            stage = "qe live",
            startedAt = "2026-09-14T23:10:05Z",
            finishedAt = "2026-09-14T23:10:20Z",
        }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal("the rating failed at qe live; see companion.log.", line)
        said(line)
        assert.is_nil(ns.Drift.Model(at(NOW)))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    -- A failure C-9 could not place still reads as a sentence.
    it("says it failed even with no stage", function()
        ns.companionStatus = { state = "failed", finishedAt = "2026-09-14T23:10:20Z" }
        assert.equal("the rating failed; see companion.log.", ns.Drift.LoadLine(at(NOW)))
    end)

    it("says the rating is coming while it is genuinely running", function()
        ns.companionStatus = { state = "running", startedAt = "2026-09-14T23:10:05Z" }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal(
            "your gear is sent; the rating usually takes about a minute. The window says when it's ready.",
            line
        )
        said(line)
        -- the wait keeps its stamp: this is the one state the strip counts on
        assert.equal("wait", ns.Drift.Model(at(NOW)).kind)
        assert.equal(STARTED, ns.db.global.drift.refreshStartedAt)
    end)

    -- The 18:21 run nearly did this: the companion finished while the client
    -- was still loading, so the plan the load carries is already the new one.
    it("says it was rated just now when the run beat the reload", function()
        ns.companionStatus = {
            state = "idle",
            startedAt = "2026-09-14T23:10:02Z",
            finishedAt = "2026-09-14T23:10:12Z",
            verdictWrittenAt = "2026-09-14T23:10:12Z",
        }
        ns.db.char.qeImports = {
            Dungeon = {
                spec = "Restoration Druid",
                exportedAt = "2026-09-14T23:10:10Z",
                companionWrittenAt = "2026-09-14T23:10:12Z",
                items = {},
                scenario = ns.QEImport.DEFAULT_SCENARIO,
            },
        }
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal("rated just now; you're up to date.", line)
        said(line)
        assert.is_nil(ns.Drift.Model(at(NOW)))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    it("asks whether the companion is running when it has never written a status file", function()
        assert.is_nil(ns.companionStatus)
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal("the companion hasn't been seen; is it running?", line)
        said(line)
        assert.is_nil(ns.Drift.Model(at(NOW)))
        assert.is_nil(ns.db.global.drift.refreshStartedAt)
    end)

    -- Said once. The stamp goes with the line in the four states that end the
    -- refresh, so the next plain `/reload` is silent.
    it("says a terminal line once and then nothing", function()
        ns.companionStatus = { state = "skipped", finishedAt = "2026-09-14T23:10:06Z" }
        assert.is_string(ns.Drift.LoadLine(at(NOW)))
        local before = tostring(world.output())
        assert.is_nil(ns.Drift.LoadLine(at(NOW)))
        assert.equal(before, tostring(world.output()))
    end)

    -- The chat frame and the strip read ONE decision, which is the whole point
    -- of `Drift.Decide` existing: whichever of them looks first, the other
    -- cannot contradict it.
    it("gives the strip and the chat line one answer per state", function()
        local cases = {
            { status = { state = "skipped", finishedAt = "2026-09-14T23:10:06Z" }, waits = false },
            { status = { state = "failed", stage = "profile", finishedAt = "2026-09-14T23:10:06Z" }, waits = false },
            { status = { state = "running", startedAt = "2026-09-14T23:10:05Z" }, waits = true },
            { status = { state = "idle", finishedAt = "2026-09-14T22:48:41Z" }, waits = true },
        }
        for _, case in ipairs(cases) do
            ns.db.global.drift.refreshStartedAt = STARTED
            ns.companionStatus = case.status
            local decision = ns.Drift.Decide(at(NOW))
            assert.equal(case.waits, decision == "waiting")
            -- the strip first, the chat line second: the stamp the strip clears
            -- must not take the line with it
            local model = ns.Drift.Model(at(NOW))
            assert.equal(case.waits, model ~= nil and model.kind == "wait")
            ns.db.global.drift.refreshStartedAt = STARTED
            assert.is_string(ns.Drift.LoadLine(at(NOW)))
        end
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
        -- A wait stands only where a companion has been seen (R-6a): this is
        -- the previous run the owner's own machine carries.
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        ns.db.global.drift.refreshStartedAt = "2026-09-14T23:10:00Z"
        assert.equal("reloaded", ns.Drift.Click(ns.EpochFromISO("2026-09-14T23:10:30Z")))
        assert.equal(1, world.reloads)
        assert.same({}, ns.db.global.captures)
    end)

    -- R-8 (WKE-616): the button's hover says which of those two the press will
    -- be. Proven red by returning `REFRESH_TOOLTIP` unconditionally: the
    -- waiting case reads `rate what you wear now` over a rating that is already
    -- being made.
    it("says which of the two the next press is, and writes nothing while it looks", function()
        assert.equal(ns.Drift.REFRESH_TOOLTIP, ns.Drift.RefreshTooltip())
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        ns.db.global.drift.refreshStartedAt = "2026-09-14T23:10:00Z"
        local at = ns.EpochFromISO("2026-09-14T23:10:30Z")
        assert.equal(ns.Drift.REFRESH_TOOLTIP_WAIT, ns.Drift.RefreshTooltip(at))
        -- a hover is not an act: the wait it just read is still there
        assert.equal("2026-09-14T23:10:00Z", ns.db.global.drift.refreshStartedAt)
        world.inCombat = true
        assert.equal(ns.Drift.REFRESH_TOOLTIP_COMBAT, ns.Drift.RefreshTooltip(at))
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

-- ---------------------------------------------------------------------------
-- R-7c (WKE-594): the sixth thing a load can say, and the one that is not about
-- a refresh.
--
-- A real logout never reads the gear. Four were measured - 2026-09-15 19:19 and
-- 22:11:52, 2026-09-16 14:00:11 and 14:25:58 - and all four answered the
-- equipment scan with nothing; on the last of them the count taken one event
-- earlier, at `PLAYER_LEAVING_WORLD`, was 0 as well, so no ordering of the two
-- events would help. R-7b refuses that read rather than storing it, and records
-- the refusal on the `env` snapshot of the same flush. This is what the player
-- is told because of it.
--
-- Everything below is hand-built rather than replayed: no committed pull has an
-- `env` snapshot with `flushRefusals` on it beside an older `inventory` read in
-- a shape a Lua spec can move the clock over. The shape itself is not invented -
-- it is read off the owner's 14:25:59 pull,
-- `spec/fixtures/captures/Lootpath-20260916-142559.lua`, the `env` list's newest
-- entry, and the refusal string is the addon's own.
describe("ns.Drift and a logout that could not read the gear (R-7c)", function()
    local ns, world
    local NOW = "2026-09-16T14:40:00Z"
    -- His own two stamps: the flush at the 14:25:58 logout, and the newest read
    -- that worked, twenty-five minutes before it.
    local FLUSH = "2026-09-16T14:25:59Z"
    local LAST_GOOD_READ = "2026-09-16T14:00:11Z"
    -- R-7d (WKE-621): and the third stamp, which is the only one the words are
    -- about - when THIS character's rating was written. Four hours before NOW,
    -- so no arithmetic over the other two could produce it by accident.
    local RATED = "2026-09-16T10:40:00Z"

    before_each(function()
        ns, world = loadToday()
    end)

    after_each(function()
        H.unload()
    end)

    local function at(iso)
        return ns.EpochFromISO(iso)
    end

    -- The refusal the addon writes, built out of `ns.INVENTORY_EMPTY_REASON` and
    -- `ns.RunCapture`'s own wrapper, so the spec cannot drift from the string a
    -- real refusal produces.
    local function refusal()
        return {
            capture = "inventory",
            reason = "capture 'inventory' read nothing worth storing: " .. ns.INVENTORY_EMPTY_REASON,
        }
    end

    local function stored(options)
        local opts = options or {}
        ns.db.global.captures.env = {
            {
                name = "env",
                trigger = opts.trigger or "flush",
                capturedAt = at(FLUSH),
                capturedAtLocal = "2026-09-16T14:25:59",
                flushRefusals = opts.refusals,
                data = {},
            },
        }
        ns.db.global.captures.inventory = {
            {
                name = "inventory",
                trigger = "refresh",
                capturedAt = at(opts.inventoryAt or LAST_GOOD_READ),
                capturedAtLocal = "2026-09-16T14:00:11",
                data = {},
            },
        }
    end

    -- A rating stored on THIS character, which is what `db.char.qeImports` is
    -- and what `ns.UI.ActiveVerdict` reads. `db.global.captures` above is the
    -- ACCOUNT's; the two being different scopes is the whole of R-7d.
    local function rated(iso)
        ns.db.char.qeImports = {
            Dungeon = {
                spec = "Restoration Druid",
                exportedAt = iso,
                companionWrittenAt = iso,
                items = {},
                scenario = ns.QEImport.DEFAULT_SCENARIO,
            },
        }
    end

    local function said(line)
        assert.is_truthy(tostring(world.output()):find(ns.PREFIX .. line, 1, true))
    end

    -- R-8 (WKE-616): the chat frame has no button on it, so the line said once
    -- at the login keeps a tail - and it names the button FIRST, because the
    -- window is where the reader is about to go.
    it("says how old this character's rating is, and what fixes it", function()
        stored({ refusals = { refusal() } })
        rated(RATED)
        assert.equal("gearunread", ns.Drift.Decide(at(NOW)))
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal(
            "your gear wasn't read at logout - last rated 4 hours ago \194\183 "
                .. "Refresh in the window, or /lootpath refresh",
            line
        )
        said(line)
    end)

    -- The strip and the chat line are one decision, which is what `Drift.Decide`
    -- is for, and one fact: the same age, read once.
    --
    -- **R-8 (WKE-616): and two endings.** The strip's clause STOPS at the age,
    -- because the Refresh button is on the strip's own row a hand's width to the
    -- right; spelling out a command beside the button that runs it is asking the
    -- reader to type what he could press. The owner, reading his own strip on
    -- 2026-09-18: "we should just make this a button that will run that command
    -- for the user when they click it."
    it("puts the same fact on the status strip, with no command written out", function()
        stored({ refusals = { refusal() } })
        rated(RATED)
        local model = ns.UI.StatusStripModel(at(NOW))
        assert.equal(ns.Drift.GearUnreadText(at(NOW)), model.gearClause)
        assert.equal(model.gearClause, model.text)
        assert.equal("your gear wasn't read at logout - last rated 4 hours ago", model.gearClause)
        assert.is_nil(model.gearClause:find("/lootpath", 1, true))
        -- one age, read once, so the two surfaces cannot disagree about it
        assert.is_truthy(ns.Drift.GearUnreadChatText(at(NOW)):find(model.gearClause, 1, true))
        -- and the facts it displaced are at the top of the tooltip, not lost
        assert.is_truthy(model.tooltip[1])
    end)

    -- **R-7d (WKE-621): the finding itself.** `db.global.captures` is
    -- account-wide, so the newest `inventory` snapshot belongs to whichever
    -- character read last - on 2026-09-18 the owner's Restoration Shaman,
    -- whose gear has never been rated, put `last rated 73 seconds ago` on its
    -- own strip and `last rated 75 seconds ago` on the Druid's. A read is not a
    -- rating. Here the account's newest read is 40 minutes old and this
    -- character's rating is four hours old, and the sentence says four hours.
    it("takes the age from this character's rating, not from the newest read on the account", function()
        stored({ refusals = { refusal() } })
        rated(RATED)
        local clause = ns.Drift.GearUnreadText(at(NOW))
        assert.equal("your gear wasn't read at logout - last rated 4 hours ago", clause)
        assert.is_nil(clause:find("40 minutes", 1, true))
        assert.is_nil(ns.Drift.GearUnreadChatText(at(NOW)):find("40 minutes", 1, true))
    end)

    -- The other half of the same finding: a read by somebody else does not move
    -- this character's age. The snapshot moves twenty-five minutes closer to
    -- the flush - still older than it, so the gate is untouched - and the
    -- sentence does not change by a second.
    it("does not move when a newer read lands on the account", function()
        stored({ refusals = { refusal() } })
        rated(RATED)
        local before = ns.Drift.GearUnreadText(at(NOW))
        stored({ refusals = { refusal() }, inventoryAt = "2026-09-16T14:25:00Z" })
        assert.equal(before, ns.Drift.GearUnreadText(at(NOW)))
        assert.equal("your gear wasn't read at logout - last rated 4 hours ago", before)
    end)

    -- The Shaman's own case: the gear was not read at the logout, and nothing
    -- on this character has ever been rated. The fact is still worth saying and
    -- there is no age to say it with, so the clause stops - `last rated` with
    -- nothing rated is a number about somebody else. The chat line keeps its
    -- tail, because the way out of this is the same either way.
    it("carries no age when this character has nothing rated", function()
        stored({ refusals = { refusal() } })
        assert.is_nil(ns.UI.ActiveVerdict())
        assert.equal("gearunread", ns.Drift.Decide(at(NOW)))
        local clause = ns.Drift.GearUnreadText(at(NOW))
        assert.equal("your gear wasn't read at logout", clause)
        assert.is_nil(clause:find("last rated", 1, true))
        assert.equal(clause, ns.UI.StatusStripModel(at(NOW)).gearClause)
        local line = ns.Drift.LoadLine(at(NOW))
        assert.equal("your gear wasn't read at logout \194\183 Refresh in the window, or /lootpath refresh", line)
        assert.is_nil(line:find("last rated", 1, true))
        said(line)
    end)

    -- The negative that matters most: a `/reload` flush reads the gear fine -
    -- `equipped 15` in 14-30 ms on every one measured - so it refuses nothing
    -- and this must say nothing at all.
    it("says nothing about a flush that read the gear", function()
        stored({ refusals = nil })
        assert.is_nil(ns.Drift.GearUnreadText(at(NOW)))
        assert.is_nil(ns.Drift.Decide(at(NOW)))
        assert.is_nil(ns.Drift.LoadLine(at(NOW)))
        assert.is_nil(ns.UI.StatusStripModel(at(NOW)).gearClause)
    end)

    -- And the cure is the read itself: a refresh or a reload stores an
    -- `inventory` snapshot newer than the refusal, and the sentence stops being
    -- said without anything clearing a flag.
    it("stops the moment a newer read exists", function()
        stored({ refusals = { refusal() }, inventoryAt = "2026-09-16T14:30:00Z" })
        assert.is_nil(ns.Drift.GearUnreadText(at(NOW)))
        assert.is_nil(ns.Drift.LoadLine(at(NOW)))
    end)

    -- A refusal of something else is not this. The flush captures `env`,
    -- `inventory` and `currencies`, and only one of the three is the gear.
    it("says nothing when the flush refused some other capture", function()
        stored({ refusals = { { capture = "currencies", reason = "errored: something" } } })
        assert.is_nil(ns.Drift.GearUnreadText(at(NOW)))
    end)

    -- The label has to be the flush's. A `command` or `refresh` snapshot cannot
    -- carry `flushRefusals` at all, and a reader that trusted the field alone
    -- would believe one that did.
    it("says nothing when the newest env snapshot is not a flush", function()
        stored({ refusals = { refusal() }, trigger = "refresh" })
        assert.is_nil(ns.Drift.GearUnreadText(at(NOW)))
    end)

    -- The player who has just clicked refresh asked a question, and the answer
    -- to THAT is what the load owes him; this waits behind every refresh state.
    it("never displaces the answer to a refresh the player asked for", function()
        stored({ refusals = { refusal() } })
        ns.companionStatus = { state = "running", startedAt = "2026-09-16T14:39:05Z" }
        ns.db.global.drift.refreshStartedAt = "2026-09-16T14:39:00Z"
        assert.equal("waiting", ns.Drift.Decide(at(NOW)))
        assert.equal(
            "your gear is sent; the rating usually takes about a minute. The window says when it's ready.",
            ns.Drift.LoadLine(at(NOW))
        )
    end)
end)

-- ---------------------------------------------------------------------------
-- R-7c (WKE-594): the promise itself, retired.
--
-- R-7 (WKE-579) said "log out and your plan is current next login" and the
-- addon's own words were written to it. A logout never captures gear, so no
-- player-facing string may say or imply that it does. The one string that is
-- allowed to mention a logout at all is the retirement - it says the logout
-- could NOT read the gear - so the guard is the promise's shape rather than the
-- word: a sentence that puts a logout together with capturing, or with the plan
-- being current, is the thing that is gone.
describe("no player-facing string promises that a logout captures gear (R-7c)", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function promises(text)
        local lower = tostring(text):lower()
        if not (lower:find("logout", 1, true) or lower:find("log out", 1, true)) then
            return false
        end
        return lower:find("captur", 1, true) ~= nil or lower:find("current", 1, true) ~= nil
    end

    local function walk(where, value, offences, seen)
        if type(value) == "string" then
            if promises(value) then
                offences[#offences + 1] = where .. ": " .. value
            end
            return
        end
        if type(value) ~= "table" or seen[value] then
            return
        end
        seen[value] = true
        for key, child in pairs(value) do
            walk(where .. "." .. tostring(key), child, offences, seen)
        end
    end

    it("says nothing of the kind in Drift's words, the companion's, or the slash help", function()
        local offences, seen = {}, {}
        walk("Drift", ns.Drift, offences, seen)
        walk("Companion", ns.Companion, offences, seen)
        ns.HandleSlash("help")
        ns.HandleSlash("status")
        for line in tostring(world.output()):gmatch("[^\n]+") do
            walk("chat", line, offences, seen)
        end
        assert.equal("", table.concat(offences, "\n"))
    end)
end)

-- ---------------------------------------------------------------------------
-- C-14 (WKE-603): the nudge's `54 items`, and what the owner actually did.
--
-- At 16:30 on 2026-09-16 his nudge row read `your gear changed since this plan
-- (54 items)`. He had taken one piece off. Everything below is his own
-- SavedVariables, `spec/fixtures/captures/Lootpath-20260916-162655.lua`, copied
-- out of the game folder unchanged: its inventory list is four reads, of which
-- 15:29:53 has 15 equipped and 16:26:34 - the reload flush behind that screen -
-- has 14, with inventory slot 7, legs, gone into a bag.
local LEGS_OFF = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
-- Their indexes in that file's `inventory` list, in the order they were taken.
local DRESSED_SNAPSHOT = 3 -- 2026-09-16T15:29:53, 15 equipped
local LEGS_OFF_SNAPSHOT = 4 -- 2026-09-16T16:26:34, 14 equipped

describe("ns.Drift over the owner's 2026-09-16 legs-off read (C-14)", function()
    local ns, world

    local function count(set)
        local n = 0
        for _ in pairs(set) do
            n = n + 1
        end
        return n
    end

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", DRESSED_SNAPSHOT, LEGS_OFF))
        ns.Drift.Rebase()
    end)

    after_each(function()
        H.unload()
    end)

    -- The two reads are the file's own; the stamps are asserted so a later pull
    -- landing in this directory cannot quietly move what is being compared.
    it("is the 15:29:53 and 16:26:34 reads, 15 equipped and 14", function()
        assert.equal("2026-09-16T15:29:53", R.snapshot("inventory", DRESSED_SNAPSHOT, LEGS_OFF).capturedAtLocal)
        assert.equal("2026-09-16T16:26:34", R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF).capturedAtLocal)
        assert.equal(15, count(ns.Drift.Read().slots))
        R.inventory(world, R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF))
        assert.equal(14, count(ns.Drift.Read().slots))
    end)

    -- **WHAT THE 54 WERE.** Every gear key he owned that minute - what he wore
    -- and what his five bags held - counted as if all of it had just arrived.
    -- That is what a comparison against an EMPTY baseline counts, and it is the
    -- number that was on his screen.
    it("reproduces the 54: it is his whole key set against an empty baseline", function()
        R.inventory(world, R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF))
        local keys = ns.Drift.Now()
        assert.equal(54, count(keys))
        local against = ns.Drift.Compare({}, keys)
        assert.equal(54, against.count)
    end)

    -- And what the two reads really differ by: nothing appeared, nothing went,
    -- one worn slot went bare.
    it("says (1 slot), because one slot is what changed", function()
        R.inventory(world, R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF))
        local behind = ns.Drift.Check()
        assert.is_table(behind)
        assert.equal(0, behind.pieces)
        assert.equal(1, behind.slots)
        assert.equal(1, behind.count)
        assert.equal("your gear changed since this rating (1 slot) \194\183 click to refresh", ns.Drift.Model().text)
    end)

    -- A slot and a loose piece are different things and are said as different
    -- things. The piece is his own Lightgrasp Worldroot, which these bags really
    -- do carry at 16:26:34 - the companion's own pool line of 21:26:46Z names it
    -- among the cards it had not asked about yet - leaving them.
    it("says both when both moved", function()
        R.inventory(world, R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF))
        assert.is_string(outOfBags(world, 251935), "his bags carry the Worldroot at 16:26:34")
        local behind = ns.Drift.Check()
        assert.equal(1, behind.slots)
        assert.equal(1, behind.pieces)
        assert.equal(
            "your gear changed since this rating (1 slot and 1 item) \194\183 click to refresh",
            ns.Drift.Model().text
        )
    end)

    -- **A read that is wearing nothing is not a baseline.** This is how the
    -- empty one gets taken in the first place: a scan that ran before the client
    -- would answer about gear, the same silence R-7b and R-7c measured at the
    -- other end of a session. Nothing is stored, so the next check takes another
    -- one, and `54 items` can never be reported again.
    it("refuses an empty read as a baseline rather than counting everything against it", function()
        ns.Drift.Reset()
        world.equipped = {}
        world.bags = {}
        assert.is_nil(ns.Drift.Rebase())
        assert.is_nil(ns.Drift.Behind())
        -- the client answers again, and the FIRST good read becomes the baseline
        R.inventory(world, R.snapshot("inventory", LEGS_OFF_SNAPSHOT, LEGS_OFF))
        assert.is_nil(ns.Drift.Check())
        assert.equal(54, count(ns.Drift.Now()))
        assert.is_nil(ns.Drift.Behind())
    end)

    -- The same silence from the other side: a good baseline, then a scan that
    -- answers nothing, must not read as "everything went".
    it("never counts a scan that answers nothing as fifty-four pieces leaving", function()
        world.equipped = {}
        world.bags = {}
        assert.is_nil(ns.Drift.Check())
        assert.is_nil(ns.Drift.Behind())
    end)
end)
