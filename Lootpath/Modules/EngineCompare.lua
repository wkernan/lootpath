-- Lootpath/Modules/EngineCompare.lua (E-0d, WKE-673)
-- `/lootpath engine compare`: our percent beside the stored rating's, for every
-- Upgrade Finder `drop` row the journal walk carries a link for and every Top
-- Gear pass-1 single-item alternative the character owns, measured per slot
-- class and stored per week. DEVELOPER-ONLY and scoped by
-- docs/ARCHITECTURE.md section 7 (2026-09-30, E-0 and E-0d) and CLAUDE.md's
-- scoped exception: behind `db.global.developer.engine`, out of combat, printed
-- to the chat frame of the developer who typed it and to no surface; no UI file
-- reads this module (spec/enginecompare_spec.lua reads every UI file to hold
-- that). It never writes `qeImports`, `ufImports` or any other rating store,
-- and it never writes the journal cache either (the walk is aggregated with
-- `db = false`). The bar it prints is a report: nothing is promoted here.
--
-- What is measured:
--   * Upgrade Finder: one stored document (content type, key level). A row is
--     compared when the document calls it a `drop` at its level
--     (ns.UFImport.IsDropAtLevel) AND the newest journal walk carries a row
--     with a link at that exact `id@level` (ns.UFImport.Key). `bonus` / `max`
--     listings are other track levels the client never previewed: left out and
--     counted, until a link can be built for a track. Ours is
--     ns.EngineScore.UpgradePercent(worn, candidate, { assumedFinish = true,
--     forceTier = true, contentType, keyLevel = the document's }); theirs is
--     `upgradePercent` read through UPGRADE_BETTER_PERCENT_SIGN.
--   * The level the candidate is read at (E-0g, WKE-677): the walk's link
--     reads at its OWN level, not the walk's (a keystone row listed at 305
--     reads 292 - ARCHITECTURE.md section 11). With REBUILD_AT_LEVEL on, every
--     joined row is read through ns.EngineStats.LinkAtLevel(link, the row's
--     level) and kept only when the client draws the rebuilt link at that
--     level (ns.EngineStats.AtLevel); a row that cannot be rebuilt, or reads
--     at another level, is LEFT OUT and counted on its own header line, never
--     scored at the wrong level. ON since E-0g step 2: the owner's `capture
--     linklevel` transcript (2026-10-01 20:09) proved the rule installed in
--     ns.EngineStats (`track-append`: the journal link with the track step that
--     draws the row's level added), and it showed why the kept link cannot be
--     scored as it is - a context-scaled link answers at whatever level the
--     Adventure Guide's current view implies (a raid link read 305 before a
--     walk and 219 after it), so the same link scored two levels apart in two
--     sessions. The rows no step draws (the world rows the walk lists at 44)
--     are left out. The `at level` line names the rule. Off, the compare reads
--     the walk's link exactly as before.
--   * The band: the key level goes into every SetValue and UpgradePercent
--     call and ns.EngineScore.BandFor picks the band (E-0h, WKE-678) - the
--     Upgrade Finder document's own level, and for the Top Gear block the
--     level the header prints (the one asked for, or the highest stored). Each
--     block's header names the band key used; a level with no band is
--     reported as `not compared: N (no band for +6)`.
--   * Top Gear `asOffered` pass 1 (the plan's own document, which is
--     QEImport.ForContentTypeAndScenario's shelf - QEImport.ForPass never holds
--     pass 1): each alternative that swaps ONE item, the item in the pass's
--     `considered` pool and owned (its link from the inventory scan), against
--     the best set: ours = 100 * (V(best set with the swap) - V(best set)) /
--     V(best set); theirs is `scorePercent` turned into the same direction
--     through ALT_WORSE_SCORE_PERCENT_SIGN, never re-derived. No best-set search
--     (E-1a). The worn set's value is printed beside it.
--   * Both are UNSCALED: Top Gear's constant 1.5 is not divided out. MAE is
--     reported raw and after k, the least-squares scale of ours onto theirs.
--   * The Upgrade Finder's floor (E-0j, WKE-681): an Upgrade Finder row never
--     reads below 0 - its Top Gear keeps the worn set when the drop is worse
--     (fork UpgradeFinderEngine.js:361-373), so 1843 of the 4730 rows in the
--     14 documents read so far are exactly 0 and none is negative. Our percent
--     is not floored, so before E-0j every censored row paired a negative ours
--     with a 0 theirs, k (sum ours*theirs / sum ours^2) shrank by the share of
--     such rows, and that share is set by the band: most +6 drops are below
--     the worn set, few +10 or raid drops are. Every Upgrade Finder row now
--     compares ours FLOORED the same way (EngineCompare.UFOurs, UF_FLOOR) and
--     keeps the unfloored percent as `raw`. Top Gear rows are not floored:
--     theirs is negative there for a worse alternative.
--   * Effects (E-3a, WKE-679): a row whose swap moves an item the effects
--     table carries without a model is `not rated` and LEFT OUT of every
--     metric - counted, and named under the count with `/lootpath engine
--     verbose`; a row whose swap moves a trinket the table does not carry is
--     left out too, counted apart. A row with a modelled effect stays in and
--     is counted as `generic`. So the trinket class holds only rows a rule
--     covers at the levels read (E-3c, WKE-686: three trinkets, from the
--     owner's `capture effects` transcript), and its metrics are printed and
--     stored beside the other classes. Reported, never gated: the bar's
--     trinket verdict moves by the same per-week rule as every class and
--     nothing reads it to promote anything.
--   * What was read (E-0i, WKE-680): every row keeps, beside `ours` and
--     `theirs`, the candidate `link` as scored and `level`, the client's read
--     level of that link (ns.EngineStats' `level`, GetDetailedItemLevelInfo),
--     so a stored run can be explained later without a recapture. With the
--     same verbose switch (`/lootpath engine verbose`) each block also lists
--     `key · link level · ours · theirs` per scored row.

local _, ns = ...

ns.EngineCompare = {}
local EngineCompare = ns.EngineCompare

-- Every client function this file calls, named rather than discovered. The
-- item reads are ns.EngineStats', the scan ns.Inventory's, the waits
-- ns.ItemData's; each names its own.
EngineCompare.FUNCTION_NAMES = {
    "InCombatLockdown",
    "C_DateAndTime.GetSecondsUntilWeeklyReset",
    "UnitName",
    "GetRealmName",
    "time",
    "date",
}

-- The metrics' fixed numbers (docs/OWN-ENGINE.md section 6).
EngineCompare.DEAD_ZONE = 0.1 -- |theirs| below this is a tie for the sign
-- The lowest an Upgrade Finder row reads (E-0j): ours is floored here too.
EngineCompare.UF_FLOOR = 0
EngineCompare.TOP1_WITHIN = 0.1 -- our pick within this many points of their best
EngineCompare.MIN_RHO_N = 5 -- no Spearman under this many rows
EngineCompare.WEEKS_KEPT = 12
EngineCompare.WEEK_SECONDS = 7 * 24 * 60 * 60

-- The proposed promotion bar, PRINTED and never enforced (memo section 6).
EngineCompare.BAR = {
    rhoMedian = 0.97,
    rhoMin = 0.90,
    top1 = 0.90,
    sign = 0.95,
    maeK = 0.07,
    kSpread = 0.10,
    weeks = 3,
    pooledN = 30,
}

-- E-0g (WKE-677): read every joined Upgrade Finder row through a link rebuilt
-- at the row's level. ON since step 2, on the `capture linklevel` transcript
-- (ARCHITECTURE.md section 7, E-0g step 2); the rule is ns.EngineStats'.
EngineCompare.REBUILD_AT_LEVEL = true

-- The shelf the Top Gear block is stored on beside the key levels.
EngineCompare.TOP_GEAR_KEY = "pass1"

EngineCompare.CLASS_ORDER = { "tier", "armour", "jewellery", "weapon", "trinket" }
EngineCompare.CLASS_OF_SLOT = {
    Head = "tier",
    Shoulder = "tier",
    Chest = "tier",
    Hands = "tier",
    Legs = "tier",
    Back = "armour",
    Wrist = "armour",
    Waist = "armour",
    Feet = "armour",
    Neck = "jewellery",
    Finger = "jewellery",
    ["1H Weapon"] = "weapon",
    ["2H Weapon"] = "weapon",
    Offhand = "weapon",
    Shield = "weapon",
    Trinket = "trinket",
}

EngineCompare.TEXT = {
    notOn = "not on",
    off = "engine off",
    combat = "Out of combat only.",
    usage = "usage: /lootpath engine compare [dungeon|raid] [keylevel] | compare weeks"
        .. " | best [dungeon|raid] [keylevel] | verbose | off",
    verboseOn = "engine verbose on: each compare lists the items it could not rate and every row it scored.",
    verboseOff = "engine verbose off.",
    header = "engine compare - weights %s, patch %s, derived %s - %s - week %s",
    notReady = "%d item(s) were not ready and are left out.",
    secret = "%d item(s) read secret and are left out.",
    ufHeader = "Upgrade Finder %s %s (exported %s), band %s: %d drop rows joined; "
        .. "%d drop rows with no link at their level; %d listings at other levels left out.",
    ufNone = "Upgrade Finder %s: no document stored at %s.",
    noWalk = "no journal walk stored: capture journal first.",
    tgHeader = "Top Gear pass 1 %s (exported %s), band %s: %d single-item swaps compared of %d alternatives "
        .. "(%d not in the pool, %d with no link here, %d paired); worn set %s, best set %s.",
    tgNone = "Top Gear pass 1 %s: none stored.",
    tgNoLink = "Top Gear pass 1 %s: %d piece(s) of the best set have no link here; not compared.",
    tableHead = "  class      n    rho    top1  top3  sign   MAE    k      MAE@k",
    tableRow = "  %-9s %4d  %-6s %-5s %-5s %-6s %-6s %-6s %s",
    generic = "  generic: %d (effect from a generic rule)",
    notRated = "  not rated: %d (effect not modelled)",
    notRatedItem = "    %s (%s)",
    unknown = "  not rated: %d (trinket not in the effects table)",
    trinketNone = "  trinket: no row a rule covers yet",
    notCompared = "  not compared: %d (%s)",
    verboseRow = "    %s · %s %s · %s · %s",
    atLevel = "  at level, rule %s: %d rebuilt, %d left out (%s)",
    bar = "bar (printed, not enforced): %s",
    stored = "stored for week %s.",
    noWeek = "the weekly reset clock did not answer; nothing stored.",
    weeksNone = "no compare stored for %s.",
    weekLine = "%s: %s",
}

-- ---------------------------------------------------------------------------
-- The switch.

local function developer()
    local global = ns.db and ns.db.global
    local dev = type(global) == "table" and global.developer
    return type(dev) == "table" and dev or nil
end

function EngineCompare.Enabled()
    local dev = developer()
    return dev ~= nil and dev.engine == true
end

-- `db.global.developer.engineVerbose`, toggled by `/lootpath engine verbose`:
-- the compare lists, under its not-rated count, the items whose effect is not
-- modelled (E-3a), and under each block every scored row with its link and
-- read level (E-0i). A sibling of `engine`, which is a boolean and cannot
-- carry a field.
function EngineCompare.Verbose()
    local dev = developer()
    return dev ~= nil and dev.engineVerbose == true
end

-- ---------------------------------------------------------------------------
-- Pure metrics. Each takes plain lists and answers numbers or nil.

-- Average ranks (1 = smallest), ties sharing the mean of their positions.
function EngineCompare.Ranks(values)
    local idx = {}
    for i = 1, #values do
        idx[i] = i
    end
    table.sort(idx, function(a, b)
        if values[a] == values[b] then
            return a < b
        end
        return values[a] < values[b]
    end)
    local ranks = {}
    local i = 1
    while i <= #idx do
        local j = i
        while j < #idx and values[idx[j + 1]] == values[idx[i]] do
            j = j + 1
        end
        local avg = (i + j) / 2
        for k = i, j do
            ranks[idx[k]] = avg
        end
        i = j + 1
    end
    return ranks
end

-- Spearman's rho with average ranks, or nil: under MIN_RHO_N rows, or when
-- either list is one value repeated (no order to compare).
function EngineCompare.Spearman(xs, ys)
    local n = #xs
    if n ~= #ys or n < EngineCompare.MIN_RHO_N then
        return nil
    end
    local rx, ry = EngineCompare.Ranks(xs), EngineCompare.Ranks(ys)
    local mean = (n + 1) / 2
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, n do
        local dx, dy = rx[i] - mean, ry[i] - mean
        sxy = sxy + dx * dy
        sxx = sxx + dx * dx
        syy = syy + dy * dy
    end
    if sxx == 0 or syy == 0 then
        return nil
    end
    return sxy / math.sqrt(sxx * syy)
end

-- UFOurs(percent) -> the percent an Upgrade Finder row compares: ours
-- floored at UF_FLOOR, as the Upgrade Finder floors theirs (E-0j, WKE-681).
function EngineCompare.UFOurs(percent)
    if percent < EngineCompare.UF_FLOOR then
        return EngineCompare.UF_FLOOR
    end
    return percent
end

-- k minimising sum (theirs - k * ours)^2, or nil when ours is all zero.
function EngineCompare.Scale(ours, theirs)
    local sot, soo = 0, 0
    for i = 1, #ours do
        sot = sot + ours[i] * theirs[i]
        soo = soo + ours[i] * ours[i]
    end
    if soo == 0 then
        return nil
    end
    return sot / soo
end

-- Mean |k * ours - theirs| (k defaults to 1), or nil for no rows.
function EngineCompare.MAE(ours, theirs, k)
    if #ours == 0 then
        return nil
    end
    k = k or 1
    local sum = 0
    for i = 1, #ours do
        sum = sum + math.abs(k * ours[i] - theirs[i])
    end
    return sum / #ours
end

local function signOf(x)
    if x > 0 then
        return 1
    elseif x < 0 then
        return -1
    end
    return 0
end

-- The share of rows whose signs agree, rows with |theirs| < DEAD_ZONE left
-- out as ties; and how many rows were counted. nil when none were.
function EngineCompare.Sign(ours, theirs)
    local agree, counted = 0, 0
    for i = 1, #ours do
        if math.abs(theirs[i]) >= EngineCompare.DEAD_ZONE then
            counted = counted + 1
            if signOf(ours[i]) == signOf(theirs[i]) then
                agree = agree + 1
            end
        end
    end
    if counted == 0 then
        return nil, 0
    end
    return agree / counted, counted
end

-- One group's top pick (rows of one slot, in key order): whether our best
-- row is within TOP1_WITHIN of their best, and whether it is inside their top
-- three. nil for a group of fewer than two rows.
function EngineCompare.TopPick(rows)
    if #rows < 2 then
        return nil
    end
    local mine, best
    for _, row in ipairs(rows) do
        if not mine or row.ours > mine.ours then
            mine = row
        end
        if not best or row.theirs > best then
            best = row.theirs
        end
    end
    local above = 0
    for _, row in ipairs(rows) do
        if row.theirs > mine.theirs then
            above = above + 1
        end
    end
    return mine.theirs >= best - EngineCompare.TOP1_WITHIN, above < 3
end

local function median(list)
    if #list == 0 then
        return nil
    end
    local sorted = {}
    for i, v in ipairs(list) do
        sorted[i] = v
    end
    table.sort(sorted)
    local mid = (#sorted + 1) / 2
    if mid % 1 == 0 then
        return sorted[mid]
    end
    return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Metrics over rows `{ key, slot, ours, theirs }`:
-- `{ n, rho, rhoBySlot = { [slot] = rho }, rhoMedian, rhoMin, top1, top3,
--    groups, sign, signN, mae, k, maeK }`; every figure nil when it cannot be
-- computed.
function EngineCompare.Metrics(rows)
    local ours, theirs, bySlot = {}, {}, {}
    for i, row in ipairs(rows) do
        ours[i], theirs[i] = row.ours, row.theirs
        local slot = row.slot or "?"
        bySlot[slot] = bySlot[slot] or {}
        bySlot[slot][#bySlot[slot] + 1] = row
    end
    local m = { n = #rows, rho = EngineCompare.Spearman(ours, theirs), rhoBySlot = {} }
    local rhos, groups, top1, top3 = {}, 0, 0, 0
    for _, slot in ipairs(sortedKeys(bySlot)) do
        local group = bySlot[slot]
        local o, t = {}, {}
        for i, row in ipairs(group) do
            o[i], t[i] = row.ours, row.theirs
        end
        local rho = EngineCompare.Spearman(o, t)
        if rho then
            m.rhoBySlot[slot] = rho
            rhos[#rhos + 1] = rho
        end
        local first, inThree = EngineCompare.TopPick(group)
        if first ~= nil then
            groups = groups + 1
            top1 = top1 + (first and 1 or 0)
            top3 = top3 + (inThree and 1 or 0)
        end
    end
    m.rhoMedian = median(rhos)
    if #rhos > 0 then
        m.rhoMin = math.min(unpack(rhos))
    end
    m.groups = groups
    if groups > 0 then
        m.top1, m.top3 = top1 / groups, top3 / groups
    end
    m.sign, m.signN = EngineCompare.Sign(ours, theirs)
    m.mae = EngineCompare.MAE(ours, theirs)
    m.k = EngineCompare.Scale(ours, theirs)
    if m.k then
        m.maeK = EngineCompare.MAE(ours, theirs, m.k)
    end
    return m
end

-- `{ [class] = Metrics }` over rows carrying `class`, for the classes present.
function EngineCompare.ClassMetrics(rows)
    local byClass = {}
    for _, row in ipairs(rows) do
        byClass[row.class] = byClass[row.class] or {}
        byClass[row.class][#byClass[row.class] + 1] = row
    end
    local out = {}
    for class, list in pairs(byClass) do
        out[class] = EngineCompare.Metrics(list)
    end
    return out
end

-- Does one class's metrics clear the per-run half of the bar?
function EngineCompare.Passes(m)
    local bar = EngineCompare.BAR
    if type(m) ~= "table" then
        return false
    end
    return (m.rhoMedian or -2) >= bar.rhoMedian
        and (m.rhoMin or -2) >= bar.rhoMin
        and (m.top1 or -1) >= bar.top1
        and (m.sign or -1) >= bar.sign
        and m.maeK ~= nil
        and m.maeK <= bar.maeK
end

-- ---------------------------------------------------------------------------
-- The week, the character, the store.

-- The reset week's start as `YYYY-MM-DD` (UTC), from the client's own reset
-- clock: the period the vault tab reads (VaultPanel.ClaimedThisPeriod) began a
-- week before now + GetSecondsUntilWeeklyReset(). Rounded to the hour, so two
-- runs a few seconds apart can never land on different days. nil without a
-- clock.
function EngineCompare.WeekKey(now, secondsUntilReset)
    now, secondsUntilReset = tonumber(now), tonumber(secondsUntilReset)
    if not now or not secondsUntilReset then
        return nil
    end
    local start = now + secondsUntilReset - EngineCompare.WEEK_SECONDS
    start = math.floor((start + 1800) / 3600) * 3600
    return date("!%Y-%m-%d", start)
end

local function readWeekKey()
    local fn = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    if type(fn) ~= "function" then
        return nil
    end
    local ok, seconds = pcall(fn)
    if not ok then
        return nil
    end
    local safe, secret = ns.Safe(seconds)
    if secret then
        return nil
    end
    return EngineCompare.WeekKey(time(), safe)
end

function EngineCompare.CharKey()
    local keys = ns.db and ns.db.keys
    if type(keys) == "table" and type(keys.char) == "string" then
        return keys.char
    end
    local name = ns.Safe(UnitName and UnitName("player"))
    local realm = ns.Safe(GetRealmName and GetRealmName())
    if type(name) ~= "string" then
        return "unknown"
    end
    return name .. " - " .. (type(realm) == "string" and realm or "?")
end

-- Files one entry under [week][char][ct][docKey], replacing a run of the same
-- week and document, and keeps the newest WEEKS_KEPT weeks.
function EngineCompare.Store(store, weekKey, charKey, contentType, docKey, entry)
    store[weekKey] = store[weekKey] or {}
    local week = store[weekKey]
    week[charKey] = week[charKey] or {}
    week[charKey][contentType] = week[charKey][contentType] or {}
    week[charKey][contentType][docKey] = entry
    local weeks = sortedKeys(store)
    for i = 1, #weeks - EngineCompare.WEEKS_KEPT do
        store[weeks[i]] = nil
    end
    return store
end

-- Per class and week: "pass" (both content types stored and every Upgrade
-- Finder entry clears the bar), "fail" (an entry does not), or "partial".
function EngineCompare.WeekStates(store, charKey)
    local out = {}
    for _, weekKey in ipairs(sortedKeys(store or {})) do
        local mine = store[weekKey][charKey]
        if type(mine) == "table" then
            local states = {}
            for _, class in ipairs(EngineCompare.CLASS_ORDER) do
                local seen, failed, content = 0, false, {}
                for ct, docs in pairs(mine) do
                    for docKey, entry in pairs(docs) do
                        local m = docKey ~= EngineCompare.TOP_GEAR_KEY
                            and type(entry) == "table"
                            and type(entry.metrics) == "table"
                            and entry.metrics[class]
                        if m then
                            seen = seen + 1
                            content[ct] = true
                            if not EngineCompare.Passes(m) then
                                failed = true
                            end
                        end
                    end
                end
                local state
                if failed then
                    state = "fail"
                elseif seen > 0 and content.Dungeon and content.Raid then
                    state = "pass"
                else
                    state = "partial"
                end
                states[class] = state
            end
            out[#out + 1] = { week = weekKey, states = states, entries = mine }
        end
    end
    return out
end

-- The bar's verdict per class over the stored weeks: "ready", "N/3 weeks" or
-- "no". A report; nothing reads it to change anything.
function EngineCompare.Verdicts(store, charKey)
    local bar = EngineCompare.BAR
    local weeks = EngineCompare.WeekStates(store, charKey)
    local out = {}
    for _, class in ipairs(EngineCompare.CLASS_ORDER) do
        local latest = weeks[#weeks]
        if latest and latest.states[class] == "fail" then
            out[class] = "no"
        else
            local passing, pooled, ks = 0, 0, {}
            for _, week in ipairs(weeks) do
                if week.states[class] == "pass" then
                    passing = passing + 1
                    for _, docs in pairs(week.entries) do
                        for docKey, entry in pairs(docs) do
                            local m = docKey ~= EngineCompare.TOP_GEAR_KEY and entry.metrics and entry.metrics[class]
                            if m then
                                pooled = pooled + m.n
                                ks[#ks + 1] = m.k
                            end
                        end
                    end
                end
            end
            if passing >= bar.weeks then
                local lo, hi, sum = math.huge, -math.huge, 0
                for _, k in ipairs(ks) do
                    lo, hi, sum = math.min(lo, k), math.max(hi, k), sum + k
                end
                local mean = sum / #ks
                local stable = mean ~= 0 and (hi - lo) / math.abs(mean) <= bar.kSpread
                out[class] = (pooled >= bar.pooledN and stable) and "ready" or "no"
            else
                out[class] = string.format("%d/%d weeks", passing, bar.weeks)
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The compare itself, pure over what Gather read and Resolve waited for.

local function vectorFor(reads, link, slot)
    local read = link and reads[link]
    if type(read) ~= "table" or read.ready ~= true or read.secret then
        return nil
    end
    local v = {}
    for k, x in pairs(read) do
        v[k] = x
    end
    v.slot = slot
    return v
end

local function scoreOpts(contentType, file, keyLevel)
    return { assumedFinish = true, forceTier = true, contentType = contentType, file = file, keyLevel = keyLevel }
end

-- The band key a block is scored with, or nil and why (BandFor's reason).
local function bandOfBlock(block, inputs, keyLevel)
    local band, key = ns.EngineScore.BandFor(inputs.file, nil, inputs.contentType, keyLevel)
    if band then
        block.band = key
    else
        block.noBand = key
    end
end

local function sortRows(rows)
    table.sort(rows, function(a, b)
        return a.key < b.key
    end)
    return rows
end

-- The journal rows with a link, indexed by `id@level`; the first in itemID
-- order wins, so a walk joins the same way every time.
function EngineCompare.JournalLinks(sources)
    local byKey = {}
    if type(sources) ~= "table" then
        return byKey
    end
    local ids = {}
    for itemID in pairs(sources) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, itemID in ipairs(ids) do
        for _, row in ipairs(sources[itemID]) do
            if type(row) == "table" and type(row.link) == "string" and not row.pending then
                local key = ns.UFImport.Key(itemID, row.itemLevel)
                if key and not byKey[key] then
                    byKey[key] = row
                end
            end
        end
    end
    return byKey
end

-- The Upgrade Finder half's joins, before anything is read: which rows,
-- which links.
function EngineCompare.UFJoin(verdict, journalByKey)
    local joined, noLink, other = {}, 0, 0
    for _, key in ipairs(verdict.order or {}) do
        local entry = verdict.items[key]
        if entry then
            if not ns.UFImport.IsDropAtLevel(entry) then
                other = other + 1
            elseif journalByKey[key] then
                joined[#joined + 1] = { entry = entry, row = journalByKey[key] }
            else
                noLink = noLink + 1
            end
        end
    end
    return { joined = joined, noLink = noLink, other = other }
end

-- The link a joined row's candidate is read from: the walk's own link with
-- REBUILD_AT_LEVEL off; with it on, the link ns.EngineStats.LinkAtLevel
-- rebuilds at the row's level, or nil and why it could not.
function EngineCompare.CandidateLink(pair)
    if not EngineCompare.REBUILD_AT_LEVEL then
        return pair.row.link
    end
    return ns.EngineStats.LinkAtLevel(pair.row.link, pair.row.itemLevel)
end

local function wornVectors(inputs)
    local worn, missing = {}, 0
    for _, record in ipairs(inputs.worn or {}) do
        local v = vectorFor(inputs.reads, record.link, record.slot)
        if v then
            worn[#worn + 1] = v
        else
            missing = missing + 1
        end
    end
    return worn, missing
end

-- A row left out because an effect it moves is not modelled (E-3a): counted,
-- and its items named for the verbose listing.
local function notRated(block, key, unmodelled)
    block.notRated = block.notRated + 1
    local names = {}
    for _, item in ipairs(unmodelled or {}) do
        names[#names + 1] = tostring(item.name or item.itemID)
    end
    block.notRatedItems[#block.notRatedItems + 1] = { key = key, names = table.concat(names, ", ") }
end

local function newCounts(block)
    block.notRated = 0
    block.notRatedItems = {}
    block.unknown = 0
    block.generic = 0
    return block
end

local function finishBlock(block, rows)
    table.sort(block.notRatedItems, function(a, b)
        return a.key < b.key
    end)
    block.rows = sortRows(rows)
    block.metrics = EngineCompare.ClassMetrics(rows)
    return block
end

-- Why a joined row is left out under REBUILD_AT_LEVEL, or nil: no rebuilt
-- link (LinkAtLevel's reason), or a read the client drew at another level
-- (AtLevel's). A rebuilt link not read yet is not left out here; it is
-- `not ready` like every unread row.
local function leftOutAtLevel(link, notBuilt, candidate, level)
    if not link then
        return notBuilt or "not rebuilt"
    end
    if not candidate then
        return nil
    end
    local _, notAt = ns.EngineStats.AtLevel(candidate, level)
    return notAt
end

function EngineCompare.CompareUF(inputs, worn)
    local document = inputs.document
    local join = EngineCompare.UFJoin(document.verdict, inputs.journalByKey or {})
    local block = {
        kind = "uf",
        keyLevel = document.keyLevel,
        exportedAt = document.verdict.exportedAt,
        joined = #join.joined,
        noLink = join.noLink,
        other = join.other,
        notCompared = 0,
        reasons = {},
    }
    newCounts(block)
    bandOfBlock(block, inputs, document.keyLevel)
    local opts = scoreOpts(inputs.contentType, inputs.file, document.keyLevel)
    local rows = {}
    local sign = ns.UFImport.UPGRADE_BETTER_PERCENT_SIGN
    if EngineCompare.REBUILD_AT_LEVEL then
        block.atLevel = { rule = ns.EngineStats.LinkLevelRuleName(), rebuilt = 0, leftOut = 0, reasons = {} }
    end
    for _, pair in ipairs(join.joined) do
        local slot = pair.row.slot or pair.entry.slot
        local link, notBuilt = EngineCompare.CandidateLink(pair)
        local candidate = vectorFor(inputs.reads, link, slot)
        local why = block.atLevel and leftOutAtLevel(link, notBuilt, candidate, pair.row.itemLevel) or nil
        if why then
            -- Counted on the block's own `at level` line: never scored at
            -- another level, and not a `not compared` row either.
            block.atLevel.leftOut = block.atLevel.leftOut + 1
            block.atLevel.reasons[why] = (block.atLevel.reasons[why] or 0) + 1
        else
            if block.atLevel and candidate then
                block.atLevel.rebuilt = block.atLevel.rebuilt + 1
            end
            local percent, detail
            if candidate then
                percent, detail = ns.EngineScore.UpgradePercent(worn, candidate, opts)
            else
                detail = "not ready"
            end
            if percent and type(detail) == "table" and detail.effectUnmodelled then
                notRated(block, pair.entry.key, detail.unmodelled)
            elseif percent and type(detail) == "table" and detail.effectUnknown then
                block.unknown = block.unknown + 1
            elseif percent then
                if type(detail) == "table" and detail.generic then
                    block.generic = block.generic + 1
                end
                rows[#rows + 1] = {
                    key = pair.entry.key,
                    slot = slot,
                    class = EngineCompare.CLASS_OF_SLOT[slot] or "other",
                    -- Floored as the Upgrade Finder floors theirs (E-0j);
                    -- the unfloored percent is kept as `raw`.
                    ours = EngineCompare.UFOurs(percent),
                    raw = percent,
                    theirs = pair.entry.upgradePercent * sign,
                    -- The link the read was made from: the rebuilt one under
                    -- REBUILD_AT_LEVEL, the walk's own otherwise.
                    link = link,
                    level = candidate and candidate.level or nil,
                }
            else
                block.notCompared = block.notCompared + 1
                local reason = tostring(detail)
                block.reasons[reason] = (block.reasons[reason] or 0) + 1
            end
        end
    end
    return finishBlock(block, rows)
end

local HANDS = { ["1H Weapon"] = true, Offhand = true, Shield = true }

-- The key level the Top Gear block is scored at: the Upgrade Finder
-- document's (the one asked for, or the highest stored - what the header
-- prints), else the level asked for.
function EngineCompare.TopGearLevel(inputs)
    local document = inputs.document
    if document and document.keyLevel ~= nil then
        return document.keyLevel
    end
    return inputs.askedLevel
end

function EngineCompare.CompareTopGear(inputs, worn)
    local verdict = inputs.topGear
    local block = {
        kind = "tg",
        exportedAt = verdict.exportedAt,
        alternatives = #(verdict.alternatives or {}),
        notInPool = 0,
        noLink = 0,
        paired = 0,
        notCompared = 0,
        reasons = {},
    }
    local keyLevel = EngineCompare.TopGearLevel(inputs)
    newCounts(block)
    bandOfBlock(block, inputs, keyLevel)
    local top, missing = {}, 0
    local topSet = verdict.topSet or {}
    for _, key in ipairs(topSet.order or {}) do
        local item = topSet.items and topSet.items[key]
        local record = inputs.owned and inputs.owned[key]
        local v = item and record and vectorFor(inputs.reads, record.link, item.slot)
        if v then
            top[#top + 1] = v
        else
            missing = missing + 1
        end
    end
    if missing > 0 then
        block.topMissing = missing
        return finishBlock(block, {})
    end
    local opts = scoreOpts(inputs.contentType, inputs.file, keyLevel)
    local base, baseWhy = ns.EngineScore.SetValue(top, opts)
    local wornValue = ns.EngineScore.SetValue(worn, opts)
    block.topValue = base and base.value or nil
    block.wornValue = wornValue and wornValue.value or nil
    local rows, seen = {}, {}
    local altSign = ns.QEImport.ALT_WORSE_SCORE_PERCENT_SIGN
    for _, alt in ipairs(verdict.alternatives or {}) do
        local items = alt.items or {}
        if #items == 1 then
            local item = items[1]
            local record = inputs.owned and inputs.owned[item.key]
            if
                type(verdict.considered) == "table"
                and not ns.Companion.IsConsidered(verdict.considered, item.key, item)
            then
                block.notInPool = block.notInPool + 1
            elseif not record then
                block.noLink = block.noLink + 1
            elseif not seen[item.key] then
                seen[item.key] = true
                local replaced = {}
                for i, v in ipairs(top) do
                    if v.slot == item.slot or (item.slot == "2H Weapon" and HANDS[v.slot]) then
                        replaced[#replaced + 1] = i
                    end
                end
                local cand = vectorFor(inputs.reads, record.link, item.slot)
                if #replaced > 1 and item.slot ~= "2H Weapon" then
                    block.paired = block.paired + 1
                elseif not cand or not base or base.value == 0 then
                    block.notCompared = block.notCompared + 1
                    local why = not cand and "not ready" or (not base and baseWhy) or "no base"
                    block.reasons[why] = (block.reasons[why] or 0) + 1
                else
                    local drop = {}
                    for _, i in ipairs(replaced) do
                        drop[i] = true
                    end
                    local set = {}
                    for i, v in ipairs(top) do
                        if not drop[i] then
                            set[#set + 1] = v
                        end
                    end
                    set[#set + 1] = cand
                    -- What the swap moves: the alternative in, what it
                    -- replaces out. An effect worn on both sides cancels.
                    local moved = { cand }
                    for _, i in ipairs(replaced) do
                        moved[#moved + 1] = top[i]
                    end
                    local flags = ns.EngineScore.ChangeEffects(moved, opts.effects)
                    local scored, why = ns.EngineScore.SetValue(set, opts)
                    if not scored then
                        block.notCompared = block.notCompared + 1
                        block.reasons[why] = (block.reasons[why] or 0) + 1
                    elseif flags.effectUnmodelled then
                        notRated(block, item.key, flags.unmodelled)
                    elseif flags.effectUnknown then
                        block.unknown = block.unknown + 1
                    else
                        if flags.generic then
                            block.generic = block.generic + 1
                        end
                        rows[#rows + 1] = {
                            key = item.key,
                            slot = item.slot,
                            class = EngineCompare.CLASS_OF_SLOT[item.slot] or "other",
                            ours = 100 * (scored.value - base.value) / base.value,
                            -- Their direction is "positive = the alternative is
                            -- worse"; the constant turns it around, so both
                            -- columns read "positive = better".
                            theirs = -(tonumber(alt.scorePercent) or 0) * altSign,
                            link = record.link,
                            level = cand.level,
                        }
                    end
                end
            end
        end
    end
    return finishBlock(block, rows)
end

-- Compute(inputs) -> `{ uf = block | nil, tg = block | nil, wornMissing }`.
-- `inputs`: contentType, file, document ({ verdict, keyLevel } | nil),
-- topGear (verdict | nil), worn (records), owned ([key] = record),
-- journalByKey, reads ([link] = EngineStats read).
function EngineCompare.Compute(inputs)
    local worn, wornMissing = wornVectors(inputs)
    local result = { wornMissing = wornMissing }
    if inputs.document and inputs.journalByKey then
        result.uf = EngineCompare.CompareUF(inputs, worn)
    end
    if inputs.topGear then
        result.tg = EngineCompare.CompareTopGear(inputs, worn)
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Printing.

local function fmt(x, pattern)
    if x == nil then
        return "-"
    end
    return string.format(pattern, x)
end

local function pct(x)
    if x == nil then
        return "-"
    end
    return string.format("%d%%", math.floor(x * 100 + 0.5))
end

function EngineCompare.TableLines(metrics)
    local lines = { EngineCompare.TEXT.tableHead }
    local classes = {}
    for _, class in ipairs(EngineCompare.CLASS_ORDER) do
        classes[#classes + 1] = class
    end
    if metrics.other then
        classes[#classes + 1] = "other"
    end
    for _, class in ipairs(classes) do
        local m = metrics[class]
        if m then
            lines[#lines + 1] = string.format(
                EngineCompare.TEXT.tableRow,
                class,
                m.n,
                fmt(m.rho, "%.3f"),
                pct(m.top1),
                pct(m.top3),
                pct(m.sign),
                fmt(m.mae, "%.3f"),
                fmt(m.k, "%.3f"),
                fmt(m.maeK, "%.3f")
            )
        end
    end
    return lines
end

-- One reason is printed bare (the count is already the line's N:
-- `not compared: 84 (no band for +6)`); several each carry their own count.
local function reasonsText(reasons)
    local keys = sortedKeys(reasons)
    if #keys == 1 then
        return tostring(keys[1])
    end
    local parts = {}
    for _, why in ipairs(keys) do
        parts[#parts + 1] = string.format("%s %d", why, reasons[why])
    end
    return table.concat(parts, ", ")
end

-- One line per scored row, in the stored order: what was read and both
-- columns, so a run can be explained from the chat log alone.
function EngineCompare.RowLines(rows)
    local lines = {}
    for _, row in ipairs(rows or {}) do
        lines[#lines + 1] = string.format(
            EngineCompare.TEXT.verboseRow,
            tostring(row.key),
            tostring(row.link or "-"),
            fmt(row.level, "%d"),
            fmt(row.ours, "%.4f"),
            fmt(row.theirs, "%.4f")
        )
    end
    return lines
end

-- After the class table: the trinket line when no trinket row is in it (the
-- class holds only rows a rule covers at the item's level), the generic
-- count, the not-rated count with its items under it
-- when verbose, the trinkets the table does not carry, and (verbose) every
-- scored row.
local function blockTail(lines, block, verbose)
    local T = EngineCompare.TEXT
    for _, line in ipairs(EngineCompare.TableLines(block.metrics)) do
        lines[#lines + 1] = line
    end
    if not block.metrics.trinket then
        lines[#lines + 1] = T.trinketNone
    end
    lines[#lines + 1] = string.format(T.generic, block.generic or 0)
    lines[#lines + 1] = string.format(T.notRated, block.notRated)
    if verbose then
        for _, item in ipairs(block.notRatedItems or {}) do
            lines[#lines + 1] = string.format(T.notRatedItem, item.names, item.key)
        end
    end
    if (block.unknown or 0) > 0 then
        lines[#lines + 1] = string.format(T.unknown, block.unknown)
    end
    if block.notCompared > 0 then
        lines[#lines + 1] = string.format(EngineCompare.TEXT.notCompared, block.notCompared, reasonsText(block.reasons))
    end
    if verbose then
        for _, line in ipairs(EngineCompare.RowLines(block.rows)) do
            lines[#lines + 1] = line
        end
    end
end

function EngineCompare.VerdictLine(verdicts)
    local parts = {}
    for _, class in ipairs(EngineCompare.CLASS_ORDER) do
        parts[#parts + 1] = class .. " " .. verdicts[class]
    end
    return string.format(EngineCompare.TEXT.bar, table.concat(parts, " · "))
end

-- Lines(run) -> the printed report, one string per chat line.
function EngineCompare.Lines(run)
    local T = EngineCompare.TEXT
    local file = run.file or {}
    local lines = {
        string.format(
            T.header,
            tostring(file.method),
            tostring(file.patch),
            tostring(file.derivedAt),
            run.charKey,
            run.weekKey or "unknown"
        ),
    }
    if run.notReady and run.notReady > 0 then
        lines[#lines + 1] = string.format(T.notReady, run.notReady)
    end
    if run.secret and run.secret > 0 then
        lines[#lines + 1] = string.format(T.secret, run.secret)
    end
    local result = run.result
    if run.noWalk then
        lines[#lines + 1] = T.noWalk
    end
    if result.uf then
        local uf = result.uf
        lines[#lines + 1] = string.format(
            T.ufHeader,
            run.contentType,
            ns.UFImport.KeyLabel(uf.keyLevel) or "(no key level)",
            tostring(uf.exportedAt),
            uf.band or "-",
            uf.joined,
            uf.noLink,
            uf.other
        )
        if uf.atLevel then
            lines[#lines + 1] = string.format(
                T.atLevel,
                tostring(uf.atLevel.rule),
                uf.atLevel.rebuilt,
                uf.atLevel.leftOut,
                uf.atLevel.leftOut > 0 and reasonsText(uf.atLevel.reasons) or "none"
            )
        end
        blockTail(lines, uf, run.verbose)
    elseif run.noDocument then
        lines[#lines + 1] = string.format(T.ufNone, run.contentType, tostring(run.askedLevel or "any key level"))
    end
    local tg = result.tg
    if tg and tg.topMissing then
        lines[#lines + 1] = string.format(T.tgNoLink, run.contentType, tg.topMissing)
    elseif tg then
        lines[#lines + 1] = string.format(
            T.tgHeader,
            run.contentType,
            tostring(tg.exportedAt),
            tg.band or "-",
            #tg.rows,
            tg.alternatives,
            tg.notInPool,
            tg.noLink,
            tg.paired,
            fmt(tg.wornValue, "%.1f"),
            fmt(tg.topValue, "%.1f")
        )
        blockTail(lines, tg, run.verbose)
    else
        lines[#lines + 1] = string.format(T.tgNone, run.contentType)
    end
    if run.verdicts then
        lines[#lines + 1] = EngineCompare.VerdictLine(run.verdicts)
    end
    if run.weekKey then
        lines[#lines + 1] = string.format(T.stored, run.weekKey)
    else
        lines[#lines + 1] = T.noWeek
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Reading the database and the client, and waiting for items.

-- The document asked for: the stored one at `keyLevel`, or the highest key
-- level stored, or the one that names none.
function EngineCompare.ChooseDocument(contentType, keyLevel)
    local documents = ns.UFImport.Documents(contentType)
    if keyLevel ~= nil then
        for _, document in ipairs(documents) do
            if document.keyLevel == keyLevel then
                return document
            end
        end
        return nil
    end
    local chosen
    for _, document in ipairs(documents) do
        if document.keyLevel ~= nil or not chosen then
            chosen = document
        end
    end
    return chosen
end

function EngineCompare.TopGearDocument(contentType)
    local verdict = ns.QEImport.ForContentTypeAndScenario(contentType, ns.QEImport.DEFAULT_SCENARIO)
    if type(verdict) ~= "table" or ns.QEImport.PassKey(verdict) ~= ns.QEImport.FIRST_PASS then
        return nil
    end
    return verdict
end

-- Gather(contentType, keyLevel) -> inputs without `reads`, plus the links
-- to read; nil and a reason in combat.
function EngineCompare.Gather(contentType, keyLevel)
    local scan = ns.Inventory.Scan()
    if not scan.ok then
        return nil, scan.reason
    end
    local inputs = {
        contentType = contentType,
        file = ns.EngineScore.file,
        worn = {},
        owned = {},
        askedLevel = keyLevel,
    }
    for _, record in ipairs(scan.records) do
        if record.location == "equipped" then
            inputs.worn[#inputs.worn + 1] = record
        end
        if not inputs.owned[record.key] or record.location == "equipped" then
            inputs.owned[record.key] = record
        end
    end
    inputs.document = EngineCompare.ChooseDocument(contentType, keyLevel)
    local snapshot = ns.Companion.NewestSnapshot("journal")
    if snapshot then
        -- `db = false`: aggregate the walk without writing the journal cache.
        local sources = ns.Journal:Build({ snapshot = snapshot, db = false })
        inputs.journalByKey = EngineCompare.JournalLinks(sources)
    end
    inputs.topGear = EngineCompare.TopGearDocument(contentType)

    local links, seen = {}, {}
    local function want(link)
        if type(link) == "string" and not seen[link] then
            seen[link] = true
            links[#links + 1] = link
        end
    end
    for _, record in ipairs(inputs.worn) do
        want(record.link)
    end
    if inputs.document and inputs.journalByKey then
        for _, pair in ipairs(EngineCompare.UFJoin(inputs.document.verdict, inputs.journalByKey).joined) do
            want((EngineCompare.CandidateLink(pair)))
        end
    end
    if inputs.topGear then
        local topSet = inputs.topGear.topSet or {}
        for _, key in ipairs(topSet.order or {}) do
            want(inputs.owned[key] and inputs.owned[key].link)
        end
        for _, alt in ipairs(inputs.topGear.alternatives or {}) do
            if #(alt.items or {}) == 1 then
                local record = inputs.owned[alt.items[1].key]
                want(record and record.link)
            end
        end
    end
    return inputs, links
end

-- Resolve(links, done): reads every link through ns.EngineStats.ForLink; a
-- link not ready is waited on through ns.ItemData.Watch, which bounds the wait
-- (ItemData.WAIT_SECONDS x MAX_ATTEMPTS). `done(reads, notReady, secret)`
-- runs once, when every link has answered or been given up on.
function EngineCompare.Resolve(links, done)
    local reads, pendingByItem, waiting = {}, {}, 0
    local finished = false
    local function count()
        local notReady, secret = 0, 0
        for _, link in ipairs(links) do
            local read = reads[link]
            if type(read) ~= "table" or read.ready ~= true then
                notReady = notReady + 1
            elseif read.secret then
                secret = secret + 1
            end
        end
        return notReady, secret
    end
    local function finish()
        if finished or waiting > 0 then
            return
        end
        finished = true
        done(reads, count())
    end
    for _, link in ipairs(links) do
        local read = ns.EngineStats.ForLink(link)
        reads[link] = read
        if type(read) == "table" and read.ready == false then
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID then
                pendingByItem[itemID] = pendingByItem[itemID] or {}
                local list = pendingByItem[itemID]
                list[#list + 1] = link
            end
        end
    end
    for _, itemID in ipairs(sortedKeys(pendingByItem)) do
        local list = pendingByItem[itemID]
        waiting = waiting + 1
        local closed = false
        local function close()
            if not closed then
                closed = true
                waiting = waiting - 1
                finish()
            end
        end
        local handle = ns.ItemData.Watch(itemID, function()
            local all = true
            for _, link in ipairs(list) do
                local read = ns.EngineStats.ForLink(link)
                reads[link] = read
                if type(read) ~= "table" or read.ready ~= true then
                    all = false
                end
            end
            if all then
                -- Closed after the watcher returns, so ItemData ends its
                -- episode before the compare runs.
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, close)
                else
                    close()
                end
            end
            return all
        end, close)
        if not handle then
            close()
        end
    end
    finish()
end

-- ---------------------------------------------------------------------------
-- The command.

local CONTENT = { dungeon = "Dungeon", raid = "Raid" }

local function store()
    local global = ns.db.global
    global.engineCompare = type(global.engineCompare) == "table" and global.engineCompare or {}
    return global.engineCompare
end

local function entryOf(block, file)
    return {
        weightsPatch = file.patch,
        method = file.method,
        derivedAt = file.derivedAt,
        qeExportedAt = block.exportedAt,
        band = block.band,
        atLevel = block.atLevel,
        rows = block.rows,
        metrics = block.metrics,
        notRated = block.notRated,
        generic = block.generic,
        unknown = block.unknown,
    }
end

-- Run(contentType, keyLevel, onDone): gathers, waits, computes, stores and
-- prints. `onDone(run)` is for tests; the lines are printed either way.
function EngineCompare.Run(contentType, keyLevel, onDone)
    if InCombatLockdown() then
        ns.Log("%s", EngineCompare.TEXT.combat)
        return
    end
    if not ns.EngineScore.file then
        local ok, line, detail = ns.EngineScore.Load()
        if not ok then
            ns.Log("%s", line)
            if detail then
                ns.Log("%s", detail)
            end
            return
        end
    end
    local inputs, links = EngineCompare.Gather(contentType, keyLevel)
    if not inputs then
        ns.Log("%s", EngineCompare.TEXT.combat)
        return
    end
    EngineCompare.Resolve(links, function(reads, notReady, secret)
        inputs.reads = reads
        local result = EngineCompare.Compute(inputs)
        local run = {
            file = inputs.file,
            contentType = contentType,
            askedLevel = keyLevel,
            charKey = EngineCompare.CharKey(),
            weekKey = readWeekKey(),
            notReady = notReady,
            secret = secret,
            noWalk = inputs.journalByKey == nil,
            noDocument = inputs.document == nil,
            verbose = EngineCompare.Verbose(),
            result = result,
        }
        if run.weekKey then
            local s = store()
            if result.uf then
                local docKey = ns.UFImport.KeyLevelKey(result.uf.keyLevel)
                EngineCompare.Store(s, run.weekKey, run.charKey, contentType, docKey, entryOf(result.uf, inputs.file))
            end
            if result.tg and not result.tg.topMissing then
                EngineCompare.Store(
                    s,
                    run.weekKey,
                    run.charKey,
                    contentType,
                    EngineCompare.TOP_GEAR_KEY,
                    entryOf(result.tg, inputs.file)
                )
            end
            run.verdicts = EngineCompare.Verdicts(s, run.charKey)
        end
        for _, line in ipairs(EngineCompare.Lines(run)) do
            ns.Log("%s", line)
        end
        if onDone then
            onDone(run)
        end
    end)
end

-- The stored weeks, one line each, then the bar's verdict.
function EngineCompare.WeeksLines(charKey)
    local s = ns.db.global.engineCompare
    local weeks = EngineCompare.WeekStates(type(s) == "table" and s or {}, charKey)
    if #weeks == 0 then
        return { string.format(EngineCompare.TEXT.weeksNone, charKey) }
    end
    local lines = {}
    for _, week in ipairs(weeks) do
        local parts = {}
        for _, class in ipairs(EngineCompare.CLASS_ORDER) do
            parts[#parts + 1] = class .. " " .. week.states[class]
        end
        lines[#lines + 1] = string.format(EngineCompare.TEXT.weekLine, week.week, table.concat(parts, " · "))
    end
    lines[#lines + 1] = EngineCompare.VerdictLine(EngineCompare.Verdicts(s, charKey))
    return lines
end

-- `/lootpath engine <rest>`: compare [dungeon|raid] [keylevel] | compare
-- weeks | best [dungeon|raid] [keylevel] (E-1a, ns.EngineSearch) | verbose |
-- off. Every word but `off` needs the switch; with it off the answer is one
-- line.
function EngineCompare.Command(rest, onDone)
    local words = {}
    for word in (rest or ""):gmatch("%S+") do
        words[#words + 1] = word:lower()
    end
    if not EngineCompare.Enabled() then
        ns.Log("%s", EngineCompare.TEXT.notOn)
        return
    end
    if words[1] == "off" then
        developer().engine = nil
        ns.Log("%s", EngineCompare.TEXT.off)
        return
    end
    if words[1] == "best" then
        -- E-1a (WKE-685): the best-set search over owned items.
        ns.EngineSearch.Command(words, onDone)
        return
    end
    if words[1] == "verbose" then
        local dev = developer() or {} -- Enabled() above means it is there
        dev.engineVerbose = (dev.engineVerbose ~= true) or nil
        ns.Log("%s", dev.engineVerbose and EngineCompare.TEXT.verboseOn or EngineCompare.TEXT.verboseOff)
        return
    end
    if words[1] ~= "compare" then
        ns.Log("%s", EngineCompare.TEXT.usage)
        return
    end
    if words[2] == "weeks" then
        for _, line in ipairs(EngineCompare.WeeksLines(EngineCompare.CharKey())) do
            ns.Log("%s", line)
        end
        return
    end
    local contentType, keyLevel = nil, nil
    for i = 2, #words do
        if CONTENT[words[i]] then
            contentType = CONTENT[words[i]]
        elseif tonumber(words[i]) then
            keyLevel = tonumber(words[i])
        else
            ns.Log("%s", EngineCompare.TEXT.usage)
            return
        end
    end
    if not contentType then
        local profile = ns.db and ns.db.profile
        local settings = type(profile) == "table" and profile.settings or nil
        contentType = type(settings) == "table" and settings.contentType or "Dungeon"
        if contentType ~= "Raid" then
            contentType = "Dungeon"
        end
    end
    EngineCompare.Run(contentType, keyLevel, onDone)
end
