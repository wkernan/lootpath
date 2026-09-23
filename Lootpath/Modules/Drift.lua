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
    -- H-1 (WKE-596). Not a gear event: it is what takes a standing nudge, the
    -- minimap badge and the bag marks down the moment the player changes spec,
    -- through the one function that already owns all three (`Drift.Check`).
    -- Blizzard's own name, in Ketho's `Core/Data/Event.lua:1175`.
    "PLAYER_SPECIALIZATION_CHANGED",
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
Drift.NUDGE_LINE = "your gear changed since this rating (%s) \194\183 click to refresh"
Drift.NUDGE_TOOLTIP = "The newest is %s. Clicking captures your gear and reloads; "
    .. "the rating is made while you play."
Drift.NUDGE_TOOLTIP_UNNAMED = "Clicking captures your gear and reloads; the rating is made while you play."
-- R-8b (WKE-623): the wait clause names the button. M3-16b wrote `click to load
-- it` when the strip's own row was the only clickable thing on the window; since
-- R-8 the `Refresh` button on that row runs the same `Drift.Click`, and the
-- owner on 2026-09-21 read the old words off his screen and asked the obvious
-- question - "I don't like this copy that just says 'click to load it'... click
-- what?" So the clause points at a thing he can see, and nothing on screen says
-- `click` about a surface that has no edges.
--
-- **R-6c (WKE-629): the clause has two heads and no tail.** The owner walked
-- his own window on 2026-09-23 (WKE-592) and said: "I hit the refresh button
-- and see that the companion run was started, but I have no idea when it is
-- finished unless I'm looking at my other screen ... Other players won't have
-- this set up and will need to know when the refresh has finished." The window
-- cannot know `done` - the client reads the companion's file only at load, and
-- nothing outside the game can push into it - so the one honest thing it can
-- say is that the usual time has passed and it is probably worth clicking. Two
-- heads, one clock: `rating your gear` under the usual time and
-- `your rating is probably ready` past it. The tail comes off both, because
-- since R-8 the button is on that same row and it makes the offer itself - it
-- is dimmed while rating and relabelled `Load rating` past the mark.
Drift.WAIT_LINE = "%s \194\183 started %s, %s"
Drift.WAIT_HEAD_RATING = "rating your gear"
Drift.WAIT_HEAD_READY = "your rating is probably ready"
Drift.WAIT_READY_DEFAULT = "usually about a minute"
Drift.WAIT_READY_MEASURED = "usually ready in about %s"
-- One tooltip per phase, read on the strip's row AND on the button's hover, so
-- the two surfaces cannot say different things about one run. The rating one
-- quotes the same `ReadyText` the clause does, so a measured run does not have
-- the line naming one figure and the hover another. `click` is said here of a
-- button that has edges and is named in the same breath, which is the line R-8b
-- drew: no sentence tells the player to click a surface he cannot see.
Drift.WAIT_TOOLTIP_RATING = "still rating - %s; Refresh loads it when you click"
Drift.WAIT_TOOLTIP_READY = "probably written by now - click Load rating; too early and this line comes back"

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
Drift.LOAD_SKIPPED = "your gear hasn't changed since the last rating, so what you have is current."
-- R-7b (WKE-591): the other `skipped`, and the opposite news. C-4's skip says
-- the plan is already right; this one says nothing was sent at all, so the plan
-- is only as new as the last read that worked. The two are told apart by the
-- exit code the companion writes (`ns.Companion.EXIT_EMPTY_GEAR`), never by its
-- message.
Drift.LOAD_SKIPPED_EMPTY = "your gear didn't reach the companion - the last read of it was empty - so what "
    .. "you have is untouched. Try /lootpath refresh."
-- C-14 (WKE-603): the third `skipped`, and the only one the player can cure in
-- ten seconds. The gear was read and it was read correctly; one slot had
-- nothing in it, and a character with a bare slot is not something the rating
-- will take. Named by its own exit code (`ns.Companion.EXIT_EMPTY_SLOT`), never
-- by reading the message.
Drift.LOAD_SKIPPED_SLOT = "a gear slot was empty when your gear was read, so it couldn't be rated. "
    .. "Put something in that slot and /lootpath refresh."
