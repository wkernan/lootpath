-- Lootpath/Modules/Drift.lua (R-6, WKE-578)
-- Has the gear moved past the plan, and what does the player do about it?
--
-- The two-reload floor stays (decision 2026-09-07, docs/ARCHITECTURE.md §7:
-- SavedVariables reach disk only on a reload or a logout, and an addon file is
-- read only at load). What this module changes is that the player never has to
-- know that. On 2026-09-14 the owner claimed his vault reward and crested it,
-- and nothing on screen said the plan was behind his bags until he hovered the
-- item and read `new since the last refresh`. So:
--
--   1. THE NUDGE. A gear item appeared, went, or changed key since the plan was
--      written -> one clause on the status strip, a dot on the minimap button,
--      and a click that runs exactly what `/lootpath refresh` runs.
--   2. THE WAIT. After that first reload, the strip says the rating is being
--      made and roughly how long it takes, counting; the click is a plain
--      `ReloadUI` that loads what the companion wrote.
--
-- Nothing here computes a healer value, and nothing here decides anything about
-- gear: it compares two key sets and formats three sentences.
--
-- Client rules: every read is `ns.Inventory.Scan`'s, which is already guarded
-- item by item through `ns.Safe`; nothing runs in combat (a check that lands in
-- combat is deferred to `PLAYER_REGEN_ENABLED`); `ReloadUI` is called only from
-- a click, which is a hardware event, and never from a timer.

local _, ns = ...

ns.Drift = {}
local Drift = ns.Drift

-- The events that can move gear past the plan. Each name is Blizzard's, checked
-- in the exported documentation under `.luals/` on 2026-09-14
-- (ContainerDocumentation, PaperDollInfoDocumentation, WeeklyRewardsDocumentation,
-- ItemUpgradeDocumentation), the way `ns.RoadsCache` names the four it listens
-- to rather than discovering them.
Drift.EVENTS = {
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "WEEKLY_REWARDS_UPDATE",
    "ITEM_UPGRADE_MASTER_UPDATE",
}

-- A burst of those events - a bag sort fires BAG_UPDATE_DELAYED once per bag,
-- and cresting an item fires two of them - is answered by one scan.
Drift.DEBOUNCE_SECONDS = 0.5

-- How long the wait line is allowed to stand before it gives up and hands the
-- strip back to C-9's companion clause. NOT a measured figure and deliberately
-- generous: the point is only that a companion which never answers - a watcher
-- the owner forgot to restart, the case docs/ARCHITECTURE.md §11 records from
-- 2026-09-09 - cannot leave `rating your gear` on the strip for the rest of the
-- session. C-9's clause is the honest thing to show then, because it says
-- outright that nothing has run.
Drift.WAIT_GIVE_UP_SECONDS = 600

-- The words, all of them, in one place, because the strip, the minimap tooltip
-- and the chat line must not be able to disagree.
Drift.NUDGE_LINE = "your gear changed since this plan (%s) \194\183 click to refresh"
Drift.NUDGE_TOOLTIP = "The newest is %s. Clicking captures your gear and reloads; "
    .. "the rating is made while you play."
Drift.NUDGE_TOOLTIP_UNNAMED = "Clicking captures your gear and reloads; the rating is made while you play."
Drift.WAIT_LINE = "rating your gear, %s \194\183 click to load it"
Drift.WAIT_READY_DEFAULT = "usually about a minute"
Drift.WAIT_READY_MEASURED = "usually ready in about %s"
Drift.WAIT_TOOLTIP = "The rating is being made now. Clicking reloads and loads whatever has been written; "
    .. "too early and this line comes back."

-- Session state. `baseline` is the key set the plan was written over; `stamp` is
-- which plan that was, so a fresh import rebases instead of reading as drift.
local state = {
    baseline = nil,
    stamp = nil,
    behind = nil,
    pending = false,
    deferred = false,
    listener = nil,
}

-- ---------------------------------------------------------------------------
-- The key set.

-- What the player can put on RIGHT NOW: equipped and bags, never the bank.
--
-- `ns.Inventory.Scan` reads the bank too, whenever the bank frame is open (the
-- 2026-09-05 transcript: `C_Bank.CanViewBank` tracks the frame exactly). Opening
-- the bank would then add every stored piece to the set at once and the nudge
-- would fire on a window being opened, which is not gear moving. The plan is
-- about what is on the character and in the bags; that is what is compared.
Drift.LOCATIONS = { equipped = true, bag = true }

-- records -> { [key] = name or true }. Only gear reaches this at all: an
-- `ns.Inventory` record exists only for an itemEquipLoc QE Live has a slot name
-- for, so a potion stack, a Hearthstone, a crest token and a bag never produce
-- one and can never move this set.
function Drift.KeySet(records)
    local set = {}
    for _, record in ipairs(records or {}) do
        if record.key and Drift.LOCATIONS[record.location] then
            set[record.key] = record.name or true
        end
    end
    return set
end

-- The key set as it is now, or nil when the client will not answer (combat).
function Drift.Now()
    if not (ns.Inventory and ns.Inventory.Scan) then
        return nil
    end
    local scan = ns.Inventory.Scan()
    if not (scan and scan.ok) then
        return nil
    end
    return Drift.KeySet(scan.records)
