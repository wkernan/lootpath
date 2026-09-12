-- spec/spike_spec.lua (R-0, WKE-561)
-- The tooltip measurement. Temporary, like the module it covers: both go when
-- R-2 lands the real block.
--
-- The client half is the stub's model of Blizzard's own tooltip data handler,
-- read from the shipped source under `.luals/` rather than remembered; what is
-- proven here is that the counter counts what fired, costs what it says, never
-- reads the item, never runs in combat, and shows the player nothing.
local H = require("spec.helpers.addon")

local LINK = "|cffa335ee|Hitem:251935::::::::90:105::13:2:6652:12838::::::|h[Worldroot Staff]|h|r"

describe("spike (R-0, WKE-561)", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function hover(data, frame)
        return world.showItemTooltip(data or { hyperlink = LINK }, frame)
    end

    describe("the hook", function()
        it("is not installed until the command asks for it", function()
            assert.same({}, world.tooltipPostCalls)
            hover()
            assert.is_nil(ns.Spike.Counters())
        end)

        it("registers exactly one post-call, for the item type, however often it is turned on", function()
            ns.HandleSlash("spike tooltip on")
            ns.HandleSlash("spike tooltip off")
            ns.HandleSlash("spike tooltip on")
            assert.equal(1, #world.tooltipPostCalls[0])
            assert.is_nil(world.tooltipPostCalls[1])
        end)

        it("refuses, and says so, on a client with no tooltip data processor", function()
            _G.TooltipDataProcessor = nil
            ns.HandleSlash("spike tooltip on")
            assert.is_false(ns.Spike.Available())
            assert.truthy(world.output():find("this client has no", 1, true))
            assert.is_nil(ns.Spike.Counters())
        end)
    end)

    describe("counting", function()
        before_each(function()
            ns.HandleSlash("spike tooltip on")
        end)

        it("counts every item tooltip and times each call", function()
            hover()
            hover()
            local run = ns.Spike.Counters()
            assert.equal(2, run.calls)
            assert.equal(2, run.hyperlinks)
            assert.is_true(run.minMs >= 0)
            assert.is_true(run.maxMs >= run.minMs)
            assert.is_true(run.avgMs >= 0)
            assert.equal(run.totalMs / 2, run.avgMs)
        end)

        it("counts which tooltip frame fired", function()
            hover()
            hover(nil, world.newTooltip("ItemRefTooltip"))
            hover(nil, world.newTooltip("ItemRefTooltip"))
            hover(nil, world.newTooltip(nil))
            local run = ns.Spike.Counters()
            assert.equal(1, run.frames.GameTooltip)
            assert.equal(2, run.frames.ItemRefTooltip)
            assert.equal(1, run.frames["<unnamed>"])
        end)

        it("counts a tooltip whose data carries a GUID as a hyperlink read", function()
            world.itemLinksByGUID["Item-69-0-4000000012345678"] = LINK
            hover({ guid = "Item-69-0-4000000012345678" })
            assert.equal(1, ns.Spike.Counters().hyperlinks)
        end)

        it("counts a tooltip with no hyperlink separately", function()
            hover({})
            local run = ns.Spike.Counters()
            assert.equal(1, run.calls)
            assert.equal(1, run.nilHyperlinks)
            assert.equal(0, run.hyperlinks)
        end)

        -- The whole reason the hyperlink passes ns.Safe before anything is
        -- decided about it: a secret value is counted and dropped, never
        -- compared and never stored.
        it("counts a secret hyperlink without keeping it", function()
            hover({ hyperlink = world.markSecret("secret-link") })
            local run = ns.Spike.Counters()
            assert.equal(1, run.secretHyperlinks)
            assert.equal(0, run.hyperlinks)
            assert.equal(0, run.nilHyperlinks)
        end)

        -- The handler is handed whatever Blizzard passed it, and some addon's
        -- own frame may not be a tooltip at all: GetDisplayedItem asks it
        -- IsTooltipType first (TooltipUtil.lua:10) and raises on a frame that
        -- has no such method. That is a count, never an error in the owner's
        -- chat.
        it("counts a read that raised rather than raising itself", function()
            local notATooltip = _G.CreateFrame("Frame")
            world.tooltipPostCalls[0][1](notATooltip, {})
            local run = ns.Spike.Counters()
            assert.equal(1, run.calls)
            assert.equal(1, run.errors)
            assert.equal(1, run.frames["<unnamed>"])
        end)

        it("returns at once in combat, and counts that it did", function()
            world.inCombat = true
            hover()
            hover()
            local run = ns.Spike.Counters()
            assert.equal(0, run.calls)
            assert.equal(2, run.combatReturns)
            assert.same({}, run.frames)
        end)

        it("counts nothing once it is off, and the hook stays installed", function()
            hover()
            ns.HandleSlash("spike tooltip off")
            hover()
            hover()
            assert.equal(1, ns.Spike.Counters().calls)
            assert.equal(1, #world.tooltipPostCalls[0])
        end)

        it("starts from zero when it is turned on again", function()
            hover()
            ns.HandleSlash("spike tooltip on")
            assert.equal(0, ns.Spike.Counters().calls)
        end)
    end)

    describe("the report", function()
        it("says so before anything has been counted", function()
            assert.same({ "tooltip spike: not counting yet - /lootpath spike tooltip on" }, ns.Spike.ReportLines())
        end)

        it("prints the counts, and names no engine anywhere", function()
            ns.HandleSlash("spike tooltip on")
            hover()
            hover({})
            hover(nil, world.newTooltip("ItemRefTooltip"))
            ns.HandleSlash("spike tooltip report")
            local out = world.output()
            assert.truthy(out:find("tooltip spike: 3 item tooltips", 1, true))
            assert.truthy(out:find("ms per call", 1, true))
            assert.truthy(out:find("hyperlink 2, nil 1, secret 0, errored 0, in combat and returned 0", 1, true))
            assert.truthy(out:find("frames GameTooltip=2 ItemRefTooltip=1", 1, true))
            assert.is_nil(out:lower():find("qe live"))
            assert.is_nil(out:lower():find("questionably"))
        end)
    end)

    describe("the snapshot", function()
        it("stores what was counted as the spike capture, on report and on off", function()
            ns.HandleSlash("spike tooltip on")
            hover()
            ns.HandleSlash("spike tooltip report")
            ns.HandleSlash("spike tooltip off")
            local stored = ns.db.global.captures.spike
            assert.equal(2, #stored)
            local data = stored[1].data
            assert.equal(1, data.run.calls)
            assert.is_true(data.enabled)
            assert.equal("function", data.api.AddTooltipPostCall)
            assert.equal("function", data.api.GetDisplayedItem)
            assert.equal(0, data.api.itemDataType)
            assert.is_false(stored[2].data.enabled)
            assert.truthy(world.output():find("numbers stored as capture 'spike'", 1, true))
        end)

        it("is a capture like any other, so combat refuses it", function()
            ns.HandleSlash("spike tooltip on")
            world.inCombat = true
            ns.HandleSlash("spike tooltip report")
            assert.is_nil(ns.db.global.captures.spike)
            assert.truthy(world.output():find("numbers not stored: combat", 1, true))
        end)

        it("stores nothing about the item the tooltip was showing", function()
            ns.HandleSlash("spike tooltip on")
            hover()
            ns.HandleSlash("spike tooltip off")
            local serialize = require("spec.helpers.serialize")
            local text = serialize.serialize(ns.db.global.captures.spike[1])
            assert.is_nil(text:find("251935", 1, true))
            assert.is_nil(text:find("Worldroot", 1, true))
        end)
    end)

    describe("the command", function()
        it("lists what it can do for anything it does not know", function()
            ns.HandleSlash("spike")
            assert.truthy(world.output():find("/lootpath spike tooltip on", 1, true))
            ns.HandleSlash("spike tooltip sideways")
            assert.truthy(world.output():find("/lootpath spike tooltip off", 1, true))
        end)

        it("is listed in the help", function()
            ns.HandleSlash("help")
            assert.truthy(world.output():find("/lootpath spike tooltip on|off|report", 1, true))
        end)
    end)
end)
