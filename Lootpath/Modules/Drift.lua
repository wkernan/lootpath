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

-- M3-16b (WKE-583): the chat line at the first load after a refresh. The owner
-- on 2026-09-15, in his own words: "after I do a refresh and the screen loads
-- and I'm back in game, I'm assuming the refresh is done. If that is not the
-- case we should have an indicator letting the player know the refresh is still
-- happening." The reload is the moment he is looking at the chat frame, so the
-- wait says itself there once, out of the same model the strip and the minimap
-- read; the window is where it then counts.
Drift.WAIT_CHAT_LINE = "your gear is sent; the rating %s. The window says when it's ready."
Drift.WAIT_CHAT_DEFAULT = "usually takes about a minute"
Drift.WAIT_CHAT_MEASURED = "usually takes about %s"

-- R-6a (WKE-590): the other four things that load can be, because M3-16b's line
-- was the only one and so a refresh that had nothing to do arrived in silence.
-- The owner on 2026-09-15 reloaded, ran `/lootpath refresh`, landed back in
-- game and saw no chat line at all: C-4's fingerprint had skipped the run in
-- under a second, the wait had nothing to wait for, and the addon said nothing
-- at exactly the moment he had asked it a question. **The first load after a
-- refresh always says one line**, and which line it is is `Drift.Decide`'s
-- single answer, which the strip reads through `Drift.Waiting` as well - so the
-- chat frame and the strip cannot say two different things about one run.
Drift.LOAD_SKIPPED = "your gear hasn't changed since the last rating, so the plan you have is current."
-- R-7b (WKE-591): the other `skipped`, and the opposite news. C-4's skip says
-- the plan is already right; this one says nothing was sent at all, so the plan
-- is only as new as the last read that worked. The two are told apart by the
-- exit code the companion writes (`ns.Companion.EXIT_EMPTY_GEAR`), never by its
-- message.
Drift.LOAD_SKIPPED_EMPTY = "your gear didn't reach the companion - the last read of it was empty - so the "
    .. "plan you have is untouched. Try /lootpath refresh."
-- R-7c (WKE-594): the sixth thing a load can say, and the only one of the six
-- that is not about a refresh at all. A real logout never reads the gear - four
-- measured, four empty (`ns.Companion.GearUnreadAtFlush`) - so R-7's "log out
-- and your plan is current next login" is retired, and this is where it is
-- retired in the player's own words instead of in a comment. The age is the
-- newest stored read's, because that read is what the plan on screen is about.
Drift.LOAD_GEAR_UNREAD = "your gear wasn't read at logout - last rated %s "
    .. "\194\183 /lootpath refresh to rate what you wear now"
Drift.LOAD_DONE = "rated just now; the plan is current."
Drift.LOAD_FAILED = "the rating failed%s; see companion.log."
Drift.LOAD_UNSEEN = "the companion hasn't been seen; is it running?"

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

-- "45 seconds", "1 minute", "1 minute 15 seconds" - the last measured run
-- rounded to the nearest 15 seconds, because a figure read to the second would
-- claim a precision one sample does not have. nil when nothing has been
-- measured, which is what makes the two lines below say `about a minute` and
-- nothing more precise.
function Drift.RunText(seconds)
    local value = tonumber(seconds)
    if not value or value <= 0 then
        return nil
    end
    local rounded = math.floor(value / 15 + 0.5) * 15
    if rounded < 15 then
        rounded = 15
    end
    if rounded < 60 then
        return ns.UI.Plural(rounded, "second")
    end
    local minutes = math.floor(rounded / 60)
    local remainder = rounded - minutes * 60
    local text = ns.UI.Plural(minutes, "minute")
    if remainder > 0 then
        text = text .. " " .. ns.UI.Plural(remainder, "second")
    end
    return text
end

-- The strip's half of that figure: `usually ready in about 3 minutes`.
function Drift.ReadyText(seconds)
    local text = Drift.RunText(seconds)
    if not text then
        return Drift.WAIT_READY_DEFAULT
    end
    return string.format(Drift.WAIT_READY_MEASURED, text)
