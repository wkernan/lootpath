-- spec/enginedevpanel_spec.lua (E-1c, WKE-689)
-- ns.EngineDevPanel: the developer engine's panel. The model over the two
-- compare weeks the owner stored (spec/fixtures/captures/Lootpath-20261009-204729.lua,
-- db.global.engineCompare["2026-09-29"] and ["2026-10-06"]), and the guards
-- the scoped exception asks of it (CLAUDE.md; ARCHITECTURE.md section 7,
-- E-0 and E-1c): it opens only behind the switch, it is built only on the
-- first open, it never sorts by ours and never puts theirs and ours in one
-- string, no other UI file reads it, and in combat it draws the combat line
-- and reads nothing.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local SV = "spec/fixtures/captures/Lootpath-20261009-204729.lua"
local CHAR = "Hotornot - Arthas"

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function stored()
    return R.load(SV).global.engineCompare
end

local function indexOf(list, text)
    for i, line in ipairs(list) do
        if line == text then
            return i
        end
    end
    return nil
end

local function findRow(model, cells)
    for _, row in ipairs(model.rows) do
        local all = true
        for i, want in pairs(cells) do
            if row.cells[i] ~= want then
                all = false
                break
            end
        end
        if all then
            return row
        end
    end
    return nil
end

-- The latest week's compare rows of one block, by the provenance line that
-- heads it.
local function blockOf(model, heading)
    local out, inside = {}, false
    for _, row in ipairs(model.rows) do
        if row.kind == "subsection" or row.kind == "section" then
            inside = row.cells[1]:find(heading, 1, true) == 1
        elseif inside and row.layout == "block" and row.kind == "row" then
            out[#out + 1] = row
        end
    end
    return out
end

describe("EngineDevPanel.Model over the two stored weeks", function()
    local ns, model
    before_each(function()
        ns = H.load()
        model = ns.EngineDevPanel.Model(stored(), nil, { charKey = CHAR })
    end)
    after_each(function()
        H.unload()
    end)

    it("names the character, the weeks and the latest", function()
        assert.equal(2, model.weeks)
        assert.equal("2026-10-06", model.latest)
        assert.equal("Developer engine", model.rows[1].cells[1])
        assert.equal("Hotornot - Arthas · 2 week(s) stored · latest 2026-10-06", model.rows[2].cells[1])
    end)

    it("lists every stored week's metrics per class, then the bar", function()
        local row = findRow(model, { "2026-10-06", "Dungeon", "+6", "6", "armour" })
        assert.same(
            { "2026-10-06", "Dungeon", "+6", "6", "armour", "15", "0.928", "0.973", "0.016", "0.016" },
            row.cells
        )
        row = findRow(model, { "2026-09-29", "Raid", "+10", "raid-3", "jewellery" })
        assert.same(
            { "2026-09-29", "Raid", "+10", "raid-3", "jewellery", "5", "0.564", "0.509", "0.412", "0.241" },
            row.cells
        )
        -- Rho is not computed under five rows: the cell says so.
        row = findRow(model, { "2026-10-06", "Raid", "Top Gear", "raid-3", "tier" })
        assert.equal("-", row.cells[7])
        local lines = ns.EngineDevPanel.Lines(model)
        assert.truthy(
            indexOf(lines, "2026-10-06: tier fail · armour fail · jewellery fail · weapon fail · trinket fail")
        )
        local bar = "bar (printed, not enforced): tier no · armour no · jewellery no · weapon no · trinket no"
        assert.truthy(indexOf(lines, bar))
        assert.equal(ns.EngineCompare.VerdictLine(ns.EngineCompare.Verdicts(stored(), CHAR)), bar)
    end)

    it("heads each latest block with its provenance and band", function()
        local lines = ns.EngineDevPanel.Lines(model)
        assert.truthy(
            indexOf(
                lines,
                "Dungeon +6 - weights fit-to-qe-exports, patch 12.1.0, derived 2026-10-02T02:21:19.971Z, band 6"
            )
        )
        assert.truthy(
            indexOf(
                lines,
                "Raid Top Gear - weights fit-to-qe-exports, patch 12.1.0, derived 2026-10-02T02:21:19.971Z, band raid-3"
            )
        )
        assert.truthy(indexOf(lines, "not rated: 11 (effect not modelled)"))
        assert.truthy(indexOf(lines, "trinket: no row a rule covers yet"))
    end)

    it("shows every stored row once, theirs and ours in two cells, in the stored order", function()
        local entry = stored()["2026-10-06"][CHAR].Dungeon[6]
        local rows = blockOf(model, "Dungeon +6 ")
        assert.equal(#entry.rows, #rows)
        local seen, last = {}, {}
        for _, row in ipairs(rows) do
            local s = entry.rows[row.storedIndex]
            assert.equal(s.key, row.key)
            assert.equal(string.format("%.3f", s.theirs), row.cells[ns.EngineDevPanel.THEIRS_CELL])
            assert.equal(string.format("%.3f", s.ours), row.cells[ns.EngineDevPanel.OURS_CELL])
            assert.is_nil(seen[row.storedIndex])
            seen[row.storedIndex] = true
            -- Inside a class, never reordered: the stored order, not ours.
            if last[row.class] then
                assert.is_true(row.storedIndex > last[row.class])
            end
            last[row.class] = row.storedIndex
        end
        -- And the stored order is not ours: a sort by ours would differ here.
        local tier = {}
        for _, row in ipairs(rows) do
            if row.class == "tier" then
                tier[#tier + 1] = row.ours
            end
        end
        local byOurs = {}
        for i, v in ipairs(tier) do
            byOurs[i] = v
        end
        table.sort(byOurs, function(a, b)
            return a > b
        end)
        assert.are_not.same(byOurs, tier)
    end)

    it("never puts theirs and ours in one string, in any block", function()
        local checked = 0
        for _, row in ipairs(model.rows) do
            if row.kind == "row" and row.layout == "block" then
                local t = string.format("%.3f", row.theirs)
                local o = string.format("%.3f", row.ours)
                assert.are_not.equal(ns.EngineDevPanel.THEIRS_CELL, ns.EngineDevPanel.OURS_CELL)
                if t ~= o then
                    checked = checked + 1
                    for _, cell in ipairs(row.cells) do
                        assert.is_false(
                            cell:find(t, 1, true) ~= nil and cell:find(o, 1, true) ~= nil,
                            "one cell holds both: " .. cell
                        )
                    end
                end
            end
        end
        -- Read from this fixture: rows whose two figures print differently.
        assert.is_true(checked > 40)
    end)

    it("shows the top-set agreement the compare stored", function()
        local lines = ns.EngineDevPanel.Lines(model)
        assert.truthy(
            indexOf(
                lines,
                "top set differs at Waist: ours Primal Dinomancer's Belt 302, theirs Venom-Cursed Lynx's Buckle 302"
                    .. " - ours by +0.165% by our value"
            )
        )
        assert.truthy(
            indexOf(
                lines,
                "top set: agrees on 14 of 15 positions (searched 30 pieces in pass 1's pool; 13 owned outside it,"
                    .. " 0 not ready; band raid-3, 200 set values)."
            )
        )
    end)

    it("asks for a search when none ran this session, and shows the last one when it did", function()
        local lines = ns.EngineDevPanel.Lines(model)
        assert.equal("Run /lootpath engine best to fill this. It is kept until you reload.", lines[#lines])
        local m = ns.EngineDevPanel.Model(stored(), { lines = { "engine best - x", "  Head: y" } }, { charKey = CHAR })
        lines = ns.EngineDevPanel.Lines(m)
        assert.same({ "Last best set this session", "engine best - x", "Head: y" }, {
            lines[#lines - 2],
            lines[#lines - 1],
            lines[#lines],
        })
    end)

    it("says what to do when nothing is stored", function()
        local m = ns.EngineDevPanel.Model({}, nil, { charKey = CHAR })
        assert.same({
            "Developer engine",
            "no compare stored for Hotornot - Arthas.",
            "Run /lootpath engine compare to store a week.",
            "Last best set this session",
            "Run /lootpath engine best to fill this. It is kept until you reload.",
        }, ns.EngineDevPanel.Lines(m))
    end)
end)

describe("/lootpath engine, the panel", function()
    local ns, world
    before_each(function()
        ns, world = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    local function built()
        if ns.EngineDevPanel.frame or _G.LootpathEngineDevPanel then
            return true
        end
        for _, f in ipairs(world.frames) do
            if f.frameName == ns.EngineDevPanel.FRAME_NAME then
                return true
            end
        end
        return false
    end

    it("says `not on` and builds nothing without the switch", function()
        ns.HandleSlash("engine")
        ns.HandleSlash("engine panel")
        assert.equal(ns.PREFIX .. "not on\n" .. ns.PREFIX .. "not on", world.output())
        assert.is_false(ns.EngineDevPanel.Toggle())
        assert.is_false(built())
        assert.is_nil(ns.EngineDevPanel.Refresh())
        assert.is_false(built())
    end)

    it("is built on the first open and not before, then toggles", function()
        ns.db.global.developer = { engine = true }
        world.fireEvent("PLAYER_REGEN_DISABLED")
        world.fireEvent("PLAYER_REGEN_ENABLED")
        ns.EngineCompare.Command("verbose")
        assert.is_false(built())
        ns.HandleSlash("engine")
        assert.is_true(built())
        local frame = ns.EngineDevPanel.frame
        assert.is_true(frame:IsShown())
        assert.equal("Developer engine", frame.lines[1])
        ns.HandleSlash("engine panel")
        assert.is_false(frame:IsShown())
        ns.HandleSlash("engine panel")
        assert.is_true(frame:IsShown())
    end)

    it("draws one font string per cell, the model's strings in order", function()
        ns.db.global.developer = { engine = true }
        ns.db.global.engineCompare = stored()
        ns.db.keys = ns.db.keys or {}
        ns.db.keys.char = CHAR
        ns.HandleSlash("engine")
        local frame = ns.EngineDevPanel.frame
        local drawn = {}
        for _, fs in ipairs(frame.cells) do
            if fs:IsShown() then
                drawn[#drawn + 1] = fs:GetText()
            end
        end
        assert.same(frame.lines, drawn)
        assert.same(ns.EngineDevPanel.Lines(frame.model), drawn)
        assert.truthy(indexOf(drawn, "Top-set agreement"))
    end)

    it("hides when the switch is turned off, and does not reopen without it", function()
        ns.db.global.developer = { engine = true }
        ns.HandleSlash("engine")
        local frame = ns.EngineDevPanel.frame
        assert.is_true(frame:IsShown())
        ns.HandleSlash("engine off")
        assert.is_false(frame:IsShown())
        frame:Show()
        assert.is_nil(ns.EngineDevPanel.Refresh())
        assert.is_false(frame:IsShown())
        ns.HandleSlash("engine")
        assert.is_false(frame:IsShown())
    end)

    it("draws the combat line and reads nothing in combat, then redraws after", function()
        ns.db.global.developer = { engine = true }
        ns.HandleSlash("engine")
        local frame = ns.EngineDevPanel.frame
        local model = ns.EngineDevPanel.Model
        ns.EngineDevPanel.Model = function()
            error("the model was built in combat")
        end
        world.inCombat = true
        world.fireEvent("PLAYER_REGEN_DISABLED")
        assert.same({ ns.EngineDevPanel.COMBAT_LINE }, frame.lines)
        -- Opened in combat, the same.
        ns.HandleSlash("engine")
        ns.HandleSlash("engine")
        assert.same({ ns.EngineDevPanel.COMBAT_LINE }, frame.lines)
        ns.EngineDevPanel.Model = model
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        assert.equal("Developer engine", frame.lines[1])
    end)

    it("keeps the last `best` in memory only, and redraws an open panel with it", function()
        ns.db.global.developer = { engine = true }
        ns.HandleSlash("engine")
        local run = { file = {}, contentType = "Raid", why = "no band for x" }
        ns.EngineSearch.Command = function(_, onDone)
            onDone(run)
        end
        local got
        ns.EngineCompare.Command("best raid", function(r)
            got = r
        end)
        assert.equal(run, got)
        assert.equal(run, ns.EngineCompare.lastBest.run)
        local lines = ns.EngineDevPanel.frame.lines
        assert.equal("engine best found no set: no band for x", lines[#lines - 1])
        for key in pairs(ns.db.global) do
            assert.is_falsy(tostring(key):lower():find("best", 1, true))
        end
        H.unload()
        ns, world = H.load()
        assert.is_nil(ns.EngineCompare.lastBest)
    end)
end)

describe("EngineDevPanel on screen", function()
    it("is read by no other UI file", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") and f ~= "UI/EngineDevPanel.lua" then
                if readAll("Lootpath/" .. f):find("EngineDevPanel", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)

    it("is in the .toc after every engine module", function()
        local files = H.tocFiles()
        local panel, lastEngine
        for i, f in ipairs(files) do
            if f == "UI/EngineDevPanel.lua" then
                panel = i
            elseif f:match("^Modules/Engine") then
                lastEngine = i
            end
        end
        assert.is_number(panel)
        assert.is_true(panel > lastEngine)
    end)
end)
