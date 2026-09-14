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

-- WHICH corner, and why it is not the one R-2 chose (R-2a, WKE-571). Read off
-- the installed copy, which is the only place these two facts are written:
--
--   * `Core/Config.lua:46-49` - the corner defaults. `top_left` ships
--     `{"junk", "item_level"}`; `top_right` ships `{}`. So top-left is where
--     Baganator draws the item level, on a fresh profile and on the owner's.
--   * `ItemViewCommon/ItemButton.lua:174-177` - one corner's widgets are walked
--     in array order and the walk **breaks on the first one that returns true**.
--     Only one widget is ever shown per corner.
--
-- Together those two mean R-2's `{ corner = "top_left", priority = 1 }` was not
-- a mark beside the item level: `API/Main.lua:185-196` inserts at the priority
-- index, so Lootpath would have been FIRST in top-left and the item level would
-- have vanished from every slot the plan marks. A mark that costs the reader a
-- number he already had is not the mark he asked for - the same rule that kept
-- Lootpath out of Baganator's upgrade-plugin slot, applied to a corner.
--
-- `top_right` is empty by default, so the mark collides with nothing there, and
-- priority 1 in an empty array is simply first.
Adapter.CORNER = "top_right"
Adapter.PRIORITY = 1
Adapter.WIDGET_ID = "lootpath_glow"

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
        Adapter.WIDGET_ID,
        Adapter.OnUpdate,
        Adapter.OnInit,
        { corner = Adapter.CORNER, priority = Adapter.PRIORITY },
        true
    )
    return ok
end

-- Whether Baganator is actually drawing the widget, which is a different
-- question from whether it was registered and is the one nothing on screen
-- answered (R-2a, WKE-571: the owner saw no mark and no way to tell "never
-- installed" from "never shown" from "answered false").
--
-- `RegisterCornerWidget` only OFFERS a widget; what draws it is the widget's id
-- being in one of the four saved corner arrays. Registering with a
-- `defaultPosition` asks Baganator to put it there once - `API/Main.lua:185`
-- guards that with `icon_corners_auto_insert_applied`, per id, so a widget new
-- to a saved profile is inserted and a widget the player has since REMOVED
-- stays removed. Both of those are answered by Baganator's own two readers,
-- which are public API and are the only thing asked here.
function Adapter.Corner()
    if type(Baganator) ~= "table" or type(Baganator.API) ~= "table" then
        return nil
    end
    if type(Baganator.API.GetCurrentCornerForWidget) ~= "function" then
        return nil
    end
    local ok, corner = pcall(Baganator.API.GetCurrentCornerForWidget, Adapter.WIDGET_ID)
    return ok and corner or nil
end

-- The adapter's own lines for `/lootpath glow`: what Baganator says about the
-- widget, in Baganator's own words, never in a guess.
Adapter.NOT_IN_A_CORNER = "Baganator has the widget but no corner is drawing it."
    .. " Turn Lootpath on under Baganator's settings > Icon corners > Top right."

-- What the status strip adds when the widget is registered and no corner is
-- drawing it: the reader who went looking for a missing mark is exactly the
-- reader this sentence is for, and it names the settings page rather than
-- asking him to find it.
Adapter.STATUS_NOTE = "bag glow: turn Lootpath on under Baganator's settings > Icon corners > Top right"

function Adapter.StatusNote()
    if not Adapter.Available() or Adapter.Corner() then
        return nil
    end
    return Adapter.STATUS_NOTE
end

function Adapter.DiagnosisLines()
    local lines = {}
    if not Adapter.Available() then
        lines[#lines + 1] = "Baganator: not loaded, or its corner-widget API is not there."
        return lines
    end
    local corner = Adapter.Corner()
    if corner then
        lines[#lines + 1] = string.format("Baganator draws the widget in its %s corner.", corner:gsub("_", " "))
    else
        lines[#lines + 1] = Adapter.NOT_IN_A_CORNER
    end
    return lines
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