end

-- The chat line's half of it: `usually takes about 3 minutes`, which is the
-- owner's own phrasing and reads as a sentence where the strip's does not.
function Drift.ChatReadyText(seconds)
    local text = Drift.RunText(seconds)
    if not text then
        return Drift.WAIT_CHAT_DEFAULT
    end
    return string.format(Drift.WAIT_CHAT_MEASURED, text)
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

-- The ONE decision about the refresh that is out there, which both the chat
-- line (`Drift.LoadLine`) and the strip (`Drift.Waiting`, through
-- `Drift.Model`) read. R-6a (WKE-590): before it there were two readings of the
-- status file - the strip's C-9 clause and the wait's - and a run C-4 skipped
-- fell between them, so the strip said `profile unchanged, no run` while the
-- chat frame said nothing at all.
--
-- Returns `state, status, since`:
--
--   nil        no refresh out there, or one older than `WAIT_GIVE_UP_SECONDS`
--   "done"     a plan written since the refresh started - the point of it all
--   "failed"   C-9 says the run died; its own message is the truer one and wins
--   "skipped"  C-4's fingerprint matched, so there was nothing to rate
--   "unseen"   no status file at all: nothing has ever run
--   "waiting"  the rating is being made; `since` is the clock to count from
--
-- Every state but "waiting" ENDS the wait, which is what keeps the two surfaces
-- together: the strip stops saying `rating your gear` in exactly the cases the
-- chat line answers with something else.
--
-- No side effects: the caller clears. `Drift.LoadLine` runs before anything can
-- have cleared the stamp out from under it (see `ns.onReady` at the foot of
-- this file), and the strip clears from then on.
local function refreshDecision(now)
    local db = store()
    local startedAt = db and db.refreshStartedAt
    if type(startedAt) ~= "string" then
        return nil
    end
    local startedEpoch = ns.EpochFromISO(startedAt, now)
    if not startedEpoch or (now - startedEpoch) > Drift.WAIT_GIVE_UP_SECONDS then
        return nil
    end
    local stamp = Drift.PlanStamp()
    local writtenEpoch = stamp and ns.EpochFromISO(stamp, now) or nil
    if writtenEpoch and writtenEpoch >= startedEpoch then
        return "done"
    end
    local status = ns.Companion.Status(ns.companionStatus)
    if status.absent then
        return "unseen", status
    end
    if status.ok and status.state == "failed" then
        return "failed", status
    end
    if status.ok and status.state == "skipped" then
        return "skipped", status
    end
    -- While a run is genuinely going, the elapsed time is ITS clock rather than
    -- the click's: a player who reloaded too early wants to know how long the
    -- rating has been running, not how long ago he asked.
    if status.ok and status.state == "running" and status.startedAt then
        return "waiting", status, status.startedAt
    end
    -- Everything left - a status file that is there but says nothing this can
    -- read, and an `idle` run older than the click - is a rating still to come.
    return "waiting", status, startedAt
end

-- The sentence R-7c retires the promise with, or nil when there is nothing to
-- retire. Built here rather than in `Decide` so the strip can ask for the words
-- directly: `Decide` names the state and this says it.
function Drift.GearUnreadText(now)
    local inventory = ns.Companion and ns.Companion.GearUnreadAtFlush and ns.Companion.GearUnreadAtFlush()
    if not inventory then
        return nil
    end
    local age = ns.UI.AgeTextFromSeconds((now or time()) - inventory.capturedAt)
    if not age then
        return nil
    end
    return string.format(Drift.LOAD_GEAR_UNREAD, age)
end

