-- Lootpath/Modules/Inventory.lua (M1-1, WKE-516)
-- The scanner: equipped slots, owned bags and, while the bank is open, every
-- bank tab, normalised into one record shape that Match (M2-2) and the panels
-- join against. Written against spec/fixtures/captures/Lootpath-20260905-133449.lua,
-- not from memory; the stub replays that transcript in spec/inventory_spec.lua.
--
-- Record: { key, itemID, link, itemLevel, bonusIDs (sorted), slot, equipLoc,
--           location = "equipped"|"bag"|"bank", bag, slotIndex, name, quality }
-- Only equippable gear becomes a record; consumables, bags, profession tools
-- and shirts/tabards have no QE Live slot and are skipped.
--
-- Every value read from the client passes ns.Safe. Nothing runs in combat.
-- The bank is reported unavailable (never a silent empty list) unless
-- C_Bank.CanViewBank answers true, which the transcript showed tracks the
-- bank frame exactly: tabs 6..13 answer their slot counts only while open.

local _, ns = ...

ns.Inventory = {}
local Inventory = ns.Inventory

-- itemEquipLoc -> QE Live slot name (its Top Gear export vocabulary, read from
-- TopGearExports.ts on 2026-09-06). Anything absent here is not gear.
Inventory.SLOT_BY_EQUIPLOC = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CLOAK = "Back",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "1H Weapon",
    INVTYPE_WEAPONMAINHAND = "1H Weapon",
    INVTYPE_WEAPONOFFHAND = "1H Weapon",
    INVTYPE_RANGEDRIGHT = "1H Weapon",
    INVTYPE_2HWEAPON = "2H Weapon",
    INVTYPE_RANGED = "2H Weapon",
    INVTYPE_HOLDABLE = "Offhand",
    INVTYPE_SHIELD = "Shield",
}

function Inventory.SlotForEquipLoc(equipLoc)
    return Inventory.SLOT_BY_EQUIPLOC[equipLoc]
end

-- Secret-guarded read: a secret value is dropped (nil) and counted.
local function guarded(counter, value)
    local safe, secret = ns.Safe(value)
    if secret then
        counter.secretsSeen = counter.secretsSeen + 1
        return nil
    end
    return safe
end

-- Builds one record from a link the client handed us. `where` carries
-- location/bag/slotIndex; `containerInfo` is the ContainerItemInfo table for
-- bag and bank items (its quality is the fallback when GetItemInfo is not
-- cached yet). Returns nil for non-gear or an unparsable link.
function Inventory.Record(link, where, containerInfo, counter)
    counter = counter or { secretsSeen = 0 }
    local parsed = ns.ParseItemLink(link)
    if not parsed then
        return nil
    end
    local instant = { C_Item.GetItemInfoInstant(link) }
    local equipLoc = guarded(counter, instant[4])
    local slot = Inventory.SlotForEquipLoc(equipLoc)
    if not slot then
        return nil
    end
    local info = { C_Item.GetItemInfo(link) }
    local itemLevel = guarded(counter, (C_Item.GetDetailedItemLevelInfo(link)))
    local quality = guarded(counter, info[3])
    if quality == nil and containerInfo then
        quality = guarded(counter, containerInfo.quality)
    end
    return {
        key = parsed.key,
        itemID = parsed.itemID,
        link = link,
        itemLevel = itemLevel,
        bonusIDs = parsed.bonusIDs,
        slot = slot,
        equipLoc = equipLoc,
        location = where.location,
        bag = where.bag,
        slotIndex = where.slotIndex,
        name = guarded(counter, info[1]),
        quality = quality,
    }
end

-- Bank tab indexes, discovered from Enum.BagIndex by name rather than
-- hardcoded: CharacterBankTab_1..6 = 6..11 and AccountBankTab_1..5 = 12..16
-- on 12.1.0 (transcript 2026-09-05).
local function bankTabs()
    local tabs = {}
    for name, value in pairs((Enum and Enum.BagIndex) or {}) do
        local kind = tostring(name):match("^(%a+)BankTab_%d+$")
        if kind then
            tabs[#tabs + 1] = { bag = value, kind = kind }
        end
    end
    table.sort(tabs, function(a, b)
        return a.bag < b.bag
    end)
    return tabs
end

local function canViewBank(kind)
    if not (C_Bank and C_Bank.CanViewBank and Enum and Enum.BankType) then
        return false
    end
    local bankType = Enum.BankType[kind]
    if bankType == nil then
        return false
    end
    local ok, viewable = pcall(C_Bank.CanViewBank, bankType)
    return ok and viewable == true
end

local function scanContainer(bag, location, records, counter)
    local numSlots = guarded(counter, C_Container.GetContainerNumSlots(bag)) or 0
    for slotIndex = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bag, slotIndex)
        local safeInfo = guarded(counter, info)
        local link = safeInfo and guarded(counter, safeInfo.hyperlink)
        if not link then
            link = guarded(counter, C_Container.GetContainerItemLink(bag, slotIndex))
        end
        if type(link) == "string" then
            local record =
                Inventory.Record(link, { location = location, bag = bag, slotIndex = slotIndex }, safeInfo, counter)
            if record then
                records[#records + 1] = record
            end
        end
    end
end

-- Scan() -> { ok = true, records, bankAvailable, secretsSeen }
--        or { ok = false, reason = "combat" }
function Inventory.Scan(_)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    local counter = { secretsSeen = 0 }
    local records = {}

    local first = INVSLOT_FIRST_EQUIPPED or 1
    local last = INVSLOT_LAST_EQUIPPED or 19
    for invSlot = first, last do
        local link = guarded(counter, GetInventoryItemLink("player", invSlot))
        if type(link) == "string" then
            local record = Inventory.Record(link, { location = "equipped", slotIndex = invSlot }, nil, counter)
            if record then
                records[#records + 1] = record
            end
        end
    end

    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5
    for bag = 0, lastBag do
        scanContainer(bag, "bag", records, counter)
    end

    local bankAvailable = canViewBank("Character")
    local accountAvailable = canViewBank("Account")
    for _, tab in ipairs(bankTabs()) do
        local viewable = (tab.kind == "Character" and bankAvailable) or (tab.kind == "Account" and accountAvailable)
        if viewable then
            scanContainer(tab.bag, "bank", records, counter)
        end
    end

    return { ok = true, records = records, bankAvailable = bankAvailable, secretsSeen = counter.secretsSeen }
end
