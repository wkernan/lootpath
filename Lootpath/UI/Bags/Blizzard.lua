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

-- THE MARK (UX-4b, WKE-611). This adapter used to draw
-- `evergreen-weeklyrewards-reward-selected` - the Great Vault's gold selection
-- edge - stretched over the whole item button with `SetAllPoints`, so that one
-- picture meant one thing here and on the Vault tab (M5-4). R-2b took that same
-- atlas out of the Baganator corner and said why: the owner measured it at
-- 214 x 121 on his own client, a wide soft-edged banner made to sit BEHIND a
-- cell, and a banner squeezed into a square frame is a smear. That lesson was
-- applied to one adapter and not to this one. It is applied here now.
--
-- So both bag adapters draw the same thing, the same size, in the same corner:
-- the Waymark at 16 points in the button's top-right, in two layers - the
-- keyline silhouette in near-black under the chevron bodies in the brand
-- colour. Top-right is where the Baganator adapter goes for a reason read off
-- Baganator's own source (R-2a), and going to the same corner here means a
-- reader who turns Baganator off finds the mark where he left it.
--
-- UX-4c (WKE-612) changed the drawing in both adapters at once, after the owner
-- opened his full bags and found the mark hard to see across them - he named the
-- colour, and the sign-off page argued the thin shape and its offset shadow were
-- the larger cause. It is the FULL double chevron now, the upper solid and the lower at 65%, with a
-- one-unit near-black outline around every edge and no plate behind it - "Fix E
-- at 16" on the brand sign-off page, which is his pick of 2026-09-17. Two files
-- rather than one, `mark16-edge` under `mark16-fill`, because one texture cannot
-- carry two tints and the brand colour stays a Lua string. Both sit at the SAME
-- anchor with no offset between them: the dilation inside the edge file is the
-- keyline, and the `EDGE_INSET` that used to shrink the fill is gone with the
-- one-sided shadow it made.
--
-- `Adapter.SIZE`, the two texture constants, `EDGE_COLOR` and `FILL_HEX` are
-- deliberately the same values the Baganator adapter carries rather than a
-- reference to it: neither adapter may load without the other, and a mark that
-- changed in one window and not the other would be the bug this comment exists
-- to prevent. The tests assert the two are equal.
Adapter.EDGE_TEXTURE = ns.UI.MEDIA.MARK16_EDGE
Adapter.FILL_TEXTURE = ns.UI.MEDIA.MARK16_FILL
Adapter.SIZE = 16
Adapter.EDGE_COLOR = { 0.05, 0.05, 0.06, 1 }
Adapter.FILL_HEX = ns.UI.BRAND_HEX
Adapter.TEXTURE_KEY = "LootpathGlow"
Adapter.EDGE_KEY = "LootpathGlowEdge"

function Adapter.Available()
    return type(ContainerFrameMixin) == "table"
        and type(ContainerFrameMixin.UpdateItems) == "function"
        and type(C_Container) == "table"
        and type(C_Container.GetContainerItemInfo) == "function"
end

-- Lootpath's own mark on one item button, made once and kept on the button.
-- Returns the FILL layer, which is what the rest of this file shows and hides;
-- the edge rides along on `.edge` and is shown and hidden with it, so no caller
-- can leave half a mark on screen.
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

    local edge = itemButton:CreateTexture(nil, "OVERLAY")
    edge:SetSize(Adapter.SIZE, Adapter.SIZE)
    edge:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", 0, 0)
    edge:SetTexture(Adapter.EDGE_TEXTURE)
    edge:SetVertexColor(unpack(Adapter.EDGE_COLOR))
    edge:Hide()

    -- The same rectangle as the edge, not an inset one: the two files are the
    -- same drawing, so the keyline only lands on the chevrons' edges if the two
    -- are registered texel for texel.
    texture = itemButton:CreateTexture(nil, "OVERLAY", nil, 1)
    texture:SetAllPoints(edge)
    texture:SetTexture(Adapter.FILL_TEXTURE)
    texture:SetVertexColor(ns.UI.ItemLine.RGB(Adapter.FILL_HEX))
    texture:Hide()

    texture.edge = edge
    itemButton[Adapter.EDGE_KEY] = edge
    itemButton[Adapter.TEXTURE_KEY] = texture
    return texture
end

-- Both layers, together, always.
function Adapter.SetShown(texture, wants)
    texture:SetShown(wants)
    if texture.edge then
        texture.edge:SetShown(wants)
    end
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
            Adapter.SetShown(texture, wants)
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