function Drift.Decide(now)
    now = now or time()
    local decision, status, since = refreshDecision(now)
    if decision then
        return decision, status, since
    end
    -- R-7c (WKE-594): nothing was asked, and there is still one thing worth
    -- saying - the last unload could not read the gear, so the plan on screen
    -- is older than the player has any reason to think. It is LAST, after every
    -- refresh state, because a player who has just asked a question is owed the
    -- answer to that one first; and it is inside `Decide` so the strip and the
    -- chat line cannot disagree about it either.
    if Drift.GearUnreadText(now) then
        return "gearunread"
    end
    return nil
end

-- Is a refresh still out there? Returns the ISO stamp the elapsed time counts
-- from, or nil, and ends the wait on every decision that is not "waiting".
function Drift.Waiting(now)
    local decision, _, since = Drift.Decide(now)
    if decision == "waiting" then
        return since
    end
    return clearWait(store())
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

-- The chat line at the first load after a refresh (M3-16b, widened by R-6a).
-- **It always says something**, because the load is the moment the player is
-- looking at the chat frame and he has just asked a question: `Drift.Decide`
-- answers it in one sentence whichever of the five the load turns out to be.
-- A load with no refresh out there - a plain `/reload`, an ordinary login -
-- says nothing at all, because nothing was asked.
--
-- Returns the line it printed, or nil.
function Drift.LoadLine(now)
    now = now or time()
    local decision, status = Drift.Decide(now)
    if not decision then
        clearWait(store())
        return nil
    end
    local line
    if decision == "waiting" then
        local db = store()
        line = string.format(Drift.WAIT_CHAT_LINE, Drift.ChatReadyText(db and db.runSeconds))
    elseif decision == "skipped" then
        if status and status.exitCode == ns.Companion.EXIT_EMPTY_GEAR then
            line = Drift.LOAD_SKIPPED_EMPTY
        else
            line = Drift.LOAD_SKIPPED
        end
    elseif decision == "gearunread" then
        -- R-7c (WKE-594). Not a refresh state: said at the login after a logout
        -- that captured no gear, and said again at the next one if that is
        -- still true. A `/reload` or a refresh stores a read newer than the
        -- refusal and it stops being said.
        line = Drift.GearUnreadText(now)
    elseif decision == "done" then
        line = Drift.LOAD_DONE
    elseif decision == "unseen" then
        line = Drift.LOAD_UNSEEN
    else
        -- failed. The stage is C-9's own word for where it died, and the clause
        -- is the strip's own, in chat as well - the two surfaces name one place.
        local where = (status and status.stage) and (" at " .. status.stage) or ""
        line = string.format(Drift.LOAD_FAILED, where)
    end
    -- Said, so a plain `/reload` later says nothing. The wait is the one state
    -- that keeps the stamp: the strip counts from it until the plan arrives,
    -- and a second reload while the rating is still going is still waiting.
    if decision ~= "waiting" then
        clearWait(store())
    end
    ns.Log("%s", line)
    -- R-7b (WKE-591): a second sentence, and only when there is one to say.
    -- The load line answers the question the player asked; this answers the one
    -- he did not know to ask, at the same moment and on the same surface. It is
    -- printed after, not instead: the rating's own news comes first.
    local specClause = ns.Companion.SpecClauseNow()
    if specClause then
        ns.Log("%s", specClause)
    end
    return line
end

ns.onReady[#ns.onReady + 1] = function()
    -- After `ns.Companion.Startup`, which is registered in Companion.lua and so
    -- runs before this one: the baseline has to be taken against the plan that
    -- was just loaded, and the run's own measurement read out of the status file
    -- while it still carries a finished run.
    Drift.RecordRun()
    -- After `Drift.RecordRun`, which is what the wait line's figure comes from,
    -- and BEFORE anything else can read the decision: `Drift.Waiting` clears
    -- the stamp on every state but the wait, so whichever surface looks first
    -- is the one that gets to speak. At this point in the load nothing has -
    -- the only `ns.onReady` ahead of this file's is `Companion.Startup`, and
    -- the window does not exist yet (`ns.UI.Frame` builds it on first open).
    Drift.LoadLine()
    Drift.Rebase()
    Drift.Listen()
end