-- R-7c (WKE-594): the sixth thing a load can say, and the only one of the six
-- that is not about a refresh at all. A real logout never reads the gear - four
-- measured, four empty (`ns.Companion.GearUnreadAtFlush`) - so R-7's "log out
-- and your plan is current next login" is retired, and this is where it is
-- retired in the player's own words instead of in a comment.
--
-- **R-7d (WKE-621): the age is the RATING's, not the read's.** R-7c took it
-- from the newest stored `inventory` snapshot, and `db.global.captures` is
-- account-wide: on 2026-09-18 the owner read `last rated 73 seconds ago` on a
-- Restoration Shaman whose gear has never been rated at all, and `last rated
-- 75 seconds ago` on the Druid whose rating on screen was written the day
-- before - both ages were the Shaman's refresh capture, which is a READ and
-- never a rating. `GearUnreadAtFlush` stays the GATE, because the fact it
-- proves is still true (the last unload could not read the gear); the CLOCK is
-- `Drift.PlanStamp()`, this character's own stored verdict, which is the thing
-- the words claim and the same stamp the tooltip's `Rated ... ago` counts from.
-- With nothing rated on this character there is no age to give, so the clause
-- says the fact and stops: `last rated` with nothing rated is a number about
-- somebody else.
--
-- **R-8 (WKE-616): two endings, one sentence.** The owner read the strip on
-- 2026-09-18 - `... \194\183 /lootpath refresh to rate what you wear now` - and said
-- "we should just make this a button that will run that command for the user
-- when they click it." So the strip's clause STOPS at the age: the Refresh
-- button is on the same row, a hand's width to the right, and a sentence that
-- spells out a command while the button is beside it is asking the reader to
-- type what he could press. The CHAT line keeps a tail, because the chat frame
-- has no button on it: it names the button first and the command second, so a
-- player reading the login line knows where to go either way.
--
-- R-7d (WKE-621): four strings, because there are two surfaces and two cases.
-- The bare pair is what a character with nothing rated gets - the fact, and on
-- the chat line the way out of it.
Drift.STRIP_GEAR_UNREAD_BARE = "your gear wasn't read at logout"
Drift.STRIP_GEAR_UNREAD = Drift.STRIP_GEAR_UNREAD_BARE .. " - last rated %s"
Drift.GEAR_UNREAD_TAIL = " \194\183 Refresh in the window, or /lootpath refresh"
Drift.LOAD_GEAR_UNREAD = Drift.STRIP_GEAR_UNREAD .. Drift.GEAR_UNREAD_TAIL
Drift.LOAD_GEAR_UNREAD_BARE = Drift.STRIP_GEAR_UNREAD_BARE .. Drift.GEAR_UNREAD_TAIL
-- R-8 (WKE-616): the button's own words. It is on the strip's row beside
-- `Import...` and `Options`, it is always there, and its click is `Drift.Click`
-- - the same function the strip's wait and `/lootpath refresh` reach, so a
-- rating that is ready loads and anything else refreshes. The tooltip is one
-- line and it says what THIS press will do, because the two are not the same
-- act: one sends the gear away, the other brings a rating back, and both cost a
-- reload, which is the fact worth warning about before the screen goes dark.
--
-- **R-6c (WKE-629): the label is a function of the wait's phase.** Past the
-- usual time the button stops offering a refresh and offers the load, in the
-- word the strip has just used - `Load rating` - so the reader's next act is
-- named rather than described. Under the mark it keeps saying `Refresh`, dimmed
-- but still clickable, and after the load it is `Refresh` again. The hover per
-- phase is the wait's own pair above, for the reason given there.
Drift.REFRESH_LABEL = "Refresh"
Drift.REFRESH_LABEL_READY = "Load rating"
Drift.REFRESH_TOOLTIP = "rate what you wear now - takes a reload"
-- Combat: the press is refused before it starts. `Companion.Refresh` already
-- says why in chat and `ReloadUI` is blocked there anyway, so the button greys
-- out like the Equip buttons and this is what the hover says instead.
Drift.REFRESH_TOOLTIP_COMBAT = "not in combat - the reload is blocked there"