end

-- Which plan the baseline belongs to. The companion's own `writtenAt` when the
-- plan came from the companion, and the export's stamp otherwise, so a pasted
-- plan rebases as surely as a written one.
function Drift.PlanStamp()
    local verdict = ns.UI and ns.UI.ActiveVerdict and (ns.UI.ActiveVerdict())
    if type(verdict) ~= "table" then
        return nil
    end
    return verdict.companionWrittenAt or verdict.exportedAt or nil
end

-- Take the gear as it is now as the plan's own. Called at load, whenever a new
-- plan arrives, and after a refresh has been asked for.
function Drift.Rebase(keys)
    state.baseline = keys or Drift.Now()
    state.stamp = Drift.PlanStamp()
    state.behind = nil
    return state.baseline
end

-- ---------------------------------------------------------------------------
-- The comparison.

-- Counts the keys that appeared and the keys that went, and names the newest
-- arrival. A key that is in both sets is an item the plan already knew - the
-- same item at the same upgrade level - however it moved between the bags and
-- the character, so equipping something the plan already rated is not drift.
function Drift.Compare(baseline, current)
    if type(baseline) ~= "table" or type(current) ~= "table" then
        return nil
    end
    local count, newest = 0, nil
    for key, name in pairs(current) do
        if baseline[key] == nil then
            count = count + 1
            if type(name) == "string" then
                newest = name
            end
        end
    end
    for key in pairs(baseline) do
        if current[key] == nil then
            count = count + 1
        end
    end
    if count == 0 then
        return nil
    end
    return { count = count, name = newest }
end

-- Rescan and re-answer. Returns what `Behind` will now say. Silent in combat:
-- the previous answer stands, which is the last thing that was true, and
-- `PLAYER_REGEN_ENABLED` runs the check that was refused.
function Drift.Check()
    if InCombatLockdown and InCombatLockdown() then
        state.deferred = true
        return state.behind
    end
    local stamp = Drift.PlanStamp()
    local current = Drift.Now()
    if current == nil then
        return state.behind
    end
    if state.baseline == nil or stamp ~= state.stamp then
        Drift.Rebase(current)
        return nil
    end
    state.behind = Drift.Compare(state.baseline, current)
    if ns.UI and ns.UI.RefreshStrip then
        ns.UI.RefreshStrip()
    end
    if ns.UI and ns.UI.RefreshMinimapDot then
        ns.UI.RefreshMinimapDot()
    end
    return state.behind
end

-- `{ count, name }` while the gear has moved past the plan, nil otherwise.
function Drift.Behind()
    return state.behind
end

-- Test seam, the way ns.RoadsCache.SetMap is one: the answer, set directly, so
-- a spec about the WIDGETS does not have to drive a bag scan to get a line onto
-- the strip. Nothing in the addon calls it.
function Drift.SetBehind(behind)
    state.behind = behind
    return behind
end

function Drift.Reset()
    state.baseline = nil
    state.stamp = nil
    state.behind = nil
    state.pending = false
    state.deferred = false
end

-- ---------------------------------------------------------------------------
-- The wait, and what the last run measured.

-- Where the two remembered facts live. `refreshStartedAt` is written just
-- before the first reload, so it survives it; `runSeconds` is how long the last
-- finished run took, which is the only measurement the wait line is allowed to
-- quote.
local function store()
    if not (ns.db and ns.db.global) then
        return nil
    end
    ns.db.global.drift = ns.db.global.drift or {}
    return ns.db.global.drift
end

-- The seconds between the last finished run's own two stamps, or nil. Recorded
-- at load rather than read at the moment the wait line is drawn, because by
-- then the status file says `running` and carries no `finishedAt` at all: the
-- measurement the line quotes is always the PREVIOUS run's.
function Drift.RecordRun(raw, now)
    local db = store()
    if not db then
        return nil
    end
    local status = ns.Companion.Status(raw == nil and ns.companionStatus or raw)
    if not (status.ok and status.state == "idle" and status.startedAt and status.finishedAt) then
        return db.runSeconds
    end
    local from = ns.EpochFromISO(status.startedAt, now)
    local to = ns.EpochFromISO(status.finishedAt, now)
    if not (from and to) or to <= from then
        return db.runSeconds
    end
    db.runSeconds = to - from
    return db.runSeconds
end

-- "about 45 seconds", "about 1 minute", "about 1 minute 15 seconds" - the last
-- measured run rounded to the nearest 15 seconds, because a figure read to the
-- second would claim a precision one sample does not have. With nothing
-- measured the line says `usually about a minute` and nothing more precise.
function Drift.ReadyText(seconds)
    local value = tonumber(seconds)
    if not value or value <= 0 then
        return Drift.WAIT_READY_DEFAULT
    end
    local rounded = math.floor(value / 15 + 0.5) * 15
    if rounded < 15 then
        rounded = 15
    end
    local text
    if rounded < 60 then
        text = ns.UI.Plural(rounded, "second")
    else
        local minutes = math.floor(rounded / 60)
        local remainder = rounded - minutes * 60
        text = ns.UI.Plural(minutes, "minute")
        if remainder > 0 then
            text = text .. " " .. ns.UI.Plural(remainder, "second")
        end
    end
    return string.format(Drift.WAIT_READY_MEASURED, text)
