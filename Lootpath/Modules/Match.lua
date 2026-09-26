-- Lootpath/Modules/Match.lua (M2-2, WKE-520)
-- The join: QE Live's top set on one side, the Inventory scan on the other,
-- one row per gear slot the answer touches.
--
-- Lootpath never computes a healer value. This module chooses nothing: the top
-- set is QE Live's, in QE Live's own order, and every row here says only which
-- of those items you are wearing, which you own, and which you do not have.
--
-- Row: { slot, equipped = record|nil, best = record|nil, verdictItem = item|nil,
--        status, matchedBy, reason, dstSlot, ratedAt, heldAt }
--   (`ratedAt` / `heldAt` only on a MATCHED_BY_ID_ABOVE row: the level the
--   rating named and the level of the copy the character holds.)
--   equipped_is_best - QE Live's item for that slot is already on the character
--   swap             - it is in the bags or the bank; `equipped` is what it replaces
--   best_in_vault    - the scan cannot find it because it is an unclaimed Great
--                      Vault option; `equipped` is what you wear meanwhile and
--                      there is nothing here to equip. Not a gap: the item is
--                      waiting for you, one claim away (WKE-541).
--   best_not_owned   - the scan cannot find it; `reason` says why it might be
--                      missing. Two meanings only: the bank was closed so it was
--                      never scanned, or it is genuinely absent.
--   no_verdict       - something is worn in a slot the export does not name
--
-- Identity is ns.ItemKey (itemID + sorted bonus IDs), the same definition
-- QEImport uses. Two fallbacks, both never silent:
--   1. itemID + the SAME item level (bonus IDs differ);
--   2. M2-5 (WKE-647): itemID at a level ABOVE the rated one - the rated piece,
--      crested since the rating (crests keep the item ID and raise the level;
--      R-3c's rule on the Roads surface, §7 2026-09-15). Tried only after every
--      rated item has had its exact and same-level match, so a crested copy
--      never takes a record another rated item matches outright. It is a claim
--      of identity, never of value: the row keeps both levels and says Refresh
--      rates the crested copy.
-- A copy BELOW the rated level is never accepted: it has not been crested to
-- the rated piece, and two copies of an item at different upgrade levels are
-- different items to QE Live (decision 2026-09-05).

local _, ns = ...

ns.Match = {}
local Match = ns.Match

Match.STATUS = {
    EQUIPPED_IS_BEST = "equipped_is_best",
    SWAP = "swap",
    BEST_IN_VAULT = "best_in_vault",
    BEST_NOT_OWNED = "best_not_owned",
    NO_VERDICT = "no_verdict",
}
local STATUS = Match.STATUS

Match.MATCHED_BY_KEY = "key"
Match.MATCHED_BY_ID_LEVEL = "itemID+level"
Match.MATCHED_BY_ID_ABOVE = "itemID+above"

-- Display order, taken from the slot order of a real export
-- (spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json, 2026-09-06),
-- extended with the three slots that export happened not to carry. The strings
-- are QE Live's own vocabulary, which Inventory records also speak.
Match.SLOT_ORDER = {
    "Head",
    "Neck",
    "Shoulder",
    "Back",
    "Chest",
    "Wrist",
    "Hands",
    "Waist",
    "Legs",
    "Feet",
    "Finger",
    "Trinket",
    "1H Weapon",
    "2H Weapon",
    "Offhand",
    "Shield",
}

Match.SLOT_RANK = {}
for i = 1, #Match.SLOT_ORDER do
    Match.SLOT_RANK[Match.SLOT_ORDER[i]] = i
end
local UNRANKED = #Match.SLOT_ORDER + 1

-- An item already worn beats a copy in the bags, which beats a copy in the
-- bank: of several identical copies, the one that needs no action is the
-- truthful row to show.
local LOCATION_RANK = { equipped = 1, bag = 2, bank = 3 }

local function rankOf(record)
    return LOCATION_RANK[record.location] or 9
end

local function levelKey(itemID, itemLevel)
    return tostring(itemID) .. "@" .. tostring(itemLevel)
end

local function push(index, key, record)
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    list[#list + 1] = record
end

local function indexRecords(records)
    local byKey, byIDLevel, byID = {}, {}, {}
    for i = 1, #records do
        local record = records[i]
        if record.key then
            push(byKey, record.key, record)
        end
        if record.itemID and record.itemLevel then
            push(byIDLevel, levelKey(record.itemID, record.itemLevel), record)
            push(byID, record.itemID, record)
        end
    end
    return byKey, byIDLevel, byID
end

-- The best unclaimed copy in a candidate list. Every record is claimed at most
-- once, so a matched pair of rings needs two records and one copy cannot
-- satisfy both halves of the set.
local function pick(list, claimed)
    if not list then
        return nil
    end
    local best
    for i = 1, #list do
        local record = list[i]
        if not claimed[record] and (not best or rankOf(record) < rankOf(best)) then
            best = record
        end
    end
    return best
end

-- M2-5: the unclaimed copy of this item ID whose level is ABOVE the rated one.
-- The worn copy first, because the one on the character is the one the player
-- crested and put on; then the highest level owned; then the usual placement
-- order. Strictly above: a copy at the rated level is the same-level fallback's,
-- and a copy below is not the rated piece at all.
local function pickAbove(list, level, claimed)
    if not list then
        return nil
    end
    local best
    for i = 1, #list do
        local record = list[i]
        local held = tonumber(record.itemLevel)
        if not claimed[record] and held and held > level then
            if not best then
                best = record
            else
                local worn, bestWorn = record.location == "equipped", best.location == "equipped"
                if worn ~= bestWorn then
                    if worn then
                        best = record
                    end
                elseif held ~= tonumber(best.itemLevel) then
                    if held > tonumber(best.itemLevel) then
                        best = record
                    end
                elseif rankOf(record) < rankOf(best) then
                    best = record
                end
            end
        end
    end
    return best
end

local function bonusText(bonusIDs)
    if type(bonusIDs) ~= "table" or #bonusIDs == 0 then
        return "none"
    end
    local parts = {}
    for i = 1, #bonusIDs do
        parts[i] = tostring(bonusIDs[i])
    end
    return table.concat(parts, ":")
end

-- `best_not_owned` is a gap, and it has two meanings the panel must be able to
-- tell apart. The third thing the scan cannot find - a Great Vault option - is
-- not a gap and never reaches here; it gets its own status above.
local function notOwnedReason(inventory)
    if inventory.bankAvailable == false then
        return "it is not in your gear or bags, and your bank is closed so Lootpath cannot see inside it"
    end
    return "the scan of your gear, bags and bank did not find it"
end

local function newRow(seq, slot, status)
    return { seq = seq, slot = slot or "Unknown", status = status }
end

-- Build(inventory, verdict) -> { ok = true, rows, bySlot, counts, fallbacks, ... }
--                           or { ok = false, reason }
-- `inventory` is an ns.Inventory.Scan() result and `verdict` an ns.QEImport
-- verdict. Either refusal is passed through rather than papered over.
function Match.Build(inventory, verdict)
    if type(inventory) ~= "table" then
        return { ok = false, reason = "no inventory scan to match against" }
    end
    if inventory.ok == false then
        return { ok = false, reason = inventory.reason or "the inventory scan failed" }
    end
    if type(verdict) ~= "table" or type(verdict.topSet) ~= "table" then
        return { ok = false, reason = "no rating imported yet" }
    end

    local records = inventory.records or {}
    local byKey, byIDLevel, byID = indexRecords(records)
    local claimed, rows, fallbacks, logs = {}, {}, {}, {}
    local found = {}

    -- Pass 1: every rated item's exact match, then its same-level match. Each
    -- claims its record here, before any crested copy is looked for.
    local items = verdict.topSet.items or {}
    local order = verdict.topSet.order or {}
    for i = 1, #order do
        local item = items[order[i]]
        if item then
            local row = newRow(#rows + 1, item.slot, nil)
            row.verdictItem = item
            local record = pick(byKey[item.key], claimed)
            if record then
                row.matchedBy = Match.MATCHED_BY_KEY
            else
                local level = tonumber(item.level)
                record = level and pick(byIDLevel[levelKey(item.itemID, level)], claimed) or nil
                if record then
                    row.matchedBy = Match.MATCHED_BY_ID_LEVEL
                    fallbacks[#fallbacks + 1] = string.format(
                        "%s: item %d at level %s matched by itemID and item level, not by key - "
                            .. "the rated bonus IDs are %s, yours are %s",
                        row.slot,
                        item.itemID,
                        tostring(level),
                        bonusText(item.bonusIDs),
                        bonusText(record.bonusIDs)
                    )
                    logs[#logs + 1] = "matched by itemID and item level, not by bonus IDs - " .. fallbacks[#fallbacks]
                end
            end
            if record then
                claimed[record] = true
                found[row] = record
            end
            rows[#rows + 1] = row
        end
    end

    -- Pass 2 (M2-5): a rated item still unmatched, and not a Great Vault option,
    -- is matched to a copy of the same item ID held ABOVE the rated level - the
    -- rated piece, crested since. Identity only: both levels stay on the row.
    for i = 1, #rows do
        local row = rows[i]
        local item = row.verdictItem
        local level = tonumber(item.level)
        if not found[row] and not item.isVault and level then
            local record = pickAbove(byID[item.itemID], level, claimed)
            if record then
                claimed[record] = true
                found[row] = record
                row.matchedBy = Match.MATCHED_BY_ID_ABOVE
                row.ratedAt = level
                row.heldAt = tonumber(record.itemLevel)
                fallbacks[#fallbacks + 1] = string.format(
                    "%s: item %d rated at %s matched to your copy at %s by itemID - "
                        .. "crested above the rated level; Refresh rates the crested copy",
                    row.slot,
                    item.itemID,
                    tostring(level),
                    tostring(row.heldAt)
                )
                logs[#logs + 1] = "matched by itemID above the rated level - " .. fallbacks[#fallbacks]
            end
        end
    end

    -- Every rated row's status is what its placement says, however it matched.
    for i = 1, #rows do
        local row = rows[i]
        local item = row.verdictItem
        local record = found[row]
        if record then
            row.best = record
            if record.location == "equipped" then
                row.equipped = record
                row.status = STATUS.EQUIPPED_IS_BEST
            else
                row.status = STATUS.SWAP
            end
            if row.slot == "Unknown" and record.slot then
                row.slot = record.slot
            end
        elseif item.isVault then
            -- No `reason`: this row is not a failure to explain away. The
            -- panel says what it is and points at the Vault tab.
            row.status = STATUS.BEST_IN_VAULT
        else
            row.status = STATUS.BEST_NOT_OWNED
            row.reason = notOwnedReason(inventory)
        end
    end

    -- What each swap replaces: the equipped items of that slot QE Live did not
    -- keep, handed out in equipment-slot order, so the first Finger row targets
    -- the first ring the character is actually wearing.
    local spare = {}
    for i = 1, #records do
        local record = records[i]
        if record.location == "equipped" and not claimed[record] then
            push(spare, record.slot, record)
        end
    end
    for _, list in pairs(spare) do
        table.sort(list, function(a, b)
            return (a.slotIndex or 0) < (b.slotIndex or 0)
        end)
    end
    for i = 1, #rows do
        local row = rows[i]
        if not row.equipped then
            local list = spare[row.slot]
            local record = list and table.remove(list, 1) or nil
            if record then
                claimed[record] = true
                row.equipped = record
            end
        end
    end

    -- Anything still worn in a slot the export never named.
    for slot, list in pairs(spare) do
        for i = 1, #list do
            local row = newRow(#rows + 1, slot, STATUS.NO_VERDICT)
            row.equipped = list[i]
            rows[#rows + 1] = row
        end
    end

    local counts = { equipped_is_best = 0, swap = 0, best_in_vault = 0, best_not_owned = 0, no_verdict = 0 }
    for i = 1, #rows do
        local row = rows[i]
        row.dstSlot = row.equipped and row.equipped.slotIndex or nil
        counts[row.status] = (counts[row.status] or 0) + 1
    end

    table.sort(rows, function(a, b)
        local ra = Match.SLOT_RANK[a.slot] or UNRANKED
        local rb = Match.SLOT_RANK[b.slot] or UNRANKED
        if ra ~= rb then
            return ra < rb
        end
        return a.seq < b.seq
    end)

    local bySlot = {}
    for i = 1, #rows do
        push(bySlot, rows[i].slot, rows[i])
    end

    -- Never silent: every fallback reaches the chat frame as well as the result.
    for i = 1, #logs do
        ns.Log("%s", logs[i])
    end

    return {
        ok = true,
        rows = rows,
        bySlot = bySlot,
        counts = counts,
        fallbacks = fallbacks,
        bankAvailable = inventory.bankAvailable,
        contentType = verdict.contentType,
        exportedAt = verdict.exportedAt,
        spec = verdict.spec,
        -- Carried, never read here: the items QE Live's Top Gear was never
        -- shown (C-8, WKE-558). This function matches what he answered against
        -- what is owned; "and these he was not asked about" is the panel's
        -- line, and the panel reads it off the match it drew.
        --
        -- The run's list and not this document's (C-11a, WKE-586). Since C-11
        -- the plan is pass 1 of a sequence, and pass 1's own `excluded` is what
        -- the later passes went on to ask about, not what nothing asked;
        -- `ns.Companion.Unrated` is the one place that difference is decided.
        -- Never `or verdict.excluded`: a run whose last pass left nothing out
        -- has nothing to say, and falling back to the plan's own list here
        -- would put 586's own defect back one line lower down.
        excluded = ns.Companion and ns.Companion.Unrated(verdict) or nil,
    }
end

-- True when this row is something the Equip button can act on: QE Live named an
-- item, the scan found it, and it is not already on the character.
function Match.IsSwap(row)
    return type(row) == "table" and row.status == STATUS.SWAP and type(row.best) == "table" and row.best.link ~= nil
end