Drift.LOAD_DONE = "rated just now; you're up to date."
Drift.LOAD_FAILED = "the rating failed%s; see companion.log."
-- C-14b (WKE-627): the one `failed` that is not a breakage, and the only one
-- the player can act on. The gear went over whole and the rating would not take
-- it, because it is leveling gear the rating does not know. Named by the reason
-- token the companion writes (`ns.Companion.UnratedGear`) and never by reading
-- the message, which is the rule the two skips above are told apart by. It is
-- still the `failed` decision: `Drift.Decide`'s six answers are untouched and
-- only the words this one says have changed.
Drift.LOAD_UNRATED_GEAR = "couldn't rate your gear - it's leveling gear the rating doesn't know. "
    .. "Hit max level, gear up, then Refresh."
Drift.LOAD_UNSEEN = "the companion hasn't been seen; is it running?"

-- Session state. `baseline` is the key set the plan was written over; `stamp` is
-- which plan that was, so a fresh import rebases instead of reading as drift.
local state = {
    baseline = nil,
    -- C-14 (WKE-603): the worn half of the same baseline, `{ [slot] = key }`.
    baselineSlots = nil,
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

-- C-14 (WKE-603). What is WORN, slot by slot: `{ [inventory slot] = key }`.
--
-- The key set above deliberately cannot see a piece moving between the bags and
-- the character, which is right for "is there anything here the rating has never
-- seen" and wrong for "is the character still wearing what was rated". The
-- owner took his legs off at 16:26 on 2026-09-16 and put them in a bag: not one
-- key appeared or went, and the rating was about a character who had legs on.
--
-- Keyed by the client's own inventory slot number rather than by the QE Live
-- slot name, because two rings and two trinkets share a name and do not share a
-- slot.
function Drift.SlotSet(records)
    local set = {}
    for _, record in ipairs(records or {}) do
        if record.key and record.location == "equipped" and record.slotIndex then
            set[record.slotIndex] = record.key
        end
    end
    return set
end

-- One scan, read both ways: `{ keys, slots }`, or nil when the client will not
-- answer (combat, or no scanner at all).
function Drift.Read()
    if not (ns.Inventory and ns.Inventory.Scan) then
        return nil
    end
    local scan = ns.Inventory.Scan()
    if not (scan and scan.ok) then
        return nil
    end
    return { keys = Drift.KeySet(scan.records), slots = Drift.SlotSet(scan.records) }
end

-- The key set as it is now, or nil when the client will not answer (combat).
function Drift.Now()
    local read = Drift.Read()
    return read and read.keys or nil
end

-- C-14 (WKE-603). **A read that is wearing nothing is not a baseline.**
--
-- The owner's nudge row said `54 items` on 2026-09-16, and 54 is every gear key
-- he owned that minute - his whole equipped-and-bagged set, counted as if all of
-- it had just arrived (reproduced over his own SavedVariables in
-- `spec/drift_spec.lua`). That is what a comparison against an EMPTY baseline
-- counts, and the baseline is empty when the scan that took it ran before the
-- client would answer about gear - the same silence R-7b and R-7c measured at
-- the other end of a session, where a flush reads `equipped 0`.
--
-- So a read with nothing worn in it is refused as a baseline, exactly as R-7b
-- refuses to store one: `state.baseline` stays nil, the next check takes another
-- one, and no count is ever reported against it.
-- A read with no slot half at all - a bare key set, which is what every caller
-- before C-14 handed over - is not refused: it simply cannot answer the
-- question, and refusing it would be an answer.
function Drift.IsReadable(read)
    if type(read) ~= "table" or type(read.slots) ~= "table" then
        return true
    end
    return next(read.slots) ~= nil
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
--
-- Takes a `Read` since C-14; a bare key set is still accepted, because that is
-- what every caller before it handed over and a baseline with no slot half is
-- simply one that cannot answer the slot question.
function Drift.Rebase(read)
    if read ~= nil and read.keys == nil and read.slots == nil then
        read = { keys = read }
    end
    read = read or Drift.Read()
    -- C-14: a read that is wearing nothing is not a baseline (see IsReadable).
    -- Nothing is stored, so the next check takes another one.
    if read ~= nil and not Drift.IsReadable(read) then
        return nil
    end
    state.baseline = read and read.keys or nil
    state.baselineSlots = read and read.slots or nil
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

-- C-14 (WKE-603). How many WORN slots went bare, or stopped being bare, since
-- the plan was written.
--
-- **A swap is still not drift**, which is R-6's own decision and its own guard:
-- the rating is made over the pool of everything the player can put on, so a
-- piece moving between the bags and the character does not change the answer.
-- What R-6 could not see is a slot going EMPTY, and that one is not a swap - it
-- is a character QE Live will not rate at all (C-14's own refusal, which is the
-- other half of this issue). So only the two edges are counted, filled -> bare
-- and bare -> filled, and nothing here counts an item `Compare` already counted:
-- a key that stays in the player's possession is never a piece that appeared or
-- went.
function Drift.CompareSlots(baseline, current)
    if type(baseline) ~= "table" or type(current) ~= "table" then
        return 0
    end
    local count = 0
    for slotIndex in pairs(current) do
        if baseline[slotIndex] == nil then
            count = count + 1
        end
    end
    for slotIndex in pairs(baseline) do
        if current[slotIndex] == nil then
            count = count + 1
        end
    end
    return count
end

-- What a player would count, in his own words (C-14, WKE-603). A slot is a slot
-- and a loose piece is an item, and when both moved both are said: the nudge's
-- job is to be recognisable as the thing that just happened.
function Drift.CountText(behind)
    if type(behind) ~= "table" then
        return nil
    end
    local parts = {}
    if (behind.slots or 0) > 0 then
        parts[#parts + 1] = ns.UI.Plural(behind.slots, "slot")
    end
    if (behind.pieces or 0) > 0 then
        parts[#parts + 1] = ns.UI.Plural(behind.pieces, "item")
    end
    -- Nothing to say about slots or pieces - a `SetBehind` from a widget test,
    -- or a record from before C-14 - and the caller falls back to the count.
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " and ")
end

-- Rescan and re-answer. Returns what `Behind` will now say. Silent in combat:
-- the previous answer stands, which is the last thing that was true, and
-- `PLAYER_REGEN_ENABLED` runs the check that was refused.
function Drift.Check()
    if InCombatLockdown and InCombatLockdown() then
        state.deferred = true
        return state.behind
    end
    -- H-1 (WKE-596): the healing gate. In a non-healer spec the nudge row and
    -- the minimap badge say nothing at all - a player who is tanking is not
    -- behind on anything Lootpath rates, and telling him to refresh would send
    -- him round a loop that is refused at the other end. A nudge that was
    -- already standing when he changed spec comes DOWN here: this runs on
    -- `PLAYER_SPECIALIZATION_CHANGED` (`Drift.EVENTS`), so the row and the badge
    -- are taken off the screen by the change itself, and the bag marks with
    -- them. The gate is re-read, never remembered, so switching back puts the
    -- baseline and the nudge back on the next scan.
    if ns.Companion and ns.Companion.Gate and ns.Companion.Gate() then
        local changed = state.behind ~= nil or state.gated ~= true
        state.behind = nil
        state.gated = true
        if changed then
            if ns.UI and ns.UI.RefreshStrip then
                ns.UI.RefreshStrip()
            end
            if ns.UI and ns.UI.RefreshMinimapDot then
                ns.UI.RefreshMinimapDot()
            end
            -- The marks already drawn in an open bag window. `ns.Glow.Wants`
            -- answers false from the moment the gate is up, so a slot drawn
            -- after this is unmarked anyway; this is what takes down the ones
            -- that were drawn before the player changed spec.
            if ns.UI and ns.UI.Bags and ns.UI.Bags.Refresh then
                ns.UI.Bags.Refresh()
            end
        end
        return nil
    end
    -- Back in a healing spec (or in a spec the client does not name, which is
    -- never gated): the marks the gate took down are drawn again by the same
    -- redraw, and everything below runs as it always has.
    if state.gated then
        state.gated = false
        if ns.UI and ns.UI.Bags and ns.UI.Bags.Refresh then
            ns.UI.Bags.Refresh()
        end
    end
    local stamp = Drift.PlanStamp()
    local current = Drift.Read()
    if current == nil then
        return state.behind
    end
    -- C-14 (WKE-603): a scan that found nothing worn is the client not
    -- answering, not the player standing there naked. It is neither compared
    -- against nor taken as a baseline; the last thing that was true stands.
    if not Drift.IsReadable(current) then
        return state.behind
    end
    if state.baseline == nil or stamp ~= state.stamp then
        Drift.Rebase(current)
        return nil
    end
    local behind = Drift.Compare(state.baseline, current.keys)
    local slots = Drift.CompareSlots(state.baselineSlots or {}, current.slots)
    if behind or slots > 0 then
        behind = behind or { count = 0 }
        behind.pieces = behind.count
        behind.slots = slots
        behind.count = behind.pieces + slots
    end
    state.behind = behind
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
    state.baselineSlots = nil
    state.stamp = nil
    state.behind = nil
    state.pending = false
    state.deferred = false
    state.gated = nil
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
-- R-6c (WKE-629): the rounding on its own, because two things need it - the
-- words below, and the mark `Drift.WaitPhase` decides `probably ready` against.
-- They must be the SAME number: a strip that says `usually ready in about 45
-- seconds` and turns green at 41 is saying one thing and doing another.
function Drift.RoundedRun(seconds)
    local value = tonumber(seconds)
    if not value or value <= 0 then
        return nil
    end
    local rounded = math.floor(value / 15 + 0.5) * 15
    if rounded < 15 then
        rounded = 15
    end
    return rounded
end

function Drift.RunText(seconds)
    local rounded = Drift.RoundedRun(seconds)
    if not rounded then
        return nil
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

-- R-6c (WKE-629). **The mark the wait's two phases are told apart by, when
-- nothing has ever been measured.** Sixty seconds, and it is not a measurement:
-- it is the number the words already say. With no `runSeconds` stored, both the
-- strip (`WAIT_READY_DEFAULT`) and the chat line (`WAIT_CHAT_DEFAULT`) promise
-- `about a minute`, and a window that says `about a minute` and then waits
-- longer before admitting the rating might be done has broken its own promise.
-- So the mark is the promise. Once a run HAS been measured the mark is that
-- run, rounded exactly as the words round it (`Drift.RoundedRun`).
Drift.WAIT_USUAL_DEFAULT_SECONDS = 60

-- The ONE place that decides whether the wait is still `rating` or already
-- `probably ready`. Pure: seconds in, a word out, no clock and no database, so
-- every surface that shows a phase is showing this answer and not its own.
--
-- `ready` is deliberately inclusive at the mark - elapsed EQUAL to the usual
-- time is already probably ready - because the usual time is where the last run
-- finished, not where it was still going.
function Drift.WaitPhase(elapsed, runSeconds)
    local usual = Drift.RoundedRun(runSeconds) or Drift.WAIT_USUAL_DEFAULT_SECONDS
    if (tonumber(elapsed) or 0) >= usual then
        return "ready"
    end
    return "rating"
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
-- R-6b (WKE-628): only a status whose OWN clock is newer than the click can be
-- one of the three answers above ("failed", "skipped", "running"). An older one
-- is the previous run's and is still "waiting".
--
-- Every state but "waiting" ENDS the wait, which is what keeps the two surfaces
-- together: the strip stops saying `rating your gear` in exactly the cases the
-- chat line answers with something else.
--
-- No side effects: the caller clears. `Drift.LoadLine` runs before anything can
-- have cleared the stamp out from under it (see `ns.onReady` at the foot of
-- this file), and the strip clears from then on.

-- R-6b (WKE-628): the clock a status keeps about ITSELF, so the decision below
-- can ask whether the file on disk is this run's answer or the last one's. A
-- run still going has only a start; one that has ended is dated by its end, and
-- by its start when the companion wrote no end. nil when the file carries
-- neither a state this can place nor a readable stamp, which is what leaves
-- such a file on the behaviour it had before this (docs/ARCHITECTURE.md §11).
local function statusClock(status)
    if not (status and status.ok) then
        return nil
    end
    if status.state == "running" then
        return status.startedAt
    end
    return status.finishedAt or status.startedAt
end

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
    -- R-6b (WKE-628): a status older than the click is not this run's answer.
    -- The owner, 2026-09-23 00:53, clicked Refresh on his Druid and read the
    -- FAILED line about the Shaman's 00:52 run: the watcher reacts to the
    -- SavedVariables the reload WRITES, so at the load the file on disk is
    -- still the previous run's, and reading its state alone answered the wrong
    -- question with somebody else's answer. The wait holds until a status newer
    -- than the click ends it - bounded, as before, by `WAIT_GIVE_UP_SECONDS`,
    -- so a companion that never answers still hands the strip back to C-9 - and
    -- the elapsed time is counted from the click, because a run whose own clock
    -- predates the click is not the run being waited for.
    local clock = statusClock(status)
    local clockEpoch = clock and ns.EpochFromISO(clock, now) or nil
    if clockEpoch and clockEpoch < startedEpoch then
        return "waiting", status, startedAt
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
--
-- R-8 (WKE-616): one age, two endings. `template` is the strip's clause and
-- `bare` the same words without an age; `Drift.GearUnreadChatText` hands over
-- the chat frame's pair instead. Both surfaces come through here, so they
-- cannot disagree about when the gear was last rated.
--
-- R-7d (WKE-621): `GearUnreadAtFlush` is only asked whether the last unload
-- refused the gear - its snapshot's `capturedAt` is a read on whichever
-- character read last, account-wide, and is never the clock. The clock is this
-- character's stored rating. A stamp that cannot be read is treated as no
-- rating at all rather than as a wrong second.
local function gearUnreadText(now, template, bare)
    local gearUnread = ns.Companion and ns.Companion.GearUnreadAtFlush and ns.Companion.GearUnreadAtFlush()
    if not gearUnread then
        return nil
    end
    now = now or time()
    local stamp = Drift.PlanStamp()
    local ratedAt = stamp and ns.EpochFromISO(stamp, now) or nil
    local age = ratedAt and ns.UI.AgeTextFromSeconds(now - ratedAt) or nil
    if not age then
        return bare
    end
    return string.format(template, age)
end

-- The strip's clause: it ends at the age, because the Refresh button is on the
-- same row (R-8).
function Drift.GearUnreadText(now)
    return gearUnreadText(now, Drift.STRIP_GEAR_UNREAD, Drift.STRIP_GEAR_UNREAD_BARE)
end

-- The chat frame's, said once at a login where there is no button to point at,
-- so it names the button and then the command (R-8).
function Drift.GearUnreadChatText(now)
    return gearUnreadText(now, Drift.LOAD_GEAR_UNREAD, Drift.LOAD_GEAR_UNREAD_BARE)
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
        local runSeconds = db and db.runSeconds
        local ready = Drift.ReadyText(runSeconds)
        -- R-6c (WKE-629): the third answer. The elapsed SECONDS decide the
        -- phase; the elapsed WORDS say it. `AgeSeconds` is nil for a stamp that
        -- cannot be read, and an unreadable stamp is a wait that has told
        -- nobody anything yet - so it counts as no time passed and the phase is
        -- `rating`, which is the state that claims the least.
        local phase = Drift.WaitPhase(ns.UI.AgeSeconds(waitingSince, now), runSeconds)
        local head = phase == "ready" and Drift.WAIT_HEAD_READY or Drift.WAIT_HEAD_RATING
        return {
            kind = "wait",
            phase = phase,
            text = string.format(Drift.WAIT_LINE, head, ns.UI.AgeText(waitingSince, now), ready),
            tooltip = phase == "ready" and Drift.WAIT_TOOLTIP_READY or string.format(Drift.WAIT_TOOLTIP_RATING, ready),
        }
    end
    local behind = Drift.Behind()
    if not behind then
        return nil
    end
    return {
        kind = "behind",
        -- C-14 (WKE-603): slots and items, not one number over both. `54 items`
        -- on the owner's screen was his whole inventory counted against an
        -- empty baseline; a player counts what he did - one slot, two pieces.
        text = string.format(Drift.NUDGE_LINE, Drift.CountText(behind) or ns.UI.Plural(behind.count, "item")),
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

-- R-8 (WKE-616): what the Refresh button's hover says, for the state the click
-- is actually in. `Decide` rather than `Waiting`, because `Waiting` ends a wait
-- it does not find and a hover must not write anything; `Decide` only reads.
--
-- R-6c (WKE-629): while a wait is out there the hover is the wait's own
-- tooltip for that phase, which is the same pair the strip's row carries.
function Drift.RefreshTooltip(now)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return Drift.REFRESH_TOOLTIP_COMBAT
    end
    local phase = Drift.RefreshPhase(now)
    if phase == "ready" then
        return Drift.WAIT_TOOLTIP_READY
    end
    if phase == "rating" then
        local db = store()
        return string.format(Drift.WAIT_TOOLTIP_RATING, Drift.ReadyText(db and db.runSeconds))
    end
    return Drift.REFRESH_TOOLTIP
end

-- R-6c (WKE-629): which phase the wait is in, for a caller that must not
-- WRITE. `Decide` rather than `Waiting` for R-8's own reason - `Waiting` ends a
-- wait it does not find, and a hover, a label and a redraw must all be able to
-- ask without changing the answer. nil when no rating is out there at all,
-- which is what puts the button back to `Refresh`.
function Drift.RefreshPhase(now)
    now = now or time()
    local decision, _, since = Drift.Decide(now)
    if decision ~= "waiting" then
        return nil
    end
    local db = store()
    return Drift.WaitPhase(ns.UI.AgeSeconds(since, now), db and db.runSeconds)
end

-- What the button says right now. `Load rating` only past the usual time; the
-- press itself is `Drift.Click` in every phase, so a player who does not wait
-- loses nothing but a reload (R-6a's `still rating` line says so, and the click
-- stamp is kept, so the count comes back where it was - R-6b).
function Drift.RefreshLabel(now)
    if Drift.RefreshPhase(now) == "ready" then
        return Drift.REFRESH_LABEL_READY
    end
    return Drift.REFRESH_LABEL
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
    -- H-1 (WKE-596): in a non-healer spec the load says the gate's own sentence
    -- and nothing else - not a refresh state, not the spec clause, not the
    -- gear-unread line. Every one of those is about a rating for healing gear,
    -- and the player has just been told that healing gear is all Lootpath rates.
    -- The wait's stamp is left alone: a rating started before the spec change is
    -- still out there, and it is still waiting when he switches back.
    local gateLine = ns.Companion.GateLine and ns.Companion.GateLine() or nil
    if gateLine then
        ns.Log("%s", gateLine)
        return gateLine
    end
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
        elseif status and status.exitCode == ns.Companion.EXIT_EMPTY_SLOT then
            line = Drift.LOAD_SKIPPED_SLOT
        else
            line = Drift.LOAD_SKIPPED
        end
    elseif decision == "gearunread" then
        -- R-7c (WKE-594). Not a refresh state: said at the login after a logout
        -- that captured no gear, and said again at the next one if that is
        -- still true. A `/reload` or a refresh stores a read newer than the
        -- refusal and it stops being said.
        line = Drift.GearUnreadChatText(now)
    elseif decision == "done" then
        line = Drift.LOAD_DONE
    elseif decision == "unseen" then
        line = Drift.LOAD_UNSEEN
    else
        -- failed. The stage is C-9's own word for where it died, and the clause
        -- is the strip's own, in chat as well - the two surfaces name one place.
        -- C-14b (WKE-627): unless the rating would not take the gear, which is
        -- the one failure with an answer rather than a log file.
        if ns.Companion.UnratedGear and ns.Companion.UnratedGear(status) then
            line = Drift.LOAD_UNRATED_GEAR
        else
            local where = (status and status.stage) and (" at " .. status.stage) or ""
            line = string.format(Drift.LOAD_FAILED, where)
        end
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