end

-- Called by `ns.Companion.Refresh` immediately before it reloads: the stamp has
-- to be in SavedVariables when the client writes them, which is what the reload
-- is for.
function Drift.RefreshStarting(now)
    local db = store()
    if not db then
        return nil
    end
    -- math.floor for the reason ns.EpochFromISO coerces its fields: `date`'s
    -- declared time parameter is an integer, which a plain number fails.
    db.refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", math.floor(now or time()))
    return db.refreshStartedAt
end

local function clearWait(db)
    if db then
        db.refreshStartedAt = nil
    end
    return nil
end

-- Is a refresh still out there? Returns the ISO stamp the elapsed time counts
-- from, or nil.
--
-- Three things end the wait: a plan written since the refresh started (the
-- point of the whole thing), a run C-9 says FAILED (its own message is the
-- truer one and wins), and `Drift.WAIT_GIVE_UP_SECONDS` of nothing at all.
function Drift.Waiting(now)
    local db = store()
    local startedAt = db and db.refreshStartedAt
    if type(startedAt) ~= "string" then
        return nil
    end
    now = now or time()
    local startedEpoch = ns.EpochFromISO(startedAt, now)
    if not startedEpoch or (now - startedEpoch) > Drift.WAIT_GIVE_UP_SECONDS then
        return clearWait(db)
    end
    local stamp = Drift.PlanStamp()
    local writtenEpoch = stamp and ns.EpochFromISO(stamp, now) or nil
    if writtenEpoch and writtenEpoch >= startedEpoch then
        return clearWait(db)
    end
    local status = ns.Companion.Status(ns.companionStatus)
    if status.ok and status.state == "failed" then
        return clearWait(db)
    end
    -- While a run is genuinely going, the elapsed time is ITS clock rather than
    -- the click's: a player who reloaded too early wants to know how long the
    -- rating has been running, not how long ago he asked.
    if status.ok and status.state == "running" and status.startedAt then
        return status.startedAt
    end
    return startedAt
end

-- ---------------------------------------------------------------------------
-- The one string builder.

-- What the nudge has to say right now, or nil when it has nothing:
-- `{ kind = "wait"|"behind", text, tooltip }`.
--
-- The wait wins over the nudge, because a player who is waiting has already
-- acted and telling him again to click refresh would send him round the loop a
-- second time.
function Drift.Model(now)
    now = now or time()
    local waitingSince = Drift.Waiting(now)
    if waitingSince then
        local db = store()
        local elapsed = ns.UI.AgeText(waitingSince, now)
        local ready = Drift.ReadyText(db and db.runSeconds)
        return {
            kind = "wait",
            text = string.format(Drift.WAIT_LINE, string.format("started %s, %s", elapsed, ready)),
            tooltip = Drift.WAIT_TOOLTIP,
        }
    end
    local behind = Drift.Behind()
    if not behind then
        return nil
    end
    return {
        kind = "behind",
        text = string.format(Drift.NUDGE_LINE, ns.UI.Plural(behind.count, "item")),
        tooltip = behind.name and string.format(Drift.NUDGE_TOOLTIP, behind.name) or Drift.NUDGE_TOOLTIP_UNNAMED,
    }
end

-- The click, for both states. One function, two callers: the strip's clause and
-- the chat command reach `ns.Companion.Refresh`, which is `/lootpath refresh`
-- itself and not a copy of it.
--
-- `ReloadUI` is only ever reached from here, and this is only ever reached from
-- an OnClick, which is the hardware event the client requires.
function Drift.Click(now)
    if Drift.Waiting(now) then
        if type(ReloadUI) == "function" then
            ReloadUI()
            return "reloaded"
        end
        return nil
    end
    ns.Companion.Refresh()
    return "refresh"
end

-- ---------------------------------------------------------------------------
-- Listening.

function Drift.Invalidate()
    if state.pending then
        return false
    end
    state.pending = true
    local function run()
        state.pending = false
        Drift.Check()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(Drift.DEBOUNCE_SECONDS, run)
    else
        run()
    end
    return true
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if state.deferred then
            state.deferred = false
            Drift.Invalidate()
        end
        return
    end
    Drift.Invalidate()
end

function Drift.Listen()
    if state.listener then
        return state.listener
    end
    local frame = CreateFrame("Frame")
    for _, event in ipairs(Drift.EVENTS) do
        frame:RegisterEvent(event)
    end
    -- Not one of the four: it is what runs the check combat refused.
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", onEvent)
    state.listener = frame
    return frame
end

ns.onReady[#ns.onReady + 1] = function()
    -- After `ns.Companion.Startup`, which is registered in Companion.lua and so
    -- runs before this one: the baseline has to be taken against the plan that
    -- was just loaded, and the run's own measurement read out of the status file
    -- while it still carries a finished run.
    Drift.RecordRun()
    Drift.Rebase()
    Drift.Listen()
end
