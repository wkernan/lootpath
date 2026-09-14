-- Lootpath/UI/Bags/Baganator.lua (R-2, WKE-563)
-- The owner's own bag window, marked.
--
-- His screenshot of 2026-09-14 is the single-view "Hotornot's Bags" frame -
-- search bar, bag-icon row, Guild Vault section, currency footer - with Pawn's
-- green arrows drawn in it through Baganator's upgrade plugin. So the mark goes
-- in as a CORNER WIDGET, not as an upgrade plugin:
--
--   Baganator.API.RegisterCornerWidget(label, id, onUpdate, onInit,
--                                      defaultPosition, isFast)
--       Baganator/API/Main.lua:229 in the installed copy (read, never copied).
--       `onInit(itemButton)` returns the widget frame, which Baganator parents,
--       skins, hides and anchors itself; `onUpdate(widget, BGR)` answers true
--       to show it and false to hide it. `BGR.itemLink` is the slot's link.
--       Baganator/ItemViewCommon/ItemButton.lua:127-149 and 265-300 are where
--       both halves are called.
--
-- **Only one upgrade plugin is active at a time** (`ItemButton.lua:102-112`
-- reads one `upgrade_plugin` setting), so registering Lootpath's through
-- `RegisterUpgradePlugin` would displace Pawn's arrow in the owner's own bags.
-- He has not asked for that, and a mark that costs him another addon's mark is
-- not a mark he asked for. A corner widget sits beside Pawn's arrow instead.
--
-- `isFast` is true: the callback is `ns.Glow.Wants`, one table index over a map
-- built off the hover path, so it never needs Baganator's deferred queue.
--
-- **Nothing here knows what a road is.** It asks `ns.Glow.Wants` and draws a
-- texture.

local _, ns = ...

local Adapter = {
    name = "baganator",
    label = "drawn in Baganator's bag window, beside whatever else marks a slot",
}

-- Lootpath's OWN texture, never Blizzard's `UpgradeIcon` and never another
-- addon's: the atlas below is the gold selection edge the Great Vault's own
-- frame uses, which is the mark the Vault tab already draws on a cell (M5-4),
-- so the two surfaces mean the same thing with the same picture.
Adapter.ATLAS = "evergreen-weeklyrewards-reward-selected"
Adapter.SIZE = 15

function Adapter.Available()
    return type(Baganator) == "table"
        and type(Baganator.API) == "table"
        and type(Baganator.API.RegisterCornerWidget) == "function"
end

-- The widget, one per item button, made once and kept by Baganator.
function Adapter.OnInit(itemButton)
    local widget = CreateFrame("Frame", nil, itemButton)
    widget:SetSize(Adapter.SIZE, Adapter.SIZE)
    local texture = widget:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    if type(texture.SetAtlas) == "function" then
        texture:SetAtlas(Adapter.ATLAS)
    end
    widget.texture = texture
    return widget
end

-- Shown or not, for one slot. `BGR.itemLink` is Baganator's own field; every
-- value read from it passes `ns.Safe` on its way through `ns.Glow.WantsLink`.
function Adapter.OnUpdate(_, cacheData)
    local link = type(cacheData) == "table" and cacheData.itemLink or nil
    return ns.Glow.WantsLink(link)
end

function Adapter.Install()
    if not Adapter.Available() then
        return false
    end
    local ok = pcall(
        Baganator.API.RegisterCornerWidget,
        "Lootpath",
        "lootpath_glow",
        Adapter.OnUpdate,
        Adapter.OnInit,
        { corner = "top_left", priority = 1 },
        true
    )
    return ok
end

-- A rebuilt map has to reach a bag that is already open. Baganator's own
-- refresh call is what does it; there is no Lootpath frame to touch.
function Adapter.Refresh()
    if type(Baganator) ~= "table" or type(Baganator.API) ~= "table" then
        return false
    end
    if type(Baganator.API.RequestItemButtonsRefresh) ~= "function" then
        return false
    end
    return pcall(Baganator.API.RequestItemButtonsRefresh) == true
end

ns.UI.Bags.Register(Adapter)
ns.UI.Bags.Baganator = Adapter
