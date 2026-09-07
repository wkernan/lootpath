-- Lootpath/Modules/Match.lua (M2-2, WKE-520)
-- The join: QE Live's top set on one side, the Inventory scan on the other,
-- one row per gear slot the answer touches.
--
-- Lootpath never computes a healer value. This module chooses nothing: the top
-- set is QE Live's, in QE Live's own order, and every row here says only which
-- of those items you are wearing, which you own, and which you do not have.
--
-- Row: { slot, equipped = record|nil, best = record|nil, verdictItem = item|nil,
--        status, matchedBy, reason, dstSlot }
--   equipped_is_best - QE Live's item for that slot is already on the character
--   swap             - it is in the bags or the bank; `equipped` is what it replaces
--   best_not_owned   - the scan cannot find it; `reason` says why it might be missing
--   no_verdict       - something is worn in a slot the export does not name
--
-- Identity is ns.ItemKey (itemID + sorted bonus IDs), the same definition
-- QEImport uses. An itemID + item-level match is the ONLY fallback, it is never
-- silent, and an itemID-only match is never accepted: two copies of an item at
-- different upgrade levels are different items to QE Live (decision 2026-09-05).

local _, ns = ...

ns.Match = {}
local Match = ns.Match

Match.STATUS = {
    EQUIPPED_IS_BEST = "equipped_is_best",
    SWAP = "swap",
    BEST_NOT_OWNED = "best_not_owned",
    NO_VERDICT = "no_verdict",
}
local STATUS = Match.STATUS

Match.MATCHED_BY_KEY = "key"
Match.MATCHED_BY_ID_LEVEL = "itemID+level"

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
    local byKey, byIDLevel = {}, {}
    for i = 1, #records do
        local record = records[i]
        if record.key then
            push(byKey, record.key, record)
        end
        if record.itemID and record.itemLevel then
            push(byIDLevel, levelKey(record.itemID, record.itemLevel), record)
        end
    end
    return byKey, byIDLevel
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

-- `best_not_owned` has three quite different meanings and the panel must be
-- able to say which one it is looking at.
local function notOwnedReason(item, inventory)
    if item.isVault then
        return "it is a Great Vault option you have not taken yet"
    end
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
        return { ok = false, reason = "no QE Live verdict imported yet" }
    end

    local records = inventory.records or {}
    local byKey, byIDLevel = indexRecords(records)
    local claimed, rows, fallbacks = {}, {}, {}

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
                            .. "QE Live's bonus IDs are %s, yours are %s",
                        row.slot,
                        item.itemID,
                        tostring(level),
                        bonusText(item.bonusIDs),
                        bonusText(record.bonusIDs)
                    )
                end
            end
            if record then
                claimed[record] = true
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
            else
                row.status = STATUS.BEST_NOT_OWNED
                row.reason = notOwnedReason(item, inventory)
            end
            rows[#rows + 1] = row
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

    local counts = { equipped_is_best = 0, swap = 0, best_not_owned = 0, no_verdict = 0 }
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
    for i = 1, #fallbacks do
        ns.Log("matched by itemID and item level, not by bonus IDs - %s", fallbacks[i])
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
    }
end

-- True when this row is something the Equip button can act on: QE Live named an
-- item, the scan found it, and it is not already on the character.
function Match.IsSwap(row)
    return type(row) == "table" and row.status == STATUS.SWAP and type(row.best) == "table" and row.best.link ~= nil
end
