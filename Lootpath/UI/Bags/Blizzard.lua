-- Lootpath/UI/Bags/Blizzard.lua (R-2, WKE-563)
-- The client's own bag frames, marked.
--
-- This is the fallback adapter: the owner draws his bags with Baganator
-- (screenshot, 2026-09-14), so this path is the second user's and his own
-- session with Baganator disabled. It is built anyway because a bag glow that
-- only works with one third-party addon installed is not a feature of Lootpath.
--
-- Every client function it touches, named rather than discovered, each read
-- from `.luals/.../Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`:
--
--   ContainerFrameMixin:UpdateItems()            line 1030 - what every bag
--       frame calls when its contents change. Hooked, never replaced.
--   BaseContainerFrameMixin:EnumerateValidItems() line 522 - `iterator, self, 0`
--       over `container.Items`, which is how Blizzard's own code walks a bag.
--   ContainerFrameMixin:GetBagID()               line 759 - `self:GetID()`.
--   C_Container.GetContainerItemInfo(bag, slot)  the slot's `hyperlink`; the
--       same call `UpdateItems` itself makes one line later.
--
-- **Lootpath draws its own texture and nothing else.** `UpgradeIcon` on a
-- container item button is Pawn's (its `PawnBags.lua` sets it), and an addon
-- that writes to another addon's texture is an addon that breaks it.
--
-- Nothing runs in combat: `UpdateItems` fires in combat, and the hook returns
-- at once under `InCombatLockdown()`, leaving every mark exactly as it was.

local _, ns = ...

local Adapter = {
    name = "blizzard",
    label = "drawn in the client's own bag frames",
}

-- The Great Vault's gold selection edge, which is the same mark the Vault tab
-- draws on a cell (M5-4), so one picture means one thing in both places.
Adapter.ATLAS = "evergreen-weeklyrewards-reward-selected"
Adapter.TEXTURE_KEY = "LootpathGlow"

function Adapter.Available()
    return type(ContainerFrameMixin) == "table"
        and type(ContainerFrameMixin.UpdateItems) == "function"
        and type(C_Container) == "table"
        and type(C_Container.GetContainerItemInfo) == "function"
end

-- Lootpath's own texture on one item button, made once and kept on the button.
function Adapter.Texture(itemButton)
    if type(itemButton) ~= "table" then
        return nil
    end
    local texture = itemButton[Adapter.TEXTURE_KEY]
    if texture then
        return texture
    end
    if type(itemButton.CreateTexture) ~= "function" then
        return nil
    end
    texture = itemButton:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    if type(texture.SetAtlas) == "function" then
        texture:SetAtlas(Adapter.ATLAS)
    end
    texture:Hide()
    itemButton[Adapter.TEXTURE_KEY] = texture
    return texture
end

-- One bag frame's buttons, marked or not. Returns how many it marked, so a
-- test can say what a frame did without reading a texture's alpha.
function Adapter.UpdateFrame(frame)
    if type(frame) ~= "table" or type(frame.EnumerateValidItems) ~= "function" then
        return 0
    end
    local marked = 0
    for _, itemButton in frame:EnumerateValidItems() do
        local texture = Adapter.Texture(itemButton)
        if texture then
            local bagID = type(frame.GetBagID) == "function" and frame:GetBagID()
                or (type(itemButton.GetBagID) == "function" and itemButton:GetBagID() or nil)
            local slot = type(itemButton.GetID) == "function" and itemButton:GetID() or nil
            local wants = false
            if bagID and slot then
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                wants = ns.Glow.WantsLink(type(info) == "table" and info.hyperlink or nil)
            end
            texture:SetShown(wants)
            if wants then
                marked = marked + 1
            end
        end
    end
    return marked
end

-- The hook. In combat it returns at once and every mark keeps its last state,
-- which is the last thing that was true (docs/ROADS-UX.md, Buildability).
function Adapter.OnUpdateItems(frame)
    if InCombatLockdown() then
        return
    end
    Adapter.UpdateFrame(frame)
end

function Adapter.Install()
    if not Adapter.Available() then
        return false
    end
    return pcall(hooksecurefunc, ContainerFrameMixin, "UpdateItems", Adapter.OnUpdateItems)
end

-- A rebuilt map has to reach a bag that is already open. Blizzard's own frames
-- are asked to update themselves, which runs the hook above with them.
function Adapter.Refresh()
    local frames = ContainerFrameUtil_EnumerateContainerFrames
    if type(frames) ~= "function" then
        return false
    end
    local ok = pcall(function()
        for _, frame in frames() do
            if type(frame.IsShown) == "function" and frame:IsShown() then
                Adapter.UpdateFrame(frame)
            end
        end
    end)
    return ok
end

ns.UI.Bags.Register(Adapter)
ns.UI.Bags.Blizzard = Adapter
